//! 本地来源（散图文件夹 / CBZ / CBR）的会话层 —— v0.1 判据 A 进入 App 的唯一入口。
//!
//! 对应 `docs/v0.1-local-core.md` §9。`rossi_local_core` 只保存「根路径 + 类型 + 页序列」，
//! 不持有任何打开的文件/归档对象，所以**会话表放在这一层**（Reader session 由 Rossi 侧持有）。
//!
//! ```text
//! open_local_source(path) -> LocalSourceOpenResult { source | rejection }
//! local_source_pages(id)  -> Vec<LocalPageInfo>
//! local_page_bytes(id, i) -> 该页的**编码字节**（JPEG/PNG/…）
//! local_close(id)         -> bool
//! ```
//!
//! ## 为什么 open 不返回 `anyhow::Result`
//!
//! `rossi_local_core` 故意用**类型**而不是错误字符串表达拒绝原因（`UnsupportedSource`），
//! 因为 UI 要区分「这本是固实压缩的 RAR」和「这文件损坏了」——这两种情况给用户的下一步动作
//! 完全不同（换一本 / 查文件）。而 `anyhow::Error` 跨 FRB 之后只剩 Dart 侧的
//! `AnyhowException.message` 一个字符串，**类别信息在那一步就丢了**。
//!
//! 所以 `open_local_source` 返回 `LocalSourceOpenResult`，让类别以**枚举**过桥；
//! 其余接口（读字节等）的失败确实是「意料之外的 IO/损坏」，继续用 `anyhow` 不会丢信息。
//!
//! ## 边界：这里传的是**编码字节**，不是像素
//!
//! `local_page_bytes` 返回的是归档里的原始 JPEG/PNG 字节。这与 ROADMAP「明确不做」里
//! 那条「不把所有图片转成 Dart `Uint8List` 再交给 Flutter」**不冲突**：
//! 那条禁止的是把**解码后的 RGBA** 搬过桥（即 decode → CPU RGBA → Flutter 的老路）。
//! 上屏路径的目标形态是 Rust 侧解码后直接进 GPU texture（Phase 1 的 `texture-bridge`），
//! 编码字节过桥只用于 Dart 侧兜底显示与尺寸探测。

use std::sync::atomic::{AtomicU64, Ordering};

use anyhow::Error;
use dashmap::DashMap;
use flutter_rust_bridge::frb;
use lazy_static::lazy_static;
use rossi_local_core::{LocalSource, ShellOnlyFormat, SourceKind, UnsupportedSource};

lazy_static! {
    /// `id → LocalSource`。**只存路径与页元数据**，所以它的体积与「打开了几本」成正比，
    /// 与「读了多少页」无关——这是判据 D 在 App 层仍然成立的原因。
    static ref SESSIONS: DashMap<u64, LocalSource> = DashMap::new();
    static ref NEXT_SESSION_ID: AtomicU64 = AtomicU64::new(1);
}

/// 来源类型。与 `rossi_local_core::SourceKind` 一一对应（单独声明是为了不受
/// 依赖里的类型改动直接影响 Dart 侧的枚举名）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LocalSourceKind {
    Folder,
    Zip,
    Rar,
}

impl From<SourceKind> for LocalSourceKind {
    fn from(value: SourceKind) -> Self {
        match value {
            SourceKind::Folder => Self::Folder,
            SourceKind::Zip => Self::Zip,
            SourceKind::Rar => Self::Rar,
        }
    }
}

/// 被**主动拒绝**的原因类别。UI 按类别给不同提示与下一步动作。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LocalRejectionKind {
    /// 扩展名不在 v0.1 范围内（7z / PDF / 视频……）。
    UnknownFormat,
    /// 固实 RAR：读第 N 页要解压前 N-1 页。
    RarSolid,
    /// 归档里含嵌套归档（v0.1 不展开）。
    RarNestedArchive,
    /// 加密 RAR（v0.1 不提供密码输入）。
    RarEncrypted,
    /// 路径不存在或不可读。
    NotFound,
    /// 其他 IO / 解析失败（含归档损坏）。
    Io,
}

