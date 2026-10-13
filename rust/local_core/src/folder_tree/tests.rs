use super::*;
#[cfg(windows)]
#[test]
fn path_eq_ignores_separator_spelling_but_keeps_path_identity() {
    assert!(path_eq(
        Path::new(r"g:/Home/comfyui\genshin_random"),
        Path::new(r"G:\home\comfyui\genshin_random")
    ));
    assert!(path_eq(
        Path::new("//Server/Share/book.zip"),
        Path::new(r"\\server\share\book.zip")
    ));
    for other in [
        r"H:\home\comfyui\genshin_random",
        r"G:\home\comfyui\genshin_random_extra",
        r"G:\home\comfyui\..\genshin_random",
    ] {
        assert!(!path_eq(
            Path::new("g:/home/comfyui/genshin_random"),
            Path::new(other)
        ));
    }
    assert!(!path_eq(Path::new(r"\\?\G:\home"), Path::new(r"G:\home")));
}

// Deliberately bypass input normalization: navigation must also handle old
// saved paths and read_dir's different separator spelling at every ancestor.
#[cfg(windows)]
fn mixed_input_spelling(path: &Path) -> PathBuf {
    let raw = path.to_str().unwrap();
    assert!(raw.as_bytes()[0].is_ascii_alphabetic() && raw.as_bytes()[1] == b':');
    let (parent, name) = raw.rsplit_once('\\').unwrap();
    PathBuf::from(format!(
        "{}\\{name}",
        parent.replace('\\', "/").to_lowercase()
    ))
}

#[cfg(windows)]
#[test]
fn mixed_path_dfs_reaches_ancestor_sibling_and_returns_backwards() {
    let (_temp, nodes) = build_seven_node_tree();
    let [root, a, _a1, a2, b, _c, _c1] = &nodes;
    let next = next_folder_dfs(&mixed_input_spelling(a2), FolderTreeOptions::default()).unwrap();
    assert!(path_eq(&next, b));
    let previous = prev_folder_dfs(&mixed_input_spelling(b), FolderTreeOptions::default()).unwrap();
    assert!(path_eq(&previous, a2));
    // Backward preorder first visits the parent, then its previous sibling.
    assert!(path_eq(
        &prev_folder_dfs(&mixed_input_spelling(a), FolderTreeOptions::default()).unwrap(),
        root
    ));
}

#[cfg(windows)]
#[test]
fn mixed_path_sibling_navigation_stays_at_same_level() {
    let (_temp, nodes) = build_seven_node_tree();
    let [_root, a, _a1, a2, b, c, _c1] = &nodes;
    assert!(path_eq(
        &next_sibling_folder(&mixed_input_spelling(a), FolderTreeOptions::default()).unwrap(),
        b
    ));
    assert!(path_eq(
        &prev_sibling_folder(&mixed_input_spelling(c), FolderTreeOptions::default()).unwrap(),
        b
    ));
    assert!(path_eq(
        &prev_sibling_folder(&mixed_input_spelling(b), FolderTreeOptions::default()).unwrap(),
        a
    ));
    assert!(next_sibling_folder(&mixed_input_spelling(a2), FolderTreeOptions::default()).is_none());
    assert!(prev_sibling_folder(&mixed_input_spelling(a), FolderTreeOptions::default()).is_none());
}

#[cfg(windows)]
#[test]
fn mixed_path_navigation_keeps_zip_pdf_in_the_tree() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().join("root");
    let leaf = root.join("a").join("last");
    let zip = root.join("b.zip");
    let pdf = root.join("c.pdf");
    let folder = root.join("d");
    std::fs::create_dir_all(&leaf).unwrap();
    std::fs::create_dir(&folder).unwrap();
    // Navigation lists container files, without decoding their contents.
    std::fs::write(&zip, b"").unwrap();
    std::fs::write(&pdf, b"").unwrap();
    let opts = FolderTreeOptions::default();
    for (from, to) in [(&leaf, &zip), (&zip, &pdf), (&pdf, &folder)] {
        assert!(path_eq(
            &next_folder_dfs(&mixed_input_spelling(from), opts).unwrap(),
            to
        ));
        assert!(path_eq(
            &prev_folder_dfs(&mixed_input_spelling(to), opts).unwrap(),
            from
        ));
    }
    assert!(path_eq(
        &next_sibling_folder(&mixed_input_spelling(&zip), opts).unwrap(),
        &pdf
    ));
    assert!(path_eq(
        &prev_sibling_folder(&mixed_input_spelling(&pdf), opts).unwrap(),
        &zip
    ));
    let resolved = resolve_openable_path(&mixed_input_spelling(&leaf)).unwrap();
    assert_eq!(
        resolved.as_os_str(),
        crate::path_key::normalize_input_path(&mixed_input_spelling(&leaf)).as_os_str()
    );
}

