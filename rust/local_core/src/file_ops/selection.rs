//! 目录多选模型。
//!
//! **T3 契约重建**：逐行翻译自 neoview（自有项目，可读可翻译）
//! `Xiranite/src/nodes/neoview/features/panels/cards/folder/DirectorySelection.ts`。
//! 函数名与类型名与上游一一对应，便于升级时对拍（`create_directory_selection` ↔
//! `createDirectorySelection`，依此类推）。
//!
//! 为什么不搬组件：neoview 的多选挂在 React 的 `useState` 上，Rossi 的 UI 是 Flutter
//! （ADR-0003「技术栈不取」）。这里搬的是**纯规则**，UI 在 Dart 侧重塑。
//!
//! ## 模型形状（不是「路径数组」）
//!
//! 上游把选中态压成四个字段，而不是一个 `Set<path>`：
//!
//! ```text
//! all_selected   反转位：默认全部选中/全部未选中
//! ranges         索引区间（选中一段连续的行，Shift 用）
//! explicit       与「默认值」不同的那些路径（path → 它在列表里的下标，rebase 后为 None）
//! anchor_index   Shift 区间的锚点
//! ```
//!
//! 这么压的理由是**列表是虚拟化的**：一次只加载一页，用索引区间表达 10 万行的「全选」
//! 比塞 10 万个路径便宜。Rossi 的文件卡片刻意不虚拟化（一屏几百条），但这套表示仍然
//! 值得照抄，因为它同时解决了**列表换了一批之后选中态怎么办**这个问题 —— 见
//! [`rebase_directory_selection`]。
//!
//! ## 与上游的唯一偏离
//!
//! 上游 `explicit` 是 JS `Map`（**插入序**），这里是 `BTreeMap`（**路径序**）。
//! 受影响的位置只有一处：`extend_directory_selection` 的非叠加分支里
//! 「找出下标等于锚点的那个已记录路径」。索引在正常情况下是唯一的，
//! 因此两种序给出同一个答案；若真出现同索引多条记录，取哪一条没有语义差别。
//! 这是本项目里 neoview 移植的**唯一登记偏离**（见 `docs/local-core-vendored-modules.md`）。

use std::collections::BTreeMap;

/// 一段连续的索引区间（闭区间，两端都含）。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DirectorySelectionRange {
    pub start: usize,
    pub end: usize,
}

/// 选中态的可序列化投影，给 FRB / 持久化用。
///
/// 对应上游 `DirectorySelectionDescriptorDto`。`explicit` 用 `Vec` 而不是 map：
/// 它要跨 FFI 边界，且消费方只需要「路径 + 可选下标」这一对。
#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct DirectorySelectionDescriptor {
    pub generation: u64,
    pub all_selected: bool,
    pub ranges: Vec<DirectorySelectionRange>,
    /// `index` 为 `None` 表示「知道这个路径被选中过，但列表换过之后它现在在第几行不知道」。
    pub explicit: Vec<(String, Option<usize>)>,
}

/// 选中态本体。
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DirectorySelectionModel {
    /// 这份选中态对应的列表快照版本号。与文件管理器的 `generation` 同源。
    pub generation: u64,
    /// 反转位：`true` 表示「默认选中」。
    pub all_selected: bool,
    pub anchor_index: Option<usize>,
    pub ranges: Vec<DirectorySelectionRange>,
    /// 与默认值不同的路径 → 它的下标（列表换代后降级为 `None`）。
    pub explicit: BTreeMap<String, Option<usize>>,
}

impl DirectorySelectionModel {
    pub fn count(&self, total: usize) -> usize {
        directory_selection_count(self, total)
    }

    /// 把选中态落成一份具体的路径表。
    ///
    /// 上游对应 `selectedLoadedDirectoryPaths`，但那里的参数是「按游标分页的 map」
    /// （因为它一次只有几页）。Rossi 的卡片一次拿到整份列表，所以这里收一个扁平的
    /// 条目名切片即可 —— 语义不变，只是把分页游标换成了切片下标。
    pub fn selected_paths<S: AsRef<str>>(&self, entries: &[S]) -> Vec<String> {
        let mut selected = Vec::new();
        for (index, entry) in entries.iter().enumerate() {
            if is_directory_index_selected(self, index, Some(entry.as_ref())) {
                selected.push(entry.as_ref().to_string());
            }
        }
        selected
    }

