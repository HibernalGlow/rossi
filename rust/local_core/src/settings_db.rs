//! 设置持久化 SQLite 后端 (M-19)。
//!
//! 出处：`vendor/mimageviewer/src/settings_db.rs`（7231 行，SQLite 后端）与
//! `src/adjustment_db.rs` 的 `favorite_view_states` 表。
//!
//! 提供：
//! 1. `settings.db` 的 SQLite 键值表 `settings_kv`，用于持久化 `Settings` 的 common 正本；
//! 2. `favorite_view_states` 表，以 `(favorite_id, state_json)` 格式整组持久化位置专属视图状态；
//! 3. 路径前缀最长匹配（继承上级位置视图状态）；
//! 4. `file_manager_view_states` 表，以 `(path_key, state_json)` 格式持久化**文件管理器**
//!    每个目录的视图与排序（见 [`crate::file_manager::FileManagerViewState`]）。

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use anyhow::{Context, Result};
use rusqlite::{Connection, OptionalExtension, params};

use crate::file_manager::FileManagerViewState;
use crate::settings::{FavoriteViewState, Settings};

pub struct SettingsDb {
    conn: Mutex<Connection>,
    path: Option<PathBuf>,
}

impl SettingsDb {
    /// 打开或新建指定路径的 SQLite 数据库。
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let path_buf = path.as_ref().to_path_buf();
        let conn = Connection::open(&path_buf)
            .with_context(|| format!("打开设置数据库失败: {}", path_buf.display()))?;
        init_connection(&conn)?;
        init_schema(&conn)?;
        Ok(Self {
            conn: Mutex::new(conn),
            path: Some(path_buf),
        })
    }

    /// 内存数据库（测试与临时模式）。
    pub fn open_in_memory() -> Result<Self> {
        let conn = Connection::open_in_memory().context("创建内存设置数据库失败")?;
        init_connection(&conn)?;
        init_schema(&conn)?;
        Ok(Self {
            conn: Mutex::new(conn),
            path: None,
        })
    }

    pub fn path(&self) -> Option<&Path> {
        self.path.as_deref()
    }

    // ── 全局公共设置 (settings_kv) ───────────────────────────────────

    /// 保存全局设置。
    ///
    /// 核心规则：**保存时永远只保存 common 正本**。
    /// 若传入的 settings 带有 overlay，会先通过 `preferences_snapshot()` 剔除 overlay，
    /// 确保任何目录的局部修改与浏览状态绝不污染全局通用配置。
    pub fn save_settings(&self, settings: &Settings) -> Result<()> {
        let clean = settings.preferences_snapshot();
        let json = serde_json::to_string(&clean).context("序列化全局设置失败")?;
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO settings_kv (key, value) VALUES ('settings', ?1)
             ON CONFLICT(key) DO UPDATE SET value = ?1",
            params![json],
        )
        .context("写入 settings_kv 失败")?;
        Ok(())
    }

    /// 读取全局设置。如不存在则返回默认设置。
    pub fn load_settings(&self) -> Result<Settings> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn
            .prepare("SELECT value FROM settings_kv WHERE key = 'settings'")
            .context("准备查询 settings_kv 失败")?;
        let maybe_json: Option<String> = stmt
            .query_row([], |row| row.get(0))
            .optional()
            .context("执行查询 settings_kv 失败")?;

        match maybe_json {
            Some(json) => {
                let settings =
                    serde_json::from_str::<Settings>(&json).unwrap_or_else(|_| Settings::default());
                Ok(settings)
            }
            None => Ok(Settings::default()),
        }
    }

    // ── per-位置视图状态 (favorite_view_states) ──────────────────────

    /// 加载全部位置视图状态（应用启动时加载一次）。
    pub fn load_all_favorite_view_states(&self) -> Result<HashMap<String, FavoriteViewState>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn
            .prepare("SELECT favorite_id, state_json FROM favorite_view_states")
            .context("准备查询 favorite_view_states 失败")?;
        let rows = stmt
            .query_map([], |row| {
                let id: String = row.get(0)?;
                let json: String = row.get(1)?;
                Ok((id, json))
            })
            .context("查询 favorite_view_states 失败")?;

        let mut map = HashMap::new();
        for (id, json) in rows.flatten() {
            if let Ok(state) = serde_json::from_str::<FavoriteViewState>(&json) {
                map.insert(id, state);
            }
        }
        Ok(map)
    }

    /// 获取特定位置的视图状态。
    pub fn get_favorite_view_state(&self, favorite_id: &str) -> Result<Option<FavoriteViewState>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn
            .prepare("SELECT state_json FROM favorite_view_states WHERE favorite_id = ?1")
            .context("准备查询 favorite_view_states 失败")?;
        let maybe_json: Option<String> = stmt
            .query_row(params![favorite_id], |row| row.get(0))
            .optional()
            .context("查询 favorite_view_states 失败")?;

        match maybe_json {
            Some(json) => Ok(serde_json::from_str::<FavoriteViewState>(&json).ok()),
            None => Ok(None),
        }
    }

    /// 写入/更新特定位置的视图状态。
    pub fn set_favorite_view_state(
        &self,
        favorite_id: &str,
        state: &FavoriteViewState,
    ) -> Result<()> {
        let json = serde_json::to_string(state).context("序列化 FavoriteViewState 失败")?;
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO favorite_view_states (favorite_id, state_json) VALUES (?1, ?2)
             ON CONFLICT(favorite_id) DO UPDATE SET state_json = ?2",
            params![favorite_id, json],
        )
        .context("写入 favorite_view_states 失败")?;
        Ok(())
    }

    /// 删除特定位置的视图状态。
    pub fn remove_favorite_view_state(&self, favorite_id: &str) -> Result<bool> {
        let conn = self.conn.lock().unwrap();
        let affected = conn
            .execute(
                "DELETE FROM favorite_view_states WHERE favorite_id = ?1",
                params![favorite_id],
            )
            .context("删除 favorite_view_states 记录失败")?;
        Ok(affected > 0)
    }

    /// 清空全部位置视图状态。
    pub fn clear_favorite_view_states(&self) -> Result<usize> {
        let conn = self.conn.lock().unwrap();
        let affected = conn
            .execute("DELETE FROM favorite_view_states", [])
            .context("清空 favorite_view_states 失败")?;
        Ok(affected)
    }

    /// 剔除失效或不在保留集合里的位置视图状态。
    pub fn prune_favorite_view_states(&self, keep: &HashSet<String>) -> Result<usize> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn
            .prepare("SELECT favorite_id FROM favorite_view_states")
            .context("查询 favorite_ids 失败")?;
        let rows = stmt
            .query_map([], |row| row.get::<_, String>(0))
            .context("读取 favorite_ids 失败")?;

        let mut to_delete = Vec::new();
        for id in rows.flatten() {
            if !keep.contains(&id) {
                to_delete.push(id);
            }
        }

        let mut deleted = 0;
        for id in to_delete {
            deleted += conn.execute(
                "DELETE FROM favorite_view_states WHERE favorite_id = ?1",
                params![id],
            )?;
        }
        Ok(deleted)
    }

    // ── per-目录视图状态 (file_manager_view_states) ──────────────────

    /// 加载全部目录视图状态（新建文件管理器会话时加载一次）。
    ///
    /// 与 `favorite_view_states` 分表存放：那边是 viewer 的表示状態（网格列数、翻页方向），
    /// 这边是文件浏览器的视图与排序，两套字段口径不同，混存会让两者的字段一起长胖。
    pub fn load_all_file_manager_view_states(
        &self,
    ) -> Result<HashMap<String, FileManagerViewState>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn
            .prepare("SELECT path_key, state_json FROM file_manager_view_states")
            .context("准备查询 file_manager_view_states 失败")?;
        let rows = stmt
            .query_map([], |row| {
                let key: String = row.get(0)?;
                let json: String = row.get(1)?;
                Ok((key, json))
            })
            .context("查询 file_manager_view_states 失败")?;

        let mut map = HashMap::new();
        for (key, json) in rows.flatten() {
            // 单行解析失败只丢这一行：一个坏 JSON 不该让整个文件管理器回到默认视图。
            if let Ok(state) = serde_json::from_str::<FileManagerViewState>(&json) {
                map.insert(key, state);
            }
        }
        Ok(map)
    }

    /// 写入/更新单个目录的视图状态。
    pub fn set_file_manager_view_state(
        &self,
        path_key: &str,
        state: &FileManagerViewState,
    ) -> Result<()> {
        let json = serde_json::to_string(state).context("序列化 FileManagerViewState 失败")?;
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO file_manager_view_states (path_key, state_json) VALUES (?1, ?2)
             ON CONFLICT(path_key) DO UPDATE SET state_json = ?2",
            params![path_key, json],
        )
        .context("写入 file_manager_view_states 失败")?;
        Ok(())
    }

    /// 清空全部目录视图状态。
    pub fn clear_file_manager_view_states(&self) -> Result<usize> {
        let conn = self.conn.lock().unwrap();
        let affected = conn
            .execute("DELETE FROM file_manager_view_states", [])
            .context("清空 file_manager_view_states 失败")?;
        Ok(affected)
    }

    /// 剔除不在保留集合里的目录视图状态（目录已被删除/改名时用）。
    pub fn prune_file_manager_view_states(&self, keep: &HashSet<String>) -> Result<usize> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn
            .prepare("SELECT path_key FROM file_manager_view_states")
            .context("查询 path_keys 失败")?;
        let rows = stmt
            .query_map([], |row| row.get::<_, String>(0))
            .context("读取 path_keys 失败")?;

        let mut to_delete = Vec::new();
        for key in rows.flatten() {
            if !keep.contains(&key) {
                to_delete.push(key);
            }
        }

        let mut deleted = 0;
        for key in to_delete {
            deleted += conn.execute(
                "DELETE FROM file_manager_view_states WHERE path_key = ?1",
                params![key],
            )?;
        }
        Ok(deleted)
    }
}

