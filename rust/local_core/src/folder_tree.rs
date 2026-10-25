//! ファイルシステム上のフォルダツリー走査ヘルパー。
//!
//! Vendored directly from `vendor/mimageviewer/src/folder_tree.rs` (MIT). The
//! compatibility modules at the local-core boundary provide only host services;
//! the folder predicates and navigation functions remain upstream source.
//!
//! - サポート画像/動画拡張子の定数
//! - フォルダ内に画像があるかの判定
//! - Ctrl+↑/↓ 用の深さ優先前順 DFS (next/prev)
//! - キャッシュ作成用の再帰サブフォルダ列挙
//!
//! ZIP ファイルもフォルダの一種としてナビゲーション対象に含める (タスク 3)。

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};

/// Ctrl+↑↓ DFS / `sorted_subdirs` の挙動を変える設定パラメータ。
///
/// Phase 4 (spec §8, Codex P2 v13b フォロー) で `Settings::load()` を内部で呼ぶ代わりに、
/// 呼び出し側 (`App` 等) が `Settings` を一度だけ読み、ここに必要な値だけ詰めて渡す。
/// これで `folder_tree` モジュールは `crate::settings` に runtime 依存しなくなる
/// (= ナビゲーション中の並列 `Settings::load()` 起動を撲滅、boot race を消す)。
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FolderTreeOptions {
    /// Shared folder/book candidate projection, after existing eligibility checks.
    pub same_name_folder_book: crate::same_name_folder_book::SameNameFolderBookPolicy,
    /// 同名 ZIP/CBZ がある変換アーカイブをスキップする。
    pub skip_archive_if_zip_exists: bool,
    /// RAR/7z/LZH などの変換アーカイブをフォルダ移動候補に含める。
    pub include_convertible_archives: bool,
    /// サブフォルダ / ZIP のソート順 (= `Settings.sort_order`)。
    pub sort_order: crate::settings::SortOrder,
}

impl FolderTreeOptions {
    /// `Settings` から関連フィールドだけ抜き出す convenience。
    pub fn from_settings(settings: &crate::settings::Settings) -> Self {
        Self {
            same_name_folder_book: settings.same_name_folder_book,
            skip_archive_if_zip_exists: settings.skip_archive_if_zip_exists,
            include_convertible_archives: !settings.archive_file_handling_ignores_convertible(),
            sort_order: settings.sort_order,
        }
    }
}

impl Default for FolderTreeOptions {
    fn default() -> Self {
        Self {
            same_name_folder_book: Default::default(),
            skip_archive_if_zip_exists: true,
            include_convertible_archives: true,
            sort_order: crate::settings::SortOrder::default(),
        }
    }
}

// -----------------------------------------------------------------------
// サポート拡張子
// -----------------------------------------------------------------------

/// 標準サポートする画像拡張子。
///
/// 前半は `image` クレートで直接デコードできる形式。
/// 後半は WIC (Windows Imaging Component) でデコードする形式で、
/// 対応コーデックが Microsoft Store からインストールされている必要がある:
/// - heic/heif → HEIF Image Extensions
/// - avif      → AV1 Video Extensions
/// - jxl       → JPEG XL Image Extensions
/// - cr2/nef/arw 等 → Raw Image Extension
///
/// Rossi Added two alias suffixes on top of the upstream table: `wbp` (a renamed
/// WebP — neoview `media.ts:13` lists it the same way) and `apng` (the container is
/// PNG). Both were invisible in the file browser before, which is a listing bug
/// rather than a decode gap: whether a page can be decoded is `page_order`'s call,
/// while this table only answers "does this entry show up at all".
pub const SUPPORTED_EXTENSIONS: &[&str] = &[
    // image クレートで直接デコード
    "jpg", "jpeg", "png", "webp", "wbp", "apng", "bmp", "gif", // WIC 経由 (モダン形式)
    "heic", "heif", "avif", "jxl",
    // WIC 経由 (TIFF: image クレートも対応するが WIC の方が高機能)
    "tiff", "tif", "dng", "cr2", "cr3", "nef", "nrw", "arw", "srf", "sr2", "raf", "orf", "rw2",
    "pef", "ptx", "rwl", "iiq", "crw", "srw", "3fr", "erf", "kdc", "dcr", "mrw", "mos",
];
// 文件列表、目录穿透与阅读器页序共用同一份视频格式表。
pub const SUPPORTED_VIDEO_EXTENSIONS: &[&str] = crate::page_order::VIDEO_EXTENSIONS;

