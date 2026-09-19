//! CBR / RAR 来源：**逐条目按需读，不落盘**（ADR-0011）。
//!
//! 这是 v0.1 里唯一需要新引入依赖的一条来源，也是读取模型被写死的一条。
//! 模型直接来自 mImageViewer 的 `src/rar_loader.rs`（模块自述
//! "Flat, non-solid RAR/CBR access used by the virtual-folder read boundary"），
//! 它的要点是：
//!
//! - 读一页 = `open_for_processing()` → 循环 `read_header()` → 命中条目 `read()`、
//!   未命中 `skip()`；函数返回即释放句柄。
//! - **不落盘、不建 session、不跨调用持有归档对象。**
//! - 缓存**只存判定结果**（key = `path + len + mtime`），不缓存归档内容或句柄。
//!
//! 被否决的做法（来自 comicRD 的 `rar-sessions`）：首次访问时把整章图片一次性解压到
//! `<app-data>/rar-sessions/chapter-<id>`，之后 probe/read 走磁盘。那会把「打开一本 CBR」
//! 变成一次全量解压加一份等量磁盘副本——这里明确不做。
//!
//! 唯一允许临时文件的场景是**嵌套归档**（内层必须先落地成路径才能被打开），v0.1 不实现。

use std::collections::HashSet;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::{LazyLock, Mutex};

use anyhow::{Context, Result, bail};

use crate::entry_name::dedup_entry_name;
use crate::page_order::{is_page_name, should_ignore_name, sort_natural};
use crate::{Locator, PageEntry, UnsupportedSource};

/// 单条目直读上限。超过就说明这大概不是漫画页，宁可报错也不要一次吃掉几 GB 内存。
const MAX_DIRECT_ENTRY_BYTES: u64 = 4 * 1024 * 1024 * 1024;
/// 判定缓存容量。条目只含判定结果与计数，不持有归档对象。
const DECISION_CACHE_CAPACITY: usize = 32;
/// 分卷解析缓存容量。条目只有两个路径加一个小枚举，可以多留一些，
/// 供同一目录下的大量 CBR 复用（同样不持有归档内容或句柄）。
const VOLUME_RESOLUTION_CACHE_CAPACITY: usize = 128;

/// 归档能否走直读路径。
///
/// 名字与语义取自 mImageViewer 的 `classify_direct_read`，判定顺序也一样
/// （solid > nested > encrypted）。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RarDirectReadDecision {
    Direct,
    Solid,
    NestedArchive,
    Encrypted,
}

impl RarDirectReadDecision {
    pub fn label(self) -> &'static str {
        match self {
            Self::Direct => "Direct",
            Self::Solid => "Solid",
            Self::NestedArchive => "Nested",
            Self::Encrypted => "Encrypted",
        }
    }
}

/// 归档在分卷序列里的位置（由头部信息判定，不猜文件名）。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RarVolumeKind {
    Single,
    First,
    Subsequent,
}

impl From<unrar::VolumeInfo> for RarVolumeKind {
    fn from(value: unrar::VolumeInfo) -> Self {
        match value {
            unrar::VolumeInfo::None => Self::Single,
            unrar::VolumeInfo::First => Self::First,
            unrar::VolumeInfo::Subsequent => Self::Subsequent,
        }
    }
}