/// 目录视图状态表的键：只统一分隔符与末尾分隔符，**保留大小写**。
///
/// 为什么不做小写化折叠：Linux/Android 上 `/Photos` 与 `/photos` 可以是两个真实存在的
/// 不同目录，折叠会把它们并成一条记录，表现为「改了一个目录，另一个目录跟着变」。
/// （`path_key::normalize_keep_drive` 是给缩略图目录库用的，那边按内容哈希取值，容得下折叠。）
pub fn view_state_key(path: &Path) -> String {
    let unified = path.to_string_lossy().replace('\\', "/");
    let trimmed = unified.trim_end_matches('/');
    if trimmed.is_empty() {
        // `/` 或 `\\`：根不能变成空串，否则前缀匹配会认为任何路径都是它的子路径。
        "/".to_string()
    } else if trimmed.ends_with(':') {
        // Windows 盘根 `C:\` → `C:/`：同样保留成根形态。
        format!("{trimmed}/")
    } else {
        trimmed.to_string()
    }
}

/// 对指定路径查找最长匹配的位置专属视图状态（最长前缀继承机制）。
///
/// 规则：
/// - 若 `path` 完全等于已记忆位置，或在某已记忆位置的子目录下，则判定为匹配；
/// - 若命中多个（例如 `/photos` 与 `/photos/manga`），选择路径深度最深（最长）的项；
/// - 比较前两侧都过 [`view_state_key`]，因此 `C:\Foo\` 与 `C:/Foo` 是同一个位置。
///
/// 泛型是为了让 viewer 的 `FavoriteViewState` 与文件管理器的
/// [`FileManagerViewState`] 共用同一套匹配规则，不必各写一份前缀逻辑。
pub fn resolve_view_state_for_path<T: Clone>(
    path: &Path,
    states: &HashMap<String, T>,
) -> Option<(String, T)> {
    let query = PathBuf::from(view_state_key(path));
    let mut best_key: Option<String> = None;
    let mut best_len = 0usize;

    for key in states.keys() {
        let saved_path = PathBuf::from(view_state_key(Path::new(key)));
        if query.starts_with(&saved_path) {
            let len = saved_path.as_os_str().len();
            if best_key.is_none() || len > best_len {
                best_key = Some(key.clone());
                best_len = len;
            }
        }
    }

    best_key.and_then(|key| states.get(&key).map(|s| (key, s.clone())))
}