#[derive(Debug, Clone)]
pub struct LocalRejection {
    pub kind: LocalRejectionKind,
    /// 可直接展示给用户的说明（已本地化）。
    pub message: String,
}

#[derive(Debug, Clone)]
pub struct LocalSourceInfo {
    /// 会话 id，后续所有调用都用它。
    pub id: u64,
    pub path: String,
    pub kind: LocalSourceKind,
    pub page_count: u32,
    pub total_bytes: u64,
}

/// `open_local_source` 的返回值：要么拿到 `source`，要么拿到 `rejection`，不会两者都有。
#[derive(Debug, Clone)]
pub struct LocalSourceOpenResult {
    pub source: Option<LocalSourceInfo>,
    pub rejection: Option<LocalRejection>,
}

#[derive(Debug, Clone)]
pub struct LocalPageInfo {
    pub index: u32,
    /// 展示名（页序已由 Rust 侧自然序决定，Dart 侧不要再排一次）。
    pub name: String,
    /// 编码字节数。文件夹来源为文件长度。
    pub size: u64,
}

#[frb]
pub async fn open_local_source(path: String) -> LocalSourceOpenResult {
    // 打开归档要解析中央目录 / RAR 头部，是阻塞 IO，放到全局阻塞线程池上。
    rquickjs_playground::global_handle()
        .spawn_blocking(move || open_local_source_impl(path))
        .await
        .unwrap_or_else(|err| LocalSourceOpenResult {
            source: None,
            rejection: Some(LocalRejection {
                kind: LocalRejectionKind::Io,
                message: format!("打开本地来源的任务失败: {err}"),
            }),
        })
}

fn open_local_source_impl(path: String) -> LocalSourceOpenResult {
    let source = match LocalSource::open(&path) {
        Ok(source) => source,
        Err(error) => {
            return LocalSourceOpenResult {
                source: None,
                rejection: Some(classify_open_error(&error)),
            };
        }
    };

    let id = NEXT_SESSION_ID.fetch_add(1, Ordering::Relaxed);
    let info = LocalSourceInfo {
        id,
        path: source.root().to_string_lossy().into_owned(),
        kind: source.kind().into(),
        page_count: source.len() as u32,
        total_bytes: source.total_bytes(),
    };
    SESSIONS.insert(id, source);
    LocalSourceOpenResult {
        source: Some(info),
        rejection: None,
    }
}

/// 把 `anyhow::Error` 还原成可分类的拒绝原因。
///
/// `LocalSource::open` 用 `with_context` 包了一层，所以类型化的原因要用
/// `downcast_ref` **向下穿透**（而不是只看最外层消息）。
fn classify_open_error(error: &Error) -> LocalRejection {
    if let Some(unsupported) = error.downcast_ref::<UnsupportedSource>() {
        let kind = match unsupported {
            UnsupportedSource::UnknownFormat(_) => LocalRejectionKind::UnknownFormat,
            UnsupportedSource::RarSolid => LocalRejectionKind::RarSolid,
            UnsupportedSource::RarNestedArchive => LocalRejectionKind::RarNestedArchive,
            UnsupportedSource::RarEncrypted => LocalRejectionKind::RarEncrypted,
        };
        return LocalRejection {
            kind,
            message: unsupported.to_string(),
        };
    }

    if let Some(io_error) = error.downcast_ref::<std::io::Error>() {
        let kind = if io_error.kind() == std::io::ErrorKind::NotFound {
            LocalRejectionKind::NotFound
        } else {
            LocalRejectionKind::Io
        };
        return LocalRejection {
            kind,
            message: format!("{error:#}"),
        };
    }

    LocalRejection {
        kind: LocalRejectionKind::Io,
        message: format!("{error:#}"),
    }
}

