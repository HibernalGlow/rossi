//! `CatalogDb` 的查询与写入接口。
//!
//! 类型定义与 schema / 缓存扫描的私有辅助函数在父级 `catalog.rs` 里。
//! 由于兄弟模块之间无法引用彼此的私有项目，**把被调用的一侧留在父级**
//! 是这个拆分唯一的形态（放宽可见性 = 为了不改动那些行）。

use super::*;

impl CatalogDb {
    /// 在 cache_dir 下的合适位置打开 DB（不存在则创建）。
    /// 子目录也会自动创建。
    pub fn open(cache_dir: &Path, folder_path: &Path) -> rusqlite::Result<Self> {
        let db_path = db_path_for(cache_dir, folder_path);
        if let Some(parent) = db_path.parent() {
            std::fs::create_dir_all(parent).ok();
        }
        let mut conn = Connection::open(&db_path)?;
        ensure_wal_journal(&conn)?;
        conn.execute_batch("PRAGMA synchronous=NORMAL;")?;
        init_schema(&conn)?;
        migrate_pdf_layout_dims(&mut conn, folder_path)?;
        Ok(Self {
            conn: Mutex::new(conn),
            has_layout_dims_columns: true,
        })
    }

    /// 只以只读方式打开已存在的 catalog。
    ///
    /// 在递归目录代表图的 cache-only 传播中，缓存被删除后如果重建空 DB，
    /// 看上去就像「有缓存」一样，因此文件不存在时返回 `Ok(None)`。
    /// 调用方仅限缩略图重 I/O worker，不要从 UI 线程做 cold open。
    pub fn open_existing_read_only(
        cache_dir: &Path,
        folder_path: &Path,
    ) -> rusqlite::Result<Option<Self>> {
        let db_path = db_path_for(cache_dir, folder_path);
        if !db_path.try_exists().unwrap_or(false) {
            return Ok(None);
        }
        let conn = Connection::open_with_flags(&db_path, OpenFlags::SQLITE_OPEN_READ_ONLY)?;
        let has_layout_dims_columns = thumbnail_column_exists(&conn, "layout_width")?
            && thumbnail_column_exists(&conn, "layout_height")?;
        Ok(Some(Self {
            conn: Mutex::new(conn),
            has_layout_dims_columns,
        }))
    }