fn labels(paths: Vec<PathBuf>) -> Vec<String> {
    paths
        .into_iter()
        .filter_map(|path| path.file_name()?.to_str().map(str::to_owned))
        .collect()
}

#[test]
fn tree_sort_drives_dfs_and_sibling_navigation_in_the_same_order() {
    let temp = tempfile::TempDir::new().unwrap();
    let root = temp.path().join("root");
    for name in ["aaa", "bbb", "ccc"] {
        std::fs::create_dir_all(root.join(name)).unwrap();
    }
    let options = FolderTreeOptions {
        sort_order: crate::settings::SortOrder::NameDesc,
        ..FolderTreeOptions::default()
    };

    assert_eq!(
        labels(sorted_subdirs(&root, options)),
        ["ccc", "bbb", "aaa"]
    );
    let first = next_folder_dfs(&root, options).expect("first DFS child");
    assert_eq!(first.file_name().unwrap(), "ccc");
    let second = next_sibling_folder(&first, options).expect("second sibling");
    assert_eq!(second.file_name().unwrap(), "bbb");
    let previous = prev_sibling_folder(&second, options).expect("previous sibling");
    assert!(path_eq(&previous, &first));
}

#[test]
fn sorted_subdirs_excludes_portable_metadata_bundle() {
    let temp = tempfile::TempDir::new().unwrap();
    std::fs::create_dir(temp.path().join("visible")).unwrap();
    std::fs::create_dir(
        temp.path()
            .join(crate::fs_entry::PORTABLE_METADATA_BUNDLE_DIRNAME),
    )
    .unwrap();
    let names = sorted_subdirs(temp.path(), FolderTreeOptions::default())
        .into_iter()
        .filter_map(|path| path.file_name()?.to_str().map(str::to_owned))
        .collect::<Vec<_>>();
    assert_eq!(names, vec!["visible"]);
}

#[test]
fn path_eq_same() {
    assert!(path_eq(Path::new("C:/foo/bar"), Path::new("C:/foo/bar")));
}

#[cfg(windows)]
#[test]
fn path_eq_case_insensitive() {
    // Windows 想定: 大文字小文字を無視する
    assert!(path_eq(Path::new("C:/Foo/Bar"), Path::new("c:/foo/bar")));
    assert!(path_eq(Path::new("D:/IMG.JPG"), Path::new("d:/img.jpg")));
}

#[cfg(not(windows))]
#[test]
fn unix_paths_preserve_case_and_backslashes() {
    assert!(!path_eq(Path::new("/books/A"), Path::new("/books/a")));
    assert!(!path_eq(Path::new(r"/books/a\b"), Path::new("/books/a/b")));
}

#[test]
fn path_eq_different() {
    assert!(!path_eq(Path::new("C:/foo"), Path::new("C:/bar")));
    assert!(!path_eq(Path::new("C:/foo/a"), Path::new("C:/foo/b")));
}

#[test]
fn supported_extensions_contains_common_formats() {
    for ext in ["jpg", "jpeg", "png", "webp", "bmp", "gif"] {
        assert!(SUPPORTED_EXTENSIONS.contains(&ext), "missing: {}", ext);
    }
}

#[test]
fn zip_extension_includes_cbz() {
    // CBZ は実体が ZIP なのでネイティブ ZIP として扱う (入力は小文字化済み拡張子)。
    assert!(is_zip_extension("zip"));
    assert!(is_zip_extension("cbz"));
    assert!(!is_zip_extension("pdf"));
    assert!(!is_zip_extension("rar"));
    assert!(!is_zip_extension("cbr"));
    assert!(!is_zip_extension("7z"));
    assert!(!is_zip_extension("cb7"));
}

#[test]
fn virtual_folder_recognizes_cbz_and_zip_and_pdf() {
    assert!(is_virtual_folder(Path::new(r"C:\books\a.cbz")));
    assert!(is_virtual_folder(Path::new(r"C:\books\a.CBZ"))); // 大文字も
    assert!(is_virtual_folder(Path::new(r"C:\books\a.zip")));
    assert!(is_virtual_folder(Path::new(r"C:\books\a.pdf")));
    // RAR/7z 系は変換対象であって仮想フォルダ (ネイティブ閲覧) ではない。
    assert!(!is_virtual_folder(Path::new(r"C:\books\a.cbr")));
    assert!(!is_virtual_folder(Path::new(r"C:\books\a.cb7")));
    assert!(!is_virtual_folder(Path::new(r"C:\books\a.jpg")));
}