    pub fn descriptor(&self) -> DirectorySelectionDescriptor {
        directory_selection_descriptor(self)
    }

    pub fn is_selected(&self, index: usize, path: Option<&str>) -> bool {
        is_directory_index_selected(self, index, path)
    }
}

pub fn create_directory_selection(generation: u64) -> DirectorySelectionModel {
    DirectorySelectionModel {
        generation,
        all_selected: false,
        anchor_index: None,
        ranges: Vec::new(),
        explicit: BTreeMap::new(),
    }
}

pub fn directory_selection_descriptor(
    selection: &DirectorySelectionModel,
) -> DirectorySelectionDescriptor {
    DirectorySelectionDescriptor {
        generation: selection.generation,
        all_selected: selection.all_selected,
        ranges: selection.ranges.clone(),
        explicit: selection
            .explicit
            .iter()
            .map(|(path, index)| (path.clone(), *index))
            .collect(),
    }
}

pub fn select_all_directory_entries(generation: u64) -> DirectorySelectionModel {
    DirectorySelectionModel {
        generation,
        all_selected: true,
        anchor_index: None,
        ranges: Vec::new(),
        explicit: BTreeMap::new(),
    }
}

pub fn invert_directory_selection(
    selection: &DirectorySelectionModel,
    generation: u64,
) -> DirectorySelectionModel {
    let current = if selection.generation == generation {
        selection.clone()
    } else {
        rebase_directory_selection(selection, generation)
    };
    DirectorySelectionModel {
        all_selected: !current.all_selected,
        ..current
    }
}

/// Shift 连选：从锚点连到 `end_index`。
///
/// 锚点缺失（或点在锚点自身）时退化成一次普通 toggle —— 这与上游一致，
/// 也是「Shift 点在同一行」时用户期望的行为。
pub fn chain_directory_selection(
    selection: &DirectorySelectionModel,
    generation: u64,
    end_index: usize,
    options: ChainOptions<'_>,
) -> DirectorySelectionModel {
    let current = if selection.generation == generation {
        selection.clone()
    } else {
        rebase_directory_selection(selection, generation)
    };
    if options.anchor_index.is_none() || options.anchor_index == Some(end_index) {
        return toggle_directory_selection(&current, generation, options.end_path, end_index);
    }
    let extended = extend_directory_selection(
        &DirectorySelectionModel {
            anchor_index: options.anchor_index,
            ..current
        },
        generation,
        end_index,
        ExtendOptions {
            additive: true,
            fallback_anchor: options.anchor_index.unwrap_or(end_index),
            anchor_path: options.anchor_path,
            end_path: Some(options.end_path),
        },
    );
    DirectorySelectionModel {
        anchor_index: Some(end_index),
        ..extended
    }
}

#[derive(Clone, Copy, Debug, Default)]
pub struct ChainOptions<'a> {
    pub anchor_index: Option<usize>,
    pub anchor_path: Option<&'a str>,
    pub end_path: &'a str,
}

#[derive(Clone, Copy, Debug)]
pub struct ExtendOptions<'a> {
    pub additive: bool,
    pub fallback_anchor: usize,
    pub anchor_path: Option<&'a str>,
    pub end_path: Option<&'a str>,
}

pub fn select_directory_single(
    generation: u64,
    path: &str,
    index: usize,
) -> DirectorySelectionModel {
    let mut explicit = BTreeMap::new();
    explicit.insert(path.to_string(), Some(index));
    DirectorySelectionModel {
        generation,
        all_selected: false,
        anchor_index: Some(index),
        ranges: Vec::new(),
        explicit,
    }
}

/// 点一下某一行：翻转它的选中态。
pub fn toggle_directory_selection(
    selection: &DirectorySelectionModel,
    generation: u64,
    path: &str,
    index: usize,
) -> DirectorySelectionModel {
    let current = if selection.generation == generation {
        selection.clone()
    } else {
        rebase_directory_selection(selection, generation)
    };
    let mut explicit = current.explicit.clone();
    let mut ranges = current.ranges.clone();
    // 「这一行的当前态 == 默认态」⇒ 要把它记成偏离；否则把偏离抹掉回到默认态。
    if is_directory_index_selected(&current, index, Some(path)) == current.all_selected {
        explicit.insert(path.to_string(), Some(index));
    } else {
        explicit.remove(path);
        ranges = remove_index(&ranges, index);
    }
    DirectorySelectionModel {
        generation,
        all_selected: current.all_selected,
        anchor_index: Some(index),
        ranges,
        explicit,
    }
}