    /// 返回 filename -> 原图尺寸，且不读取 thumbnail 的 blob。
    ///
    /// `load_all` 连 `thumb_data` 也会 SELECT，实测平均每行 35 KiB
    ///（4,628 张图的 catalog 为 157 MiB），在 5 万张图的目录里仅为了知道尺寸
    /// 就要搬运 1.7 GB。能只靠整数列回答的问题就用这个。
    ///
    /// 值的 `None` 表示「有这一行但尺寸列为 NULL」（在尺寸列之前保存的旧条目），
    /// key 不存在表示「没有这一行」。需要从 blob 恢复的调用方，只在前者这种情况下
    /// 用 `load_one` 单独重新取一次。
    pub fn load_source_dims(&self) -> rusqlite::Result<HashMap<String, Option<(u32, u32)>>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt =
            conn.prepare("SELECT filename, source_width, source_height FROM thumbnails")?;
        let mut map = HashMap::new();
        let iter = stmt.query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, Option<u32>>(1)?,
                row.get::<_, Option<u32>>(2)?,
            ))
        })?;
        for (filename, width, height) in iter.flatten() {
            map.insert(filename, valid_dims(width, height));
        }
        Ok(map)
    }

    /// 把 DB 内的全部条目作为 HashMap<filename, CacheEntry> 返回（一次性 SELECT）。
    pub fn load_all(&self) -> rusqlite::Result<HashMap<String, CacheEntry>> {
        let conn = self.conn.lock().unwrap();
        let layout_columns = if self.has_layout_dims_columns {
            "layout_width, layout_height"
        } else {
            "NULL, NULL"
        };
        let sql = format!(
            "SELECT filename, mtime, file_size, thumb_data, source_width, source_height, \
                    {layout_columns} FROM thumbnails"
        );
        let mut stmt = conn.prepare(&sql)?;
        let mut map = HashMap::new();
        let iter = stmt.query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, i64>(1)?,
                row.get::<_, i64>(2)?,
                row.get::<_, Vec<u8>>(3)?,
                row.get::<_, Option<u32>>(4)?,
                row.get::<_, Option<u32>>(5)?,
                row.get::<_, Option<u32>>(6)?,
                row.get::<_, Option<u32>>(7)?,
            ))
        })?;
        for item in iter.flatten() {
            let (filename, mtime, file_size, jpeg_data, src_w, src_h, layout_w, layout_h) = item;
            let source_dims = match (src_w, src_h) {
                (Some(w), Some(h)) if w > 0 && h > 0 => Some((w, h)),
                _ => None,
            };
            map.insert(
                filename,
                CacheEntry {
                    mtime,
                    file_size,
                    jpeg_data,
                    source_dims,
                    layout_dims: valid_dims(layout_w, layout_h),
                },
            );
        }
        Ok(map)
    }

    /// 只取出单个条目。用于还不到调用 `load_all` 的程度、但只想确认特定 key 的
    /// 场合（例如：进入虚拟目录时从父 catalog 做 seed lookup）。
    pub fn load_one(&self, filename: &str) -> rusqlite::Result<Option<CacheEntry>> {
        let conn = self.conn.lock().unwrap();
        let layout_columns = if self.has_layout_dims_columns {
            "layout_width, layout_height"
        } else {
            "NULL, NULL"
        };
        let sql = format!(
            "SELECT mtime, file_size, thumb_data, source_width, source_height, \
                    {layout_columns} FROM thumbnails WHERE filename = ?1"
        );
        let mut stmt = conn.prepare(&sql)?;
        let mut iter = stmt.query_map(params![filename], |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, i64>(1)?,
                row.get::<_, Vec<u8>>(2)?,
                row.get::<_, Option<u32>>(3)?,
                row.get::<_, Option<u32>>(4)?,
                row.get::<_, Option<u32>>(5)?,
                row.get::<_, Option<u32>>(6)?,
            ))
        })?;
        if let Some(item) = iter.next() {
            let (mtime, file_size, jpeg_data, src_w, src_h, layout_w, layout_h) = item?;
            let source_dims = match (src_w, src_h) {
                (Some(w), Some(h)) if w > 0 && h > 0 => Some((w, h)),
                _ => None,
            };
            return Ok(Some(CacheEntry {
                mtime,
                file_size,
                jpeg_data,
                source_dims,
                layout_dims: valid_dims(layout_w, layout_h),
            }));
        }
        Ok(None)
    }

    /// 在 `filename` 以 `prefix` 开头的条目中，只返回 mtime / size 最新的那一条。
    /// 用于目录代表缩略图这类场景：base key 与 `#pin:` 派生 key
    /// 两边都可能残留已有缩略图，此时只做 cache-only 查询。
    pub fn load_latest_with_prefix(
        &self,
        prefix: &str,
    ) -> rusqlite::Result<Option<(String, CacheEntry)>> {
        let conn = self.conn.lock().unwrap();
        let layout_columns = if self.has_layout_dims_columns {
            "layout_width, layout_height"
        } else {
            "NULL, NULL"
        };
        let sql = format!(
            "SELECT filename, mtime, file_size, thumb_data, source_width, source_height, \
                    {layout_columns} FROM thumbnails \
             WHERE substr(filename, 1, ?1) = ?2 \
             ORDER BY mtime DESC, file_size DESC, filename DESC \
             LIMIT 1"
        );
        let mut stmt = conn.prepare(&sql)?;
        let mut iter = stmt.query_map(params![prefix.chars().count() as i64, prefix], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, i64>(1)?,
                row.get::<_, i64>(2)?,
                row.get::<_, Vec<u8>>(3)?,
                row.get::<_, Option<u32>>(4)?,
                row.get::<_, Option<u32>>(5)?,
                row.get::<_, Option<u32>>(6)?,
                row.get::<_, Option<u32>>(7)?,
            ))
        })?;
        if let Some(item) = iter.next() {
            let (filename, mtime, file_size, jpeg_data, src_w, src_h, layout_w, layout_h) = item?;
            let source_dims = match (src_w, src_h) {
                (Some(w), Some(h)) if w > 0 && h > 0 => Some((w, h)),
                _ => None,
            };
            return Ok(Some((
                filename,
                CacheEntry {
                    mtime,
                    file_size,
                    jpeg_data,
                    source_dims,
                    layout_dims: valid_dims(layout_w, layout_h),
                },
            )));
        }
        Ok(None)
    }

    /// 用 INSERT OR REPLACE 保存缩略图。
    ///
    /// `width` / `height` 是被缓存的 WebP 缩略图尺寸，
    /// `source_dims` 是原图 / PDF raster 的像素尺寸（未取到时为 None）。
    #[allow(clippy::too_many_arguments)]
    pub fn save(
        &self,
        filename: &str,
        mtime: i64,
        file_size: i64,
        width: u32,
        height: u32,
        source_dims: Option<(u32, u32)>,
        jpeg_data: &[u8],
    ) -> rusqlite::Result<()> {
        self.save_with_layout_dims(
            filename,
            mtime,
            file_size,
            width,
            height,
            source_dims,
            None,
            jpeg_data,
        )
    }

    /// 在 `save` 之上附加与 raster 相互独立的布局尺寸，供 PDF 使用的保存路径。
    #[allow(clippy::too_many_arguments)]
    pub fn save_with_layout_dims(
        &self,
        filename: &str,
        mtime: i64,
        file_size: i64,
        width: u32,
        height: u32,
        source_dims: Option<(u32, u32)>,
        layout_dims: Option<(u32, u32)>,
        jpeg_data: &[u8],
    ) -> rusqlite::Result<()> {
        let conn = self.conn.lock().unwrap();
        let src_w: Option<u32> = source_dims.map(|(w, _)| w);
        let src_h: Option<u32> = source_dims.map(|(_, h)| h);
        let layout_w: Option<u32> = layout_dims.map(|(w, _)| w);
        let layout_h: Option<u32> = layout_dims.map(|(_, h)| h);
        conn.execute(
            "INSERT OR REPLACE INTO thumbnails \
             (filename, mtime, file_size, width, height, thumb_data, source_width, source_height, \
              layout_width, layout_height) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
            params![
                filename, mtime, file_size, width, height, jpeg_data, src_w, src_h, layout_w,
                layout_h
            ],
        )?;
        Ok(())
    }

    /// 只从缩略图字节流的头部取出 `(w, h)` 再交给 `save` 的轻量包装。
    /// 由于 `CacheEntry` 没有尺寸字段，经由 save 保存时 `(w, h)` 必须由调用方
    /// 自己准备好。虚拟目录的 seed / write-back 这类「把父 catalog 的字节
    /// 原样镜像过来」的用途很容易反复写同样的代码，因此做了集中。
    /// 因为只解析头部，不会执行完整解码。
    ///
    /// 返回值的 `bool` 表示「是否真的保存成功」。`false` 意味着「取不到尺寸而放弃
    /// 保存」（= 字节流已损坏）。调用方据此「连 cache_map 也不放进」，
    /// 就能避免显示缩略图时陷入 `Failed` 状态。
    pub fn save_thumb_bytes(
        &self,
        filename: &str,
        mtime: i64,
        file_size: i64,
        source_dims: Option<(u32, u32)>,
        jpeg_data: &[u8],
    ) -> rusqlite::Result<bool> {
        self.save_thumb_bytes_with_layout_dims(
            filename,
            mtime,
            file_size,
            source_dims,
            None,
            jpeg_data,
        )
    }

    /// `save_thumb_bytes` 的带 PDF 布局尺寸版本。
    pub fn save_thumb_bytes_with_layout_dims(
        &self,
        filename: &str,
        mtime: i64,
        file_size: i64,
        source_dims: Option<(u32, u32)>,
        layout_dims: Option<(u32, u32)>,
        jpeg_data: &[u8],
    ) -> rusqlite::Result<bool> {
        let Some((w, h)) = decode_thumb_dims(jpeg_data) else {
            // 取不到尺寸（= 字节流已损坏）就放弃保存。按 SQLite 的 schema
            // width/height 是 NOT NULL，填 0 会破坏一致性。
            return Ok(false);
        };
        self.save_with_layout_dims(
            filename,
            mtime,
            file_size,
            w,
            h,
            source_dims,
            layout_dims,
            jpeg_data,
        )?;
        Ok(true)
    }

    /// 按 `filename` 键删除单个条目。没有对应行时也不报错。
    ///
    /// 用途：目录代表图钉指向 Video，但对应的 `video_pins` 的 WebP
    /// 消失 / 变空时，需要显式删除 `folderthumb:{dir}#pin:...` 的缓存行，
    /// 让 worker 回落到 auto-pick fallback（Codex Phase C P2 指出）。
    pub fn delete_one(&self, filename: &str) -> rusqlite::Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "DELETE FROM thumbnails WHERE filename = ?1",
            params![filename],
        )?;
        Ok(())
    }

    /// 删除不在 `existing` 中的文件名对应的行（清理已删除的文件）。
    pub fn delete_missing(&self, existing: &HashSet<String>) -> rusqlite::Result<()> {
        let conn = self.conn.lock().unwrap();
        let db_names: Vec<String> = {
            let mut stmt = conn.prepare("SELECT filename FROM thumbnails")?;
            stmt.query_map([], |r| r.get(0))?.flatten().collect()
        };
        for name in db_names {
            if !existing.contains(&name) {
                conn.execute("DELETE FROM thumbnails WHERE filename = ?1", params![name])?;
            }
        }
        Ok(())
    }

    // -------------------------------------------------------------------
    // PDF 页数元信息缓存 (v1.0.0)
    //
    // 为了让 load_pdf_as_folder 的「进入 → 页面列表」体感变成瞬时，把 PDFium
    // 的 PDF open + 结构解析结果（warm 5-30ms / cold 100-1300ms）按目录
    // 持久化到各自的 catalog DB。lookup 时 mtime/file_size 一致就视为 cache hit，
    // 立刻搭起 N 个单元格的 placeholder grid（= 规避 824ms 的等待）。
    //
    // `password_required` 记录「最后一次成功的 enumerate 是否处于密码保护下」。
    // 若在未保存密码的情况下展示 cache hit 的 grid，日后保存的密码被删除时就会
    // bypass 掉保护，因此在使用 cache 之前，要把
    // `password_required==1 && pdf_passwords 中无条目` 这种组合
    // 显式拒绝（对应 Codex P1）。
    // -------------------------------------------------------------------

    /// 查询 PDF 元信息缓存。
    ///
    /// 只有 `(filename, mtime, file_size)` 完全一致时才返回 `Some((page_count,
    /// password_required))`。mtime/file_size 不一致视为 cache miss (None)。
    /// 当 `password_required == true` 时，调用方还要再确认「存在保存的密码」，
    /// 确认之后才能使用该 cache。
    pub fn get_pdf_meta(
        &self,
        filename: &str,
        mtime: i64,
        file_size: i64,
    ) -> rusqlite::Result<Option<(u32, bool)>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT page_count, password_required FROM pdf_meta \
             WHERE filename = ?1 AND mtime = ?2 AND file_size = ?3",
        )?;
        let result = stmt
            .query_row(params![filename, mtime, file_size], |r| {
                let page_count: i64 = r.get(0)?;
                let pw_req: i64 = r.get(1)?;
                Ok((page_count.max(0) as u32, pw_req != 0))
            })
            .ok();
        Ok(result)
    }

    /// 对 PDF 元信息缓存执行 INSERT OR REPLACE。
    /// `page_count == 0` 这类无效值也照原样记录（= 之后可用于 stale 检测）。
    /// `password_required` 只在调用方确信「这个 PDF 需要其专属的保存密码」时才传
    /// true。经由 session 的临时密码要用 `set_pdf_meta_thumb` 那一侧
    /// （它会保留已有值）。
    pub fn set_pdf_meta(
        &self,
        filename: &str,
        mtime: i64,
        file_size: i64,
        page_count: u32,
        password_required: bool,
    ) -> rusqlite::Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT OR REPLACE INTO pdf_meta \
             (filename, mtime, file_size, page_count, password_required) \
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![
                filename,
                mtime,
                file_size,
                page_count as i64,
                if password_required { 1i64 } else { 0i64 },
            ],
        )?;
        Ok(())
    }

    /// 仅当已有 `pdf_meta` 行的 **mtime/file_size 相同** 时才更新 `page_count`。
    /// 其它情况 (新行 / mtime 或 file_size 变化) 都是 no-op。
    ///
    /// 用途: password=Some 但无法确信「存在这个 PDF 的保存密码」的
    /// 路径 (= 可能只是 session 级的 `pdf_current_password` 还留在里面没清掉，
    /// 或者用户在对话框里输入了但选择了「不保存」)。
    ///
    /// **mtime/file_size 一致条件的理由 (对应 Codex P1 round 3)**:
    /// 如果只是简单的 `UPDATE WHERE filename=?`，那么 stale 的「未加密版」行，会在文件被
    /// 替换成加密版之后的 UPDATE 中盖上新的 mtime/size，从而 lookup hit
    /// → password_required=0 被保留下来，用 placeholder 直接 bypass 掉保护。
    /// 通过只在 mtime/file_size 与已有行一致时才更新，使得
    ///   - 文件未变 (= mtime/size 相同) → 在保留对已有 password_required 的确信的前提下
    ///     verify update page_count（多数情况下实质是 no-op）
    ///   - 文件已变 (= mtime/size 不同) → no-op，stale 行原样放着不管。下次 lookup
    ///     时会因 mtime mismatch 而 miss，因此由确信有的路径重新写入
    /// 这两条同时成立。
    pub fn set_pdf_meta_thumb(
        &self,
        filename: &str,
        mtime: i64,
        file_size: i64,
        page_count: u32,
    ) -> rusqlite::Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "UPDATE pdf_meta \
             SET page_count = ?4 \
             WHERE filename = ?1 AND mtime = ?2 AND file_size = ?3",
            params![filename, mtime, file_size, page_count as i64],
        )?;
        Ok(())
    }

    /// `能确信不需要 password 的情况**所用的 UPSERT。
    /// 无论新行还是已有行都以 `password_required=0` 写入，
    /// 并更新 `page_count`/`mtime`/`file_size`。
    ///
    /// 用途: 缩略图 worker 以 `pdf_password=None` 成功完成 render 的情况 (=
    /// PDFium 侧已判明「不需要密码」= 有确信)。
    ///
    /// **连已有行的 `password_required` 也要覆盖的原因 (对应 review #1)**:
    /// 调用方的不变条件「password=None 且 render 成功」已经成立，因此由
    /// (filename, mtime, file_size) 组合指向的当前文件肯定是非保护的。
    /// 若保留已有行的 `password_required=1`，把保护版换成非保护版时，就会
    /// 永久残留「按保护处理」的状态，placeholder grid 无法显示，
    /// 每次都不得不打开无意义的密码输入对话框。
    /// 直接反映「render 以 None 通过的那一刻就已判明 password_required 为 0」这一
    /// 事实。
    pub fn set_pdf_meta_safe(
        &self,
        filename: &str,
        mtime: i64,
        file_size: i64,
        page_count: u32,
    ) -> rusqlite::Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO pdf_meta \
             (filename, mtime, file_size, page_count, password_required) \
             VALUES (?1, ?2, ?3, ?4, 0) \
             ON CONFLICT(filename) DO UPDATE SET \
               mtime = excluded.mtime, \
               file_size = excluded.file_size, \
               page_count = excluded.page_count, \
               password_required = 0",
            params![filename, mtime, file_size, page_count as i64],
        )?;
        Ok(())
    }

    /// 只在内容 identity 与判定设置的 fingerprint 完全一致时，才返回 ZIP / 仅图片目录 /
    /// 转换目标归档的页数。失败结果不保存，`page_count=NULL` 表示正常扫描该目录后
    /// 判定它「不属于作为书处理的对象」。
    pub fn get_container_page_meta(
        &self,
        filename: &str,
        kind: ContainerPageKind,
        mtime: i64,
        file_size: i64,
        fingerprint: i64,
    ) -> rusqlite::Result<Option<ContainerPageMeta>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT page_count FROM container_page_meta \
             WHERE filename = ?1 AND kind = ?2 AND mtime = ?3 \
               AND file_size = ?4 AND fingerprint = ?5",
        )?;
        stmt.query_row(
            params![filename, kind as i64, mtime, file_size, fingerprint],
            |row| {
                let count: Option<i64> = row.get(0)?;
                Ok(ContainerPageMeta {
                    page_count: count.map(|value| value.max(0) as u32),
                })
            },
        )
        .optional()
    }

    pub fn set_container_page_meta(
        &self,
        filename: &str,
        kind: ContainerPageKind,
        mtime: i64,
        file_size: i64,
        fingerprint: i64,
        page_count: Option<u32>,
    ) -> rusqlite::Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO container_page_meta \
             (filename, kind, mtime, file_size, fingerprint, page_count) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6) \
             ON CONFLICT(filename, kind) DO UPDATE SET \
               mtime = excluded.mtime, file_size = excluded.file_size, \
               fingerprint = excluded.fingerprint, page_count = excluded.page_count",
            params![
                filename,
                kind as i64,
                mtime,
                file_size,
                fingerprint,
                page_count.map(i64::from),
            ],
        )?;
        Ok(())
    }
}