#[test]
fn opened_container_predicate_covers_direct_read_rar_without_reclassifying_scans() {
    for path in [r"C:\books\a.rar", r"C:\books\a.CBR"] {
        assert!(is_open_as_container(Path::new(path)));
        assert!(!is_virtual_folder(Path::new(path)));
    }
    assert!(is_open_as_container(Path::new(r"C:\books\a.zip")));
    assert!(is_open_as_container(Path::new(r"C:\books\a.pdf")));
    assert!(!is_open_as_container(Path::new(r"C:\books\a.7z")));
    assert!(!is_open_as_container(Path::new(r"C:\books\a.jpg")));
}

#[test]
fn convertible_archive_path_detection() {
    for ext in ["rar", "cbr", "7z", "cb7", "lzh", "lha", "RAR", "CBR"] {
        assert!(
            is_convertible_archive_path(&PathBuf::from(format!(r"C:\books\a.{ext}"))),
            "{ext} should be a convertible archive"
        );
    }
    // ネイティブ ZIP/PDF は変換対象ではない (is_virtual_folder の領分)。
    for ext in ["zip", "cbz", "pdf", "jpg"] {
        assert!(
            !is_convertible_archive_path(&PathBuf::from(format!(r"C:\books\a.{ext}"))),
            "{ext} should not be a convertible archive"
        );
    }
}

#[test]
fn resolve_openable_path_keeps_convertible_archive() {
    // 変換アーカイブ (CBR) は親フォルダに丸めず、そのパス自身を返す。
    // (旧実装は is_virtual_folder=false で親フォルダへ落ちていた → 起動時に元の本を
    //  開き直せなかった回帰の防止)
    let tmp = tempfile::TempDir::new().unwrap();
    let cbr = tmp.path().join("book.cbr");
    std::fs::write(&cbr, b"rar").unwrap();
    assert_eq!(resolve_openable_path(&cbr).as_deref(), Some(cbr.as_path()));

    let detailed = resolve_openable_path_detailed(&cbr).unwrap();
    assert_eq!(detailed.path, cbr);
    assert_eq!(detailed.kind, OpenablePathKind::File);
    assert!(detailed.requested_is_file);
}

#[test]
fn resolve_openable_path_detailed_marks_requested_file_parent_fallback() {
    let tmp = tempfile::TempDir::new().unwrap();
    let image = tmp.path().join("page.jpg");
    std::fs::write(&image, b"jpg").unwrap();

    let detailed = resolve_openable_path_detailed(&image).unwrap();

    assert_eq!(detailed.path, tmp.path());
    assert_eq!(detailed.kind, OpenablePathKind::Directory);
    assert!(detailed.requested_is_file);
}

#[test]
fn bug766_folder_should_stop_convertible_archive_true() {
    let tmp = tempfile::TempDir::new().unwrap();
    let rar = tmp.path().join("book.rar");
    std::fs::write(&rar, b"rar").unwrap();

    assert!(folder_should_stop(&rar, None));
    assert!(folder_has_still_image(&rar, None));
}

#[test]
fn bug766_sorted_subdirs_includes_convertible_archives() {
    let tmp = tempfile::TempDir::new().unwrap();
    let root = tmp.path();
    std::fs::create_dir(root.join("folder")).unwrap();
    for name in ["a.zip", "b.pdf", "c.rar", "d.7z", "e.lzh"] {
        std::fs::write(root.join(name), b"").unwrap();
    }

    let names: Vec<_> = sorted_subdirs(root, FolderTreeOptions::default())
        .into_iter()
        .filter_map(|p| p.file_name().map(|n| n.to_string_lossy().into_owned()))
        .collect();

    for expected in ["a.zip", "b.pdf", "c.rar", "d.7z", "e.lzh", "folder"] {
        assert!(
            names.iter().any(|n| n == expected),
            "missing {expected}: {names:?}"
        );
    }
}

#[test]
fn sorted_subdirs_uses_rar_header_truth_for_volume_filtering() {
    // The upstream fixture lives in the checked-out mImageViewer vendor tree;
    // local_core intentionally does not duplicate the binary samples.
    let fixture = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../vendor/mimageviewer/testdata/archives/rar-multipart-filename-regression");
    if !fixture.is_dir() {
        eprintln!(
            "skip: upstream RAR fixture is not checked out: {}",
            fixture.display()
        );
        return;
    }
    let standalone = sorted_subdirs(&fixture, FolderTreeOptions::default());
    let standalone_names: Vec<_> = standalone
        .iter()
        .filter_map(|path| path.file_name().and_then(|name| name.to_str()))
        .collect();
    for name in [
        "○×△□ Vol.1.rar",
        "○×△□ Vol.2.rar",
        "○×△□ Vol.2a.rar",
        "○×△□ Vol.10.rar",
        "○×△□ Vol.10a.rar",
        "○×△□ Vol.123.rar",
        "○×△□ Vol.１.rar",
    ] {
        assert!(standalone_names.contains(&name), "missing {name}");
    }

    let split = fixture.join("real-split-control");
    let split_names: Vec<_> = sorted_subdirs(&split, FolderTreeOptions::default())
        .into_iter()
        .filter_map(|path| {
            path.file_name()
                .and_then(|name| name.to_str())
                .map(str::to_owned)
        })
        .collect();
    assert!(split_names.contains(&"real-split-control.part1.rar".to_string()));
    assert!(!split_names.contains(&"real-split-control.part2.rar".to_string()));
}

