//! 本地上下本导航。游标保存打开来源与分支栈，文件卡片换目录/页签不改变阅读顺序。
//! 交互参照 Neo 的分层遍历，排序、文件分类与循环身份沿用本地核心的 mImageViewer 能力。

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

use anyhow::{Result, bail};
use serde::{Deserialize, Serialize};

use crate::file_manager::{
    FileManagerSettings, FileManagerState, FileManagerViewState, compare_entries,
};
use crate::file_tree::{FileTreeNode, list_directory_with_hidden};
use crate::folder_tree::path_eq;

const MAX_DEPTH: usize = 32;
const MAX_VISITS: usize = 4096;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BookFrame {
    directory: PathBuf,
    entry: PathBuf,
    /// 该目录的直属媒体先作为一本，之后才能进入它的子书。
    self_terminal: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BookNavigation {
    source: PathBuf,
    frames: Vec<BookFrame>,
    /// 开书时的可见列表（含搜索、筛选及排序）；无需让浏览器会话一直活着。
    root_entries: Option<Vec<PathBuf>>,
    view: FileManagerViewState,
    penetration: bool,
}

impl BookNavigation {
    pub fn from_browser(state: &FileManagerState, activated: &Path, source: &Path) -> Result<Self> {
        // 上下本是 Neo 的目录级服务：搜索词与类型筛选只影响文件卡片当前这一屏，
        // 不应把书架筛选误当成阅读顺序。复用核心的隐藏项与排序设置，但重新枚举
        // 当前目录的完整书目。
        let mut listing =
            list_directory_with_hidden(state.active_path(), state.settings().show_hidden_files)?;
        listing.sort_by(|left, right| compare_entries(state.settings(), left, right));
        let entries: Vec<PathBuf> = listing.into_iter().map(|entry| entry.path.into()).collect();
        let root_entry = entries
            .iter()
            .find(|path| path_eq(path, activated))
            .or_else(|| {
                entries
                    .iter()
                    .filter(|path| activated.starts_with(path))
                    .max_by_key(|path| path.components().count())
            });
        let Some(root_entry) = root_entry else {
            return Ok(Self::standalone(source));
        };
        let mut frames = vec![BookFrame {
            directory: state.active_path().to_path_buf(),
            entry: root_entry.clone(),
            self_terminal: path_eq(root_entry, source) && source.is_dir(),
        }];
        // 点击子文件名时记录每一层；不能把深层文件冒充为根列表的一个条目。
        // `source` 是穿透后真正交给 Reader 的终点。用 activated 只会留下根目录一帧，
        // 下一本回退时就无法知道已经走过哪一层分支。
        let leaf = source;
        if let Ok(relative) = leaf.strip_prefix(root_entry) {
            let mut directory = root_entry.clone();
            for part in relative.components() {
                let entry = directory.join(part);
                frames.push(BookFrame {
                    directory,
                    self_terminal: path_eq(&entry, source) && source.is_dir(),
                    entry: entry.clone(),
                });
                directory = entry;
            }
        }
        Ok(Self {
            source: source.to_path_buf(),
            frames,
            root_entries: Some(entries),
            view: FileManagerViewState::from_settings(state.settings()),
            penetration: state.settings().penetration_enabled,
        })
    }

    pub fn standalone(source: &Path) -> Self {
        Self {
            source: source.to_path_buf(),
            frames: vec![BookFrame {
                directory: source.parent().unwrap_or(source).to_path_buf(),
                entry: source.to_path_buf(),
                self_terminal: source.is_dir(),
            }],
            root_entries: None,
            view: FileManagerViewState::from_settings(&FileManagerSettings::default()),
            penetration: false,
        }
    }

    pub fn source(&self) -> &Path {
        &self.source
    }

    pub fn adjacent(&self, source: &Path, forward: bool) -> Result<Option<Self>> {
        // 独立图片是页而不是书；过期的上下文也不能套在另一份来源上。
        if !path_eq(source, &self.source) {
            bail!("上下本导航与当前阅读来源不匹配");
        }
        if source.is_file()
            && crate::folder_tree::is_recognized_image_ext(
                source
                    .extension()
                    .and_then(|ext| ext.to_str())
                    .unwrap_or_default()
                    .to_ascii_lowercase()
                    .as_str(),
            )
        {
            return Ok(None);
        }
        if self.frames.is_empty() || self.frames.len() > MAX_DEPTH {
            bail!("上下本导航层数超出限制");
        }
        let mut walker = Walker::new(self);
        for index in (0..self.frames.len()).rev() {
            let frame = &self.frames[index];
            if self.penetration && frame.self_terminal {
                if !forward && index + 1 < self.frames.len() {
                    return Ok(Some(
                        self.at(frame.entry.clone(), self.frames[..=index].to_vec()),
                    ));
                }
                if forward && index + 1 == self.frames.len() {
                    if let Some(found) =
                        walker.scan(&frame.entry, None, true, &self.frames[..=index], true)?
                    {
                        return Ok(Some(found));
                    }
                }
            }
            let owns_media = index > 0 && self.frames[index - 1].self_terminal;
            if let Some(found) = walker.scan(
                &frame.directory,
                Some(&frame.entry),
                forward,
                &self.frames[..index],
                owns_media,
            )? {
                return Ok(Some(found));
            }
        }
        Ok(None)
    }

    fn at(&self, source: PathBuf, frames: Vec<BookFrame>) -> Self {
        Self {
            source,
            frames,
            ..self.clone()
        }
    }
}

struct Walker<'a> {
    navigation: &'a BookNavigation,
    settings: FileManagerSettings,
    listings: HashMap<PathBuf, Vec<FileTreeNode>>,
    visits: usize,
}