pub fn extend_directory_selection(
    selection: &DirectorySelectionModel,
    generation: u64,
    end_index: usize,
    options: ExtendOptions<'_>,
) -> DirectorySelectionModel {
    let current = if selection.generation == generation {
        selection.clone()
    } else {
        rebase_directory_selection(selection, generation)
    };
    let anchor_index = current.anchor_index.unwrap_or(options.fallback_anchor);
    let range = normalized_range(anchor_index, end_index);

    if !options.additive {
        // 非叠加：整份选中态换成这一段。锚点与终点显式记下来，
        // 这样列表换代（rebase）之后至少这两个端点还活着。
        let mut explicit: BTreeMap<String, Option<usize>> = BTreeMap::new();
        let anchor_path = options.anchor_path.map(str::to_string).or_else(|| {
            current
                .explicit
                .iter()
                .find(|(_, index)| **index == Some(anchor_index))
                .map(|(path, _)| path.clone())
        });
        if let Some(path) = anchor_path.filter(|path| !path.is_empty()) {
            explicit.insert(path, Some(anchor_index));
        }
        if let Some(path) = options.end_path.filter(|path| !path.is_empty()) {
            explicit.insert(path.to_string(), Some(end_index));
        }
        return DirectorySelectionModel {
            generation,
            all_selected: false,
            anchor_index: Some(anchor_index),
            ranges: vec![range],
            explicit,
        };
    }

    if current.all_selected {
        // 默认全选时，拖一段是**取消**这一段 ⇒ 把区间内已记录的偏离清掉。
        let mut explicit = current.explicit.clone();
        let doomed: Vec<String> = explicit
            .iter()
            .filter(|(path, index)| {
                index
                    .map(|index| range_contains(range, index))
                    .unwrap_or(false)
                    || options.end_path == Some(path.as_str())
            })
            .map(|(path, _)| path.clone())
            .collect();
        for path in doomed {
            explicit.remove(&path);
        }
        return DirectorySelectionModel {
            generation,
            all_selected: true,
            anchor_index: Some(anchor_index),
            ranges: remove_range(&current.ranges, range),
            explicit,
        };
    }

    let mut ranges = current.ranges.clone();
    ranges.push(range);
    let ranges = merge_ranges(&ranges);
    let mut explicit = current.explicit.clone();
    if let Some(path) = options.end_path.filter(|path| !path.is_empty()) {
        explicit.insert(path.to_string(), Some(end_index));
    }
    DirectorySelectionModel {
        generation,
        all_selected: false,
        anchor_index: Some(anchor_index),
        ranges,
        explicit,
    }
}

/// 列表换代后的降级。
///
/// 索引区间不再可信（行被删/被排序/被筛掉了），所以**丢掉 ranges**；
/// 而 `explicit` 里的路径仍然可信，保留下来但把下标抹成 `None` ——
/// 此后它们只靠路径匹配，不再靠位置。
pub fn rebase_directory_selection(
    selection: &DirectorySelectionModel,
    generation: u64,
) -> DirectorySelectionModel {
    DirectorySelectionModel {
        generation,
        all_selected: selection.all_selected,
        anchor_index: None,
        ranges: Vec::new(),
        explicit: selection
            .explicit
            .keys()
            .map(|path| (path.clone(), None))
            .collect(),
    }
}

/// 重命名之后把选中态跟着搬过去，免得选中项因为路径变了而「掉选」。
pub fn replace_directory_selection_path(
    selection: &DirectorySelectionModel,
    source_path: &str,
    destination_path: &str,
) -> DirectorySelectionModel {
    let source = selection
        .explicit
        .iter()
        .find(|(path, _)| same_folder_path(path, source_path))
        .map(|(path, index)| (path.clone(), *index));
    let Some((source_key, index)) = source else {
        return selection.clone();
    };
    if same_folder_path(&source_key, destination_path) {
        return selection.clone();
    }
    let mut explicit = selection.explicit.clone();
    explicit.remove(&source_key);
    explicit.insert(destination_path.to_string(), index);
    DirectorySelectionModel {
        explicit,
        ..selection.clone()
    }
}