#[frb]
pub async fn local_source_pages(id: u64) -> Result<Vec<LocalPageInfo>, Error> {
    let source = session(id)?;
    rquickjs_playground::global_handle()
        .spawn_blocking(move || {
            Ok(source
                .pages()
                .iter()
                .enumerate()
                .map(|(index, page)| LocalPageInfo {
                    index: index as u32,
                    name: page.name.clone(),
                    size: page.size,
                })
                .collect())
        })
        .await?
}

/// 取一页的**编码字节**。每调用一次都会重新打开来源（不常驻句柄，判据 D）。
#[frb]
pub async fn local_page_bytes(id: u64, index: u32) -> Result<Vec<u8>, Error> {
    let source = session(id)?;
    rquickjs_playground::global_handle()
        .spawn_blocking(move || source.page_bytes(index as usize))
        .await?
}

/// 一页解码后的像素（RGBA8，未预乘，行主序）。
#[derive(Debug, Clone)]
pub struct LocalPagePixels {
    pub width: u32,
    pub height: u32,
    /// `width * height * 4` 字节。
    pub rgba: Vec<u8>,
}

/// 解码失败的**类别**。用枚举而不是字符串，理由与 `LocalRejection` 相同：
/// 「这一页的格式核心没解码器」和「字节坏了」给用户的下一步动作完全不同。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LocalDecodeFailureKind {
    /// 核心没有这个格式的解码器（`jxl` / `heic` / `heif`），要交外壳 —— 而外壳解得动
    /// 与否取决于平台（Windows 引擎实测解不动，见 `rossi_local_core::page_order`）。
    ShellOnlyFormat,
    /// 核心有解码器但没解出来：字节损坏、内容与格式不符等。
    DecodeFailed,
}

#[derive(Debug, Clone)]
pub struct LocalDecodeFailure {
    pub kind: LocalDecodeFailureKind,
    /// 可直接展示的说明（已本地化）。
    pub message: String,
}

/// `local_page_pixels` 的返回值：要么 `pixels`，要么 `failure`。
#[derive(Debug, Clone)]
pub struct LocalPageDecodeResult {
    pub pixels: Option<LocalPagePixels>,
    pub failure: Option<LocalDecodeFailure>,
}

/// 取一页的**解码后像素**。
///
/// 和 [`local_page_bytes`] 的分工必须说清，否则很容易用错：
/// - `local_page_bytes` 给的是**编码字节**，Dart 侧自己解 —— 只对 Dart 引擎认识的格式有效。
///   Windows 引擎没有 AV1 解码器，所以 avif 走那条路只会得到
///   `Could not decompress image.`（实测见 `rossi_local_core::page_order`）。
/// - 这一条走 **Rust 侧解码器**，是 avif 目前唯一能出图的路。
///
/// # 这是过渡形态，不是终点
///
/// Phase 1 的目标是「Rust 解码 → GPU texture 上屏」，那一步**不过桥**。
/// 这里把 RGBA 整块搬给 Dart（再由 `ui.decodeImageFromPixels` 上屏），
/// 一页 44.8 MPix 就是 179 MB 的拷贝 —— 判据 C 的 p95 ≤ 16.7 ms
/// **不在这一形态下成立**，别拿它的数字当结论。
#[frb]
pub async fn local_page_pixels(id: u64, index: u32) -> LocalPageDecodeResult {
    let source = match session(id) {
        Ok(source) => source,
        Err(error) => return decode_failed(format!("{error:#}")),
    };

    rquickjs_playground::global_handle()
        .spawn_blocking(move || decode_page_impl(&source, index as usize))
        .await
        .unwrap_or_else(|error| decode_failed(format!("解码任务失败: {error}")))
}

fn decode_failed(message: String) -> LocalPageDecodeResult {
    LocalPageDecodeResult {
        pixels: None,
        failure: Some(LocalDecodeFailure {
            kind: LocalDecodeFailureKind::DecodeFailed,
            message,
        }),
    }
}

