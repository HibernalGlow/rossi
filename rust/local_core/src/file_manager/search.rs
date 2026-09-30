// 从 file_manager.rs 整块原样搬出；除补必要的可见性前缀外未改一个字符。
use super::*;

/// 一条目是否命中当前设置里的查询与类型筛选。
///
/// `tokens` 由调用方解析一次后复用（见 [`entries`]）。
pub(super) fn matches_entry(
    settings: &FileManagerSettings,
    node: &FileTreeNode,
    tokens: &[crate::search_query::Token],
    root: &Path,
) -> bool {
    if !tokens.is_empty() {
        let mode = if settings.search_or_mode {
            crate::search_query::MatchMode::Or
        } else {
            crate::search_query::MatchMode::And
        };
        let hay = search_hay(node, settings.search_in_path.then_some(root));
        // 索引期 / 查询期 / 后置过滤必须走同一个归一化函数，否则出假阴性；
        // 查询期由 `search_query::parse` 内部完成，这里负责 hay 侧。
        let hay = crate::search_norm::normalize_for_match(&hay);
        if !crate::search_query::matches_lowercased_with_mode(tokens, &hay, mode) {
            return false;
        }
    }
    entry_filter_matches(settings.entry_filter, node)
}

pub(super) fn entry_filter_matches(filter: EntryFilter, node: &FileTreeNode) -> bool {
    match filter {
        EntryFilter::All => true,
        EntryFilter::Folders => node.is_dir,
        EntryFilter::Archives => node.is_archive,
        EntryFilter::Images => node.is_image,
        EntryFilter::Video => node.is_video,
        EntryFilter::Audio => node.is_audio,
    }
}

pub(crate) fn compare_entries(
    settings: &FileManagerSettings,
    left: &FileTreeNode,
    right: &FileTreeNode,
) -> std::cmp::Ordering {
    use std::cmp::Ordering;

    let rank = |node: &FileTreeNode| !node.is_dir;
    let directories = settings
        .directories_first
        .then(|| rank(left).cmp(&rank(right)));
    let field_order = match settings.sort_field {
        SortField::Name => natural_name_cmp(&left.name, &right.name),
        SortField::Type => {
            extension_cmp(left, right).then_with(|| natural_name_cmp(&left.name, &right.name))
        }
        SortField::Size => left
            .size
            .cmp(&right.size)
            .then_with(|| natural_name_cmp(&left.name, &right.name)),
        SortField::Date => left
            .modified_secs
            .cmp(&right.modified_secs)
            .then_with(|| natural_name_cmp(&left.name, &right.name)),
        SortField::Random => {
            // 名称兜底让比较器保持全序；同一目录内名称唯一，实际不会触发。
            shuffle_key(settings.shuffle_seed, &left.name)
                .cmp(&shuffle_key(settings.shuffle_seed, &right.name))
                .then_with(|| natural_name_cmp(&left.name, &right.name))
        }
    };
    let order = if settings.sort_order == SortOrder::Descending {
        field_order.reverse()
    } else {
        field_order
    };
    directories.unwrap_or(Ordering::Equal).then(order)
}

/// 搜索的 hay：条目名，加上（可选）相对搜索根的那段目录。
///
/// 只喂**相对**路径，父目录名才不会把它的所有子项都匹配上；分隔符统一成 `/`，
/// 这样 Windows 的 `春\001.jpg` 用 `春/001` 也能命中。
pub(super) fn search_hay_for_name(name: &str, relative_dir: Option<&str>) -> String {
    match relative_dir {
        Some(rel) if !rel.is_empty() => format!("{rel}/{name}"),
        _ => name.to_owned(),
    }
}

pub(super) fn search_hay(node: &FileTreeNode, root: Option<&Path>) -> String {
    let Some(root) = root else {
        return node.name.clone();
    };
    let relative_dir = Path::new(&node.path)
        .parent()
        .and_then(|parent| parent.strip_prefix(root).ok())
        .filter(|rel| !rel.as_os_str().is_empty())
        .map(|rel| rel.to_string_lossy().replace('\\', "/"));
    search_hay_for_name(&node.name, relative_dir.as_deref())
}

