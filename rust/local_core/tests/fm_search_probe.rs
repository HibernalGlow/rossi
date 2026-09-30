//! 临时探针（量完即删）：用真实文件系统量 FM 搜索在各种真实命名下的命中/漏检。
//!
//! 运行：cargo test -p rossi_local_core --test fm_search_probe -- --nocapture

use std::fs;
use std::path::Path;
use std::sync::atomic::AtomicBool;

use rossi_local_core::file_manager::{
    FileManagerSearchRequest, FileManagerSettings, search_entries,
};

fn probe(
    root: &Path,
    query: &str,
    include_subfolders: bool,
    depth: usize,
) -> (usize, usize, Vec<String>) {
    let mut settings = FileManagerSettings::default();
    settings.search_query = query.to_owned();
    settings.search_include_subfolders = include_subfolders;
    settings.search_max_depth = depth;
    let request = FileManagerSearchRequest {
        root: root.to_path_buf(),
        settings,
    };
    let cancel = AtomicBool::new(false);
    let outcome = search_entries(&request, &cancel);
    (
        outcome.matched,
        outcome.scanned,
        outcome.hits.iter().map(|n| n.name.clone()).collect(),
    )
}

fn report(label: &str, root: &Path, query: &str, sub: bool, depth: usize) {
    let (matched, scanned, hits) = probe(root, query, sub, depth);
    println!(
        "{label:<34} q={query:<26} sub={sub:<5} depth={depth:<3} -> matched={matched:<3} scanned={scanned:<4} hits={hits:?}"
    );
}

fn touch(path: &Path) {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).unwrap();
    }
    fs::write(path, b"x").unwrap();
}

#[test]
fn fm_search_probe() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();

    // 阳性对照：同文种、逐字相同的名字
    touch(&root.join("三上ミカ").join("[DL版] がっこうの時間 第1話.zip"));
    // NFC 存储的 kana（濁点合成的が）
    touch(&root.join("nfc").join("がっこうの時間 第1話.zip"));
    // NFD 存储的 kana（か + U+3099），macOS 之外的来源常是这个形态
    touch(&root.join("nfd").join("か\u{3099}っこうの時間 第1話.zip"));
    // 全角括号
    touch(&root.join("full").join("[サークル (作者)] タイトル（DL版）.zip"));
    // 日文汉字标题
    touch(&root.join("kanji").join("進撃の巨人 第01巻.zip"));
    // 非媒体扩展名
    touch(&root.join("media").join("notes.txt"));
    touch(&root.join("media").join("cover.png"));
    touch(&root.join("media").join("book.pdf"));
    touch(&root.join("media").join("song.mp3"));
    // 深层嵌套（文件位于第 9 层目录里）
    touch(&root.join("deep/a/b/c/d/e/f/g/h").join("たどりつく.zip"));

    // 读回 nfd 目录的实际字节，证明盘上存的是分解形态
    for entry in fs::read_dir(root.join("nfd")).unwrap() {
        let name = entry.unwrap().file_name();
        println!("nfd 盘上名称: {:?}", name.to_string_lossy().escape_debug().to_string());
    }

    println!("\n=== 1. 同文种阳性对照 ===");
    report("三上ミカ (目录名)", root, "三上", true, 6);
    report("NFC がっこう (盘上NFC)", root, "がっこう", true, 6);
    report("NFC がっこう 只在 nfd 子树", &root.join("nfd"), "がっこう", true, 6);
    report("NFD がっこう 只在 nfd 子树", &root.join("nfd"), "か\u{3099}っこう", true, 6);

    println!("\n=== 2. 全角/半角 ===");
    report("半角括号查询", root, "(DL版)", true, 6);
    report("全角括号查询", root, "（DL版）", true, 6);

    println!("\n=== 3. 简繁/日汉字变体 ===");
    report("简体 进击 (应为0)", root, "进击", true, 6);
    report("日文 進撃", root, "進撃", true, 6);

    println!("\n=== 4. 非媒体扩展名 ===");
    for query in ["notes", "cover", "book", "song"] {
        report("扩展名探测", root, query, true, 6);
    }

    println!("\n=== 5. 深度上限 ===");
    report("深层 たどりつく depth=6", root, "たどりつく", true, 6);
    report("深层 たどりつく depth=12", root, "たどりつく", true, 12);

    println!("\n=== 6. 只搜当前层（默认口径）===");
    report("当前层 がっこう", root, "がっこう", false, 6);
    report("当前层 三上(目录在根下)", root, "三上", false, 6);
}