#[test]
fn sorted_subdirs_can_ignore_convertible_archives() {
    let tmp = tempfile::TempDir::new().unwrap();
    let root = tmp.path();
    std::fs::create_dir(root.join("folder")).unwrap();
    for name in ["a.zip", "b.pdf", "c.rar", "d.7z", "e.lzh"] {
        std::fs::write(root.join(name), b"").unwrap();
    }
    let opts = FolderTreeOptions {
        include_convertible_archives: false,
        ..FolderTreeOptions::default()
    };

    let names: Vec<_> = sorted_subdirs(root, opts)
        .into_iter()
        .filter_map(|p| p.file_name().map(|n| n.to_string_lossy().into_owned()))
        .collect();

    for expected in ["a.zip", "b.pdf", "folder"] {
        assert!(
            names.iter().any(|n| n == expected),
            "missing {expected}: {names:?}"
        );
    }
    for ignored in ["c.rar", "d.7z", "e.lzh"] {
        assert!(
            !names.iter().any(|n| n == ignored),
            "unexpected {ignored}: {names:?}"
        );
    }
}

#[test]
fn sorted_subdirs_prefers_same_name_zip_over_convertible_archives() {
    let tmp = tempfile::TempDir::new().unwrap();
    for name in ["book.zip", "book.rar", "other.7z"] {
        std::fs::write(tmp.path().join(name), b"").unwrap();
    }
    let names: Vec<_> = sorted_subdirs(tmp.path(), FolderTreeOptions::default())
        .into_iter()
        .filter_map(|path| {
            path.file_name()
                .map(|name| name.to_string_lossy().into_owned())
        })
        .collect();
    assert!(names.iter().any(|name| name == "book.zip"));
    assert!(!names.iter().any(|name| name == "book.rar"));
    assert!(names.iter().any(|name| name == "other.7z"));

    let options = FolderTreeOptions {
        skip_archive_if_zip_exists: false,
        ..FolderTreeOptions::default()
    };
    let names: Vec<_> = sorted_subdirs(tmp.path(), options)
        .into_iter()
        .filter_map(|path| {
            path.file_name()
                .map(|name| name.to_string_lossy().into_owned())
        })
        .collect();
    assert!(names.iter().any(|name| name == "book.zip"));
    assert!(names.iter().any(|name| name == "book.rar"));
}

#[test]
fn folder_should_stop_can_ignore_convertible_archive_file() {
    let tmp = tempfile::TempDir::new().unwrap();
    let rar = tmp.path().join("book.rar");
    std::fs::write(&rar, b"rar").unwrap();
    let opts = FolderTreeOptions {
        include_convertible_archives: false,
        ..FolderTreeOptions::default()
    };

    assert!(!folder_should_stop_with_options(&rar, None, opts));
    assert!(!folder_has_still_image_with_options(&rar, None, opts));
}

#[cfg(windows)]
#[test]
fn sorted_subdirs_includes_windows_directory_symlink() {
    let tmp = tempfile::TempDir::new().unwrap();
    let root = tmp.path();
    let target = root.join("target");
    let link = root.join("link");
    std::fs::create_dir(&target).unwrap();
    if std::os::windows::fs::symlink_dir(&target, &link).is_err() {
        return;
    }

    let names: Vec<_> = sorted_subdirs(root, FolderTreeOptions::default())
        .into_iter()
        .filter_map(|p| p.file_name().map(|n| n.to_string_lossy().into_owned()))
        .collect();

    assert_eq!(names, vec!["link", "target"]);
}

#[test]
fn supported_video_extensions_contains_common_formats() {
    for ext in ["mp4", "mov", "mkv", "avi"] {
        assert!(
            SUPPORTED_VIDEO_EXTENSIONS.contains(&ext),
            "missing: {}",
            ext
        );
    }
}

/// skip_limit == 0 でも隣フォルダ `first` を 1 回評価する回帰テスト。
/// `first` が画像フォルダなら hit_image_folder=true で返ること。
#[test]
fn navigate_skip_limit_zero_returns_image_folder() {
    let temp = tempfile::TempDir::new().unwrap();
    let root = temp.path();
    let start = root.join("start");
    let image_folder = root.join("images");
    std::fs::create_dir(&start).unwrap();
    std::fs::create_dir(&image_folder).unwrap();
    std::fs::write(image_folder.join("a.jpg"), b"").unwrap();

    let target = image_folder.clone();
    let nav_fn = move |_: &Path| Some(target.clone());

    let result =
        navigate_folder_with_skip(&start, nav_fn, folder_should_stop, 0, None).expect("outcome");
    assert_eq!(result.path, image_folder);
    assert!(result.hit_image_folder);
}

