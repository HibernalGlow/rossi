use std::collections::{HashMap, HashSet};
use std::path::Path;
use std::sync::Mutex;

use rusqlite::{Connection, OpenFlags, OptionalExtension, TransactionBehavior, params};

mod cache_store;
mod db;
mod thumbnail;

pub use cache_store::*;
pub use thumbnail::*;

const CATALOG_VERSION: &str = "2";
const PDF_LAYOUT_DIMS_META_KEY: &str = "pdf_layout_dims_version";
const PDF_LAYOUT_DIMS_VERSION: &str = "2";

// -----------------------------------------------------------------------
// 缓存条目
// -----------------------------------------------------------------------

#[derive(Clone)]
pub struct CacheEntry {
    pub mtime: i64,
    pub file_size: i64,
    pub jpeg_data: Vec<u8>,
    /// 原图 / PDF 缩略图栅格的像素尺寸（宽, 高）。
    /// 旧版本保存的条目里是 NULL，因此用 Option 表示。
    pub source_dims: Option<(u32, u32)>,
    /// 不依赖栅格整数取整的布局尺寸。PDF page box 以 1/1000 point 为单位
    /// 保留。普通图像与旧条目为 NULL。
    pub layout_dims: Option<(u32, u32)>,
}

fn valid_dims(width: Option<u32>, height: Option<u32>) -> Option<(u32, u32)> {
    match (width, height) {
        (Some(width), Some(height)) if width > 0 && height > 0 => Some((width, height)),
        _ => None,
    }
}

/// ZIP / 仅含图片的文件夹 / 需转换归档的页数缓存类别。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ContainerPageKind {
    Folder = 1,
    Zip = 2,
    Archive = 3,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ContainerPageMeta {
    /// `None` 表示扫描成功，但该对象并非应作为书处理的目标。
    pub page_count: Option<u32>,
}

// -----------------------------------------------------------------------
// CatalogDb
// -----------------------------------------------------------------------

pub struct CatalogDb {
    conn: Mutex<Connection>,
    has_layout_dims_columns: bool,
}

/// 修改 journal mode 需要排他锁，因此 **`busy_timeout` 不起作用**。SQLite 为了
/// 避免死锁不会等待这个冲突，而是立即返回 `SQLITE_BUSY` (`database is locked`)。
///
/// mode 会持久化到文件里，因此**只有创建时的那 1 次是必要的**。可以往每次打开都
/// 会执行一次，若打开列表的瞬间 12 个缩略图 worker 涌向同一个新建 catalog，
/// 就有几个会立即失败 (2026-08-13 的实际受损: 列表里 2 张图一直停留在符号上。也不会再重新请求)。
///
/// 若已是 WAL 则先什么都不做。这样第 2 次及以后的 open 就不会去取锁。只在需要转换
/// 时串行化，若别处已先完成转换，那目的就已经达到了。
fn ensure_wal_journal(conn: &Connection) -> rusqlite::Result<()> {
    if journal_mode_is_wal(conn)? {
        return Ok(());
    }
    // 同一进程内的冲突在这里消除。与其它进程的冲突靠下面的再次确认来兜住。
    static CONVERT: Mutex<()> = Mutex::new(());
    let _serialized = CONVERT.lock().unwrap_or_else(|error| error.into_inner());
    if journal_mode_is_wal(conn)? {
        return Ok(());
    }
    match conn.execute_batch("PRAGMA journal_mode=WAL;") {
        Ok(()) => Ok(()),
        Err(error) if journal_mode_is_wal(conn).unwrap_or(false) => {
            let _ = error;
            Ok(())
        }
        Err(error) => Err(error),
    }
}

fn journal_mode_is_wal(conn: &Connection) -> rusqlite::Result<bool> {
    let mode: String = conn.query_row("PRAGMA journal_mode", [], |row| row.get(0))?;
    Ok(mode.eq_ignore_ascii_case("wal"))
}

fn init_schema(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS meta (
             key   TEXT PRIMARY KEY,
             value TEXT NOT NULL
         );
         CREATE TABLE IF NOT EXISTS thumbnails (
             filename       TEXT    NOT NULL PRIMARY KEY,
             mtime          INTEGER NOT NULL,
             file_size      INTEGER NOT NULL,
             width          INTEGER NOT NULL,
             height         INTEGER NOT NULL,
             thumb_data     BLOB    NOT NULL,
             source_width   INTEGER,
             source_height  INTEGER,
             layout_width   INTEGER,
             layout_height  INTEGER
         );
         CREATE TABLE IF NOT EXISTS pdf_meta (
             filename          TEXT    NOT NULL PRIMARY KEY,
             mtime             INTEGER NOT NULL,
             file_size         INTEGER NOT NULL,
             page_count        INTEGER NOT NULL,
             password_required INTEGER NOT NULL DEFAULT 0
         );
         CREATE TABLE IF NOT EXISTS container_page_meta (
             filename       TEXT    NOT NULL,
             kind           INTEGER NOT NULL,
             mtime          INTEGER NOT NULL,
             file_size      INTEGER NOT NULL,
             fingerprint    INTEGER NOT NULL,
             page_count     INTEGER,
             PRIMARY KEY(filename, kind)
         );",
    )?;
    // 非破坏性迁移。避免每次 open 都留下 ALTER 失败日志，仅当并发 open 同时
    // 观测到 missing 时，才把 duplicate column 当作幂等成功处理。
    add_thumbnail_column_if_missing(
        conn,
        "source_width",
        "ALTER TABLE thumbnails ADD COLUMN source_width INTEGER",
    )?;
    add_thumbnail_column_if_missing(
        conn,
        "source_height",
        "ALTER TABLE thumbnails ADD COLUMN source_height INTEGER",
    )?;
    add_thumbnail_column_if_missing(
        conn,
        "layout_width",
        "ALTER TABLE thumbnails ADD COLUMN layout_width INTEGER",
    )?;
    add_thumbnail_column_if_missing(
        conn,
        "layout_height",
        "ALTER TABLE thumbnails ADD COLUMN layout_height INTEGER",
    )?;

    // 版本不一致（schema 变更）时全量删除并重新生成
    let version: Option<String> = conn
        .query_row("SELECT value FROM meta WHERE key = 'version'", [], |r| {
            r.get(0)
        })
        .ok();
    if version.as_deref() != Some(CATALOG_VERSION) {
        conn.execute_batch("DELETE FROM thumbnails;")?;
        conn.execute(
            "INSERT OR REPLACE INTO meta (key, value) VALUES ('version', ?1)",
            params![CATALOG_VERSION],
        )?;
    }
    Ok(())
}