/// 標準サポートする音声拡張子 (フルスクリーン音楽ビューで再生する)。
/// FFmpeg (LGPL build) がデコードできる主要なコンテナに絞る
/// (`docs/music-integration-plan.md`)。動画コンテナと共有する拡張子 (mp4 等) は
/// `SUPPORTED_VIDEO_EXTENSIONS` 側で動画として扱うので、ここには含めない。
pub const SUPPORTED_AUDIO_EXTENSIONS: &[&str] =
    &["mp3", "flac", "wav", "m4a", "aac", "ogg", "opus", "wma"];

/// 拡張子 (小文字、先頭 `.` なし) が音声ファイルとして扱えるか判定する。
pub fn is_audio_ext(ext_lower: &str) -> bool {
    SUPPORTED_AUDIO_EXTENSIONS.contains(&ext_lower)
}

#[cfg(test)]
mod audio_ext_tests {
    use super::*;

    #[test]
    fn recognizes_common_audio_extensions() {
        for ext in ["mp3", "flac", "wav", "m4a", "aac", "ogg", "opus", "wma"] {
            assert!(is_audio_ext(ext), "{ext} should be audio");
        }
    }

    #[test]
    fn rejects_non_audio_and_video_shared_extensions() {
        // 画像・動画・非対応は false。動画と共有する mp4 は動画扱いなので音声にしない。
        for ext in ["jpg", "png", "mp4", "mkv", "txt", "zip", "pdf"] {
            assert!(!is_audio_ext(ext), "{ext} should not be audio");
        }
    }
}

/// 拡張子 (小文字、先頭 `.` なし) が画像として扱えるか判定する。
///
/// ネイティブ対応の `SUPPORTED_EXTENSIONS` に加え、起動時にロードした Susie プラグイン
/// が対応する拡張子もここで画像扱いとする。Susie がロード前、または無効の場合は
/// `SUPPORTED_EXTENSIONS` のみで判定する。
///
/// Rossi 追加の一段：`SUPPORTED_EXTENSIONS` は**デフォルト表**であって唯一の表ではない。
/// 設定で自定义した后缀（[`crate::media_formats`]）もここで効く —— 这一档必须落在 Rust，
/// 因为它决定的是条目**是否出现在列表里**。只改 Dart 侧那套 `RossiMediaKind` 的话，
/// 用户加了后缀仍然在文件管理器里看不见（`.wbp` 被隐藏就是这个根因）。
pub fn is_recognized_image_ext(ext_lower: &str) -> bool {
    crate::media_formats::is_image_ext(ext_lower)
        || crate::susie_loader::supports_extension(ext_lower)
}

// -----------------------------------------------------------------------
// macOS AppleDouble (._) ファイルの除外
// -----------------------------------------------------------------------

/// macOS / iPhone から FAT32/NTFS にコピーした際に生成される
/// AppleDouble メタデータファイル (`._*`) を除外する。
/// 拡張子は画像と同じだが中身はメタデータなのでデコードできない。
pub fn is_apple_double(path: &Path) -> bool {
    path.file_name()
        .and_then(|n| n.to_str())
        .map(|s| s.starts_with("._"))
        .unwrap_or(false)
}

/// `.zip` と、その別名 (comic-book) 拡張子 `.cbz` を ZIP 仮想フォルダとして扱うかの判定。
/// 入力は小文字化済みの拡張子 (他の `is_*_ext` と同じ規約)。CBZ は実体が ZIP なので
/// 変換せずネイティブ ZIP として最速で閲覧する。
pub fn is_zip_extension(ext: &str) -> bool {
    ext == "zip" || ext == "cbz"
}

/// `.pdf` を PDF 仮想フォルダとして扱うかの判定。入力は小文字化済みの拡張子
/// (`is_zip_extension` と同じ規約)。ZIP 側と対で置くことで、仮想フォルダ判定と
/// 名前索引の分類が同じ綴りを共有する。
pub fn is_pdf_extension(ext: &str) -> bool {
    ext == "pdf"
}

/// .zip / .cbz / .pdf ファイルを仮想フォルダとして扱うかの判定。
pub fn is_virtual_folder(path: &Path) -> bool {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_ascii_lowercase())
        .unwrap_or_default();
    is_zip_extension(&ext) || is_pdf_extension(&ext)
}

/// Runtime container predicate for a path already opened as a page list.
/// Static scanning keeps RAR as `ConvertibleArchive`; only the active direct-read
/// RAR/CBR view uses this broader predicate.
pub fn is_open_as_container(path: &Path) -> bool {
    is_virtual_folder(path) || crate::rar_loader::is_rar_path(path)
}