/// skip_limit == 0 で `first` が画像フォルダでないときはフォールバックで
/// first を返し、hit_image_folder=false を立てること。
#[test]
fn navigate_skip_limit_zero_falls_back_when_first_empty() {
    let temp = tempfile::TempDir::new().unwrap();
    let root = temp.path();
    let start = root.join("start");
    let empty_folder = root.join("empty");
    std::fs::create_dir(&start).unwrap();
    std::fs::create_dir(&empty_folder).unwrap();

    let target = empty_folder.clone();
    let nav_fn = move |_: &Path| Some(target.clone());

    let result =
        navigate_folder_with_skip(&start, nav_fn, folder_should_stop, 0, None).expect("outcome");
    assert_eq!(result.path, empty_folder);
    assert!(!result.hit_image_folder);
}

/// skip_limit >= 1 の既存挙動が壊れていないこと: 画像を含まない first を
/// 1 回スキップして 2 番目の候補 (画像あり) を返す。
#[test]
fn navigate_skip_limit_one_skips_to_image_folder() {
    let temp = tempfile::TempDir::new().unwrap();
    let root = temp.path();
    let start = root.join("start");
    let empty_folder = root.join("empty");
    let image_folder = root.join("images");
    std::fs::create_dir(&start).unwrap();
    std::fs::create_dir(&empty_folder).unwrap();
    std::fs::create_dir(&image_folder).unwrap();
    std::fs::write(image_folder.join("a.jpg"), b"").unwrap();

    let empty_clone = empty_folder.clone();
    let image_clone = image_folder.clone();
    let nav_fn = move |p: &Path| {
        if path_eq(p, &empty_clone) {
            Some(image_clone.clone())
        } else {
            Some(empty_clone.clone())
        }
    };

    // skip_limit=1 だと first (empty) は評価されるが advance 後の検査はしない想定。
    // 現実装: iter 0 で empty をチェック→スキップ→advance して image へ。ループ終了。
    // → fallback path=first=empty, hit_image_folder=false
    let result =
        navigate_folder_with_skip(&start, nav_fn, folder_should_stop, 1, None).expect("outcome");
    assert_eq!(result.path, empty_folder);
    assert!(!result.hit_image_folder);

    // skip_limit=2 なら image_folder まで検査されて hit=true になる。
    let empty_clone2 = empty_folder.clone();
    let image_clone2 = image_folder.clone();
    let nav_fn2 = move |p: &Path| {
        if path_eq(p, &empty_clone2) {
            Some(image_clone2.clone())
        } else {
            Some(empty_clone2.clone())
        }
    };
    let result =
        navigate_folder_with_skip(&start, nav_fn2, folder_should_stop, 2, None).expect("outcome");
    assert_eq!(result.path, image_folder);
    assert!(result.hit_image_folder);
}

fn make_zip_with_entries(zip_path: &Path, entry_names: &[&str]) {
    use std::io::Write;
    let file = std::fs::File::create(zip_path).unwrap();
    let mut zw = zip::ZipWriter::new(file);
    let opts: zip::write::FileOptions<()> =
        zip::write::FileOptions::default().compression_method(zip::CompressionMethod::Stored);
    for name in entry_names {
        zw.start_file(*name, opts).unwrap();
        zw.write_all(b"dummy").unwrap();
    }
    zw.finish().unwrap();
}

#[test]
fn folder_should_stop_pdf_file_always_true() {
    let temp = tempfile::TempDir::new().unwrap();
    let pdf = temp.path().join("doc.pdf");
    std::fs::write(&pdf, b"%PDF-1.4 dummy").unwrap();
    assert!(folder_should_stop(&pdf, None));
}

#[test]
fn folder_should_stop_zip_with_image_true() {
    let temp = tempfile::TempDir::new().unwrap();
    let zip_path = temp.path().join("comic.zip");
    make_zip_with_entries(&zip_path, &["page01.jpg"]);
    assert!(folder_should_stop(&zip_path, None));
}

#[test]
fn folder_should_stop_zip_without_image_false() {
    let temp = tempfile::TempDir::new().unwrap();
    let zip_path = temp.path().join("installer.zip");
    make_zip_with_entries(&zip_path, &["readme.pdf"]);
    assert!(!folder_should_stop(&zip_path, None));
}