impl<'a> Walker<'a> {
    fn new(navigation: &'a BookNavigation) -> Self {
        let mut settings = FileManagerSettings::default();
        navigation.view.apply_to_settings(&mut settings);
        Self {
            navigation,
            settings,
            listings: HashMap::new(),
            visits: 0,
        }
    }

    fn entries(&mut self, path: &Path) -> Result<Vec<FileTreeNode>> {
        if let Some(entries) = self.listings.get(path) {
            return Ok(entries.clone());
        }
        self.visits += 1;
        if self.visits > MAX_VISITS {
            bail!("上下本查找超过 {MAX_VISITS} 个条目，请从更具体的目录打开");
        }
        let mut entries = list_directory_with_hidden(path, self.settings.show_hidden_files)?;
        entries.sort_by(|a, b| compare_entries(&self.settings, a, b));
        self.listings.insert(path.to_path_buf(), entries.clone());
        Ok(entries)
    }

    fn scan(
        &mut self,
        directory: &Path,
        after: Option<&Path>,
        forward: bool,
        parents: &[BookFrame],
        owns_media: bool,
    ) -> Result<Option<BookNavigation>> {
        let entries = if parents.is_empty() {
            match &self.navigation.root_entries {
                Some(entries) => entries.clone(),
                None => self
                    .entries(directory)?
                    .into_iter()
                    .map(|e| e.path.into())
                    .collect(),
            }
        } else {
            self.entries(directory)?
                .into_iter()
                .map(|e| e.path.into())
                .collect()
        };
        let start = match after {
            Some(current) => match entries.iter().position(|entry| path_eq(entry, current)) {
                Some(index) => index as isize + if forward { 1 } else { -1 },
                None => return Ok(None),
            },
            None => {
                if forward {
                    0
                } else {
                    entries.len() as isize - 1
                }
            }
        };
        let mut index = start;
        while index >= 0 && (index as usize) < entries.len() {
            let entry = &entries[index as usize];
            self.visits += 1;
            if self.visits > MAX_VISITS {
                bail!("上下本查找超过 {MAX_VISITS} 个条目");
            }
            let mut frames = parents.to_vec();
            frames.push(BookFrame {
                directory: directory.into(),
                entry: entry.clone(),
                self_terminal: false,
            });
            if entry.is_dir() {
                if let Some(candidate) = self.directory(entry, forward, frames)? {
                    return Ok(Some(candidate));
                }
            } else if entry.is_file()
                && (crate::file_tree::is_comic_archive_path(entry)
                    || (!owns_media && crate::page_order::is_video_name(&entry.to_string_lossy())))
            {
                return Ok(Some(self.navigation.at(entry.clone(), frames)));
            }
            index += if forward { 1 } else { -1 };
        }
        Ok(None)
    }