pub fn is_directory_index_selected(
    selection: &DirectorySelectionModel,
    index: usize,
    path: Option<&str>,
) -> bool {
    let differs_from_default = path
        .map(|path| selection.explicit.contains_key(path))
        .unwrap_or(false)
        || selection
            .ranges
            .iter()
            .any(|range| range_contains(*range, index));
    if differs_from_default {
        !selection.all_selected
    } else {
        selection.all_selected
    }
}

pub fn directory_selection_count(selection: &DirectorySelectionModel, total: usize) -> usize {
    let ranged: usize = selection
        .ranges
        .iter()
        .map(|range| range.end.saturating_sub(range.start) + 1)
        .sum();
    let mut outside_ranges = 0usize;
    for index in selection.explicit.values() {
        let inside = index
            .map(|index| {
                selection
                    .ranges
                    .iter()
                    .any(|range| range_contains(*range, index))
            })
            .unwrap_or(false);
        if !inside {
            outside_ranges += 1;
        }
    }
    let deviations = ranged + outside_ranges;
    if selection.all_selected {
        total.saturating_sub(deviations)
    } else {
        deviations.min(total)
    }
}

fn normalized_range(left: usize, right: usize) -> DirectorySelectionRange {
    DirectorySelectionRange {
        start: left.min(right),
        end: left.max(right),
    }
}

fn merge_ranges(values: &[DirectorySelectionRange]) -> Vec<DirectorySelectionRange> {
    if values.len() < 2 {
        return values.to_vec();
    }
    let mut sorted = values.to_vec();
    sorted.sort_by_key(|value| (value.start, value.end));
    let mut merged: Vec<DirectorySelectionRange> = Vec::new();
    for value in sorted {
        match merged.last_mut() {
            // `+1`：首尾相接的两段也算一段（`[1,3]` 与 `[4,6]` → `[1,6]`）。
            None => merged.push(value),
            Some(last) if value.start > last.end + 1 => merged.push(value),
            Some(last) => {
                if value.end > last.end {
                    last.end = value.end;
                }
            }
        }
    }
    merged
}

fn remove_index(values: &[DirectorySelectionRange], index: usize) -> Vec<DirectorySelectionRange> {
    let mut next = Vec::new();
    for range in values {
        if !range_contains(*range, index) {
            next.push(*range);
            continue;
        }
        if range.start < index {
            next.push(DirectorySelectionRange {
                start: range.start,
                end: index - 1,
            });
        }
        if index < range.end {
            next.push(DirectorySelectionRange {
                start: index + 1,
                end: range.end,
            });
        }
    }
    next
}

fn remove_range(
    values: &[DirectorySelectionRange],
    removed: DirectorySelectionRange,
) -> Vec<DirectorySelectionRange> {
    let mut next = Vec::new();
    for range in values {
        if range.end < removed.start || range.start > removed.end {
            next.push(*range);
            continue;
        }
        if range.start < removed.start {
            next.push(DirectorySelectionRange {
                start: range.start,
                end: removed.start - 1,
            });
        }
        if range.end > removed.end {
            next.push(DirectorySelectionRange {
                start: removed.end + 1,
                end: range.end,
            });
        }
    }
    next
}

fn range_contains(range: DirectorySelectionRange, index: usize) -> bool {
    index >= range.start && index <= range.end
}