fn init_connection(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "PRAGMA journal_mode = WAL;
         PRAGMA synchronous = NORMAL;
         PRAGMA busy_timeout = 5000;",
    )
    .context("配置 SQLite 连接参数失败")?;
    Ok(())
}

fn init_schema(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS schema_meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
         );
         CREATE TABLE IF NOT EXISTS settings_kv (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
         );
         CREATE TABLE IF NOT EXISTS favorite_view_states (
            favorite_id TEXT PRIMARY KEY,
            state_json TEXT NOT NULL
         );
         CREATE TABLE IF NOT EXISTS file_manager_view_states (
            path_key TEXT PRIMARY KEY,
            state_json TEXT NOT NULL
         );",
    )
    .context("初始化设置数据库 schema 失败")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::settings::{GridViewMode, SortOrder, SpreadMode, ThumbAspect};

    #[test]
    fn test_settings_db_roundtrip_and_overlay_isolation() {
        let db = SettingsDb::open_in_memory().unwrap();

        let mut settings = Settings::default();
        settings.grid_cols = 4;
        settings.sort_order = SortOrder::Numeric;
        db.save_settings(&settings).unwrap();

        let loaded = db.load_settings().unwrap();
        assert_eq!(loaded.grid_cols, 4);
        assert_eq!(loaded.sort_order, SortOrder::Numeric);

        // 模拟给 settings 加上 overlay 并修改字段
        let mut overlay_state = FavoriteViewState::from_settings(&loaded);
        overlay_state.grid_cols = 10;
        overlay_state.grid_view_mode = GridViewMode::Details;
        settings.apply_favorite_view_overlay("/manga", &overlay_state);
        assert_eq!(settings.grid_cols, 10);

        // 保存时必须隔离 overlay，落盘的一定是 common (grid_cols: 4)
        db.save_settings(&settings).unwrap();

        let reloaded = db.load_settings().unwrap();
        assert_eq!(reloaded.grid_cols, 4);
        assert!(reloaded.favorite_view_overlay.is_none());
    }

    #[test]
    fn test_favorite_view_states_crud_and_prune() {
        let db = SettingsDb::open_in_memory().unwrap();

        let mut state_a = FavoriteViewState::from_settings(&Settings::default());
        state_a.grid_cols = 3;
        state_a.thumb_aspect = ThumbAspect::Portrait2x3;

        let mut state_b = FavoriteViewState::from_settings(&Settings::default());
        state_b.grid_cols = 6;
        state_b.default_spread_mode = SpreadMode::Rtl;

        db.set_favorite_view_state("/folder/a", &state_a).unwrap();
        db.set_favorite_view_state("/folder/b", &state_b).unwrap();

        let all = db.load_all_favorite_view_states().unwrap();
        assert_eq!(all.len(), 2);
        assert_eq!(all.get("/folder/a").unwrap().grid_cols, 3);
        assert_eq!(all.get("/folder/b").unwrap().grid_cols, 6);

        // 单个查询
        let fetched = db.get_favorite_view_state("/folder/a").unwrap().unwrap();
        assert_eq!(fetched.thumb_aspect, ThumbAspect::Portrait2x3);

        // prune 测试
        let mut keep = HashSet::new();
        keep.insert("/folder/a".to_string());
        let deleted = db.prune_favorite_view_states(&keep).unwrap();
        assert_eq!(deleted, 1);
        assert!(db.get_favorite_view_state("/folder/b").unwrap().is_none());
        assert!(db.get_favorite_view_state("/folder/a").unwrap().is_some());

        // clear
        let cleared = db.clear_favorite_view_states().unwrap();
        assert_eq!(cleared, 1);
        assert!(db.load_all_favorite_view_states().unwrap().is_empty());
    }

    #[test]
    fn test_resolve_view_state_for_path_longest_prefix() {
        let mut states = HashMap::new();

        let mut root_state = FavoriteViewState::from_settings(&Settings::default());
        root_state.grid_cols = 3;
        states.insert("/library".to_string(), root_state);

        let mut sub_state = FavoriteViewState::from_settings(&Settings::default());
        sub_state.grid_cols = 7;
        states.insert("/library/comics/series_a".to_string(), sub_state);

        // 1. 完全匹配
        let matched = resolve_view_state_for_path(Path::new("/library"), &states);
        assert_eq!(matched.as_ref().map(|s| s.0.as_str()), Some("/library"));
        assert_eq!(matched.unwrap().1.grid_cols, 3);

        // 2. 匹配子目录但无更深配置时，继承最近祖先配置
        let matched_sub = resolve_view_state_for_path(Path::new("/library/general"), &states);
        assert_eq!(matched_sub.unwrap().1.grid_cols, 3);

        // 3. 存在更深专属配置时，选择最长前缀
        let matched_deep =
            resolve_view_state_for_path(Path::new("/library/comics/series_a/vol1"), &states);
        assert_eq!(
            matched_deep.as_ref().map(|s| s.0.as_str()),
            Some("/library/comics/series_a")
        );
        assert_eq!(matched_deep.unwrap().1.grid_cols, 7);

        // 4. 无关路径
        let unmatched = resolve_view_state_for_path(Path::new("/other/path"), &states);
        assert!(unmatched.is_none());
    }

    #[test]
    fn view_state_key_unifies_separators_without_folding_case() {
        assert_eq!(
            view_state_key(Path::new("/library/comics/")),
            "/library/comics"
        );
        assert_eq!(
            view_state_key(Path::new(r"C:\Library\Comics")),
            "C:/Library/Comics"
        );
        // 根不能被裁剪成空串：空前缀会命中一切路径。
        assert_eq!(view_state_key(Path::new("/")), "/");
        assert_eq!(view_state_key(Path::new(r"C:\")), "C:/");
        // 大小写是位置的一部分，不折叠。
        assert_ne!(
            view_state_key(Path::new("/Photos")),
            view_state_key(Path::new("/photos"))
        );
    }

    #[test]
    fn trailing_separator_and_windows_slashes_hit_the_same_row() {
        let mut states = HashMap::new();
        states.insert(
            view_state_key(Path::new("/library/comics")),
            FileManagerViewState::from_settings(
                &crate::file_manager::FileManagerSettings::default(),
            ),
        );

        assert!(resolve_view_state_for_path(Path::new("/library/comics/"), &states).is_some());
        assert!(resolve_view_state_for_path(Path::new("/library/comics/vol1"), &states).is_some());
        // 同前缀但不同目录：`/library/comics2` 不是子目录。
        assert!(resolve_view_state_for_path(Path::new("/library/comics2"), &states).is_none());
    }

    #[test]
    fn file_manager_view_states_roundtrip_prune_and_longest_prefix() {
        let db = SettingsDb::open_in_memory().unwrap();
        let root_key = view_state_key(Path::new("/library"));
        let deep_key = view_state_key(Path::new("/library/comics/series_a"));

        let mut root_state = FileManagerViewState::from_settings(
            &crate::file_manager::FileManagerSettings::default(),
        );
        root_state.view_mode = crate::file_manager::ViewMode::CoverList;
        let mut deep_state = root_state.clone();
        deep_state.view_mode = crate::file_manager::ViewMode::MosaicGrid;
        deep_state.entry_filter = crate::file_manager::EntryFilter::Images;

        db.set_file_manager_view_state(&root_key, &root_state)
            .unwrap();
        db.set_file_manager_view_state(&deep_key, &deep_state)
            .unwrap();

        let all = db.load_all_file_manager_view_states().unwrap();
        assert_eq!(all.len(), 2);
        // 视图模式必须逐字往返：不再是 reader 那套两档有损映射。
        assert_eq!(
            all.get(&root_key).unwrap().view_mode,
            crate::file_manager::ViewMode::CoverList
        );
        assert_eq!(
            all.get(&deep_key).unwrap().view_mode,
            crate::file_manager::ViewMode::MosaicGrid
        );

        // 最长前缀：`/library/comics/series_a/vol1` 命中更深的 series_a。
        let matched =
            resolve_view_state_for_path(Path::new("/library/comics/series_a/vol1"), &all).unwrap();
        assert_eq!(matched.0, deep_key);
        assert_eq!(
            matched.1.entry_filter,
            crate::file_manager::EntryFilter::Images
        );

        // prune 只留根目录那一条。
        let mut keep = HashSet::new();
        keep.insert(root_key.clone());
        assert_eq!(db.prune_file_manager_view_states(&keep).unwrap(), 1);
        assert!(db.load_all_file_manager_view_states().unwrap().len() == 1);

        assert_eq!(db.clear_file_manager_view_states().unwrap(), 1);
        assert!(db.load_all_file_manager_view_states().unwrap().is_empty());
    }
}