    fn directory(
        &mut self,
        path: &Path,
        forward: bool,
        mut frames: Vec<BookFrame>,
    ) -> Result<Option<BookNavigation>> {
        if frames.len() >= MAX_DEPTH {
            bail!(
                "上下本查找已达到 {MAX_DEPTH} 层目录限制：{}",
                path.display()
            );
        }
        // canonicalize 身份只用于防循环，游标仍保留用户打开的路径与顺序。
        let mut ancestors = HashSet::new();
        for directory in frames
            .iter()
            .map(|frame| frame.directory.as_path())
            .chain(std::iter::once(path))
        {
            let key = directory
                .canonicalize()?
                .to_string_lossy()
                .to_ascii_lowercase();
            if !ancestors.insert(key) {
                bail!("上下本查找遇到循环目录：{}", path.display());
            }
        }
        let entries = self.entries(path)?;
        let directories = entries.iter().filter(|entry| entry.is_dir).count();
        let archives = entries.iter().filter(|entry| entry.is_archive).count();
        let media = entries
            .iter()
            .filter(|entry| entry.is_image || entry.is_video)
            .count();
        if self.navigation.penetration && directories == 0 && archives == 1 {
            let archive = entries.iter().find(|entry| entry.is_archive).unwrap();
            let mut archive_frames = frames;
            archive_frames.push(BookFrame {
                directory: path.to_path_buf(),
                entry: archive.path.clone().into(),
                self_terminal: false,
            });
            return Ok(Some(
                self.navigation
                    .at(archive.path.clone().into(), archive_frames),
            ));
        }
        // 单一归档允许封面并存；纯媒体与 Neo 的混合目录作为一本。
        let terminal =
            (directories == 0 && archives == 0 && media > 0) || (directories > 0 && media >= 2);
        if terminal {
            frames.last_mut().unwrap().self_terminal = true;
            if !forward && self.navigation.penetration {
                if let Some(child) = self.scan(path, None, false, &frames, true)? {
                    return Ok(Some(child));
                }
            }
            return Ok(Some(self.navigation.at(path.to_path_buf(), frames)));
        }
        if !self.navigation.penetration {
            // 普通模式只读相邻目录直属媒体，不展开分支或唯一归档链。
            return Ok((media > 0).then(|| self.navigation.at(path.to_path_buf(), frames)));
        }
        self.scan(path, None, forward, &frames, false)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::file_manager::FileManagerState;
    use tempfile::tempdir;

    fn touch(path: &Path) {
        std::fs::write(path, b"placeholder").unwrap();
    }

    #[test]
    fn penetrated_branch_keeps_root_order_across_next_and_previous() {
        let root = tempdir().unwrap();
        let a = root.path().join("A");
        let b = root.path().join("B");
        std::fs::create_dir_all(&a).unwrap();
        std::fs::create_dir_all(&b).unwrap();
        let a1 = a.join("book-1.cbz");
        let a2 = a.join("book-2.cbz");
        let b1 = b.join("book-3.cbz");
        touch(&a1);
        touch(&a2);
        touch(&b1);

        let mut browser = FileManagerState::new(Some(root.path().into())).unwrap();
        browser.set_penetration_enabled(true);
        let navigation = BookNavigation::from_browser(&browser, &a, &a1).unwrap();

        let second = navigation.adjacent(&a1, true).unwrap().unwrap();
        assert_eq!(second.source(), a2.as_path());
        let third = second.adjacent(&a2, true).unwrap().unwrap();
        assert_eq!(third.source(), b1.as_path());
        let back = third.adjacent(&b1, false).unwrap().unwrap();
        assert_eq!(back.source(), a2.as_path());
    }

    #[test]
    fn mixed_media_directory_reads_direct_pages_before_nested_books() {
        let root = tempdir().unwrap();
        let mixed = root.path().join("mixed");
        let nested = mixed.join("volumes");
        std::fs::create_dir_all(&nested).unwrap();
        touch(&mixed.join("001.jpg"));
        touch(&mixed.join("002.jpg"));
        let nested_book = nested.join("book.cbz");
        touch(&nested_book);

        let mut browser = FileManagerState::new(Some(root.path().into())).unwrap();
        browser.set_penetration_enabled(true);
        let navigation = BookNavigation::from_browser(&browser, &mixed, &mixed).unwrap();
        let child = navigation.adjacent(&mixed, true).unwrap().unwrap();
        assert_eq!(child.source(), nested_book.as_path());
        let parent = child.adjacent(&nested_book, false).unwrap().unwrap();
        assert_eq!(parent.source(), mixed.as_path());
    }

    #[test]
    fn shelf_ends_return_none_instead_of_wrapping() {
        let root = tempdir().unwrap();
        let a = root.path().join("A");
        let b = root.path().join("B");
        std::fs::create_dir_all(&a).unwrap();
        std::fs::create_dir_all(&b).unwrap();
        let first = a.join("book-1.cbz");
        let last = b.join("book-2.cbz");
        touch(&first);
        touch(&last);

        let mut browser = FileManagerState::new(Some(root.path().into())).unwrap();
        browser.set_penetration_enabled(true);
        let opening = BookNavigation::from_browser(&browser, &a, &first).unwrap();
        // 第一本没有上一本；最后一本没有下一本 —— 都不许回绕成另一端。
        assert!(opening.adjacent(&first, false).unwrap().is_none());

        let closing = opening.adjacent(&first, true).unwrap().unwrap();
        assert_eq!(closing.source(), last.as_path());
        assert!(closing.adjacent(&last, true).unwrap().is_none());
        assert_eq!(
            closing.adjacent(&last, false).unwrap().unwrap().source(),
            first.as_path()
        );
    }

    #[test]
    fn standalone_image_is_a_page_not_a_book() {
        let root = tempdir().unwrap();
        let single = root.path().join("001.jpg");
        let sibling = root.path().join("002.jpg");
        touch(&single);
        touch(&sibling);

        // 单张散图按原样阅读，不接管上下本；游标与来源不符时也必须拒绝。
        let navigation = BookNavigation::standalone(&single);
        assert!(navigation.adjacent(&single, true).unwrap().is_none());
        assert!(navigation.adjacent(&sibling, true).is_err());
    }
}
