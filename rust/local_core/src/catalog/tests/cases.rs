use super::*;
use rusqlite::Connection;
use std::sync::Mutex;

/// 测试用：用 in-memory SQLite 创建 CatalogDb。
fn open_in_memory() -> CatalogDb {
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;")
        .unwrap();
    init_schema(&conn).unwrap();
    CatalogDb {
        conn: Mutex::new(conn),
        has_layout_dims_columns: true,
    }
}

// -- db_path_for --

#[test]
fn db_path_for_deterministic() {
    let cache = Path::new(r"C:\cache");
    let folder = Path::new(r"D:\photos\2024");
    let a = db_path_for(cache, folder);
    let b = db_path_for(cache, folder);
    assert_eq!(a, b);
}

#[test]
fn db_path_for_different_paths() {
    let cache = Path::new(r"C:\cache");
    let a = db_path_for(cache, Path::new(r"D:\photos\2024"));
    let b = db_path_for(cache, Path::new(r"D:\photos\2025"));
    assert_ne!(a, b);
}

#[test]
fn db_path_for_case_insensitive() {
    let cache = Path::new(r"C:\cache");
    let a = db_path_for(cache, Path::new(r"C:\Photos\Vacation"));
    let b = db_path_for(cache, Path::new(r"D:\photos\vacation"));
    // 盘符会被去掉并转成小写，所以应该得到相同的路径
    assert_eq!(a, b);
}