/// 一次递归搜索的输入：搜索根 + 当时生效的设置。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileManagerSearchRequest {
    pub root: PathBuf,
    pub settings: FileManagerSettings,
}

/// 一次遍历的**范围**：命中池之外的、决定「这批命中是怎么来的」的那几个条件。
///
/// 单独立一个类型是为了把「就地收窄」的判据写死在一处：旧的命中池只有在**同样的范围**
/// 里才是新查询的超集。设置里剩下的那些（排序字段、视图模式、穿透投影）不参与匹配，
/// 所以不需要重新扫盘，也不该被算进范围里。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileManagerSearchScope {
    pub root: PathBuf,
    /// 实际生效的递归层数：已按 [`MAX_SEARCH_DEPTH`] 夹过，关掉子目录时为 `0`。
    pub max_depth: usize,
    pub show_hidden_files: bool,
    pub search_in_path: bool,
    pub search_or_mode: bool,
    pub entry_filter: EntryFilter,
}

impl FileManagerSearchScope {
    pub(crate) fn from_request(request: &FileManagerSearchRequest) -> Self {
        let settings = &request.settings;
        Self {
            root: request.root.clone(),
            max_depth: if settings.search_include_subfolders {
                settings.search_max_depth.min(MAX_SEARCH_DEPTH)
            } else {
                0
            },
            show_hidden_files: settings.show_hidden_files,
            search_in_path: settings.search_in_path,
            search_or_mode: settings.search_or_mode,
            entry_filter: settings.entry_filter,
        }
    }
}

/// 一条命中就是目录列表里那种条目，不另加「相对目录」字段：那段信息已经完整地
/// 包含在 `path` 里，展示时由 UI 投影层用搜索根算出来（同一事实不留两份）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileManagerSearchOutcome {
    pub root: PathBuf,
    /// 这一次结果对应的查询原文（回声）。UI 用它与 `generation` 一起把迟到的
    /// 旧结果丢掉 —— 遍历跑在别的线程上，返回时用户可能已经改了词。
    pub query: String,
    pub hits: Vec<FileTreeNode>,
    /// 检视过的条目数（含未命中的）。用来区分「确实没有」和「还没扫到」。
    pub scanned: usize,
    /// 命中总数，可能大于 `hits.len()`（被 [`MAX_SEARCH_RESULTS`] 截断）。
    pub matched: usize,
    pub truncated: bool,
    pub cancelled: bool,
    /// 这一次是按什么范围扫的，随结果一起落到页签上（收窄判据要用）。
    pub scope: FileManagerSearchScope,
}

impl FileManagerSearchOutcome {
    /// 把一次遍历的结果变成页签上的搜索列表。
    ///
    /// 命中不带子文件名投影：那需要逐条目录再读一次盘，而结果页要的是「哪些条目命中了」，
    /// 不是每本的完整上下文。
    pub fn into_listing(self) -> FileManagerSearchListing {
        FileManagerSearchListing {
            root: self.root,
            query: self.query,
            entries: self
                .hits
                .into_iter()
                .map(|node| FileManagerEntry {
                    node,
                    children: Vec::new(),
                })
                .collect(),
            scanned: self.scanned,
            matched: self.matched,
            truncated: self.truncated,
            cancelled: self.cancelled,
            scope: self.scope,
        }
    }
}