/// 以前の「2+ ヒューリスティクス」による偽陽性を避ける回帰テスト。
#[test]
fn folder_should_stop_dir_with_only_zips_false() {
    let temp = tempfile::TempDir::new().unwrap();
    let dir = temp.path().join("installer_collection");
    std::fs::create_dir(&dir).unwrap();
    std::fs::write(dir.join("a.zip"), b"").unwrap();
    std::fs::write(dir.join("b.zip"), b"").unwrap();
    std::fs::write(dir.join("c.pdf"), b"").unwrap();
    assert!(!folder_should_stop(&dir, None));
}

#[test]
fn folder_should_stop_dir_with_image_true() {
    let temp = tempfile::TempDir::new().unwrap();
    let dir = temp.path().join("photos");
    std::fs::create_dir(&dir).unwrap();
    std::fs::write(dir.join("a.jpg"), b"").unwrap();
    assert!(folder_should_stop(&dir, None));
}

/// `folder_has_still_image`: 静止画があれば true。
#[test]
fn folder_has_still_image_dir_with_image_true() {
    let temp = tempfile::TempDir::new().unwrap();
    let dir = temp.path().join("photos");
    std::fs::create_dir(&dir).unwrap();
    std::fs::write(dir.join("a.jpg"), b"").unwrap();
    assert!(folder_has_still_image(&dir, None));
}

/// `folder_has_still_image`: 動画のみのフォルダは false (folder_should_stop とは
/// ここが異なる)。スライドショー NextFolder が動画のみフォルダを飛ばす根拠。
#[test]
fn folder_has_still_image_dir_with_only_video_false() {
    let temp = tempfile::TempDir::new().unwrap();
    let dir = temp.path().join("movies");
    std::fs::create_dir(&dir).unwrap();
    std::fs::write(dir.join("clip.mp4"), b"").unwrap();
    // folder_should_stop は動画込みなので true、folder_has_still_image は false。
    assert!(folder_should_stop(&dir, None));
    assert!(!folder_has_still_image(&dir, None));
}

/// `folder_has_still_image`: 空フォルダは false。
#[test]
fn folder_has_still_image_empty_dir_false() {
    let temp = tempfile::TempDir::new().unwrap();
    let dir = temp.path().join("empty");
    std::fs::create_dir(&dir).unwrap();
    assert!(!folder_has_still_image(&dir, None));
}

/// `folder_has_still_image`: PDF は静止画系コンテナとして true、画像入り ZIP も true。
#[test]
fn folder_has_still_image_pdf_and_zip_true() {
    let temp = tempfile::TempDir::new().unwrap();
    let pdf = temp.path().join("doc.pdf");
    std::fs::write(&pdf, b"%PDF-1.4 dummy").unwrap();
    assert!(folder_has_still_image(&pdf, None));

    let zip_path = temp.path().join("comic.zip");
    make_zip_with_entries(&zip_path, &["page01.jpg"]);
    assert!(folder_has_still_image(&zip_path, None));
}

// -----------------------------------------------------------------------
// next_folder_dfs / prev_folder_dfs の DFS 前順走査 (Ctrl+↑↓ の根幹)。
// 既存テストは `navigate_folder_with_skip` のスキップ挙動を nav_fn closure 経由で
// 確認していたが、DFS 自体は実 read_dir に依存するためここで実フォルダを作って
// 検証する。ZIP との同名コリジョンが発生しない構造に絞ることで、ユーザー設定
// (`skip_zip_if_folder_exists`) の値に依らず決定的にする。
// -----------------------------------------------------------------------

/// 7 ノード DFS テスト用の共通フィクスチャ:
/// ```
/// root/{a/{a1,a2}, b, c/{c1}}
/// ```
/// 段階 join (`.join("a").join("a1")`) で `\` セパレータに揃える
/// (`path_eq` はセパレータ正規化をしないため `.join("a/a1")` だと一致しない)。
fn build_seven_node_tree() -> (tempfile::TempDir, [PathBuf; 7]) {
    let temp = tempfile::TempDir::new().unwrap();
    let root = temp.path().join("root");
    let a = root.join("a");
    let a1 = a.join("a1");
    let a2 = a.join("a2");
    let b = root.join("b");
    let c = root.join("c");
    let c1 = c.join("c1");
    for d in [&a1, &a2, &b, &c1] {
        std::fs::create_dir_all(d).unwrap();
    }
    (temp, [root, a, a1, a2, b, c, c1])
}