/// RAR/CBR / 7z/CB7 / LZH/LHA など、クリックで ZIP に変換してから開くアーカイブか。
///
/// `is_virtual_folder` (= 変換不要でネイティブに開ける ZIP/PDF) とは別物。起動時の
/// last_folder 復元やアドレスバー入力で、変換アーカイブも「開けるパス」として扱うために使う。
/// 実際の変換 / キャッシュ参照は呼び出し側 (`load_folder_or_convert_archive`) の責務。
pub fn is_convertible_archive_path(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .and_then(crate::archive_converter::ArchiveFormat::from_extension)
        .is_some()
}

fn is_folder_nav_file_candidate(path: &Path, opts: FolderTreeOptions) -> bool {
    is_virtual_folder(path)
        || (opts.include_convertible_archives
            && is_convertible_archive_path(path)
            && !is_confirmed_subsequent_rar_volume(path))
}

/// Folder navigation runs on its DFS worker, so it may confirm ambiguous RAR names by opening
/// the supplied file's header. Name matching only narrows the candidates; unreadable files stay
/// visible instead of being hidden on a guess.
fn is_confirmed_subsequent_rar_volume(path: &Path) -> bool {
    crate::archive_converter::looks_like_non_first_rar_part(path)
        && crate::rar_loader::is_subsequent_volume(path).unwrap_or(false)
}

// -----------------------------------------------------------------------
// 画像有無の判定
// -----------------------------------------------------------------------

/// Ctrl+↑↓ でフォルダをスキップすべきか判定する。
/// スキップしない（＝立ち寄る）条件:
/// - PDF ファイル → 常に立ち寄る（ページが必ずある）
/// - ZIP ファイル → 中に画像エントリが 1 つでもあれば立ち寄る
/// - 通常フォルダ → 画像・動画が 1 つでもあれば立ち寄る
///
/// ZIP の中身検査はセントラルディレクトリを開くのみで、インストーラ等の
/// 画像なし ZIP をスキップ扱いにするための判定。以前はフォルダ直下の
/// ZIP/PDF を 2 個以上数えて立ち寄る実装だったが、ドキュメント/インストーラ
/// ZIP だけのフォルダで誤ヒットしたため廃止した。DFS は `sorted_subdirs`
/// 経由で ZIP/PDF ファイル自体を個別に訪問するので通常フォルダ側で束ねる
/// 必要がない。
///
/// `cancel` が指定された場合、エントリ走査中に定期的に確認し、
/// セットされていれば `false` を返して早期離脱する (呼び出し元もキャンセルを
/// 見ている想定なので、この戻り値は「止まるべきではない」ではなく
/// 「判定を打ち切った」という意味で使われる)。
pub fn folder_should_stop(path: &Path, cancel: Option<&AtomicBool>) -> bool {
    folder_should_stop_with_options(path, cancel, FolderTreeOptions::default())
}

pub fn folder_should_stop_with_options(
    path: &Path,
    cancel: Option<&AtomicBool>,
    opts: FolderTreeOptions,
) -> bool {
    folder_qualifies(path, cancel, true, opts)
}

/// スライドショーの次フォルダ判定用: 静止画系コンテンツがあるか。
/// `folder_should_stop` と同じだが、**動画拡張子は「コンテンツあり」と数えない**
/// (= 動画のみフォルダ・画像なしフォルダは false)。これにより NextFolder スライドショーが
/// 動画のみフォルダを skip-walk で飛ばし、静止画フォルダに直接着地できる。
/// PDF / 画像入り ZIP は静止画系コンテナとして true。
pub fn folder_has_still_image(path: &Path, cancel: Option<&AtomicBool>) -> bool {
    folder_has_still_image_with_options(path, cancel, FolderTreeOptions::default())
}

pub fn folder_has_still_image_with_options(
    path: &Path,
    cancel: Option<&AtomicBool>,
    opts: FolderTreeOptions,
) -> bool {
    folder_qualifies(path, cancel, false, opts)
}