/// 在搜索根（可选地连同子目录）里按名称找条目。
///
/// 三处刻意的设计：
///
/// 1. **广度优先**。搜索要的是「最近的命中」，深度优先会先钻到某一条分支的
///    最深处，撞上 [`MAX_SEARCH_RESULTS`] 上限时把同级的其它分支整个丢掉。
/// 2. **未命中的条目不付 syscall 代价**。`file_name()` 与 `file_type()` 来自目录
///    枚举本身，先按名字预筛，只有命中项和候选目录才构造完整节点（那才需要
///    `metadata()`）。整库扫一眼与逐条目 stat 的差距就在这里。
/// 3. **策略只有一个出口**。隐藏项、内部 bundle、「已识别媒体」的判定全部经由
///    [`crate::file_tree::node_for_dir_entry`]，所以搜索结果里不会出现列表里根本
///    不存在条目，反之也不会把列表能看到的漏掉。
///
/// `cancel` 在每条目与每目录两处检查；置位后已收集的结果照常交出。
pub fn search_entries(
    request: &FileManagerSearchRequest,
    cancel: &AtomicBool,
) -> FileManagerSearchOutcome {
    let settings = &request.settings;
    let tokens = crate::search_query::parse(&settings.search_query);
    let mode = if settings.search_or_mode {
        crate::search_query::MatchMode::Or
    } else {
        crate::search_query::MatchMode::And
    };
    let scope = FileManagerSearchScope::from_request(request);
    // 生效层数由范围算：遍历与「就地收窄」的判据读的是同一个值，不会各说各话。
    let max_depth = scope.max_depth;
    let show_hidden = settings.show_hidden_files;
    // 与列表同一口径：关掉路径匹配后，相对目录不参与命中，只看条目名。
    let in_path = settings.search_in_path;

    let mut queue = VecDeque::new();
    queue.push_back((request.root.clone(), 0usize, String::new()));
    // 环保护与上游 DFS 同一把键（canonicalize 后按平台决定大小写敏感性）。
    let mut visited: HashSet<String> = HashSet::new();
    let mut outcome = FileManagerSearchOutcome {
        root: request.root.clone(),
        query: settings.search_query.clone(),
        hits: Vec::new(),
        scanned: 0,
        matched: 0,
        truncated: false,
        cancelled: false,
        scope,
    };
    // 空查询**不是**「全量列出」。少了这道闸，一次误触（或一个忘了判空的调用方）
    // 就会把整棵目录树扫一遍再交出前 512 条 —— 那不是搜索结果，是磁盘遍历。
    if tokens.is_empty() {
        return outcome;
    }

    while let Some((directory, depth, relative)) = queue.pop_front() {
        if cancel.load(std::sync::atomic::Ordering::Relaxed) {
            outcome.cancelled = true;
            break;
        }
        if !crate::fs_entry::mark_directory_visited(&directory, &mut visited) {
            continue;
        }
        let Ok(entries) = std::fs::read_dir(&directory) else {
            // 权限 / 失效目录 / 竞态删除：跳过这一支，不把整次搜索作废。
            continue;
        };
        let descend = depth < max_depth;
        for entry in entries.flatten() {
            if cancel.load(std::sync::atomic::Ordering::Relaxed) {
                outcome.cancelled = true;
                break;
            }
            outcome.scanned += 1;
            let Ok(file_type) = entry.file_type() else {
                continue;
            };
            let raw_name = entry.file_name();
            let Some(name) = raw_name.to_str() else {
                continue;
            };
            // 目录即使不命中也要检视（下钻用）；符号链接目录要靠 classify 才认得出来。
            let candidate_dir = descend && (file_type.is_dir() || file_type.is_symlink());
            // 词元非空由上面的早退保证：空查询根本不进这里。
            let name_hit = {
                let hay = crate::search_norm::normalize_for_match(&search_hay_for_name(
                    name,
                    in_path.then_some(relative.as_str()),
                ));
                crate::search_query::matches_lowercased_with_mode(&tokens, &hay, mode)
            };
            if !name_hit && !candidate_dir {
                continue;
            }
            let Some(node) =
                crate::file_tree::node_for_dir_entry(&entry, &file_type, show_hidden, false)
            else {
                continue;
            };
            if candidate_dir && node.is_dir {
                let child_relative = if relative.is_empty() {
                    node.name.clone()
                } else {
                    format!("{relative}/{}", node.name)
                };
                queue.push_back((
                    Path::new(&node.path).to_path_buf(),
                    depth + 1,
                    child_relative,
                ));
            }
            if !name_hit || !entry_filter_matches(settings.entry_filter, &node) {
                continue;
            }
            outcome.matched += 1;
            if outcome.hits.len() >= MAX_SEARCH_RESULTS {
                outcome.truncated = true;
                break;
            }
            outcome.hits.push(node);
        }
        if outcome.truncated || outcome.cancelled {
            break;
        }
    }

    // 主序仍是用户的排序字段（与列表同一比较器）；同键时按「离搜索根更近」，
    // 例如两个不同目录里的同名 `001.jpg` —— 浅层的那本先出现。
    let depth_of = |node: &FileTreeNode| {
        Path::new(&node.path)
            .parent()
            .and_then(|parent| parent.strip_prefix(&outcome.root).ok())
            .map_or(0, |rel| rel.iter().count())
    };
    outcome.hits.sort_by(|left, right| {
        compare_entries(settings, left, right)
            .then_with(|| depth_of(left).cmp(&depth_of(right)))
            .then_with(|| left.path.cmp(&right.path))
    });
    outcome
}