/// 路径同一性。上游 `FolderPathIdentity.sameFolderPath`：非 Windows 上保留大小写。
fn same_folder_path(left: &str, right: &str) -> bool {
    if cfg!(windows) {
        left.replace('\\', "/").to_lowercase() == right.replace('\\', "/").to_lowercase()
    } else {
        left == right
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn names(count: usize) -> Vec<String> {
        (0..count)
            .map(|index| format!("entry-{index:02}"))
            .collect()
    }

    #[test]
    fn toggle_records_deviations_from_the_default() {
        // 注意：`explicit` 的键是**列表里的真实路径**，不是任意标签 ——
        // 上游 `selectedLoadedDirectoryPaths` 也是拿 `entry.path` 去比。
        let entries = names(10);
        let selection = create_directory_selection(1);
        assert_eq!(selection.count(entries.len()), 0);

        let selection = toggle_directory_selection(&selection, 1, &entries[1], 1);
        assert_eq!(selection.count(entries.len()), 1);
        assert_eq!(selection.selected_paths(&entries), vec![entries[1].clone()]);

        // 再点一次：偏离被抹掉，回到默认（全不选）。
        let selection = toggle_directory_selection(&selection, 1, &entries[1], 1);
        assert_eq!(selection.count(entries.len()), 0);
        assert!(selection.selected_paths(&entries).is_empty());
    }

    #[test]
    fn select_all_then_toggle_deselects_one() {
        let entries = names(10);
        let selection = select_all_directory_entries(1);
        assert_eq!(selection.count(entries.len()), 10);

        // 全选态下点一行 = 取消这一行（记成一条偏离）。
        let selection = toggle_directory_selection(&selection, 1, &entries[2], 2);
        assert_eq!(selection.count(entries.len()), 9);
        let paths = selection.selected_paths(&entries);
        assert_eq!(paths.len(), 9);
        assert!(!paths.contains(&entries[2]));
    }

    #[test]
    fn extend_selects_a_range_and_merge_joins_adjacent_ranges() {
        let selection = select_directory_single(1, "a", 0);
        let selection = extend_directory_selection(
            &selection,
            1,
            3,
            ExtendOptions {
                additive: true,
                fallback_anchor: 0,
                anchor_path: Some("a"),
                end_path: Some("d"),
            },
        );
        assert_eq!(selection.count(10), 4);
        assert_eq!(
            selection.ranges,
            vec![DirectorySelectionRange { start: 0, end: 3 }]
        );

        // 与 [0,3] 首尾相接的 [4,5] 应被并成 [0,5]，而不是留两段。
        let selection = extend_directory_selection(
            &selection,
            1,
            5,
            ExtendOptions {
                additive: true,
                fallback_anchor: 0,
                anchor_path: Some("a"),
                end_path: Some("f"),
            },
        );
        assert_eq!(
            selection.ranges,
            vec![DirectorySelectionRange { start: 0, end: 5 }]
        );
        assert_eq!(selection.count(10), 6);
    }

    /// 全选态下 `ranges` 的含义与未全选时**相反**：它记的是「取消掉的那一段」。
    /// 因此叠加拖选在这里是「把这一段重新选中」，不是「取消这一段」。
    #[test]
    fn extend_on_select_all_reselects_the_dragged_range() {
        let mut selection = select_all_directory_entries(1);
        selection = toggle_directory_selection(&selection, 1, "b", 1);
        selection = toggle_directory_selection(&selection, 1, "c", 2);
        assert_eq!(selection.count(10), 8);
        // toggle 会把锚点挪到刚点的那一行；显式定锚，免得判据依赖那个副作用。
        selection.anchor_index = Some(1);

        let extended = extend_directory_selection(
            &selection,
            1,
            3,
            ExtendOptions {
                additive: true,
                fallback_anchor: 1,
                anchor_path: None,
                end_path: None,
            },
        );
        // [1,3] 里的两条「取消」被抹掉 ⇒ 重新选中，回到 10。
        assert_eq!(extended.count(10), 10);
        assert!(extended.explicit.is_empty());
    }

    #[test]
    fn non_additive_extend_replaces_the_whole_selection() {
        // 先靠一次叠加拖选造出 ranges 和一条 explicit("h")，再整份换掉。
        let selection = extend_directory_selection(
            &create_directory_selection(1),
            1,
            7,
            ExtendOptions {
                additive: true,
                fallback_anchor: 0,
                anchor_path: None,
                end_path: Some("h"),
            },
        );
        assert_eq!(selection.count(10), 8);
        assert_eq!(
            selection.ranges,
            vec![DirectorySelectionRange { start: 0, end: 7 }]
        );

        let selection = extend_directory_selection(
            &selection,
            1,
            4,
            ExtendOptions {
                additive: false,
                fallback_anchor: 0,
                anchor_path: Some("a"),
                end_path: Some("e"),
            },
        );
        // 非叠加 = 整份换掉：旧区间与旧的 explicit("h") 都必须消失。
        assert_eq!(
            selection.ranges,
            vec![DirectorySelectionRange { start: 0, end: 4 }]
        );
        assert_eq!(selection.count(10), 5);
        assert!(!selection.explicit.contains_key("h"));
        assert_eq!(
            selection.explicit,
            BTreeMap::from([("a".to_string(), Some(0)), ("e".to_string(), Some(4))])
        );
    }

    /// 这一条是本模块存在的理由：**列表换代之后，索引区间不再可信，路径仍然可信**。
    #[test]
    fn rebase_drops_ranges_and_keeps_paths_without_an_index() {
        let selection = extend_directory_selection(
            &select_directory_single(1, "a", 0),
            1,
            9,
            ExtendOptions {
                additive: true,
                fallback_anchor: 0,
                anchor_path: Some("a"),
                end_path: Some("j"),
            },
        );
        assert_eq!(selection.count(10_000), 10);

        let rebased = rebase_directory_selection(&selection, 2);
        assert_eq!(rebased.generation, 2);
        assert!(rebased.ranges.is_empty(), "区间必须被丢掉");
        assert_eq!(
            rebased.explicit.values().cloned().collect::<Vec<_>>(),
            vec![None, None],
            "路径留下，下标抹掉"
        );
        // 降级后只剩端点还选着（10 万里 2 条），而不是继续宣称选了 10 条。
        assert_eq!(rebased.count(10_000), 2);
    }

    #[test]
    fn operations_rebase_that_happened_on_an_older_generation() {
        let stale = select_directory_single(1, "a", 0);
        // 拿着 generation=1 的选中态，作用在 generation=2 的列表上：不 panic，按降级后的态继续。
        let toggled = toggle_directory_selection(&stale, 2, "z", 25);
        assert_eq!(toggled.generation, 2);
        assert_eq!(toggled.count(100), 2, "旧路径 a + 新点的 z");
    }

    #[test]
    fn invert_flips_the_default_bit() {
        let inverted = invert_directory_selection(&create_directory_selection(1), 1);
        assert!(inverted.all_selected);
        assert_eq!(inverted.count(5), 5);

        let inverted_again = invert_directory_selection(&inverted, 1);
        assert!(!inverted_again.all_selected);
        assert_eq!(inverted_again.count(5), 0);
    }

    #[test]
    fn chain_to_the_same_index_falls_back_to_toggle() {
        let selection = select_directory_single(1, "a", 3);
        let chained = chain_directory_selection(
            &selection,
            1,
            3,
            ChainOptions {
                anchor_index: Some(3),
                anchor_path: Some("a"),
                end_path: "a",
            },
        );
        // Shift 点在同一行 = 普通 toggle ⇒ 把 a 取消掉。
        assert_eq!(chained.count(10), 0);
    }

    #[test]
    fn chain_extends_and_moves_the_anchor_to_the_end() {
        let selection = select_directory_single(1, "a", 1);
        let chained = chain_directory_selection(
            &selection,
            1,
            4,
            ChainOptions {
                anchor_index: Some(1),
                anchor_path: Some("a"),
                end_path: "e",
            },
        );
        assert_eq!(chained.anchor_index, Some(4));
        assert_eq!(chained.count(10), 4);
    }

    #[test]
    fn count_never_exceeds_the_total() {
        // 未全选时，偏离数被 total 夹住（区间可能来自更大的旧列表）。
        let selection = extend_directory_selection(
            &create_directory_selection(1),
            1,
            99,
            ExtendOptions {
                additive: true,
                fallback_anchor: 0,
                anchor_path: None,
                end_path: None,
            },
        );
        assert_eq!(selection.count(10), 10);
    }

    #[test]
    fn replace_path_follows_a_rename() {
        let selection = select_directory_single(1, "/books/old", 0);
        let renamed = replace_directory_selection_path(&selection, "/books/old", "/books/new");
        assert!(!renamed.explicit.contains_key("/books/old"));
        assert_eq!(renamed.explicit.get("/books/new"), Some(&Some(0)));
        // 改到同一个路径上是空操作，不该多出一条记录。
        let same = replace_directory_selection_path(&renamed, "/books/new", "/books/new");
        assert_eq!(same, renamed);
    }

    #[test]
    fn descriptor_round_trips_the_compressed_shape() {
        let selection = extend_directory_selection(
            &select_directory_single(7, "a", 0),
            7,
            5,
            ExtendOptions {
                additive: true,
                fallback_anchor: 0,
                anchor_path: Some("a"),
                end_path: Some("f"),
            },
        );
        let descriptor = selection.descriptor();
        assert_eq!(descriptor.generation, 7);
        assert!(!descriptor.all_selected);
        assert_eq!(
            descriptor.ranges,
            vec![DirectorySelectionRange { start: 0, end: 5 }]
        );
        assert_eq!(
            descriptor.explicit,
            vec![("a".to_string(), Some(0)), ("f".to_string(), Some(5))]
        );
    }
}