fn decode_page_impl(source: &LocalSource, index: usize) -> LocalPageDecodeResult {
    match source.page_pixels(index) {
        Ok(pixels) => LocalPageDecodeResult {
            pixels: Some(LocalPagePixels {
                width: pixels.width,
                height: pixels.height,
                rgba: pixels.rgba,
            }),
            failure: None,
        },
        Err(error) => {
            // 与 `classify_open_error` 同理：`page_pixels` 内部也用 `with_context` 包过，
            // 类型化的原因必须 `downcast_ref` **向下穿透**。否则「这本是 jxl、要交外壳」
            // 会退化成「解码失败」，而这两者的下一步动作完全不同。
            let kind = if error.downcast_ref::<ShellOnlyFormat>().is_some() {
                LocalDecodeFailureKind::ShellOnlyFormat
            } else {
                LocalDecodeFailureKind::DecodeFailed
            };
            LocalPageDecodeResult {
                pixels: None,
                failure: Some(LocalDecodeFailure {
                    kind,
                    message: format!("{error:#}"),
                }),
            }
        }
    }
}

/// 关闭会话并释放。返回 `false` 表示 id 不存在（重复关闭、或已被回收）。
#[frb(sync)]
pub fn local_close(id: u64) -> bool {
    SESSIONS.remove(&id).is_some()
}

/// 当前打开的会话数。
///
/// 这是判据 D 的**探针**：连读三本之后，这个数必须回落到基线附近，
/// 不允许单调上升。GPU/handle 侧泄漏不体现在 RSS 里，只能靠这种计数观测。
#[frb(sync)]
pub fn local_open_session_count() -> u32 {
    SESSIONS.len() as u32
}

/// 关闭全部会话。用于「换书」「退出阅读器」这类整批释放的场景。
#[frb(sync)]
pub fn local_close_all() -> u32 {
    let count = SESSIONS.len() as u32;
    SESSIONS.clear();
    count
}