#[test]
fn db_path_for_drive_roots_keeps_drive_letter() {
    let cache = Path::new(r"C:\cache");
    let c = db_path_for(cache, Path::new(r"C:\"));
    let d = db_path_for(cache, Path::new(r"D:\"));
    assert_ne!(c, d, "驱动器根目录 catalog 要避免直下同名项目冲突");
}

#[test]
fn db_path_for_non_root_still_ignores_drive_letter() {
    let cache = Path::new(r"C:\cache");
    let c = db_path_for(cache, Path::new(r"C:\Photos"));
    let d = db_path_for(cache, Path::new(r"D:\photos"));
    assert_eq!(c, d, "非 root 照旧跟随盘符的变化");
}

#[test]
fn db_path_for_structure() {
    let cache = Path::new(r"C:\cache");
    let result = db_path_for(cache, Path::new(r"D:\test"));
    let result_str = result.to_string_lossy();
    // {cache_dir}/{xx}/{hash}.db 的形式
    let expected_prefix = cache.to_string_lossy();
    assert!(result_str.starts_with(expected_prefix.as_ref()));
    assert!(result_str.ends_with(".db"));
    // xx 子目录是 2 个字符的 hex
    let relative = result.strip_prefix(cache).unwrap();
    let components: Vec<_> = relative.components().collect();
    assert_eq!(components.len(), 2); // xx/ 和 hash.db
}

// -- CatalogDb schema --

#[test]
fn catalog_open_and_schema() {
    let db = open_in_memory();
    let conn = db.conn.lock().unwrap();
    // meta 表里是否记录了版本
    let version: String = conn
        .query_row("SELECT value FROM meta WHERE key = 'version'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(version, CATALOG_VERSION);
    let columns = conn
        .prepare("SELECT name FROM pragma_table_info('thumbnails')")
        .unwrap()
        .query_map([], |row| row.get::<_, String>(0))
        .unwrap()
        .flatten()
        .collect::<HashSet<_>>();
    assert!(columns.contains("source_width"));
    assert!(columns.contains("source_height"));
    assert!(columns.contains("layout_width"));
    assert!(columns.contains("layout_height"));
}

#[test]
fn pdf_layout_migration_rebuilds_development_v1_page_rows_once() {
    let tmp = tempfile::tempdir().unwrap();
    let cache_dir = tmp.path().join("cache");
    let pdf_path = tmp.path().join("book.pdf");
    let db = CatalogDb::open(&cache_dir, &pdf_path).unwrap();
    db.save(
        "page_0000",
        1,
        10,
        327,
        473,
        Some((595_276, 841_890)),
        b"development-v1",
    )
    .unwrap();
    db.conn
        .lock()
        .unwrap()
        .execute(
            "INSERT OR REPLACE INTO meta (key, value) VALUES (?1, '1')",
            [PDF_LAYOUT_DIMS_META_KEY],
        )
        .unwrap();
    drop(db);

    let migrated = CatalogDb::open(&cache_dir, &pdf_path).unwrap();
    assert!(migrated.load_all().unwrap().is_empty());
    migrated
        .save_with_layout_dims(
            "page_0000",
            1,
            10,
            327,
            473,
            Some((327, 473)),
            Some((595_276, 841_890)),
            b"fixed",
        )
        .unwrap();
    drop(migrated);

    let reopened = CatalogDb::open(&cache_dir, &pdf_path).unwrap();
    assert_eq!(
        reopened.load_all().unwrap()["page_0000"].source_dims,
        Some((327, 473)),
        "the migration marker must preserve regenerated rows on later opens"
    );
    assert_eq!(
        reopened.load_all().unwrap()["page_0000"].layout_dims,
        Some((595_276, 841_890))
    );
}

#[test]
fn pdf_layout_migration_keeps_non_pdf_rows_in_folder_catalogs() {
    let tmp = tempfile::tempdir().unwrap();
    let cache_dir = tmp.path().join("cache");
    let folder = tmp.path().join("photos");
    let db = CatalogDb::open(&cache_dir, &folder).unwrap();
    db.save("image.jpg", 1, 10, 8, 8, Some((4000, 3000)), b"image")
        .unwrap();
    db.save(
        "pdfthumb:book.pdf",
        1,
        10,
        8,
        8,
        Some((327, 473)),
        b"legacy-pdf",
    )
    .unwrap();
    db.conn
        .lock()
        .unwrap()
        .execute(
            "DELETE FROM meta WHERE key = ?1",
            [PDF_LAYOUT_DIMS_META_KEY],
        )
        .unwrap();
    drop(db);

    let migrated = CatalogDb::open(&cache_dir, &folder).unwrap();
    let rows = migrated.load_all().unwrap();
    assert!(rows.contains_key("image.jpg"));
    assert!(!rows.contains_key("pdfthumb:book.pdf"));
}

// -- CatalogDb CRUD --

#[test]
fn catalog_save_and_load_all() {
    let db = open_in_memory();
    db.save(
        "test.jpg",
        1000,
        2048,
        256,
        192,
        Some((4000, 3000)),
        b"fake_webp",
    )
    .unwrap();

    let map = db.load_all().unwrap();
    assert_eq!(map.len(), 1);
    let entry = &map["test.jpg"];
    assert_eq!(entry.mtime, 1000);
    assert_eq!(entry.file_size, 2048);
    assert_eq!(entry.jpeg_data, b"fake_webp");
    assert_eq!(entry.source_dims, Some((4000, 3000)));
    assert_eq!(entry.layout_dims, None);
}

#[test]
fn catalog_keeps_pdf_raster_pixels_separate_from_page_layout() {
    let db = open_in_memory();
    db.save_with_layout_dims(
        "page_0000",
        1000,
        2048,
        273,
        416,
        Some((273, 416)),
        Some((468_600, 714_360)),
        b"fake_webp",
    )
    .unwrap();

    let entry = db.load_one("page_0000").unwrap().unwrap();
    assert_eq!(entry.source_dims, Some((273, 416)));
    assert_eq!(entry.layout_dims, Some((468_600, 714_360)));
}

/// 打开列表的瞬间，远程缩略图会用 12 个 worker 同时打开同一个 catalog。
/// 2026-08-13 的实际受损就在这里：2 个请求以 `database is locked` 在 1.1ms 内失败，也不再重新请求，
/// 列表里只有那 2 张一直停留在符号上。`busy_timeout` 默认设了 5 秒却不起作用。
#[test]
fn opening_one_catalog_from_many_threads_at_once_never_reports_it_locked() {
    let tmp = tempfile::tempdir().unwrap();
    let cache_dir = tmp.path().to_path_buf();
    let folder = tmp.path().join("folder");
    std::fs::create_dir_all(&folder).unwrap();

    let barrier = std::sync::Arc::new(std::sync::Barrier::new(12));
    let mut handles = Vec::new();
    for _ in 0..12 {
        let barrier = std::sync::Arc::clone(&barrier);
        let cache_dir = cache_dir.clone();
        let folder = folder.clone();
        handles.push(std::thread::spawn(move || {
            barrier.wait();
            CatalogDb::open(&cache_dir, &folder)
                .map(|_| ())
                .map_err(|error| error.to_string())
        }));
    }
    let failures: Vec<String> = handles
        .into_iter()
        .filter_map(|handle| handle.join().unwrap().err())
        .collect();
    assert!(failures.is_empty(), "{failures:?}");
}

#[test]
fn read_only_legacy_catalog_treats_missing_layout_columns_as_none() {
    let tmp = tempfile::tempdir().unwrap();
    let cache_dir = tmp.path().join("cache");
    let folder = tmp.path().join("photos");
    let db_path = db_path_for(&cache_dir, &folder);
    std::fs::create_dir_all(db_path.parent().unwrap()).unwrap();
    let conn = Connection::open(&db_path).unwrap();
    conn.execute_batch(
        "CREATE TABLE thumbnails (
                 filename TEXT NOT NULL PRIMARY KEY,
                 mtime INTEGER NOT NULL,
                 file_size INTEGER NOT NULL,
                 width INTEGER NOT NULL,
                 height INTEGER NOT NULL,
                 thumb_data BLOB NOT NULL,
                 source_width INTEGER,
                 source_height INTEGER
             );
             INSERT INTO thumbnails VALUES
                 ('image.jpg', 1, 10, 8, 8, X'0102', 4000, 3000);",
    )
    .unwrap();
    drop(conn);

    let db = CatalogDb::open_existing_read_only(&cache_dir, &folder)
        .unwrap()
        .unwrap();
    let all = db.load_all().unwrap();
    assert_eq!(all["image.jpg"].source_dims, Some((4000, 3000)));
    assert_eq!(all["image.jpg"].layout_dims, None);
    assert_eq!(db.load_one("image.jpg").unwrap().unwrap().layout_dims, None);
    assert_eq!(
        db.load_latest_with_prefix("image")
            .unwrap()
            .unwrap()
            .1
            .layout_dims,
        None
    );
}

#[test]
fn catalog_save_overwrites() {
    let db = open_in_memory();
    db.save("img.jpg", 100, 500, 128, 96, None, b"data1")
        .unwrap();
    db.save("img.jpg", 200, 600, 128, 96, None, b"data2")
        .unwrap();

    let map = db.load_all().unwrap();
    assert_eq!(map.len(), 1);
    assert_eq!(map["img.jpg"].mtime, 200);
    assert_eq!(map["img.jpg"].jpeg_data, b"data2");
}

#[test]
fn catalog_source_dims_none() {
    let db = open_in_memory();
    db.save("no_dims.jpg", 100, 500, 128, 96, None, b"data")
        .unwrap();

    let map = db.load_all().unwrap();
    assert_eq!(map["no_dims.jpg"].source_dims, None);
}

#[test]
fn source_dims_query_separates_a_missing_row_from_a_row_without_dimensions() {
    // Callers use the difference to decide whether reading a thumbnail is worth it:
    // a missing row has nothing to recover, an empty one predates the columns.
    let db = open_in_memory();
    db.save("wide.jpg", 1, 10, 128, 96, Some((4000, 3000)), b"thumb")
        .unwrap();
    db.save("legacy.jpg", 2, 20, 128, 96, None, b"thumb")
        .unwrap();

    let dims = db.load_source_dims().unwrap();
    assert_eq!(dims.get("wide.jpg"), Some(&Some((4000, 3000))));
    assert_eq!(dims.get("legacy.jpg"), Some(&None));
    assert_eq!(dims.get("absent.jpg"), None);
    assert_eq!(dims.len(), 2);
}

#[test]
fn source_dims_query_agrees_with_the_full_load_it_replaces() {
    let db = open_in_memory();
    db.save("a.jpg", 1, 10, 128, 96, Some((1200, 1800)), b"a")
        .unwrap();
    db.save("b.jpg", 2, 20, 128, 96, Some((1800, 1200)), b"b")
        .unwrap();
    db.save("c.jpg", 3, 30, 128, 96, None, b"c").unwrap();

    let full = db.load_all().unwrap();
    let dims = db.load_source_dims().unwrap();
    assert_eq!(full.len(), dims.len());
    for (filename, entry) in &full {
        assert_eq!(dims.get(filename), Some(&entry.source_dims), "{filename}");
    }
}

#[test]
fn catalog_delete_missing() {
    let db = open_in_memory();
    db.save("keep.jpg", 100, 500, 128, 96, None, b"a").unwrap();
    db.save("remove.jpg", 200, 600, 128, 96, None, b"b")
        .unwrap();
    db.save("also_remove.jpg", 300, 700, 128, 96, None, b"c")
        .unwrap();

    let existing: HashSet<String> = ["keep.jpg".to_string()].into_iter().collect();
    db.delete_missing(&existing).unwrap();

    let map = db.load_all().unwrap();
    assert_eq!(map.len(), 1);
    assert!(map.contains_key("keep.jpg"));
}

#[test]
fn catalog_delete_one_removes_only_target() {
    let db = open_in_memory();
    db.save("a.jpg", 1, 10, 8, 8, None, b"a").unwrap();
    db.save("b.jpg", 1, 10, 8, 8, None, b"b").unwrap();
    db.delete_one("a.jpg").unwrap();
    let map = db.load_all().unwrap();
    assert_eq!(map.len(), 1);
    assert!(map.contains_key("b.jpg"));
    assert!(!map.contains_key("a.jpg"));
    // 第二次 delete（不存在的键）也不报错
    db.delete_one("a.jpg").unwrap();
    db.delete_one("never_existed.jpg").unwrap();
}

#[test]
fn catalog_load_latest_with_prefix_picks_newest_matching_pin_entry() {
    let db = open_in_memory();
    db.save("folderthumb:child", 10, 1, 8, 8, None, b"base")
        .unwrap();
    db.save(
        "folderthumb:child#pin:image|cover|-|-|20|2",
        20,
        2,
        8,
        8,
        None,
        b"pin",
    )
    .unwrap();
    db.save("folderthumb:child-other", 99, 9, 8, 8, None, b"other")
        .unwrap();

    let (filename, entry) = db
        .load_latest_with_prefix("folderthumb:child#pin:")
        .unwrap()
        .expect("narrow prefix hit");
    assert_eq!(filename, "folderthumb:child#pin:image|cover|-|-|20|2");
    assert_eq!(entry.jpeg_data, b"pin");
    assert!(db.load_latest_with_prefix("missing:").unwrap().is_none());
}

#[test]
fn catalog_column_migration_runs_once_and_is_idempotent() {
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch(
        "CREATE TABLE thumbnails (
                filename TEXT NOT NULL PRIMARY KEY,
                mtime INTEGER NOT NULL,
                file_size INTEGER NOT NULL,
                width INTEGER NOT NULL,
                height INTEGER NOT NULL,
                thumb_data BLOB NOT NULL
            );",
    )
    .unwrap();

    init_schema(&conn).unwrap();
    init_schema(&conn).unwrap();
    let migrated: i64 = conn
        .query_row(
            "SELECT count(*) FROM pragma_table_info('thumbnails')
                 WHERE name IN ('source_width', 'source_height')",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(migrated, 2);
}

#[test]
fn catalog_version_mismatch_clears() {
    // 1) 创建 DB 并保存数据
    let conn = Connection::open_in_memory().unwrap();
    init_schema(&conn).unwrap();
    conn.execute(
        "INSERT INTO thumbnails (filename, mtime, file_size, width, height, thumb_data) \
             VALUES ('old.jpg', 1, 1, 1, 1, X'00')",
        [],
    )
    .unwrap();
    // 确认数据存在
    let count: i64 = conn
        .query_row("SELECT count(*) FROM thumbnails", [], |r| r.get(0))
        .unwrap();
    assert_eq!(count, 1);

    // 2) 把版本改写成非法值
    conn.execute(
        "UPDATE meta SET value = 'old_version' WHERE key = 'version'",
        [],
    )
    .unwrap();

    // 3) 再次调用 init_schema，应因版本不一致而全部删除
    init_schema(&conn).unwrap();
    let count: i64 = conn
        .query_row("SELECT count(*) FROM thumbnails", [], |r| r.get(0))
        .unwrap();
    assert_eq!(count, 0);
}

#[test]
fn container_page_meta_roundtrip_and_identity_invalidation() {
    let db = open_in_memory();
    db.set_container_page_meta("book.zip", ContainerPageKind::Zip, 100, 2_048, 0, Some(123))
        .unwrap();
    db.set_container_page_meta(
        "book.rar",
        ContainerPageKind::Archive,
        300,
        4_096,
        77,
        Some(45),
    )
    .unwrap();

    assert_eq!(
        db.get_container_page_meta("book.zip", ContainerPageKind::Zip, 100, 2_048, 0)
            .unwrap(),
        Some(ContainerPageMeta {
            page_count: Some(123)
        })
    );
    assert_eq!(
        db.get_container_page_meta("book.zip", ContainerPageKind::Zip, 101, 2_048, 0)
            .unwrap(),
        None,
        "mtime 变了就重新扫描"
    );
    assert_eq!(
        db.get_container_page_meta("book.zip", ContainerPageKind::Zip, 100, 4_096, 0)
            .unwrap(),
        None,
        "大小变了就重新扫描"
    );
    assert_eq!(
        db.get_container_page_meta("book.zip", ContainerPageKind::Folder, 100, 2_048, 0)
            .unwrap(),
        None,
        "即使同名也不混淆容器类别"
    );
    assert_eq!(
        db.get_container_page_meta("book.rar", ContainerPageKind::Archive, 300, 4_096, 77,)
            .unwrap(),
        Some(ContainerPageMeta {
            page_count: Some(45)
        }),
        "独立保存需转换归档的页数"
    );
}

#[test]
fn container_page_meta_preserves_non_book_and_fingerprint() {
    let db = open_in_memory();
    db.set_container_page_meta("pictures", ContainerPageKind::Folder, 200, 0, 77, None)
        .unwrap();

    assert_eq!(
        db.get_container_page_meta("pictures", ContainerPageKind::Folder, 200, 0, 77)
            .unwrap(),
        Some(ContainerPageMeta { page_count: None }),
        "已扫描过的不合格文件夹以 NULL 区分"
    );
    assert_eq!(
        db.get_container_page_meta("pictures", ContainerPageKind::Folder, 200, 0, 78)
            .unwrap(),
        None,
        "判定设置变了就重新扫描"
    );
}

// -- WebP encode/decode --

#[test]
fn encode_thumb_webp_basic() {
    // 生成一个小的 4x4 测试图像
    let img = image::DynamicImage::ImageRgb8(image::RgbImage::from_fn(4, 4, |x, y| {
        image::Rgb([(x * 60) as u8, (y * 60) as u8, 128])
    }));
    let result = encode_thumb_webp(&img, 4, 75.0);
    assert!(result.is_some());
    let (data, w, h) = result.unwrap();
    assert!(!data.is_empty());
    assert!(w <= 4 && h <= 4);
}

/// `collect_db_paths` 能覆盖 `cache_dir/<sub>/*.db`。
/// `cache_dir/file.db`（top-level）不在 subdir 里所以**忽略**，
/// 非 .db 文件 / 多余文件夹里的非 .db 也忽略。
/// 从功能层面保证与 docs/ui-responsiveness.md §4（经由 file_type）的一致。
#[test]
fn collect_db_paths_enumerates_only_subdir_db_files() {
    let temp = tempfile::TempDir::new().unwrap();
    let cache_dir = temp.path().join("cache");
    std::fs::create_dir_all(&cache_dir).unwrap();
    // sub1: foo.db + readme.txt
    let sub1 = cache_dir.join("sub1");
    std::fs::create_dir_all(&sub1).unwrap();
    std::fs::write(sub1.join("foo.db"), b"x").unwrap();
    std::fs::write(sub1.join("readme.txt"), b"x").unwrap();
    // sub2: bar.db
    let sub2 = cache_dir.join("sub2");
    std::fs::create_dir_all(&sub2).unwrap();
    std::fs::write(sub2.join("bar.db"), b"x").unwrap();
    // top-level 的 loose db（不在 subdir 里）不收集
    std::fs::write(cache_dir.join("loose.db"), b"x").unwrap();
    // 空子文件夹无害
    std::fs::create_dir_all(cache_dir.join("empty_sub")).unwrap();

    let mut found: Vec<String> = Vec::new();
    super::collect_db_paths(&cache_dir, &mut |p, _meta| {
        found.push(
            p.file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("")
                .to_string(),
        );
    });
    found.sort();
    assert_eq!(
        found,
        vec!["bar.db".to_string(), "foo.db".to_string()],
        "只枚举 subdir 下的 .db，忽略 top-level 的 loose.db"
    );
}

/// `collect_db_paths` 在 cache_dir 本身不存在时不 panic，
/// 只是不调用回调直接返回（`std::fs::read_dir` 返回 Err 时的约定）。
#[test]
fn collect_db_paths_handles_missing_cache_dir() {
    let temp = tempfile::TempDir::new().unwrap();
    let nonexistent = temp.path().join("does_not_exist");
    let mut count = 0usize;
    super::collect_db_paths(&nonexistent, &mut |_, _| count += 1);
    assert_eq!(count, 0, "missing cache_dir 时枚举为空");
}

/// 即便大量子文件夹（200 个）也能枚举全部 .db 文件、不漏一个。
/// 实测耗时 assert 会 flaky，所以只严格确认条数（间接保证经由 file_type 路径
/// 没有产生 per-entry syscall）。
#[test]
fn collect_db_paths_handles_many_subfolders() {
    let temp = tempfile::TempDir::new().unwrap();
    let cache_dir = temp.path().join("cache");
    std::fs::create_dir_all(&cache_dir).unwrap();
    for i in 0..200 {
        let sub = cache_dir.join(format!("s{i:03}"));
        std::fs::create_dir_all(&sub).unwrap();
        std::fs::write(sub.join("a.db"), b"x").unwrap();
    }
    let mut count = 0usize;
    super::collect_db_paths(&cache_dir, &mut |_, _| count += 1);
    assert_eq!(count, 200, "200 个全部枚举");
}

/// 0.8.2 把 `decode_thumb_dims` 从固定 WebP 改成 `with_guessed_format()` auto-detect
/// 的回归守卫。如果这里读不出 JPEG，旧版本以 JPEG 写下的
/// 父 catalog 条目就无法 seed/writeback（= 虚拟文件夹的首次 thumb
/// 会永久丢失）。
#[test]
fn decode_thumb_dims_reads_webp_jpeg_and_rejects_garbage() {
    let img = image::DynamicImage::ImageRgb8(image::RgbImage::from_fn(8, 6, |x, y| {
        image::Rgb([(x * 30) as u8, (y * 40) as u8, 200])
    }));

    // WebP（现行格式）：返回尺寸
    let (webp_bytes, _, _) = encode_thumb_webp(&img, 8, 75.0).expect("webp encode ok");
    assert_eq!(decode_thumb_dims(&webp_bytes), Some((8, 6)));

    // JPEG（旧版本写入的格式）：返回尺寸
    let mut jpeg_bytes = Vec::new();
    img.write_to(
        &mut std::io::Cursor::new(&mut jpeg_bytes),
        image::ImageFormat::Jpeg,
    )
    .expect("jpeg encode");
    assert_eq!(decode_thumb_dims(&jpeg_bytes), Some((8, 6)));

    // 损坏数据: None。空字节序列、文本、只有 WebP magic、截断的 JPEG 都 reject。
    assert_eq!(decode_thumb_dims(&[]), None);
    assert_eq!(decode_thumb_dims(b"NOT-AN-IMAGE-AT-ALL"), None);
    // 只有 RIFF/WEBP magic 的前 12 字节（没有本体）
    assert_eq!(
        decode_thumb_dims(b"RIFF\x00\x00\x00\x00WEBP"),
        None,
        "只有 header 没有本体 → None"
    );
    // 只有 JPEG SOI（到不了 SOF0）
    assert_eq!(decode_thumb_dims(b"\xFF\xD8\xFF\xE0"), None);
}

// -- pdf_meta --

#[test]
fn pdf_meta_set_and_get_roundtrip() {
    let db = open_in_memory();
    db.set_pdf_meta("foo.pdf", 1000, 2048, 32, false).unwrap();

    let result = db.get_pdf_meta("foo.pdf", 1000, 2048).unwrap();
    assert_eq!(result, Some((32, false)));
}

#[test]
fn pdf_meta_mtime_mismatch_returns_none() {
    let db = open_in_memory();
    db.set_pdf_meta("foo.pdf", 1000, 2048, 32, false).unwrap();

    // mtime 变了就 cache miss
    let result = db.get_pdf_meta("foo.pdf", 1001, 2048).unwrap();
    assert_eq!(result, None, "mtime 变化导致 cache miss");
}

#[test]
fn pdf_meta_file_size_mismatch_returns_none() {
    let db = open_in_memory();
    db.set_pdf_meta("foo.pdf", 1000, 2048, 32, false).unwrap();

    // file_size 变了就 cache miss
    let result = db.get_pdf_meta("foo.pdf", 1000, 4096).unwrap();
    assert_eq!(result, None, "file_size 变化导致 cache miss");
}

#[test]
fn pdf_meta_password_required_flag_preserved() {
    let db = open_in_memory();
    db.set_pdf_meta("locked.pdf", 100, 500, 8, true).unwrap();

    let result = db.get_pdf_meta("locked.pdf", 100, 500).unwrap();
    assert_eq!(result, Some((8, true)));
}

#[test]
fn pdf_meta_insert_or_replace() {
    let db = open_in_memory();
    // 用同一个 filename set 两次 → 第二次覆盖
    db.set_pdf_meta("foo.pdf", 1000, 2048, 32, false).unwrap();
    db.set_pdf_meta("foo.pdf", 1000, 2048, 100, true).unwrap();

    let result = db.get_pdf_meta("foo.pdf", 1000, 2048).unwrap();
    assert_eq!(result, Some((100, true)), "保留第 2 次的值");
}

#[test]
fn pdf_meta_get_missing_returns_none() {
    let db = open_in_memory();
    let result = db.get_pdf_meta("nonexistent.pdf", 1000, 2048).unwrap();
    assert_eq!(result, None);
}

#[test]
fn pdf_meta_does_not_affect_thumbnails_table() {
    // 确认 pdf_meta 表与 thumbnails 表相互独立
    let db = open_in_memory();
    db.set_pdf_meta("foo.pdf", 1000, 2048, 32, false).unwrap();

    let all = db.load_all().unwrap();
    assert!(all.is_empty(), "thumbnails 保持为空");
}

#[test]
fn pdf_meta_thumb_preserves_password_required_flag() {
    // unknown 路径（仅本会话的 pw 等）的 verify update 不会抹掉 password_required
    // （只有 mtime/size 一致时才会执行 page_count update）
    let db = open_in_memory();
    // 已存在：作为必须输入密码记录在案
    db.set_pdf_meta("locked.pdf", 1000, 2048, 32, true).unwrap();
    // 相同 mtime/size 下的 unknown 路径 update（page_count 恰好也相同）
    db.set_pdf_meta_thumb("locked.pdf", 1000, 2048, 32).unwrap();

    let result = db.get_pdf_meta("locked.pdf", 1000, 2048).unwrap();
    assert_eq!(result, Some((32, true)), "password_required=true 被保留");
}

#[test]
fn pdf_meta_thumb_does_not_insert_new_row() {
    // **对应 Codex P1 round 2**：新 PDF（= 还没有 pdf_meta 行）时，即使调用
    // unknown 路径（set_pdf_meta_thumb），也不创建 false-default 的行。
    // 以防用「输入了密码但不保存」打开保护 PDF 的场景，被永久
    // 记录成「非保护」的绕过。
    let db = open_in_memory();
    db.set_pdf_meta_thumb("new.pdf", 500, 1024, 16).unwrap();

    let result = db.get_pdf_meta("new.pdf", 500, 1024).unwrap();
    assert_eq!(result, None, "不创建新行 (UPDATE only)");
}

#[test]
fn pdf_meta_thumb_does_not_promote_stale_row() {
    // **对应 Codex P1 round 3**：旧的 stale 行（例：已作为非加密 cache）在
    // 文件替换后（加密版、新 mtime/size）经 unknown 路径 update
    // 覆盖成新 mtime/size 的话，就会以 password_required=0 的状态被提升。
    // 靠「仅当 mtime/file_size 一致才生效、否则 no-op」的实现来防止。
    let db = open_in_memory();
    // 旧行：记录为非加密（mtime=1000, size=2000）
    db.set_pdf_meta("foo.pdf", 1000, 2000, 10, false).unwrap();
    // 文件更新后，用户用 session pw 打开新版，unknown 路径的 update 到达
    // （新 mtime=2000, size=3000）— 试图 promote 旧的 stale 行
    db.set_pdf_meta_thumb("foo.pdf", 2000, 3000, 20).unwrap();

    // 用新 mtime/size 查找是 cache miss（stale 行保持旧的，不会被新值 promote）
    let new_lookup = db.get_pdf_meta("foo.pdf", 2000, 3000).unwrap();
    assert_eq!(
        new_lookup, None,
        "不会发生新 mtime/size 的 cache hit（stale 行未被 promote）"
    );
    // 旧 mtime/size 的行保持原样（page_count=10, password_required=false）
    let old_lookup = db.get_pdf_meta("foo.pdf", 1000, 2000).unwrap();
    assert_eq!(
        old_lookup,
        Some((10, false)),
        "旧 mtime/size 的行保持原样不变"
    );
}

#[test]
fn pdf_meta_thumb_updates_page_count_when_mtime_size_match() {
    // mtime/file_size 与已有行一致时更新 page_count（verify update）。
    // password_required 列保留。
    let db = open_in_memory();
    db.set_pdf_meta("foo.pdf", 1000, 2048, 32, true).unwrap();
    // 相同 mtime/size、只有 page_count 不同的 update（例：经另一路径重新计数）
    db.set_pdf_meta_thumb("foo.pdf", 1000, 2048, 35).unwrap();

    let result = db.get_pdf_meta("foo.pdf", 1000, 2048).unwrap();
    assert_eq!(
        result,
        Some((35, true)),
        "page_count 更新，password_required 保留"
    );
}

#[test]
fn pdf_meta_thumb_noop_when_only_mtime_differs() {
    // **对应 Codex P3 round 4**：即使只有 mtime 不同的 stale 情况也不 promote。
    let db = open_in_memory();
    db.set_pdf_meta("foo.pdf", 1000, 2048, 32, true).unwrap();
    // 以新 mtime=2000（size 相同）来 update → 不在一致条件内
    db.set_pdf_meta_thumb("foo.pdf", 2000, 2048, 50).unwrap();

    // 用新 mtime 查找是 cache miss（stale 行保持旧的）
    let new_lookup = db.get_pdf_meta("foo.pdf", 2000, 2048).unwrap();
    assert_eq!(new_lookup, None);
    // 旧 mtime 的行不变
    let old_lookup = db.get_pdf_meta("foo.pdf", 1000, 2048).unwrap();
    assert_eq!(old_lookup, Some((32, true)));
}

#[test]
fn pdf_meta_thumb_noop_when_only_file_size_differs() {
    // **对应 Codex P3 round 4**：即使只有 file_size 不同的 stale 情况也不 promote。
    let db = open_in_memory();
    db.set_pdf_meta("foo.pdf", 1000, 2048, 32, true).unwrap();
    // 以新 size=4096（mtime 相同）来 update → 不在一致条件内
    db.set_pdf_meta_thumb("foo.pdf", 1000, 4096, 50).unwrap();

    // 用新 size 查找是 cache miss
    let new_lookup = db.get_pdf_meta("foo.pdf", 1000, 4096).unwrap();
    assert_eq!(new_lookup, None);
    // 旧 size 的行不变
    let old_lookup = db.get_pdf_meta("foo.pdf", 1000, 2048).unwrap();
    assert_eq!(old_lookup, Some((32, true)));
}

#[test]
fn pdf_meta_safe_inserts_new_row_with_false() {
    // password=None 的确定路径：以 password_required=false 插入新行
    let db = open_in_memory();
    db.set_pdf_meta_safe("new.pdf", 500, 1024, 16).unwrap();

    let result = db.get_pdf_meta("new.pdf", 500, 1024).unwrap();
    assert_eq!(result, Some((16, false)), "新行以 false 插入");
}

#[test]
fn pdf_meta_safe_overrides_password_required_on_existing_row() {
    // **对应 review #1**：即使已有行是 password_required=true，safe 路径
    // （= 以 None password 渲染成功 = 确信非保护）也会覆盖为 0。
    // 以防把保护版同名替换成非保护版时，把 stale 的「保护」标志
    // 持久化下来。
    let db = open_in_memory();
    db.set_pdf_meta("locked.pdf", 100, 500, 8, true).unwrap();
    db.set_pdf_meta_safe("locked.pdf", 200, 600, 10).unwrap();

    let result = db.get_pdf_meta("locked.pdf", 200, 600).unwrap();
    assert_eq!(
        result,
        Some((10, false)),
        "被 safe 路径的确信（password_required=false）覆盖"
    );
}