/// 打字流实测（只在 FM_PROBE_ROOT 给出时跑）：
/// `FM_PROBE_ROOT=/Volumes/BOX cargo test -p rossi_local_core --test fm_search_probe typed_query -- --nocapture`
#[test]
fn fm_search_typed_query_probe() {
    use rossi_local_core::file_manager::{FileManagerState, search_entries};
    use std::time::Instant;

    let Ok(root) = std::env::var("FM_PROBE_ROOT") else {
        println!("FM_PROBE_ROOT 未设置，跳过打字流实测");
        return;
    };
    let mut state = FileManagerState::new(Some(std::path::PathBuf::from(&root))).unwrap();
    state.set_search_include_subfolders(true);
    state.set_search_query("すごい");

    let started = Instant::now();
    let listing =
        search_entries(&state.search_request(), &AtomicBool::new(false)).into_listing();
    let scan = (started.elapsed(), listing.matched, listing.scanned);
    state.set_search_listing(listing);
    println!(
        "第一次键入「すごい」  : {:.1?} matched={} scanned={}",
        scan.0, scan.1, scan.2
    );

    // 接着打字（收窄）：应当只在上一批命中里筛，不再读盘。
    state.set_search_query("すごい 火");
    let started = Instant::now();
    let refined = state.try_refine_search_listing();
    println!(
        "接着打「すごい 火」   : {:.1?} refine={refined} 命中={}",
        started.elapsed(),
        state.entries().unwrap().len()
    );

    // 再补一个词元。
    state.set_search_query("すごい 火 マシカル");
    let started = Instant::now();
    let refined = state.try_refine_search_listing();
    println!(
        "再补「マシカル」      : {:.1?} refine={refined} 命中={}",
        started.elapsed(),
        state.entries().unwrap().len()
    );

    // 删字（放宽）：捷径不成立，必须回去真扫。
    state.set_search_query("すごい");
    let started = Instant::now();
    let refined = state.try_refine_search_listing();
    println!(
        "删回「すごい」（放宽）: {:.1?} refine={refined}（必须 false）",
        started.elapsed()
    );
}

/// 真库实测（只在 FM_PROBE_ROOT 给出时跑）：
/// `FM_PROBE_ROOT=/Volumes/BOX cargo test -p rossi_local_core --test fm_search_probe real_library -- --nocapture`
#[test]
fn fm_search_probe_real_library() {
    let Ok(root) = std::env::var("FM_PROBE_ROOT") else {
        println!("FM_PROBE_ROOT 未设置，跳过真库实测");
        return;
    };
    let root = Path::new(&root);
    if !root.is_dir() {
        println!("FM_PROBE_ROOT 不是目录: {}", root.display());
        return;
    }

    let timed = |label: &str, query: &str, sub: bool, depth: usize| {
        let started = std::time::Instant::now();
        let (matched, scanned, hits) = probe(root, query, sub, depth);
        println!(
            "{label:<30} q={:<22} depth={depth:<3} -> matched={matched:<4} scanned={scanned:<7} {:.0?}  hits[..3]={:?}",
            query.escape_debug().to_string(),
            started.elapsed(),
            &hits[..hits.len().min(3)],
        );
    };

    println!("\n=== 真库: {} ===", root.display());
    // すごい 的 NFC 与 NFD 两种写法（盘上两种都存在）
    timed("NFC すごい", "す\u{3054}\u{3044}", true, 6);
    timed("NFD すごい", "す\u{3053}\u{3099}\u{3044}", true, 6);
    timed("NFC おっぱい", "お\u{3063}\u{3071}\u{3044}", true, 6);
    timed("NFD おっぱい", "お\u{3063}\u{306F}\u{309A}\u{3044}", true, 6);
    // 全角与半角括号
    timed("半角 (DL版)", "(DL版)", true, 6);
    timed("全角 （DL版）", "（DL版）", true, 6);
    // 全量扫描成本（查一个必然无命中的词）
    timed("无命中全扫 depth=6", "zzz_no_such_entry_zzz", true, 6);
    timed("无命中全扫 depth=12", "zzz_no_such_entry_zzz", true, 12);
    timed("当前层扫描", "zzz_no_such_entry_zzz", false, 6);
}