/// 深さ優先前順 (preorder) のシーケンスを root から完走させて確認する。
/// 期待される next の連鎖: root → a → a1 → a2 → b → c → c1 → (None)
#[test]
fn next_folder_dfs_preorder_traversal_full_chain() {
    let (_temp, nodes) = build_seven_node_tree();
    let [root, a, a1, a2, b, c, c1] = &nodes;

    let order = [a, a1, a2, b, c, c1];
    let mut cur = root.clone();
    for expected in order {
        let next =
            next_folder_dfs(&cur, FolderTreeOptions::default()).expect("next_folder_dfs Some");
        assert!(
            path_eq(&next, expected),
            "expected {:?}, got {:?}",
            expected,
            next
        );
        cur = next;
    }
    // 末尾の c1 から見て次は無い (tempdir 親には OS 上の他フォルダが見える可能性が
    // あるので Some/None どちらでも許容して「少なくとも root 配下ではない」だけ保証)。
    if let Some(beyond) = next_folder_dfs(&cur, FolderTreeOptions::default()) {
        assert!(
            !beyond.starts_with(root),
            "c1 から先は root より外に抜けるはず, got {:?}",
            beyond
        );
    }
}

/// `prev_folder_dfs` の連鎖を末端から root に向けて辿る。
/// `next_folder_dfs` の正確な逆順を期待する (= round-trip 性質)。
#[test]
fn prev_folder_dfs_is_reverse_of_next_chain() {
    let (_temp, nodes) = build_seven_node_tree();
    let [root, a, a1, a2, b, c, c1] = &nodes;

    let chain = [root, a, a1, a2, b, c, c1];
    for w in chain.windows(2).rev() {
        let from = w[1];
        let expected_prev = w[0];
        let prev =
            prev_folder_dfs(from, FolderTreeOptions::default()).expect("prev_folder_dfs Some");
        assert!(
            path_eq(&prev, expected_prev),
            "from {:?}: expected prev {:?}, got {:?}",
            from,
            expected_prev,
            prev
        );
    }
}

/// 深い枝の最後の子孫から、上位フォルダの次の兄弟へ正しく "ジャンプ" する。
/// ```
/// root/
///   a/
///     deep/
///       deeper/
///   b/
/// ```
/// `root/a/deep/deeper` から next は `root/b` (ancestor-sibling jump)。
#[test]
fn next_folder_dfs_jumps_from_deep_leaf_to_ancestor_sibling() {
    let temp = tempfile::TempDir::new().unwrap();
    let root = temp.path().join("root");
    let deeper = root.join("a").join("deep").join("deeper");
    let b = root.join("b");
    std::fs::create_dir_all(&deeper).unwrap();
    std::fs::create_dir_all(&b).unwrap();

    let next = next_folder_dfs(&deeper, FolderTreeOptions::default()).expect("Some");
    assert!(
        path_eq(&next, &b),
        "deep leaf → ancestor sibling: expected root/b, got {:?}",
        next
    );
}

/// `prev_folder_dfs` で「最初の子」から親に戻るときに、誤って前の枝の最後の子孫を
/// 返さないこと。`root/a/a1` の prev は `root/a` (親) であって `root/a/a2` ではない。
#[test]
fn prev_folder_dfs_first_child_returns_parent() {
    let temp = tempfile::TempDir::new().unwrap();
    let root = temp.path().join("root");
    let a = root.join("a");
    let a1 = a.join("a1");
    let a2 = a.join("a2");
    for d in [&a1, &a2] {
        std::fs::create_dir_all(d).unwrap();
    }
    let prev = prev_folder_dfs(&a1, FolderTreeOptions::default()).expect("Some");
    assert!(
        path_eq(&prev, &a),
        "first child の prev は親, got {:?}",
        prev
    );
}

/// `prev` が前の兄弟の **最も深い** 末端まで一気に降りる。
/// `root/{a/x/y, b}` で b の prev は a/x/y。
#[test]
fn prev_folder_dfs_descends_into_last_sibling_depth() {
    let temp = tempfile::TempDir::new().unwrap();
    let root = temp.path().join("root");
    let y = root.join("a").join("x").join("y");
    let b = root.join("b");
    std::fs::create_dir_all(&y).unwrap();
    std::fs::create_dir_all(&b).unwrap();
    let prev = prev_folder_dfs(&b, FolderTreeOptions::default()).expect("Some");
    assert!(
        path_eq(&prev, &y),
        "前の兄弟の最深子孫まで降りる, got {:?}",
        prev
    );
}

/// Ctrl+PageDown 用の sibling 移動は DFS と違い、子へ潜らず同じ親の次だけを見る。
#[test]
fn next_sibling_folder_stays_at_same_depth() {
    let (_temp, nodes) = build_seven_node_tree();
    let [_root, a, _a1, _a2, b, c, c1] = &nodes;

    let next = next_sibling_folder(a, FolderTreeOptions::default()).expect("a next sibling");
    assert!(path_eq(&next, b), "a の次兄弟は b, got {:?}", next);

    let next = next_sibling_folder(b, FolderTreeOptions::default()).expect("b next sibling");
    assert!(path_eq(&next, c), "b の次兄弟は c, got {:?}", next);

    assert!(
        next_sibling_folder(c, FolderTreeOptions::default()).is_none(),
        "最後の兄弟 c の次は無い"
    );
    assert!(
        next_sibling_folder(c1, FolderTreeOptions::default()).is_none(),
        "深い末端 c1 から祖先の次兄弟へは出ない"
    );
}