fn session(id: u64) -> Result<LocalSource, Error> {
    SESSIONS
        .get(&id)
        .map(|entry| entry.value().clone())
        .ok_or_else(|| anyhow::anyhow!("本地来源会话不存在或已关闭: id={id}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 碰全局 `SESSIONS` 的测试必须串行 —— `cargo test` 默认是多线程的。
    ///
    /// `SESSIONS` 是进程级单例：`open_read_close_round_trip` 插入会话的那一瞬间，
    /// 如果 `session_count_does_not_drift_when_books_are_cycled` 正在读计数，
    /// 断言就会看到 1 而不是 0。这不是逻辑错，是**拿共享全局状态当夹具**的固有代价。
    /// 2026-09-16 观察到这个抖动：新增一条测试改变了调度顺序，它才露出来。
    static SESSIONS_TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    fn lock_sessions() -> std::sync::MutexGuard<'static, ()> {
        // 有测试 panic 过会把锁标记为 poisoned；这里关心的是互斥，不是那次失败。
        SESSIONS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn make_cbz(dir: &std::path::Path, name: &str) -> std::path::PathBuf {
        use std::io::Write;
        let path = dir.join(name);
        let file = std::fs::File::create(&path).unwrap();
        let mut zip = zip::ZipWriter::new(file);
        let options = zip::write::SimpleFileOptions::default();
        for page in ["p1.png", "p2.png"] {
            zip.start_file(page, options).unwrap();
            let buffer = image::RgbaImage::new(4, 3);
            let mut bytes = std::io::Cursor::new(Vec::new());
            image::DynamicImage::ImageRgba8(buffer)
                .write_to(&mut bytes, image::ImageFormat::Png)
                .unwrap();
            zip.write_all(&bytes.into_inner()).unwrap();
        }
        zip.finish().unwrap();
        path
    }

    #[test]
    fn open_read_close_round_trip() {
        let _guard = lock_sessions();
        let dir = tempfile::tempdir().unwrap();
        let path = make_cbz(dir.path(), "book.cbz");

        let opened = open_local_source_impl(path.to_string_lossy().into_owned());
        assert!(opened.rejection.is_none(), "{:?}", opened.rejection);
        let info = opened.source.unwrap();
        assert_eq!(info.kind, LocalSourceKind::Zip);
        assert_eq!(info.page_count, 2);

        let source = session(info.id).unwrap();
        assert_eq!(source.pages()[0].name, "p1.png");
        assert!(!source.page_bytes(0).unwrap().is_empty());

        assert!(local_close(info.id));
        assert!(!local_close(info.id), "重复关闭应当返回 false");
        assert!(session(info.id).is_err());
    }

    #[test]
    fn rejection_keeps_the_category_across_the_boundary() {
        // 未知扩展名：必须是 UnknownFormat，而不是笼统的 Io。
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("book.7z");
        std::fs::write(&path, b"7z\xBC\xAF\x27\x1C").unwrap();

        let opened = open_local_source_impl(path.to_string_lossy().into_owned());
        let rejection = opened.rejection.expect("应当被拒绝");
        assert_eq!(rejection.kind, LocalRejectionKind::UnknownFormat);
        assert!(opened.source.is_none());

        // 路径不存在：必须是 NotFound（UI 提示「文件不见了」而不是「格式不支持」）。
        let opened = open_local_source_impl(
            dir.path().join("nope.cbz").to_string_lossy().into_owned(),
        );
        let rejection = opened.rejection.expect("应当被拒绝");
        assert_eq!(rejection.kind, LocalRejectionKind::NotFound);
    }

    #[test]
    fn session_count_does_not_drift_when_books_are_cycled() {
        let _guard = lock_sessions();
        // 判据 D 的探针在 App 层仍然要成立：反复开关不会留下会话。
        let dir = tempfile::tempdir().unwrap();
        let baseline = local_open_session_count();
        for round in 0..5 {
            let path = make_cbz(dir.path(), &format!("book-{round}.cbz"));
            let opened = open_local_source_impl(path.to_string_lossy().into_owned());
            let info = opened.source.unwrap();
            assert_eq!(local_close(info.id), true);
            assert_eq!(local_open_session_count(), baseline);
        }
    }

    /// 解码归属**不能**在过桥时退化成「解码失败」。
    ///
    /// 三种输入各走一条岔路：能解的、核心没解码器的（交外壳）、核心解不出来的（坏了）。
    /// 前两个若被合成一个，UI 就没法给出正确的下一步动作 —— 这是 `LocalRejection`
    /// 那条教训在解码侧的同一个形状。
    #[test]
    fn page_pixels_separate_shell_only_from_broken_bytes() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("mixed");
        std::fs::create_dir(&root).unwrap();

        let buffer = image::RgbaImage::new(4, 3);
        let mut encoded = std::io::Cursor::new(Vec::new());
        image::DynamicImage::ImageRgba8(buffer)
            .write_to(&mut encoded, image::ImageFormat::Png)
            .unwrap();
        std::fs::write(root.join("1.png"), encoded.into_inner()).unwrap();
        // 垃圾字节冒充 jxl：闸门在解码**之前**，所以内容是什么无关紧要。
        std::fs::write(root.join("2.jxl"), b"not really a jxl").unwrap();
        // 垃圾字节冒充 png：这一页会真的走到解码器，报出的必须是 DecodeFailed。
        std::fs::write(root.join("3.png"), b"not really a png").unwrap();

        let source = LocalSource::open(&root).unwrap();
        assert_eq!(source.len(), 3);

        let ok = decode_page_impl(&source, 0);
        assert!(ok.failure.is_none(), "{:?}", ok.failure);
        assert_eq!(ok.pixels.unwrap().width, 4);

        let shell = decode_page_impl(&source, 1);
        assert_eq!(
            shell.failure.expect("应当失败").kind,
            LocalDecodeFailureKind::ShellOnlyFormat
        );

        let broken = decode_page_impl(&source, 2);
        assert_eq!(
            broken.failure.expect("应当失败").kind,
            LocalDecodeFailureKind::DecodeFailed
        );
    }
}