/// `folder_should_stop` / `folder_has_still_image` の共通実装。
/// `include_video=true` なら動画拡張子も「立ち寄る」条件に含める。
fn folder_qualifies(
    path: &Path,
    cancel: Option<&AtomicBool>,
    include_video: bool,
    opts: FolderTreeOptions,
) -> bool {
    if cancel.is_some_and(|c| c.load(Ordering::Relaxed)) {
        return false;
    }

    if path.is_file() {
        if is_convertible_archive_path(path) {
            return opts.include_convertible_archives && !is_confirmed_subsequent_rar_volume(path);
        }
        if !is_virtual_folder(path) {
            return false;
        }
        let ext = path
            .extension()
            .and_then(|e| e.to_str())
            .map(|e| e.to_ascii_lowercase())
            .unwrap_or_default();
        return match ext.as_str() {
            "pdf" => true,
            e if is_zip_extension(e) => {
                crate::zip_loader::first_image_entry(path, cancel).is_some()
            }
            _ => false,
        };
    }

    let entries = match std::fs::read_dir(path) {
        Ok(rd) => rd,
        Err(_) => return false,
    };
    for e in entries.flatten() {
        if cancel.is_some_and(|c| c.load(Ordering::Relaxed)) {
            return false;
        }
        let p = e.path();
        if is_apple_double(&p) {
            continue;
        }
        if let Some(ext) = p.extension().and_then(|e| e.to_str()) {
            let ext_lower = ext.to_lowercase();
            if is_recognized_image_ext(&ext_lower)
                || (include_video && crate::media_formats::is_video_ext(&ext_lower))
            {
                return true;
            }
        }
    }

    false
}

// -----------------------------------------------------------------------
// フォルダツリー走査（深さ優先・前順）
// -----------------------------------------------------------------------

/// `navigate_folder_with_skip` の結果。画像フォルダを見つけたか、
/// skip_limit / DFS 末端でのフォールバックかを呼び出し側が区別できるようにする。
pub struct FolderNavOutcome {
    /// 移動先フォルダ (DFS が示した次候補、または画像ありフォルダ)。
    pub path: PathBuf,
    /// `folder_should_stop` をパスした (= 画像/動画/ZIP/PDF を含む) フォルダか。
    /// `false` のときは skip_limit 尽きまたは DFS 末端でのフォールバックで、
    /// 呼び出し側は「見つからなかった」扱いにできる。
    pub hit_image_folder: bool,
}

/// Ctrl+↑↓ フォルダ移動：画像なしフォルダを最大 skip_limit 回スキップする。
/// skip_limit 回以内に画像ありフォルダが見つかればそこへ移動
/// (`hit_image_folder = true`)。見つからなければ直近の隣フォルダ（1ステップ先）に
/// フォールバックして `hit_image_folder = false` で返す。
/// DFS 末端 (nav_fn が None を返す) に達した場合も同様。
///
/// `cancel` が指定された場合、各ステップ開始時に確認し、セットされていれば
/// `None` を返して早期離脱する。連打で新しい要求が入ったときに旧スレッドの
/// DFS をすぐ畳めるようにするための機構。
pub fn navigate_folder_with_skip<F, S>(
    start: &Path,
    nav_fn: F,
    should_stop: S,
    skip_limit: usize,
    cancel: Option<&AtomicBool>,
) -> Option<FolderNavOutcome>
where
    F: Fn(&Path) -> Option<PathBuf>,
    S: Fn(&Path, Option<&AtomicBool>) -> bool,
{
    if cancel.is_some_and(|c| c.load(Ordering::Relaxed)) {
        return None;
    }
    let first = nav_fn(start)?;
    let mut candidate = first.clone();
    // skip_limit == 0 のとき (設定 JSON 手編集等で 0 が入った場合) でも、
    // 最低 1 回は first を評価する。さもないと first が画像フォルダでも
    // hit_image_folder = false で返って、フルスクリーン側が「見つからなかった」
    // 扱いで移動を取り消してしまう。
    let iterations = skip_limit.max(1);
    for _ in 0..iterations {
        if cancel.is_some_and(|c| c.load(Ordering::Relaxed)) {
            return None;
        }
        if should_stop(&candidate, cancel) {
            return Some(FolderNavOutcome {
                path: candidate,
                hit_image_folder: true,
            });
        }
        match nav_fn(&candidate) {
            Some(next) => candidate = next,
            None => {
                return Some(FolderNavOutcome {
                    path: first,
                    hit_image_folder: false,
                });
            }
        }
    }
    // skip_limit 回分全て画像なし → 直近の隣フォルダにフォールバック
    Some(FolderNavOutcome {
        path: first,
        hit_image_folder: false,
    })
}

/// 深さ優先前順で次のフォルダを返す。
/// 子があれば最初の子、なければ次の兄弟、なければ祖先の次の兄弟。
///
/// ただし `current` 自身やその祖先へ戻る循環 junction / ディレクトリシンボリック
/// リンクの子には潜らない (葉として扱い、次の子 → 兄弟へ進める)。junction を
/// フォルダ候補に含めるようにした (v1.6.x) ため、自己参照 junction に潜ると
/// `loop\loop\…` と 1 ステップずつ無限に前進し、junction 後ろの実フォルダへ
/// 到達できなくなる。後方 DFS (`last_descendant_dir_inner`) の visited-set ガードと
/// 対になる前方側の循環対策。
pub fn next_folder_dfs(current: &Path, opts: FolderTreeOptions) -> Option<PathBuf> {
    // 1. 子フォルダがあれば最初の (循環でない) 子へ
    let children = sorted_subdirs(current, opts);
    if !children.is_empty() {
        let current_ancestor_keys = canonical_ancestor_keys(current);
        for child in children {
            if !directory_descent_creates_cycle(&current_ancestor_keys, &child) {
                return Some(child);
            }
        }
    }
    // 2. 子がない / 子がすべて循環なら、次の兄弟または祖先の次の兄弟を探す
    next_sibling_or_ancestor_sibling(current, opts)
}