/// sibling 移動は空フォルダを skip せず、直近の兄弟そのものを返す。
#[test]
fn sibling_folder_returns_empty_direct_sibling() {
    let temp = tempfile::TempDir::new().unwrap();
    let root = temp.path().join("root");
    let a = root.join("Folder-A");
    let b = root.join("Folder-B");
    let b1 = b.join("Folder-B-1");
    let b2 = b.join("Folder-B-2");
    let c = root.join("Folder-C");
    for d in [&a, &b1, &b2, &c] {
        std::fs::create_dir_all(d).unwrap();
    }
    std::fs::write(b1.join("b1.jpg"), b"").unwrap();
    std::fs::write(b2.join("b2.jpg"), b"").unwrap();
    std::fs::write(c.join("c.jpg"), b"").unwrap();

    assert!(
        !folder_should_stop(&b, None),
        "Folder-B 自身に画像が無いことを確認"
    );

    let next = next_sibling_folder(&a, FolderTreeOptions::default()).expect("a next sibling");
    assert!(path_eq(&next, &b), "a の次兄弟は空の b, got {:?}", next);

    let prev = prev_sibling_folder(&c, FolderTreeOptions::default()).expect("c prev sibling");
    assert!(path_eq(&prev, &b), "c の前兄弟は空の b, got {:?}", prev);
}

/// Ctrl+PageUp 用の sibling 移動は、前兄弟の最深子孫へ潜らず兄弟自身を返す。
#[test]
fn prev_sibling_folder_does_not_descend_into_previous_branch() {
    let (_temp, nodes) = build_seven_node_tree();
    let [_root, a, _a1, _a2, b, c, _c1] = &nodes;

    let prev = prev_sibling_folder(c, FolderTreeOptions::default()).expect("c prev sibling");
    assert!(path_eq(&prev, b), "c の前兄弟は b, got {:?}", prev);

    let prev = prev_sibling_folder(b, FolderTreeOptions::default()).expect("b prev sibling");
    assert!(path_eq(&prev, a), "b の前兄弟は a, got {:?}", prev);

    assert!(
        prev_sibling_folder(a, FolderTreeOptions::default()).is_none(),
        "最初の兄弟 a の前は無い"
    );
}

/// 自己参照 junction (`root/a_loop` → `root`) の子には潜らず、実在する次の子
/// (`root/z_real`) を返す。junction をフォルダ候補に含めた後の循環対策の回帰テスト。
/// 修正前は `a_loop\a_loop\…` と無限に前進していた。
#[cfg(windows)]
#[test]
fn next_folder_dfs_skips_self_referential_junction_and_descends_into_real_child() {
    let temp = tempfile::TempDir::new().unwrap();
    let root = temp.path().join("root");
    let real = root.join("z_real");
    let loop_link = root.join("a_loop");
    std::fs::create_dir_all(&real).unwrap();
    // a_loop → root (= current 自身に戻る循環)。権限が無い環境では skip。
    if std::os::windows::fs::symlink_dir(&root, &loop_link).is_err() {
        return;
    }

    let next = next_folder_dfs(&root, FolderTreeOptions::default()).expect("Some");
    assert!(
        path_eq(&next, &real),
        "自己 junction を飛ばして実在の子 z_real へ, got {:?}",
        next
    );
}

/// 祖先へ戻る junction (`root/mid/only_loop` → `root`) が唯一の子のとき、そこへ
/// 潜らず `mid` の次の兄弟 (`root/other`) へ進む。祖先循環 + 兄弟フォールスルーの検証。
#[cfg(windows)]
#[test]
fn next_folder_dfs_skips_ancestor_junction_and_advances_to_sibling() {
    let temp = tempfile::TempDir::new().unwrap();
    let root = temp.path().join("root");
    let mid = root.join("mid");
    let other = root.join("other");
    let loop_link = mid.join("only_loop");
    std::fs::create_dir_all(&mid).unwrap();
    std::fs::create_dir_all(&other).unwrap();
    // only_loop → root (= 祖先に戻る循環)。権限が無い環境では skip。
    if std::os::windows::fs::symlink_dir(&root, &loop_link).is_err() {
        return;
    }

    let next = next_folder_dfs(&mid, FolderTreeOptions::default()).expect("Some");
    assert!(
        path_eq(&next, &other),
        "祖先 junction には潜らず mid の次兄弟 other へ, got {:?}",
        next
    );
}