/// 一次判定扫描的结果。
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RarInspection {
    pub decision: RarDirectReadDecision,
    pub image_count: u32,
    pub total_uncompressed_bytes: u64,
    pub nested_archive_count: u32,
    /// **调用方给的那个路径**的头部事实。
    pub volume_kind: RarVolumeKind,
    /// 真正应该被列出/读取的路径：给出后续分卷时，这里会是第一卷。
    pub resolved_path: PathBuf,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct CacheKey {
    path: PathBuf,
    len: u64,
    mtime: Option<std::time::SystemTime>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct VolumeResolution {
    resolved_path: PathBuf,
    volume_kind: RarVolumeKind,
}

static DECISION_CACHE: LazyLock<Mutex<Vec<(CacheKey, RarInspection)>>> =
    LazyLock::new(|| Mutex::new(Vec::new()));
static VOLUME_RESOLUTION_CACHE: LazyLock<Mutex<Vec<(CacheKey, VolumeResolution)>>> =
    LazyLock::new(|| Mutex::new(Vec::new()));

pub fn is_rar_path(path: &Path) -> bool {
    path.extension()
        .and_then(|ext| ext.to_str())
        .is_some_and(|ext| ext.eq_ignore_ascii_case("rar") || ext.eq_ignore_ascii_case("cbr"))
}

/// 嵌套归档的扩展名。命中即判定为 `NestedArchive`（v0.1 不递归展开）。
fn is_nested_archive_name(name: &str) -> bool {
    const NESTED: &[&str] = &[
        "zip", "cbz", "rar", "cbr", "7z", "cb7", "tar", "gz", "bz2", "xz", "lzh", "lha",
    ];
    name.rsplit_once('.')
        .is_some_and(|(_, ext)| NESTED.contains(&ext.to_ascii_lowercase().as_str()))
}

fn normalized_entry_name(path: &Path) -> String {
    path.to_string_lossy().replace('\\', "/")
}

fn unrar_error(err: unrar::error::UnrarError) -> anyhow::Error {
    use unrar::error::Code;
    let hint = match err.code {
        Code::MissingPassword | Code::BadPassword => "（归档需要密码；v0.1 不支持加密 CBR）",
        _ => "",
    };
    anyhow::anyhow!("RAR: {err}{hint}")
}

fn cache_key(path: &Path) -> io::Result<CacheKey> {
    let meta = std::fs::metadata(path)?;
    Ok(CacheKey {
        path: path.to_path_buf(),
        len: meta.len(),
        mtime: meta.modified().ok(),
    })
}

/// 判定顺序取自 mImageViewer：solid 优先于 nested，nested 优先于 encrypted。
pub fn classify_direct_read(
    is_solid: bool,
    has_nested: bool,
    has_encrypted: bool,
) -> RarDirectReadDecision {
    if is_solid {
        RarDirectReadDecision::Solid
    } else if has_nested {
        RarDirectReadDecision::NestedArchive
    } else if has_encrypted {
        RarDirectReadDecision::Encrypted
    } else {
        RarDirectReadDecision::Direct
    }
}

fn cached_volume_resolution(key: &CacheKey) -> Option<VolumeResolution> {
    let cache = VOLUME_RESOLUTION_CACHE.lock().ok()?;
    cache
        .iter()
        .rev()
        .find(|(cached, _)| cached == key)
        .map(|(_, resolution)| resolution.clone())
}

fn remember_volume_resolution(key: &CacheKey, resolution: VolumeResolution) {
    let Ok(mut cache) = VOLUME_RESOLUTION_CACHE.lock() else {
        return;
    };
    // 同一路径的 (len, mtime) 变了，说明文件被换过，旧身份作废。
    cache.retain(|(cached, _)| cached.path != key.path);
    if cache.len() >= VOLUME_RESOLUTION_CACHE_CAPACITY {
        cache.remove(0);
    }
    cache.push((key.clone(), resolution));
}

/// 解析「这个路径应该从哪一卷开始读」。
///
/// 分卷判定的依据是**头部信息**，不是文件名：`Vol.2a.rar` 这种名字看起来像后续卷，
/// 实际可能是独立归档。文件名猜测在这件事上一定会出错。
pub fn resolved_volume_path(path: &Path) -> Result<(PathBuf, RarVolumeKind)> {
    let key = cache_key(path).ok();
    if let Some(resolution) = key.as_ref().and_then(cached_volume_resolution) {
        return Ok((resolution.resolved_path, resolution.volume_kind));
    }

    let archive = unrar::Archive::new(path);
    let first_part = archive.first_part();
    let opened = archive
        .open_for_listing()
        .map_err(unrar_error)
        .with_context(|| format!("打开 RAR 失败: {}", path.display()))?;
    let volume_kind = RarVolumeKind::from(opened.volume_info());
    drop(opened);

    let resolved = if volume_kind == RarVolumeKind::Subsequent {
        first_part
    } else {
        path.to_path_buf()
    };
    if let Some(key) = key.as_ref() {
        remember_volume_resolution(
            key,
            VolumeResolution {
                resolved_path: resolved.clone(),
                volume_kind,
            },
        );
    }
    Ok((resolved, volume_kind))
}

/// 打开一个列表游标，必要时先跳到第一卷。
fn open_listing(
    path: &Path,
) -> Result<(
    unrar::OpenArchive<unrar::List, unrar::CursorBeforeHeader>,
    RarVolumeKind,
    PathBuf,
)> {
    let (resolved, volume_kind) = resolved_volume_path(path)?;
    let opened = unrar::Archive::new(&resolved)
        .open_for_listing()
        .map_err(unrar_error)
        .with_context(|| format!("打开 RAR 失败: {}", resolved.display()))?;
    Ok((opened, volume_kind, resolved))
}

/// 检查归档是否具备直读资格。不合格时返回可被调用方精确识别的错误。
///
/// 注意 v0.1 的口径：solid / 加密 / 嵌套都是**明确报错**，而不是静默降级到解压。
/// Rossi 手里没有「解压兜底」这条路，所以静默降级只会在别处变成更难懂的失败。
pub fn ensure_direct_readable(inspection: &RarInspection) -> Result<()> {
    let unsupported = match inspection.decision {
        RarDirectReadDecision::Direct => return Ok(()),
        RarDirectReadDecision::Solid => UnsupportedSource::RarSolid,
        RarDirectReadDecision::NestedArchive => UnsupportedSource::RarNestedArchive,
        RarDirectReadDecision::Encrypted => UnsupportedSource::RarEncrypted,
    };
    Err(anyhow::Error::new(unsupported).context(format!(
        "{}（判定 {}，图片 {} 张）",
        inspection.resolved_path.display(),
        inspection.decision.label(),
        inspection.image_count
    )))
}

/// 判定一个 RAR 是否能直读。结果按 `(path, len, mtime)` 缓存。
pub fn inspect(path: &Path) -> Result<RarInspection> {
    let key = cache_key(path).with_context(|| format!("读取文件属性失败: {}", path.display()))?;
    if let Ok(cache) = DECISION_CACHE.lock()
        && let Some((_, inspection)) = cache.iter().find(|(cached, _)| cached == &key)
    {
        return Ok(inspection.clone());
    }

    let (mut archive, volume_kind, resolved_path) = open_listing(path)?;
    let is_solid = archive.is_solid();
    let mut has_encrypted = archive.has_encrypted_headers();
    let mut image_count = 0u32;
    let mut total_uncompressed_bytes = 0u64;
    let mut nested_archive_count = 0u32;

    for entry in archive.by_ref() {
        let entry = entry.map_err(unrar_error)?;
        // 加密是「整包是否可用」的属性，要包括 UI 里看不见的条目。
        has_encrypted |= entry.is_encrypted();
        if !entry.is_file() {
            continue;
        }
        let name = normalized_entry_name(&entry.filename);
        if should_ignore_name(&name) {
            continue;
        }
        if is_page_name(&name) {
            image_count = image_count.saturating_add(1);
            total_uncompressed_bytes = total_uncompressed_bytes.saturating_add(entry.unpacked_size);
        } else if is_nested_archive_name(&name) {
            nested_archive_count = nested_archive_count.saturating_add(1);
        }
    }

    let inspection = RarInspection {
        decision: classify_direct_read(is_solid, nested_archive_count > 0, has_encrypted),
        image_count,
        total_uncompressed_bytes,
        nested_archive_count,
        volume_kind,
        resolved_path,
    };

    if let Ok(mut cache) = DECISION_CACHE.lock() {
        cache.retain(|(cached, _)| cached.path != key.path);
        if cache.len() >= DECISION_CACHE_CAPACITY {
            cache.remove(0);
        }
        cache.push((key, inspection.clone()));
    }
    Ok(inspection)
}

/// 枚举页面。会先做直读资格检查。
pub fn enumerate_pages(path: &Path) -> Result<Vec<PageEntry>> {
    let inspection = inspect(path)?;
    ensure_direct_readable(&inspection)?;

    let (archive, _, _) = open_listing(path)?;
    let mut seen = HashSet::new();
    let mut pages = Vec::new();
    for entry in archive {
        let entry = entry.map_err(unrar_error)?;
        if !entry.is_file() {
            continue;
        }
        let name = normalized_entry_name(&entry.filename);
        if should_ignore_name(&name) || !is_page_name(&name) {
            continue;
        }
        let display = dedup_entry_name(name, &mut seen);
        pages.push(PageEntry {
            size: entry.unpacked_size,
            locator: Locator::RarEntryName(display.clone()),
            name: display,
        });
    }

    sort_natural(&mut pages, |page| page.name.as_str());
    Ok(pages)
}

/// 按名字读一条条目的字节。**这就是 ADR-0011 写死的那条路径。**
///
/// 每次调用重新开归档、顺序推进头部；命中就读进内存，未命中就跳过；
/// 返回即释放，不跨调用留下任何句柄或内容。
pub fn read_entry(path: &Path, wanted: &str) -> Result<Vec<u8>> {
    let wanted = wanted.replace('\\', "/");
    let (resolved_path, _) = resolved_volume_path(path)?;
    let mut archive = unrar::Archive::new(&resolved_path)
        .open_for_processing()
        .map_err(unrar_error)
        .with_context(|| format!("打开 RAR 失败: {}", resolved_path.display()))?;

    // 去重名是「扫描顺序」的函数，所以读的时候必须用同一套 seen 集合重放一遍，
    // 否则第 2 个重名条目会对不上号。
    let mut seen = HashSet::new();
    loop {
        let Some(header) = archive.read_header().map_err(unrar_error)? else {
            bail!("归档里没有条目: {wanted}");
        };
        let entry = header.entry();
        let name = normalized_entry_name(&entry.filename);
        let resolved_name = entry
            .is_file()
            .then(|| {
                if should_ignore_name(&name) || !is_page_name(&name) {
                    None
                } else {
                    Some(dedup_entry_name(name.clone(), &mut seen))
                }
            })
            .flatten();

        if resolved_name.as_deref() == Some(wanted.as_str()) {
            if entry.unpacked_size > MAX_DIRECT_ENTRY_BYTES {
                bail!("条目声明大小 {} 字节，超过直读上限", entry.unpacked_size);
            }
            let (bytes, _next) = header.read().map_err(unrar_error)?;
            return Ok(bytes);
        }
        archive = header.skip().map_err(unrar_error)?;
    }
}

/// 读出第一个图片条目（缩略图/首屏用），跳过整个前导部分只做一次。
pub fn read_first_image(path: &Path) -> Result<Option<(String, Vec<u8>)>> {
    let (resolved_path, _) = resolved_volume_path(path)?;
    let mut archive = unrar::Archive::new(&resolved_path)
        .open_for_processing()
        .map_err(unrar_error)?;
    let mut seen = HashSet::new();
    loop {
        let Some(header) = archive.read_header().map_err(unrar_error)? else {
            return Ok(None);
        };
        let entry = header.entry();
        let name = normalized_entry_name(&entry.filename);
        let display = entry
            .is_file()
            .then(|| {
                if should_ignore_name(&name) || !is_page_name(&name) {
                    None
                } else {
                    Some(dedup_entry_name(name.clone(), &mut seen))
                }
            })
            .flatten();
        if let Some(display) = display {
            if entry.unpacked_size <= MAX_DIRECT_ENTRY_BYTES {
                let (bytes, _next) = header.read().map_err(unrar_error)?;
                return Ok(Some((display, bytes)));
            }
        }
        archive = header.skip().map_err(unrar_error)?;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 两页非固实 RAR 的夹具，**取自 mImageViewer 源码里的测试夹具**
    /// （`src/rar_loader.rs::direct_read_test_fixture_bytes`，MIT）。
    /// 它的价值在于两条条目的**存储名都叫 `page.png`**——正好压住「同名去重必须
    /// 与读取时重放的 seen 集合一致」这条约束。
    /// 两个 PNG 解压后分别是 165 与 188 字节。
    fn fixture_bytes() -> Vec<u8> {
        use base64::Engine as _;
        base64::engine::general_purpose::STANDARD
            .decode(concat!(
                "UmFyIRoHAQAzkrXlCgEFBgAFAQGAgABdyPuwJAIDC6UBBKUBIL8JEzuAAAAIcGFnZS5wbmcKAwKX0YuaNf3cAYlQTkcNChoKAAAADUlIRFIAAABAAAAAMAgCAAAALinrSAAAAGxJREFUeJztz7EJgDAAAEEMYiGW7j9mCgtxjCP48APcb+8z9+tetzGOc+28oAEtaEALGtCCBrSgAS1oQAsa0IIGtKABLWhACxrQgga0oAEtaEALGtCCBrSgAS1oQAsa0IIGtKABLWhAC34+8AHOE9+qokthcQAAAABJRU5ErkJggo4TMhYkAgMLvAEEvAEgRG2V/YAAAAhwYWdlLnBuZwoDAgoki5o1/dwBiVBORw0KGgoAAAANSUhEUgAAAEAAAAAwCAIAAAAuKetIAAAAC3RFWHRwYXJhbWV0ZXJzAAmqaREAAABsSURBVHic7c+xCYAwAABBDGIhli6YeR3I1jGO4MMPcL89892ve93GOM6184IGtKABLWhACxrQgga0oAEtaEALGtCCBrSgAS1oQAsa0IIGtKABLWhACxrQgga0oAEtaEALGtCCBrSgAS34+cAHG8He3/HxQZMAAAAASUVORK5CYIIdd1ZRAwUEAA=="
            ))
            .expect("内嵌夹具必须是合法 base64")
    }

    fn write_fixture(dir: &Path) -> PathBuf {
        let path = dir.join("duplicate-names.cbr");
        std::fs::write(&path, fixture_bytes()).unwrap();
        path
    }

    #[test]
    fn classifier_accepts_only_flat_non_solid_unencrypted_archives() {
        assert_eq!(
            classify_direct_read(false, false, false),
            RarDirectReadDecision::Direct
        );
        assert_eq!(
            classify_direct_read(true, false, false),
            RarDirectReadDecision::Solid
        );
        assert_eq!(
            classify_direct_read(false, true, false),
            RarDirectReadDecision::NestedArchive
        );
        assert_eq!(
            classify_direct_read(false, false, true),
            RarDirectReadDecision::Encrypted
        );
        // 判定优先级：solid 压过 nested
        assert_eq!(
            classify_direct_read(true, true, true),
            RarDirectReadDecision::Solid
        );
    }

    #[test]
    fn duplicate_entry_names_are_unique_and_read_back_distinct_bytes() {
        let dir = tempfile::tempdir().unwrap();
        let path = write_fixture(dir.path());

        let inspection = inspect(&path).unwrap();
        assert_eq!(inspection.decision, RarDirectReadDecision::Direct);
        assert_eq!(inspection.image_count, 2);
        assert_eq!(inspection.volume_kind, RarVolumeKind::Single);
        ensure_direct_readable(&inspection).unwrap();

        let pages = enumerate_pages(&path).unwrap();
        let mut names: Vec<&str> = pages.iter().map(|p| p.name.as_str()).collect();
        // 去重保证两个名字都存在。顺序不钉死：自然序下 `page (2).png` 会排在
        // `page.png` 前面（`(` 的码位小于 `.`），这只是稳定的实现细节，
        // 真正要钉的是下面这条——名字与字节必须一一对上。
        names.sort_unstable();
        assert_eq!(names, vec!["page (2).png", "page.png"]);

        for page in &pages {
            let bytes = read_entry(&path, &page.name).unwrap();
            assert_eq!(
                bytes.len() as u64,
                page.size,
                "{} 的字节长度必须与列表里声明的一致",
                page.name
            );
        }
        let first = read_entry(&path, "page.png").unwrap();
        let second = read_entry(&path, "page (2).png").unwrap();
        assert_eq!(first.len(), 165);
        assert_eq!(second.len(), 188);
        assert_ne!(first, second);

        // 两页都能真的解码出来（直读模型交付的是可解码字节，不是原始容器数据）
        let decoded = crate::decode::decode_rgba(&first).unwrap();
        assert_eq!((decoded.width, decoded.height), (64, 48));
    }

    #[test]
    fn reading_a_missing_entry_reports_not_found() {
        let dir = tempfile::tempdir().unwrap();
        let path = write_fixture(dir.path());
        let error = read_entry(&path, "nope.png").unwrap_err();
        assert!(error.to_string().contains("nope.png"), "{error}");
    }

    #[test]
    fn first_image_short_circuits_the_scan() {
        let dir = tempfile::tempdir().unwrap();
        let path = write_fixture(dir.path());
        let (name, bytes) = read_first_image(&path).unwrap().unwrap();
        assert_eq!(name, "page.png");
        assert_eq!(bytes.len(), 165);
    }

    #[test]
    fn decision_cache_does_not_keep_the_archive_alive() {
        // 判定缓存里只能有判定结果：把文件删掉之后，缓存条目必须因为 stat 失败而失效，
        // 而不是继续返回一份「看起来还能读」的判定。
        let dir = tempfile::tempdir().unwrap();
        let path = write_fixture(dir.path());
        assert_eq!(
            inspect(&path).unwrap().decision,
            RarDirectReadDecision::Direct
        );
        std::fs::remove_file(&path).unwrap();
        assert!(inspect(&path).is_err());
    }

    /// 上游检出的真实样本更能压住分卷判定：文件名（`Vol.2.rar`、`Vol.１.rar`）
    /// 全都像后续卷，头部却说它们是独立归档。猜文件名一定错，读头部才对。
    ///
    /// 样本在 `vendor/mimageviewer` 子模块里，未检出时跳过（不算失败）。
    #[test]
    fn real_world_multipart_names_are_resolved_by_header() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../vendor/mimageviewer/testdata/archives/rar-multipart-filename-regression");
        if !root.is_dir() {
            eprintln!("跳过：{} 不存在（vendor 子模块未检出）", root.display());
            return;
        }
        let mut checked = 0;
        for entry in std::fs::read_dir(&root).unwrap() {
            let path = entry.unwrap().path();
            if !is_rar_path(&path) {
                continue;
            }
            let inspection = inspect(&path).unwrap();
            assert_eq!(
                inspection.volume_kind,
                RarVolumeKind::Single,
                "{} 应按头部判定为独立归档",
                path.display()
            );
            assert_eq!(inspection.resolved_path, path);
            let pages = enumerate_pages(&path).unwrap();
            assert!(!pages.is_empty(), "{} 应该能列出页面", path.display());
            checked += 1;
        }
        assert!(checked > 0, "样本目录里应当有 RAR");
    }
}