/// `current` を canonicalize し、その実体パスと全祖先の正規化キーを返す。
/// canonicalize に失敗した場合 (壊れた junction / 権限なし) は空 `Vec` を返し、
/// 循環判定をすべて false に倒して従来の DFS 動作へフォールバックする。
fn canonical_ancestor_keys(current: &Path) -> Vec<String> {
    let Ok(real) = std::fs::canonicalize(current) else {
        return Vec::new();
    };
    real.ancestors()
        .map(crate::fs_entry::directory_visit_key)
        .collect()
}

/// `child` ディレクトリへ DFS で潜ると無限ループになるか (= `child` の実体が
/// `current` 自身またはその祖先へ戻る循環か) を判定する。`current_ancestor_keys`
/// が空 (= current を解決できなかった) なら常に false。`child` の canonicalize に
/// 失敗した場合 (壊れた junction / 権限なし) も安全側で false を返し、skip_limit /
/// 深さ上限のバックストップに委ねる。
fn directory_descent_creates_cycle(current_ancestor_keys: &[String], child: &Path) -> bool {
    if current_ancestor_keys.is_empty() {
        return false;
    }
    let Ok(child_real) = std::fs::canonicalize(child) else {
        return false;
    };
    let child_key = crate::fs_entry::directory_visit_key(&child_real);
    current_ancestor_keys.iter().any(|k| k == &child_key)
}

/// 深さ優先前順で前のフォルダを返す。
/// 前の兄弟がいればその最後の子孫、最初の子であれば親。
pub fn prev_folder_dfs(current: &Path, opts: FolderTreeOptions) -> Option<PathBuf> {
    let parent = current.parent()?;
    let siblings = sorted_subdirs(parent, opts);
    let pos = siblings.iter().position(|s| path_eq(s, current))?;

    if pos == 0 {
        // 最初の子 → 親へ
        Some(parent.to_path_buf())
    } else {
        // 前の兄弟の最後の子孫へ
        Some(last_descendant_dir(&siblings[pos - 1], opts))
    }
}

/// 現在のフォルダ / 仮想フォルダと同じ親を持つ、次の兄弟を返す。
/// 子や祖先の兄弟へは移動しない (Ctrl+PageDown 用)。
pub fn next_sibling_folder(current: &Path, opts: FolderTreeOptions) -> Option<PathBuf> {
    let parent = current.parent()?;
    let siblings = sorted_subdirs(parent, opts);
    let pos = siblings.iter().position(|s| path_eq(s, current))?;
    siblings.get(pos + 1).cloned()
}

/// 現在のフォルダ / 仮想フォルダと同じ親を持つ、前の兄弟を返す。
/// 前の兄弟の末端へ潜らず、兄弟そのものを返す (Ctrl+PageUp 用)。
pub fn prev_sibling_folder(current: &Path, opts: FolderTreeOptions) -> Option<PathBuf> {
    let parent = current.parent()?;
    let siblings = sorted_subdirs(parent, opts);
    let pos = siblings.iter().position(|s| path_eq(s, current))?;
    pos.checked_sub(1)
        .and_then(|idx| siblings.get(idx).cloned())
}

/// path の次の兄弟を返す。兄弟がなければ親で再帰する。
fn next_sibling_or_ancestor_sibling(path: &Path, opts: FolderTreeOptions) -> Option<PathBuf> {
    let parent = path.parent()?;
    let siblings = sorted_subdirs(parent, opts);
    let pos = siblings.iter().position(|s| path_eq(s, path))?;

    if pos + 1 < siblings.len() {
        Some(siblings[pos + 1].clone())
    } else {
        next_sibling_or_ancestor_sibling(parent, opts)
    }
}

/// path の最も深い最後の子孫フォルダを返す（子がなければ path 自身）。
fn last_descendant_dir(path: &Path, opts: FolderTreeOptions) -> PathBuf {
    let mut visited = HashSet::new();
    last_descendant_dir_inner(path, opts, 0, &mut visited)
}