/// Released catalogs store PDF thumbnail raster pixels in `source_*`, but do not
/// contain the page box needed for exact layout. The short-lived development
/// schema version 1 instead wrote page-box units into `source_*`. Neither row can
/// be upgraded from the cached WebP alone, so invalidate only PDF-derived rows
/// once and regenerate both independent dimension pairs.
///
/// A catalog whose owner is a PDF contains its virtual `page_NNNN` rows only;
/// ordinary folder catalogs may contain `pdfthumb:` representative rows beside
/// unrelated image/ZIP entries, which must remain intact.
fn migrate_pdf_layout_dims(conn: &mut Connection, folder_path: &Path) -> rusqlite::Result<()> {
    let current: Option<String> = conn
        .query_row(
            "SELECT value FROM meta WHERE key = ?1",
            [PDF_LAYOUT_DIMS_META_KEY],
            |row| row.get(0),
        )
        .optional()?;
    if current.as_deref() == Some(PDF_LAYOUT_DIMS_VERSION) {
        return Ok(());
    }

    let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;
    // Another opener may have completed the migration while this connection
    // waited for the write lock. Recheck under the transaction before deleting.
    let version: Option<String> = tx
        .query_row(
            "SELECT value FROM meta WHERE key = ?1",
            [PDF_LAYOUT_DIMS_META_KEY],
            |row| row.get(0),
        )
        .optional()?;
    if version.as_deref() == Some(PDF_LAYOUT_DIMS_VERSION) {
        return tx.commit();
    }
    let is_pdf_catalog = folder_path
        .extension()
        .and_then(|ext| ext.to_str())
        .is_some_and(|ext| ext.eq_ignore_ascii_case("pdf"));
    if is_pdf_catalog {
        tx.execute("DELETE FROM thumbnails", [])?;
    } else {
        tx.execute(
            "DELETE FROM thumbnails WHERE filename LIKE 'pdfthumb:%'",
            [],
        )?;
    }
    tx.execute(
        "INSERT OR REPLACE INTO meta (key, value) VALUES (?1, ?2)",
        params![PDF_LAYOUT_DIMS_META_KEY, PDF_LAYOUT_DIMS_VERSION],
    )?;
    tx.commit()
}

fn add_thumbnail_column_if_missing(
    conn: &Connection,
    column: &str,
    alter_sql: &str,
) -> rusqlite::Result<()> {
    if thumbnail_column_exists(conn, column)? {
        return Ok(());
    }
    match conn.execute(alter_sql, []) {
        Ok(_) => Ok(()),
        Err(rusqlite::Error::SqliteFailure(_, Some(message)))
            if message.contains("duplicate column name") =>
        {
            Ok(())
        }
        Err(error) => Err(error),
    }
}

fn thumbnail_column_exists(conn: &Connection, column: &str) -> rusqlite::Result<bool> {
    Ok(conn
        .query_row(
            "SELECT 1 FROM pragma_table_info('thumbnails') WHERE name = ?1 LIMIT 1",
            [column],
            |_| Ok(()),
        )
        .optional()?
        .is_some())
}

/// 枚举 cache_dir 下 .db 文件的路径与元数据，并调用回调。
fn collect_db_paths(cache_dir: &Path, cb: &mut impl FnMut(&Path, std::fs::Metadata)) {
    let Ok(top) = std::fs::read_dir(cache_dir) else {
        return;
    };
    for entry in top.flatten() {
        // 为避免每个条目一次 GetFileAttributes 系统调用，只取一次 file_type
        // (docs/ui-responsiveness.md §4)。缓存全量扫描会有数千文件夹的规模，所以这很有效。
        let Ok(ft) = entry.file_type() else {
            continue;
        };
        if !ft.is_dir() {
            continue;
        }
        let sub = entry.path();
        let Ok(sub_entries) = std::fs::read_dir(&sub) else {
            continue;
        };
        for file in sub_entries.flatten() {
            let p = file.path();
            if p.extension().and_then(|e| e.to_str()) == Some("db") {
                if let Ok(meta) = file.metadata() {
                    cb(&p, meta);
                }
            }
        }
    }
}

/// collect_db_paths 的仅统计变体（不需要路径）。
fn collect_db_files(cache_dir: &Path, cb: &mut impl FnMut(std::fs::Metadata)) {
    collect_db_paths(cache_dir, &mut |_, meta| cb(meta));
}

// -----------------------------------------------------------------------
// 测试
// -----------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    mod cases;
}