/// 词元集合是否**只窄不宽** —— 新查询的命中集合必须是旧查询命中集合的子集。
///
/// - **include**：旧的每个 `t` 都要有新的 `u` 满足 `u` 含 `t`。名字里出现 `u` 就一定出现
///   `t`，所以旧池里没有的东西，新查询也不可能凭空多出来。
/// - **exclude**：旧的每个 `e` 都要有新的 `e'` 满足 `e` 含 `e'`。名字里出现 `e` 就一定出现
///   `e'`，于是旧里被排除掉的，在新里仍然被排除。
///
/// 任一条不成立就是**放宽**（删字、换词、去掉排除词），旧池不是超集，只能重新遍历 ——
/// 走捷径的代价是一份「看起来没毛病」的漏检结果。
fn narrows_only(
    previous: &[crate::search_query::Token],
    next: &[crate::search_query::Token],
) -> bool {
    if previous.is_empty() || next.is_empty() {
        return false;
    }
    // 方向与语义一致：include 要「新的更长」，exclude 要「旧的更长」。
    let covered = |old: &crate::search_query::Token| {
        next.iter().any(|new| {
            new.include == old.include
                && if old.include {
                    new.needle.contains(&old.needle)
                } else {
                    old.needle.contains(&new.needle)
                }
        })
    };
    previous.iter().all(covered)
}

/// 只在上一次的命中池里筛，回答这次的查询。返回 `None` 表示这次不能走捷径，必须重新遍历。
///
/// 「用户接着打字」是唯一不需要重新扫盘的常见情形：一次整库遍历在外挂盘上实测 5–12 秒，
/// 而搜索框每停一下就发一次请求。捷径成立要同时满足三件事：范围一个字没动、上一批既没被
/// 条数上限截断也没被中止（否则旧池本身不完整，筛出来的是漏检），以及查询只窄不宽
/// （[`narrows_only`]）。
pub fn refine_listing(
    listing: &FileManagerSearchListing,
    request: &FileManagerSearchRequest,
) -> Option<Vec<FileManagerEntry>> {
    if listing.truncated || listing.cancelled {
        return None;
    }
    if FileManagerSearchScope::from_request(request) != listing.scope {
        return None;
    }
    let settings = &request.settings;
    // OR 下「多打一个词」是放宽而不是收窄（命中的是并集），词元判据救不回来。
    if settings.search_or_mode {
        return None;
    }
    let previous = crate::search_query::parse(&listing.query);
    let next = crate::search_query::parse(&settings.search_query);
    if !narrows_only(&previous, &next) {
        return None;
    }
    let mut hits: Vec<FileManagerEntry> = listing
        .entries
        .iter()
        .filter(|entry| matches_entry(settings, &entry.node, &next, &listing.scope.root))
        .cloned()
        .collect();
    // 排序字段不属于范围，所以同键时的先后可能已经变了 —— 用列表同一个比较器重排一次。
    hits.sort_by(|left, right| compare_entries(settings, &left.node, &right.node));
    Some(hits)
}

pub(super) fn normalize_initial_directory(path: PathBuf) -> Option<PathBuf> {
    let path = std::path::absolute(path).ok()?;
    if path.is_dir() {
        return Some(path);
    }
    if path.is_file() {
        return path.parent().map(Path::to_path_buf);
    }
    None
}