fn last_descendant_dir_inner(
    path: &Path,
    opts: FolderTreeOptions,
    depth: u32,
    visited: &mut HashSet<String>,
) -> PathBuf {
    const MAX_DESCEND_DEPTH: u32 = 64;
    if depth >= MAX_DESCEND_DEPTH || !crate::fs_entry::mark_directory_visited(path, visited) {
        return path.to_path_buf();
    }
    let children = sorted_subdirs(path, opts);
    match children.last() {
        Some(last) => last_descendant_dir_inner(last, opts, depth + 1, visited),
        None => path.to_path_buf(),
    }
}

// -----------------------------------------------------------------------
// 再帰的サブフォルダ列挙 (キャッシュ作成用)
// -----------------------------------------------------------------------

/// path 以下のすべてのサブフォルダ（path 自身を含む）を再帰的に収集する。
pub fn walk_dirs_recursive(path: &Path, out: &mut Vec<PathBuf>, cancel: &AtomicBool) {
    walk_dirs_recursive_with_progress(path, out, cancel, &mut |_| {}, &mut |_, _| {}, None);
}

/// `walk_dirs_recursive` の進捗通知付きバージョン。
/// 訪問するディレクトリごとに `on_visit(path)` を呼ぶ。
/// `read_dir` 失敗時は `on_error(path, &err)` を呼ぶ (汎用 DFS なのでこの関数自体は
/// log を出さず、callback を経由して呼び出し側が用途別に判断する。鳥小屋論理を
/// `name_bulk_indexer` 等の利用者に集中させ、他用途 (キャッシュ作成等) には影響させない
/// ため — Codex P2 レビュー指摘)。`on_visit` 同様にスロットリング (rate limit) は
/// 呼び出し側の責務。
///
/// `yield_check` を渡すと、各ディレクトリの entries ループ内で 64 件ごとに
/// `ActivityGate::wait_until_idle` を呼ぶ。大量ファイル (1 フォルダ 10000+ 件) を
/// 持つフォルダの file_type 連続呼び出し中でも、UI 操作 (動画オープン等) で
/// 64 entry 以内に indexer が停止する。
pub fn walk_dirs_recursive_with_progress(
    path: &Path,
    out: &mut Vec<PathBuf>,
    cancel: &AtomicBool,
    on_visit: &mut dyn FnMut(&Path),
    on_error: &mut dyn FnMut(&Path, &std::io::Error),
    yield_check: Option<&crate::activity_gate::ActivityGate>,
) {
    walk_dirs_recursive_with_progress_excluding(
        path,
        out,
        cancel,
        on_visit,
        on_error,
        yield_check,
        &[],
    );
}

/// `walk_dirs_recursive_with_progress` と同じだが、`excluded_roots` 配下には入らない。
pub fn walk_dirs_recursive_with_progress_excluding(
    path: &Path,
    out: &mut Vec<PathBuf>,
    cancel: &AtomicBool,
    on_visit: &mut dyn FnMut(&Path),
    on_error: &mut dyn FnMut(&Path, &std::io::Error),
    yield_check: Option<&crate::activity_gate::ActivityGate>,
    excluded_roots: &[PathBuf],
) {
    let mut visited = HashSet::new();
    walk_dirs_recursive_with_progress_inner(
        path,
        out,
        cancel,
        on_visit,
        on_error,
        yield_check,
        excluded_roots,
        0,
        &mut visited,
    );
}

#[allow(clippy::too_many_arguments)]
fn walk_dirs_recursive_with_progress_inner(
    path: &Path,
    out: &mut Vec<PathBuf>,
    cancel: &AtomicBool,
    on_visit: &mut dyn FnMut(&Path),
    on_error: &mut dyn FnMut(&Path, &std::io::Error),
    yield_check: Option<&crate::activity_gate::ActivityGate>,
    excluded_roots: &[PathBuf],
    depth: u32,
    visited: &mut HashSet<String>,
) {
    const MAX_WALK_DEPTH: u32 = 64;
    if cancel.load(Ordering::Relaxed) {
        return;
    }
    if depth > MAX_WALK_DEPTH || !crate::fs_entry::mark_directory_visited(path, visited) {
        return;
    }
    if crate::books::path_is_under_any(path, excluded_roots) {
        return;
    }
    if !path.is_dir() {
        return;
    }
    on_visit(path);
    // on_visit 内で ActivityGate 等の待機が入るケースがある。待機中に cancel が
    // 立った場合、ここで弾かないと「停止要求後にもう 1 フォルダ分だけ read_dir
    // が走る」挙動になる (Codex P3)。
    if cancel.load(Ordering::Relaxed) {
        return;
    }
    out.push(path.to_path_buf());
    match std::fs::read_dir(path) {
        Ok(entries) => {
            const YIELD_EVERY_N: usize = 64;
            let mut processed: usize = 0;
            for entry in entries.flatten() {
                if cancel.load(Ordering::Relaxed) {
                    return;
                }
                if processed > 0
                    && processed % YIELD_EVERY_N == 0
                    && let Some(gate) = yield_check
                {
                    gate.wait_until_idle(cancel);
                    if cancel.load(Ordering::Relaxed) {
                        return;
                    }
                }
                processed += 1;
                if crate::fs_entry::is_internal_app_entry_name(&entry.file_name()) {
                    continue;
                }
                // file_type() で GetFileAttributes syscall を避ける (scan_directory と同様)
                let is_dir = entry
                    .file_type()
                    .map(|ft| crate::fs_entry::classify_dir_entry(&entry, &ft).is_directory())
                    .unwrap_or(false);
                if is_dir {
                    let child = entry.path();
                    if crate::books::path_is_under_any(&child, excluded_roots) {
                        continue;
                    }
                    walk_dirs_recursive_with_progress_inner(
                        &child,
                        out,
                        cancel,
                        on_visit,
                        on_error,
                        yield_check,
                        excluded_roots,
                        depth + 1,
                        visited,
                    );
                }
            }
        }
        Err(e) => on_error(path, &e),
    }
}

// -----------------------------------------------------------------------
// 共通ユーティリティ
// -----------------------------------------------------------------------

/// path 配下の "子フォルダ + 開けるコンテナファイル" をソート済みで返す。
/// ZIP/PDF と変換アーカイブもナビゲーション対象として扱う。
///
/// Phase 4 (spec §8): 旧版は内部で `Settings::load()` を呼んでいたが、boot race を
/// 撲滅するため `FolderTreeOptions` を呼び出し側から受け取る形に変更
/// (= ナビ中の並列 Settings::load() を 0 件に)。
pub fn sorted_subdirs(path: &Path, opts: FolderTreeOptions) -> Vec<PathBuf> {
    let sort_order = opts.sort_order;

    // (PathBuf, mtime_secs) を蓄積。ソート時に mtime と name を引く。
    let mut dirs: Vec<(PathBuf, i64)> = Vec::new();
    let mut real_folder_names: std::collections::HashSet<String> = std::collections::HashSet::new();
    let mut container_candidates: Vec<(PathBuf, i64)> = Vec::new();

    if let Ok(entries) = std::fs::read_dir(path) {
        for e in entries.flatten() {
            if crate::fs_entry::is_internal_app_entry_name(&e.file_name()) {
                continue;
            }
            // Windows: `DirEntry::file_type()` は FindFirstFile のキャッシュ読み
            // (追加 syscall なし)。`Path::is_dir()` / `is_file()` は都度
            // `GetFileAttributes` を呼ぶので、数百ファイルのフォルダで
            // 数百 ms のブロック源になる。DFS は毎ステップ sorted_subdirs を
            // 呼ぶため影響が大きい。必ず file_type 経由で判定する。
            let ft = match e.file_type() {
                Ok(t) => t,
                Err(_) => continue,
            };
            let p = e.path();
            // mtime は DateAsc/Desc のソートでだけ意味を持つので、それ以外なら
            // 0 でも構わない。`metadata()` が追加 syscall になるので、必要なときだけ取る。
            let mtime: i64 = if sort_order.uses_mtime() {
                e.metadata()
                    .and_then(|m| m.modified())
                    .ok()
                    .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                    .map(|d| d.as_secs() as i64)
                    .unwrap_or(0)
            } else {
                0
            };
            let kind = crate::fs_entry::classify_dir_entry(&e, &ft);
            if kind.is_directory() {
                if let Some(name) = p.file_name().and_then(|n| n.to_str()) {
                    real_folder_names.insert(name.to_lowercase());
                }
                dirs.push((p, mtime));
            } else if kind.is_file() && is_folder_nav_file_candidate(&p, opts) {
                container_candidates.push((p, mtime));
            }
        }
    }

    let native_zip_stems: std::collections::HashSet<String> = container_candidates
        .iter()
        .filter_map(|(path, _)| {
            let ext = path.extension()?.to_str()?.to_ascii_lowercase();
            is_zip_extension(&ext).then(|| {
                path.file_stem()
                    .and_then(|stem| stem.to_str())
                    .unwrap_or("")
                    .to_lowercase()
            })
        })
        .collect();

    // Existing book-vs-book precedence, followed by the shared folder/book policy.
    for (zp, mtime) in container_candidates {
        if opts.skip_archive_if_zip_exists
            && is_convertible_archive_path(&zp)
            && native_zip_stems.contains(
                &zp.file_stem()
                    .and_then(|stem| stem.to_str())
                    .unwrap_or("")
                    .to_lowercase(),
            )
        {
            continue;
        }
        dirs.push((zp, mtime));
    }

    let mask = crate::same_name_folder_book::keep_mask(
        opts.same_name_folder_book,
        dirs.iter().map(|(path, _)| {
            (
                path.as_path(),
                real_folder_names.contains(
                    &path
                        .file_name()
                        .unwrap_or_default()
                        .to_string_lossy()
                        .to_lowercase(),
                ),
            )
        }),
    );
    let mut mask = mask.into_iter();
    dirs.retain(|_| mask.next().unwrap());

    // グリッドと同じソート規則を使う。名前キーは候補ごとに 1 回だけ作る。
    let mut keyed_dirs: Vec<_> = dirs
        .into_iter()
        .map(|(path, mtime)| {
            let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
            let key = sort_order.name_key(name);
            (path, mtime, key)
        })
        .collect();
    keyed_dirs
        .sort_by(|(_, a_mt, ak), (_, b_mt, bk)| sort_order.compare_name_keys(ak, *a_mt, bk, *b_mt));
    keyed_dirs.into_iter().map(|(p, _, _)| p).collect()
}

/// 保留上游 Windows 比较规则；Unix 不折叠大小写或反斜杠。
pub fn path_eq(a: &Path, b: &Path) -> bool {
    #[cfg(windows)]
    {
        crate::path_key::eq_keep_drive(a, b)
    }
    #[cfg(not(windows))]
    {
        a == b
    }
}

/// `resolve_openable_path_detailed` が返した「開けるパス」の実体種別。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OpenablePathKind {
    Directory,
    File,
}

/// 与えられたパスを「開けるパス」に解決した結果。
///
/// `requested_is_file` は、通常画像ファイルを起動引数で受け取ったときに
/// 親フォルダを開いてそのファイルを選択するために使う。UI スレッドで
/// `Path::is_file` を再実行しないよう、解決時点の判定をここに載せる。
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OpenablePathResolution {
    pub path: PathBuf,
    pub kind: OpenablePathKind,
    pub requested_is_file: bool,
}

/// 与えられたパスを「開けるパス」に解決する。
///
/// - 通常のディレクトリならそのまま返す
/// - `.zip` / `.cbz` / `.pdf` ファイル (ファイルとして存在) ならそのまま返す
/// - RAR/CBR / 7z/CB7 / LZH/LHA など変換対応アーカイブ (ファイルとして存在) もそのまま返す
///   (実際の変換 / キャッシュ参照は呼び出し側 `load_folder_or_convert_archive` が行う)
/// - 存在しない/開けない場合は親ディレクトリを再帰的に遡り、最初に見つかった
///   有効なディレクトリを返す
/// - どこにも辿り着けない場合 (ドライブ自体が存在しない等) は `None`
///
/// 起動時の last_folder 復元やアドレスバー入力で、削除済み・移動済み・取り外された
/// ドライブのパスでもクラッシュせず最も近い場所を表示するために使う。
pub fn resolve_openable_path(path: &Path) -> Option<std::path::PathBuf> {
    resolve_openable_path_detailed(path).map(|r| r.path)
}

/// `resolve_openable_path` の詳細版。返却 path の種別と、元リクエストが
/// ファイルだったかを同じ filesystem stat の流れで返す。
pub fn resolve_openable_path_detailed(path: &Path) -> Option<OpenablePathResolution> {
    let accepted_path = crate::path_key::normalize_input_path(path);
    let path = accepted_path.as_path();
    // そのまま開けるか
    if path.is_dir() {
        return Some(OpenablePathResolution {
            path: path.to_path_buf(),
            kind: OpenablePathKind::Directory,
            requested_is_file: false,
        });
    }
    let requested_is_file = path.is_file();
    if requested_is_file && (is_virtual_folder(path) || is_convertible_archive_path(path)) {
        return Some(OpenablePathResolution {
            path: path.to_path_buf(),
            kind: OpenablePathKind::File,
            requested_is_file,
        });
    }

    // 親を再帰的に遡る
    let mut current = path.parent();
    while let Some(p) = current {
        if p.as_os_str().is_empty() {
            return None;
        }
        if p.is_dir() {
            return Some(OpenablePathResolution {
                path: p.to_path_buf(),
                kind: OpenablePathKind::Directory,
                requested_is_file,
            });
        }
        current = p.parent();
    }
    None
}

#[cfg(test)]
#[path = "folder_tree/tests.rs"]
mod tests;
