// 原为 `#[cfg(test)] mod tests { … }`：剥掉外壳、内容原样。
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    fn touch(path: &Path) {
        fs::write(path, b"x").unwrap();
    }

    #[test]
    fn video_entries_open_as_the_selected_media_file() {
        let dir = tempdir().unwrap();
        touch(&dir.path().join("000-cover.jpg"));
        for ext in crate::page_order::VIDEO_EXTENSIONS {
            touch(&dir.path().join(format!("视频 2.{}", ext.to_uppercase())));
        }
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        state.set_entry_filter(EntryFilter::Video);
        let entries = state.entries().unwrap();
        assert_eq!(entries.len(), crate::page_order::VIDEO_EXTENSIONS.len());
        for entry in entries {
            let entry = entry.node;
            assert!(entry.is_video, "{}", entry.name);
            let OpenEntryResult::Opened(path) = state.open_entry(&entry.path, false).unwrap()
            else {
                panic!("点击视频应该打开 Reader");
            };
            assert_eq!(path, Path::new(&entry.path));
            assert_eq!(state.active_path(), dir.path());

            // 不能只放行文件管理器：交给 Reader 的路径也必须能真正打开。
            let source = crate::LocalSource::open(&path).unwrap();
            assert_eq!(source.kind(), crate::SourceKind::MediaFile);
            assert_eq!(source.root(), path);
            assert_eq!(source.len(), 1);
            assert_eq!(source.pages()[0].name, entry.name);
            assert_eq!(source.total_bytes(), 1);
            assert_eq!(source.page_bytes(0).unwrap(), b"x");
            assert!(source.page_bytes(1).is_err());
        }
    }

    #[test]
    fn loose_image_opens_the_directory_it_lives_in() {
        let dir = tempdir().unwrap();
        touch(&dir.path().join("page_1.jpg"));
        let target = dir.path().join("page_2.jpg");
        touch(&target);
        fs::create_dir(dir.path().join("nested")).unwrap();
        touch(&dir.path().join("nested").join("page_9.jpg"));
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();

        let OpenEntryResult::Opened(opened) = state.open_entry(&target, false).unwrap() else {
            panic!("点击松散图片应该打开 Reader");
        };
        // 书是那个目录，不是这一张；点开的那一张由调用方作为起始页带上。
        assert_eq!(opened, dir.path());
        let source = crate::LocalSource::open(&opened).unwrap();
        assert_eq!(source.kind(), crate::SourceKind::Folder);
        // 平铺里有东西就不进子目录，所以这一本只有两张。
        assert_eq!(source.len(), 2);

        // 压缩包自身就是一本书，不能被同样的解析提到父目录。
        let archive = dir.path().join("book.cbz");
        touch(&archive);
        assert_eq!(
            state.open_entry(&archive, false).unwrap(),
            OpenEntryResult::Opened(archive)
        );

        // RAW 在文件列表那张表里算图片，但页序不认它：提升上去只会翻出一本空书，
        // 平铺为空时还要递归进子目录捞无关页，所以这种后缀保持按单个文件交给 Reader。
        let raw = dir.path().join("shot.cr2");
        touch(&raw);
        assert!(crate::folder_tree::is_recognized_image_ext("cr2"));
        assert!(!crate::page_order::is_page_name("shot.cr2"));
        assert_eq!(
            state.open_entry(&raw, false).unwrap(),
            OpenEntryResult::Opened(raw)
        );
    }

    #[test]
    fn open_entry_still_rejects_unsupported_or_missing_files() {
        let dir = tempdir().unwrap();
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        for name in ["readme.txt", "song.mp3"] {
            let path = dir.path().join(name);
            touch(&path);
            assert!(state.open_entry(&path, false).is_err());
        }
        assert!(
            state
                .open_entry(dir.path().join("missing.mp4"), false)
                .is_err()
        );
        assert_eq!(state.active_path(), dir.path());
    }

    #[test]
    fn tabs_keep_history_and_switch_active_tab() {
        let dir = tempdir().unwrap();
        let a = dir.path().join("a");
        let b = dir.path().join("b");
        fs::create_dir(&a).unwrap();
        fs::create_dir(&b).unwrap();
        let mut state = FileManagerState::new(Some(a.clone())).unwrap();
        state.navigate(b.clone()).unwrap();
        assert!(state.active_tab().can_go_back());
        assert!(state.go_back());
        assert!(same_path(state.active_path(), &a));
        let id = state.new_tab(Some(b.clone())).unwrap();
        assert_eq!(state.active_tab_id(), id);
        assert!(state.activate_tab(1));
        assert!(same_path(state.active_path(), &a));
    }

    #[test]
    fn breadcrumb_navigation_and_text_edits_share_history_and_reject_bad_paths() {
        let dir = tempdir().unwrap();
        let chapter = dir.path().join("中文 空格").join("chapter");
        fs::create_dir_all(&chapter).unwrap();
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        state.navigate_text("\"中文 空格/chapter\"").unwrap();
        assert_eq!(state.active_path(), chapter);
        let parts = state.breadcrumbs();
        assert!(parts.first().unwrap().is_root);
        assert!(parts.last().unwrap().is_current);
        assert_eq!(parts.last().unwrap().name, "chapter");
        assert_eq!(parts[parts.len() - 2].name, "中文 空格");
        state.navigate(&parts[parts.len() - 2].path).unwrap();
        assert!(state.go_back());
        assert_eq!(state.active_path(), chapter);
        let tabs = state.tabs().to_vec();
        let generation = state.generation();
        for invalid in ["", " \"\" ", "missing", "missing/../chapter"] {
            assert!(state.navigate_text(invalid).is_err());
            assert_eq!(state.tabs(), tabs);
            assert_eq!(state.generation(), generation);
        }
        state.navigate(&parts.first().unwrap().path).unwrap();
        assert!(!state.can_go_up());
    }

    #[test]
    fn directory_columns_are_opt_in_tab_local_and_independent_of_search() {
        let dir = tempdir().unwrap();
        let books = dir.path().join("books");
        let chapter = books.join("chapter 2");
        fs::create_dir_all(&chapter).unwrap();
        fs::create_dir(books.join("chapter 10")).unwrap();
        touch(&books.join("book.cbz"));
        let mut state = FileManagerState::new(Some(chapter.clone())).unwrap();
        assert!(state.directory_columns().is_empty());
        state.set_directory_columns_enabled(true);
        state.set_search_query("does not match folders");
        let columns = state.directory_columns();
        assert!(columns.len() <= 3);
        let column = columns.iter().find(|column| column.path == books).unwrap();
        assert_eq!(
            column
                .entries
                .iter()
                .map(|entry| entry.name.as_str())
                .collect::<Vec<_>>(),
            ["chapter 2", "chapter 10"]
        );
        assert!(column.entries[0].selected);
        assert!(!column.entries[1].selected);
        assert!(columns.last().unwrap().entries.is_empty());
        state.new_tab(None).unwrap();
        assert!(!state.settings().directory_columns_enabled);
        state.activate_tab(1);
        assert!(state.settings().directory_columns_enabled);
        let copied = state.duplicate_tab(1).unwrap();
        assert!(state.settings().directory_columns_enabled);
        assert_eq!(state.active_tab_id(), copied);
    }

    #[cfg(unix)]
    #[test]
    fn path_edit_resolves_parent_after_symlink_and_preserves_backslash_names() {
        use std::os::unix::fs::symlink;
        let dir = tempdir().unwrap();
        let real = dir.path().join("real").join("child");
        fs::create_dir_all(&real).unwrap();
        symlink(&real, dir.path().join("link")).unwrap();
        fs::create_dir(dir.path().join(r"a\b")).unwrap();
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        state.navigate_text(r"a\b").unwrap();
        assert_eq!(state.breadcrumbs().last().unwrap().name, r"a\b");
        assert!(state.go_back());
        state.navigate_text("link/..").unwrap();
        assert_eq!(
            state.active_path(),
            fs::canonicalize(real.parent().unwrap()).unwrap()
        );
    }

    #[test]
    fn penetration_resolves_unique_nested_archive_and_rejects_branch() {
        let dir = tempdir().unwrap();
        let root = dir.path().join("root");
        let nested = root.join("nested");
        fs::create_dir(&root).unwrap();
        fs::create_dir(&nested).unwrap();
        touch(&nested.join("book.cbz"));
        let state = FileManagerState::new(Some(root.clone())).unwrap();
        assert_eq!(
            state.resolve_penetration(&root),
            PenetrationResult::Terminal(nested.join("book.cbz"))
        );
        touch(&nested.join("second.cbz"));
        assert_eq!(state.resolve_penetration(&root), PenetrationResult::Branch);
    }

    #[test]
    fn child_name_projection_supports_single_and_all_modes() {
        let dir = tempdir().unwrap();
        let root = dir.path().join("root");
        let child = root.join("child");
        fs::create_dir(&root).unwrap();
        fs::create_dir(&child).unwrap();
        touch(&child.join("1.cbz"));
        touch(&child.join("2.cbz"));
        let mut state = FileManagerState::new(Some(root)).unwrap();
        state.set_penetration_enabled(true);
        state.set_show_child_names(true);
        assert_eq!(state.entries().unwrap()[0].children.len(), 1);
        state.set_internal_items_mode(InternalItemsMode::All);
        assert_eq!(state.entries().unwrap()[0].children.len(), 2);
    }

    #[test]
    fn open_archive_accepts_mimageviewer_containers_without_navigating() {
        let dir = tempdir().unwrap();
        let archive = dir.path().join("book.CBZ");
        touch(&archive);
        let mut state = FileManagerState::new(Some(dir.path().to_path_buf())).unwrap();
        let generation = state.generation();

        assert_eq!(state.open_archive(&archive).unwrap(), archive);
        assert_eq!(state.generation(), generation);
        assert!(same_path(state.active_path(), dir.path()));
    }

    #[test]
    fn open_archive_rejects_non_archive_files() {
        let dir = tempdir().unwrap();
        let image = dir.path().join("cover.jpg");
        touch(&image);
        let mut state = FileManagerState::new(Some(dir.path().to_path_buf())).unwrap();

        let error = state.open_archive(&image).unwrap_err().to_string();
        assert!(error.contains("不是可打开的压缩包"));
    }
    #[test]
    fn bulk_close_noop_keeps_tabs_and_generation() {
        let dir = tempdir().unwrap();
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        let original = state.tabs().to_vec();
        let generation = state.generation();
        assert!(!state.close_other_tabs(1));
        assert!(!state.close_tabs_left(1));
        assert!(!state.close_tabs_right(1));
        assert_eq!(state.tabs(), original);
        assert_eq!(state.active_tab_id(), 1);
        assert_eq!(state.generation(), generation);
        let second = state.new_tab(None).unwrap();
        state.toggle_tab_pinned(second);
        assert!(!state.close_other_tabs(1));
        assert_eq!(state.tabs().len(), 2);
        assert_eq!(state.active_tab_id(), second);
    }

    #[test]
    fn bulk_close_protects_pins_and_preserves_surviving_active_tab() {
        let dir = tempdir().unwrap();
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        let pinned = state.new_tab(None).unwrap();
        state.toggle_tab_pinned(pinned);
        let third = state.new_tab(None).unwrap();
        let fourth = state.new_tab(None).unwrap();
        state.activate_tab(pinned);
        assert!(state.close_tabs_right(third));
        assert_eq!(state.active_tab_id(), pinned);
        assert_eq!(state.recently_closed()[0].id, fourth);
        assert!(state.close_other_tabs(1));
        assert_eq!(
            state.tabs().iter().map(|tab| tab.id).collect::<Vec<_>>(),
            [1, pinned]
        );
        assert_eq!(state.active_tab_id(), pinned);
        assert!(!state.close_tabs_right(1));
        assert!(!state.can_close_tabs_on_side(1, false));
    }

    #[test]
    fn duplicate_and_reopen_keep_independent_query_sort_and_history() {
        let dir = tempdir().unwrap();
        let child = dir.path().join("child");
        fs::create_dir(&child).unwrap();
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        state.navigate(&child).unwrap();
        state.set_search_query("book");
        state.set_sort(SortField::Size, SortOrder::Descending);
        state.set_entry_filter(EntryFilter::Archives);
        let copied = state.duplicate_tab(1).unwrap();
        state.set_search_query("other");
        state.activate_tab(1);
        assert_eq!(state.settings().search_query, "book");
        assert!(state.close_tab(copied));
        let reopened = state.reopen_closed_tab(copied).unwrap();
        assert_ne!(reopened, copied);
        assert_eq!(state.settings().search_query, "other");
        assert_eq!(state.settings().sort_field, SortField::Size);
        assert_eq!(state.settings().sort_order, SortOrder::Descending);
        assert_eq!(state.settings().entry_filter, EntryFilter::Archives);
        assert!(state.active_tab().can_go_back());
        assert!(state.go_back());
        assert!(state.settings().search_query.is_empty());
        assert!(same_path(state.active_path(), dir.path()));
    }

    #[test]
    fn unavailable_closed_tab_is_not_lost_and_limits_are_enforced() {
        let dir = tempdir().unwrap();
        let child = dir.path().join("removed");
        fs::create_dir(&child).unwrap();
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        let closed = state.new_tab(Some(child.clone())).unwrap();
        assert!(state.close_tab(closed));
        fs::remove_dir(child).unwrap();
        assert!(state.reopen_closed_tab(closed).is_err());
        assert_eq!(state.recently_closed().len(), 1);
        assert_eq!(state.tabs().len(), 1);
        assert!(!state.can_close_tab(1));
        for _ in 1..MAX_FILE_MANAGER_TABS {
            state.new_tab(None).unwrap();
        }
        assert!(!state.can_create_tab());
        assert!(state.new_tab(None).is_err());
        assert!(state.duplicate_tab(1).is_err());
        assert!(state.reopen_closed_tab(closed).is_err());
    }

    #[test]
    fn search_is_unicode_name_matching_and_filters_sort_in_rust() {
        let dir = tempdir().unwrap();
        fs::create_dir(dir.path().join("zzz-folder")).unwrap();
        fs::write(dir.path().join("Book 2.cbz"), b"xx").unwrap();
        fs::write(dir.path().join("Book 10.cbz"), b"xxxxxxxxxx").unwrap();
        touch(&dir.path().join("ÉTÉ.jpg"));
        touch(&dir.path().join("aaa.jpg"));
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        state.set_search_query("  BOOK  ");
        let names = |state: &FileManagerState| {
            state
                .entries()
                .unwrap()
                .into_iter()
                .map(|entry| entry.node.name)
                .collect::<Vec<_>>()
        };
        assert_eq!(names(&state), ["Book 2.cbz", "Book 10.cbz"]);
        state.set_sort(SortField::Size, SortOrder::Descending);
        assert_eq!(names(&state), ["Book 10.cbz", "Book 2.cbz"]);
        state.set_search_query("été");
        assert_eq!(names(&state), ["ÉTÉ.jpg"]);
        state.set_entry_filter(EntryFilter::Archives);
        assert!(names(&state).is_empty());
        state.set_search_query("");
        assert_eq!(names(&state).len(), 2);
        state.set_entry_filter(EntryFilter::All);
        state.set_sort(SortField::Name, SortOrder::Ascending);
        assert_eq!(names(&state)[0], "zzz-folder");
        assert_eq!(names(&state)[1], "aaa.jpg");
        state.set_directories_first(false);
        assert_eq!(names(&state)[0], "aaa.jpg");
        // A parent directory name must not make every child match.
        state.set_search_query(dir.path().file_name().unwrap().to_string_lossy());
        assert!(names(&state).is_empty());
    }

    #[test]
    fn search_uses_token_grammar_and_or_mode() {
        let dir = tempdir().unwrap();
        touch(&dir.path().join("summer_photo.jpg"));
        touch(&dir.path().join("summer draft.jpg"));
        touch(&dir.path().join("autumn.jpg"));
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        let names = |state: &FileManagerState| {
            state
                .entries()
                .unwrap()
                .into_iter()
                .map(|entry| entry.node.name)
                .collect::<Vec<_>>()
        };
        // 空格分词：整串子串匹配在这条上必然 0 结果，文件名里的 `_` 也不该挡住。
        state.set_search_query("summer photo");
        assert_eq!(names(&state), ["summer_photo.jpg"]);
        // 否定词元与引号短语。
        state.set_search_query("summer -draft");
        assert_eq!(names(&state), ["summer_photo.jpg"]);
        state.set_search_query(r#""summer draft""#);
        assert_eq!(names(&state), ["summer draft.jpg"]);
        // AND 下两个词都必须在；切到 OR 后任命中即保留，并按名称排序。
        state.set_search_query("photo autumn");
        assert!(names(&state).is_empty());
        state.set_search_or_mode(true);
        assert_eq!(names(&state), ["autumn.jpg", "summer_photo.jpg"]);
        // 只有否定词元时是「不含它的都留下」。
        state.set_search_query("-summer");
        assert_eq!(names(&state), ["autumn.jpg"]);
    }

    #[test]
    fn search_in_path_never_lets_the_root_name_match_every_child() {
        let dir = tempdir().unwrap();
        let spring = dir.path().join("spring");
        fs::create_dir(&spring).unwrap();
        touch(&spring.join("001.jpg"));
        touch(&spring.join("002.jpg"));
        let mut state = FileManagerState::new(Some(spring.clone())).unwrap();
        assert!(state.settings().search_in_path);
        state.set_search_query("spring");
        assert!(state.entries().unwrap().is_empty());
        state.set_search_query("00");
        assert_eq!(state.entries().unwrap().len(), 2);
        state.set_search_in_path(false);
        assert_eq!(state.entries().unwrap().len(), 2);
    }

    fn search_fixture(root: &Path) {
        fs::create_dir_all(root.join("春组/本子")).unwrap();
        fs::create_dir_all(root.join("秋组")).unwrap();
        touch(&root.join("春组/本子/001.jpg"));
        touch(&root.join("春组/cover.cbz"));
        touch(&root.join("秋组/wind.jpg"));
        // 非媒体：列表本来就不收，搜索也不该凭空造出一条来。
        touch(&root.join("readme.txt"));
    }

    #[test]
    fn recursive_search_descends_and_reports_relative_directory() {
        let dir = tempdir().unwrap();
        search_fixture(dir.path());
        let mut state = FileManagerState::new(Some(dir.path().to_path_buf())).unwrap();
        state.set_search_query("春");
        let single = search_entries(&state.search_request(), &AtomicBool::new(false));
        assert_eq!(single.scanned, 3);
        assert_eq!(single.matched, 1);
        assert_eq!(single.hits[0].name, "春组");
        assert_eq!(
            single.hits[0].path,
            dir.path().join("春组").to_string_lossy()
        );

        state.set_search_include_subfolders(true);
        let deep = search_entries(&state.search_request(), &AtomicBool::new(false));
        assert_eq!(deep.scanned, 7);
        // 命中 4 条：`春组` 本身，以及相对路径里带着 `春` 的三条
        //（`春组/本子`、`春组/cover.cbz`、`春组/本子/001.jpg`）。
        assert_eq!(deep.matched, 4);
        // 相对目录不再单独带字段，用 path 相对搜索根算出来即可。
        let mut hits = deep
            .hits
            .iter()
            .map(|node| {
                let relative = Path::new(&node.path)
                    .parent()
                    .and_then(|parent| parent.strip_prefix(dir.path()).ok())
                    .map(|rel| rel.to_string_lossy().replace('\\', "/"))
                    .unwrap_or_default();
                (relative, node.name.clone())
            })
            .collect::<Vec<_>>();
        hits.sort_unstable();
        assert_eq!(
            hits,
            [
                (String::new(), "春组".to_string()),
                ("春组".to_string(), "cover.cbz".to_string()),
                ("春组".to_string(), "本子".to_string()),
                ("春组/本子".to_string(), "001.jpg".to_string()),
            ]
        );
        assert!(!deep.truncated);
    }

    #[test]
    fn recursive_search_matches_relative_path_tokens_and_respects_depth() {
        let dir = tempdir().unwrap();
        search_fixture(dir.path());
        let mut state = FileManagerState::new(Some(dir.path().to_path_buf())).unwrap();
        state.set_search_include_subfolders(true);
        // 「本子 001」跨目录分隔符匹配：词元分别命中相对目录与条目名。
        state.set_search_query("本子 001");
        assert_eq!(
            search_entries(&state.search_request(), &AtomicBool::new(false)).matched,
            1
        );
        state.set_search_in_path(false);
        assert_eq!(
            search_entries(&state.search_request(), &AtomicBool::new(false)).matched,
            0
        );

        // 深度 1 只多扫一层：春组看得到，春组/本子 看不到。
        state.set_search_in_path(true);
        state.set_search_query("001");
        state.set_search_max_depth(99);
        let deep = search_entries(&state.search_request(), &AtomicBool::new(false));
        assert!(deep.hits[0].path.ends_with("春组/本子/001.jpg"));
        state.set_search_max_depth(1);
        assert_eq!(
            search_entries(&state.search_request(), &AtomicBool::new(false)).matched,
            0
        );
    }

    #[test]
    fn recursive_search_honours_hidden_policy_entry_filter_and_cancel() {
        let dir = tempdir().unwrap();
        search_fixture(dir.path());
        touch(&dir.path().join("春组/.secret.cbz"));
        fs::create_dir(dir.path().join("春组/mimageviewer.meta.miv")).unwrap();
        touch(&dir.path().join("春组/mimageviewer.meta.miv/ghost.jpg"));
        let mut state = FileManagerState::new(Some(dir.path().to_path_buf())).unwrap();
        state.set_search_include_subfolders(true);
        state.set_search_query("secret ghost");
        assert_eq!(
            search_entries(&state.search_request(), &AtomicBool::new(false)).matched,
            0
        );
        state.set_search_query("secret ghost 001 wind cover");
        state.set_search_or_mode(true);
        assert_eq!(
            search_entries(&state.search_request(), &AtomicBool::new(false)).matched,
            3
        );
        state.set_search_or_mode(false);
        // 空查询不是「全量列出」：递归搜索直接早退，一个条目都不检视。
        state.set_search_query("");
        let idle = search_entries(&state.search_request(), &AtomicBool::new(false));
        assert!(idle.hits.is_empty());
        assert_eq!(idle.scanned, 0);
        state.set_search_query("cbz");
        state.set_entry_filter(EntryFilter::Archives);
        let archives = search_entries(&state.search_request(), &AtomicBool::new(false));
        assert_eq!(
            archives
                .hits
                .iter()
                .map(|node| node.name.as_str())
                .collect::<Vec<_>>(),
            ["cover.cbz"]
        );
        state.set_show_hidden_files(true);
        assert_eq!(
            search_entries(&state.search_request(), &AtomicBool::new(false)).matched,
            2
        );

        // 取消：已置位的令牌让遍历一步都不走，但请求本身仍算正常交出。
        let cancelled = search_entries(&state.search_request(), &AtomicBool::new(true));
        assert!(cancelled.cancelled);
        assert!(cancelled.hits.is_empty());
        assert_eq!(cancelled.scanned, 0);
    }

    #[test]
    fn recursive_search_caps_results_at_the_limit_and_flags_truncation() {
        let dir = tempdir().unwrap();
        fs::create_dir(dir.path().join("many")).unwrap();
        for index in 0..=MAX_SEARCH_RESULTS {
            touch(&dir.path().join("many").join(format!("book-{index:04}.cbz")));
        }
        let mut state = FileManagerState::new(Some(dir.path().to_path_buf())).unwrap();
        state.set_search_query("book");
        state.set_search_include_subfolders(true);
        let outcome = search_entries(&state.search_request(), &AtomicBool::new(false));
        assert_eq!(outcome.hits.len(), MAX_SEARCH_RESULTS);
        assert!(outcome.truncated);
        assert!(outcome.matched >= MAX_SEARCH_RESULTS);
        assert!(!outcome.cancelled);
    }

    #[cfg(unix)]
    #[test]
    fn hidden_policy_is_shared_by_listing_children_and_penetration() {
        let dir = tempdir().unwrap();
        let books = dir.path().join("books");
        fs::create_dir(&books).unwrap();
        touch(&books.join("visible.cbz"));
        touch(&books.join(".hidden.cbz"));
        touch(&books.join("._metadata.jpg"));
        fs::create_dir(books.join("mimageviewer.meta.miv")).unwrap();
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        state.set_penetration_enabled(true);
        state.set_internal_items_mode(InternalItemsMode::All);
        assert!(matches!(
            state.resolve_penetration(&books),
            PenetrationResult::Terminal(_)
        ));
        assert_eq!(state.entries().unwrap()[0].children.len(), 1);
        state.set_show_hidden_files(true);
        assert_eq!(state.resolve_penetration(&books), PenetrationResult::Branch);
        assert_eq!(state.entries().unwrap()[0].children.len(), 2);
        state.navigate(books).unwrap();
        assert_eq!(state.entries().unwrap().len(), 2);
    }

    #[test]
    fn projected_media_directory_can_be_opened_as_a_directory() {
        let dir = tempdir().unwrap();
        let series = dir.path().join("series");
        let chapter = series.join("chapter");
        fs::create_dir_all(&chapter).unwrap();
        touch(&chapter.join("page.jpg"));
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        state.set_penetration_enabled(true);
        let child = state.entries().unwrap().remove(0).children.remove(0);
        assert!(child.is_dir);
        assert_eq!(
            state.open_entry(&child.path, false).unwrap(),
            OpenEntryResult::Opened(chapter)
        );
    }

    #[cfg(unix)]
    #[test]
    fn unix_symlinks_are_browsable_and_penetration_stops_cycles() {
        use std::os::unix::fs::symlink;
        let dir = tempdir().unwrap();
        let books = dir.path().join("books");
        fs::create_dir(&books).unwrap();
        touch(&books.join("book.cbz"));
        symlink(&books, dir.path().join("linked-books")).unwrap();
        symlink(books.join("book.cbz"), dir.path().join("linked.cbz")).unwrap();
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        let entries = state.entries().unwrap();
        assert!(
            entries
                .iter()
                .any(|entry| entry.node.name == "linked-books" && entry.node.is_dir)
        );
        assert!(
            entries
                .iter()
                .any(|entry| entry.node.name == "linked.cbz" && entry.node.is_archive)
        );
        state.navigate(dir.path().join("linked-books")).unwrap();
        assert_eq!(state.entries().unwrap().len(), 1);
        let loop_dir = dir.path().join("loop");
        fs::create_dir(&loop_dir).unwrap();
        symlink(&loop_dir, loop_dir.join("self")).unwrap();
        assert_eq!(
            state.resolve_penetration(&loop_dir),
            PenetrationResult::Blocked
        );
    }

    #[cfg(unix)]
    #[test]
    fn upstream_dfs_does_not_fold_distinct_unix_paths_into_a_cycle() {
        use std::os::unix::fs::symlink;
        let dir = tempdir().unwrap();
        // Backslash is a valid Unix filename character, not a path separator.
        // This works on the default case-insensitive macOS filesystem as well.
        let origin = dir.path().join(r"a\b");
        let target = dir.path().join("a").join("b");
        fs::create_dir(&origin).unwrap();
        fs::create_dir_all(&target).unwrap();
        let link = origin.join("link");
        symlink(&target, &link).unwrap();
        assert_eq!(
            crate::folder_tree::next_folder_dfs(
                &origin,
                crate::folder_tree::FolderTreeOptions::default()
            ),
            Some(link),
        );
    }

    #[test]
    fn natural_sort_orders_numbers_before_letters_in_entries() {
        let dir = tempdir().unwrap();
        fs::create_dir(dir.path().join("BaiduNetdiskDownload")).unwrap();
        fs::create_dir(dir.path().join("CloudMusic")).unwrap();
        fs::create_dir(dir.path().join("Game")).unwrap();
        fs::create_dir(dir.path().join("1BACKUP")).unwrap();
        fs::create_dir(dir.path().join("1GAME")).unwrap();

        let state = FileManagerState::new(Some(dir.path().into())).unwrap();
        let names: Vec<String> = state
            .entries()
            .unwrap()
            .into_iter()
            .map(|e| e.node.name)
            .collect();

        assert_eq!(
            names,
            vec![
                "1BACKUP",
                "1GAME",
                "BaiduNetdiskDownload",
                "CloudMusic",
                "Game"
            ]
        );
    }

    #[test]
    fn per_location_view_state_persistence_and_inheritance() {
        let dir = tempdir().unwrap();
        let folder_a = dir.path().join("folder_a");
        let sub_a = folder_a.join("sub");
        let folder_b = dir.path().join("folder_b");
        fs::create_dir_all(&sub_a).unwrap();
        fs::create_dir_all(&folder_b).unwrap();

        let mut state = FileManagerState::new(Some(folder_a.clone())).unwrap();
        assert_eq!(state.settings().view_mode, ViewMode::Compact);
        assert_eq!(state.settings().sort_order, SortOrder::Ascending);

        // 在 folder_a 中设置封面网格和降序
        state.set_view_mode(ViewMode::CoverGrid);
        state.set_sort(SortField::Name, SortOrder::Descending);

        // 导航到 sub_a，继承 folder_a 的视图配置
        state.navigate(&sub_a).unwrap();
        assert_eq!(state.settings().view_mode, ViewMode::CoverGrid);
        assert_eq!(state.settings().sort_order, SortOrder::Descending);

        // 导航到未配置的 folder_b，恢复默认配置（Compact + Ascending）
        state.navigate(&folder_b).unwrap();
        assert_eq!(state.settings().view_mode, ViewMode::Compact);
        assert_eq!(state.settings().sort_order, SortOrder::Ascending);

        // 后退回到 sub_a，再次继承并还原 folder_a 的 CoverGrid + Descending
        assert!(state.go_back());
        assert_eq!(state.settings().view_mode, ViewMode::CoverGrid);
        assert_eq!(state.settings().sort_order, SortOrder::Descending);
    }

    fn entry_names(state: &FileManagerState) -> Vec<String> {
        state
            .entries()
            .unwrap()
            .into_iter()
            .map(|entry| entry.node.name)
            .collect()
    }

    fn set_mtime(path: &Path, secs: u64) {
        let file = fs::File::options().write(true).open(path).unwrap();
        file.set_modified(std::time::UNIX_EPOCH + std::time::Duration::from_secs(secs))
            .unwrap();
    }

    #[test]
    fn home_pad_target_is_settable_and_enters_the_back_stack() {
        let dir = tempdir().unwrap();
        let books = dir.path().join("books");
        let other = dir.path().join("other");
        fs::create_dir(&books).unwrap();
        fs::create_dir(&other).unwrap();
        let mut state = FileManagerState::new(Some(other.clone())).unwrap();

        // 未设置主页：主页键不可跳转，但允许右键写入一个主页。
        assert!(state.home_path().is_none());
        assert!(!state.is_home());
        assert!(state.can_set_home());
        assert!(!state.go_home());

        assert!(state.set_home_path(Some(books.clone())));
        assert_eq!(state.home_path(), Some(books.as_path()));
        assert!(state.can_set_home());
        assert!(!state.is_home());
        // 同一值重复写入是空操作。
        let generation = state.generation();
        assert!(!state.set_home_path(Some(books.clone())));
        assert_eq!(state.generation(), generation);

        assert!(state.go_home());
        assert!(state.is_home());
        assert!(!state.can_set_home());
        assert!(same_path(state.active_path(), &books));
        assert!(state.generation() > generation);
        // 主页跳转进入后退栈，后退回到原目录。
        assert!(state.go_back());
        assert!(same_path(state.active_path(), &other));

        // 已在主页上再点一次不产生历史、也不推进 generation。
        assert!(state.go_home());
        let generation = state.generation();
        assert!(!state.go_home());
        assert_eq!(state.generation(), generation);
        assert!(same_path(state.active_path(), &books));

        // 不存在的目录不能成为主页；清除后主页键重新不可用。
        assert!(!state.set_home_path(Some(dir.path().join("missing"))));
        assert!(state.is_home());
        assert!(state.set_home_path(None));
        assert!(state.home_path().is_none());
        assert!(!state.go_home());
    }

    #[test]
    fn date_sort_uses_mtime_and_random_sort_is_stable_between_snapshots() {
        let dir = tempdir().unwrap();
        for (name, mtime) in [("a.cbz", 30u64), ("b.cbz", 10), ("c.cbz", 20)] {
            let path = dir.path().join(name);
            touch(&path);
            set_mtime(&path, mtime);
        }
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();

        state.set_sort(SortField::Date, SortOrder::Ascending);
        assert_eq!(entry_names(&state), ["b.cbz", "c.cbz", "a.cbz"]);
        state.set_sort(SortField::Date, SortOrder::Descending);
        assert_eq!(entry_names(&state), ["a.cbz", "c.cbz", "b.cbz"]);

        let by_name = {
            state.set_sort(SortField::Name, SortOrder::Ascending);
            entry_names(&state)
        };
        assert_eq!(by_name, ["a.cbz", "b.cbz", "c.cbz"]);

        // 切进随机：重新掷种子，并且同一快照序列内顺序不跳动。
        state.set_sort(SortField::Random, SortOrder::Ascending);
        let seed = state.settings().shuffle_seed;
        assert_ne!(seed, 0);
        let shuffled = entry_names(&state);
        assert_eq!(shuffled, entry_names(&state));
        let mut permutation = shuffled.clone();
        permutation.sort();
        assert_eq!(permutation, by_name);

        // 在随机字段上只换方向不重掷种子，顺序就是同一个洗牌的倒序。
        state.set_sort(SortField::Random, SortOrder::Descending);
        assert_eq!(state.settings().shuffle_seed, seed);
        let mut reversed = entry_names(&state);
        reversed.reverse();
        assert_eq!(reversed, shuffled);

        // 刷新才重新洗牌。
        state.set_sort(SortField::Random, SortOrder::Ascending);
        assert_eq!(entry_names(&state), shuffled);
        state.refresh();
        assert_ne!(state.settings().shuffle_seed, seed);
        let mut reshuffled = entry_names(&state);
        reshuffled.sort();
        assert_eq!(reshuffled, by_name);
    }

    #[test]
    fn fixed_shuffle_seed_does_not_degenerate_into_name_order() {
        // 洗牌键必须是名称的函数，且真的会打乱名称序，否则「随机」只是换个说法。
        assert_eq!(shuffle_key(7, "a.cbz"), shuffle_key(7, "a.cbz"));
        assert_ne!(shuffle_key(7, "a.cbz"), shuffle_key(8, "a.cbz"));
        assert_ne!(shuffle_key(7, "a.cbz"), shuffle_key(7, "b.cbz"));

        let dir = tempdir().unwrap();
        for name in ["a.cbz", "b.cbz", "c.cbz", "d.cbz", "e.cbz"] {
            touch(&dir.path().join(name));
        }
        let mut state = FileManagerState::new(Some(dir.path().into())).unwrap();
        state.set_sort(SortField::Name, SortOrder::Ascending);
        let by_name = entry_names(&state);
        state.set_sort(SortField::Random, SortOrder::Ascending);
        state.tabs[state.active_tab].settings.shuffle_seed = 0x1234_5678;
        let fixed = entry_names(&state);
        let mut permutation = fixed.clone();
        permutation.sort();
        assert_eq!(permutation, by_name);
        assert_ne!(fixed, by_name);
    }

    #[test]
    fn temporary_sort_keeps_the_locked_directory_sort() {
        let dir = tempdir().unwrap();
        let books = dir.path().join("books");
        let other = dir.path().join("other");
        fs::create_dir(&books).unwrap();
        fs::create_dir(&other).unwrap();
        let mut state = FileManagerState::new(Some(books.clone())).unwrap();
        let key = crate::settings_db::view_state_key(&books);
        assert!(!state.sort_temporary());
        assert!(state.can_sort_preference());

        // 锁定：降序写进本目录的视图状态。
        state.set_sort(SortField::Name, SortOrder::Descending);
        assert_eq!(state.view_states()[&key].sort_order, SortOrder::Descending);

        // 临时：画面变升序，但目录偏好仍是降序。
        state.set_sort_temporary(true);
        assert!(state.sort_temporary());
        let generation = state.generation();
        state.set_sort_temporary(true);
        assert_eq!(state.generation(), generation);
        state.set_sort(SortField::Name, SortOrder::Ascending);
        assert_eq!(state.settings().sort_order, SortOrder::Ascending);
        assert_eq!(state.view_states()[&key].sort_order, SortOrder::Descending);

        // 离开再回来：恢复的是锁定的降序，临时排序没有漏进偏好。
        state.navigate(&other).unwrap();
        assert_eq!(state.settings().sort_order, SortOrder::Ascending);
        state.navigate(&books).unwrap();
        assert_eq!(state.settings().sort_order, SortOrder::Descending);

        // 关闭临时排序＝把当前排序锁定下来。
        state.set_sort_temporary(false);
        assert!(!state.sort_temporary());
        state.set_sort(SortField::Name, SortOrder::Ascending);
        state.navigate(&other).unwrap();
        state.navigate(&books).unwrap();
        assert_eq!(state.settings().sort_order, SortOrder::Ascending);
    }

    #[test]
    fn every_view_setting_is_captured_and_round_trips_without_loss() {
        let dir = tempdir().unwrap();
        let books = dir.path().join("books");
        fs::create_dir(&books).unwrap();
        let mut state = FileManagerState::new(Some(books.clone())).unwrap();
        let key = crate::settings_db::view_state_key(&books);

        // 六种视图模式里挑三种只存在于文件管理器的：经 reader 那套两档映射往返
        // 会被塌成「详细信息」，这里必须逐字记住。
        for mode in [
            ViewMode::CoverList,
            ViewMode::MosaicList,
            ViewMode::MosaicGrid,
        ] {
            state.set_view_mode(mode);
            assert_eq!(state.view_states()[&key].view_mode, mode);
        }
        state.set_entry_filter(EntryFilter::Images);
        assert_eq!(state.view_states()[&key].entry_filter, EntryFilter::Images);
        state.set_directories_first(false);
        assert!(!state.view_states()[&key].directories_first);
        state.set_show_hidden_files(true);
        assert!(state.view_states()[&key].show_hidden_files);

        // 这些偏好必须能越过 JSON 边界：会话层就是靠它落盘的。
        let before = state.view_states()[&key].clone();
        let json = serde_json::to_string(&before).unwrap();
        let after: FileManagerViewState = serde_json::from_str(&json).unwrap();
        assert_eq!(before, after);

        // 换个会话把它 hydrate 回来：视图、筛选、隐藏项与目录优先都要还原。
        let mut restored = FileManagerState::new(Some(books.clone())).unwrap();
        restored.hydrate_view_states(state.view_states().clone());
        assert_eq!(restored.settings().view_mode, ViewMode::MosaicGrid);
        assert_eq!(restored.settings().entry_filter, EntryFilter::Images);
        assert!(!restored.settings().directories_first);
        assert!(restored.settings().show_hidden_files);
    }

    #[test]
    fn dirty_view_states_only_report_real_changes() {
        let dir = tempdir().unwrap();
        let books = dir.path().join("books");
        let other = dir.path().join("other");
        fs::create_dir(&books).unwrap();
        fs::create_dir(&other).unwrap();
        let mut state = FileManagerState::new(Some(books.clone())).unwrap();
        let books_key = crate::settings_db::view_state_key(&books);
        let other_key = crate::settings_db::view_state_key(&other);

        // 新建会话本身没有待写入的改动。
        assert!(state.take_dirty_view_states().is_empty());

        state.set_view_mode(ViewMode::Details);
        let dirty = state.take_dirty_view_states();
        assert_eq!(dirty.len(), 1);
        assert_eq!(dirty[0].0, books_key);
        assert_eq!(dirty[0].1.view_mode, ViewMode::Details);
        // 取出即清空。
        assert!(state.take_dirty_view_states().is_empty());

        // 同一值重复写入不产生脏记录（否则每次导航都会重写一遍数据库）。
        state.set_view_mode(ViewMode::Details);
        assert!(state.take_dirty_view_states().is_empty());

        // 临时排序只活在画面里：改了排序也不该产生待写入的目录偏好。
        state.set_sort_temporary(true);
        state.set_sort(SortField::Size, SortOrder::Descending);
        assert!(state.take_dirty_view_states().is_empty());
        state.set_sort_temporary(false);
        let _ = state.take_dirty_view_states();

        // 离开目录时的写回收口：`refresh()` 重掷的种子不经过 capture，
        // 要等离开这个目录才落进它的偏好。
        state.set_sort(SortField::Random, SortOrder::Ascending);
        let _ = state.take_dirty_view_states();
        state.tabs[state.active_tab].settings.shuffle_seed = 0xBEEF;
        assert!(state.take_dirty_view_states().is_empty());

        state.navigate(&other).unwrap();
        let dirty = state.take_dirty_view_states();
        assert_eq!(dirty.len(), 1, "只应该带回离开的那个目录: {dirty:?}");
        assert_eq!(dirty[0].0, books_key);
        assert_eq!(dirty[0].1.shuffle_seed, 0xBEEF);
        assert_ne!(dirty[0].0, other_key);
    }

    #[test]
    fn hydrate_never_marks_rows_dirty_and_remember_off_stops_capture() {
        let dir = tempdir().unwrap();
        let books = dir.path().join("books");
        let other = dir.path().join("other");
        fs::create_dir(&books).unwrap();
        fs::create_dir(&other).unwrap();
        let books_key = crate::settings_db::view_state_key(&books);

        let mut source = FileManagerState::new(Some(books.clone())).unwrap();
        source.set_view_mode(ViewMode::CoverGrid);
        let saved = source.view_states().clone();

        // hydrate 进来的数据来自磁盘，不是待写入的改动。
        let mut restored = FileManagerState::new(Some(books.clone())).unwrap();
        restored.hydrate_view_states(saved);
        assert!(restored.take_dirty_view_states().is_empty());
        assert_eq!(restored.settings().view_mode, ViewMode::CoverGrid);

        // 关掉记忆：视图照样生效，但不再产生目录偏好。
        restored.set_remember_view_state(false);
        assert!(!restored.can_sort_preference());
        restored.set_view_mode(ViewMode::Compact);
        assert!(restored.take_dirty_view_states().is_empty());
        assert_eq!(
            restored.view_states()[&books_key].view_mode,
            ViewMode::CoverGrid
        );
        // 关着的时候换目录也不留下新记录。
        restored.navigate(&other).unwrap();
        assert!(restored.take_dirty_view_states().is_empty());
        assert_eq!(restored.settings().view_mode, ViewMode::Compact);

        // 重新打开：从这一刻起继续记，且不会把关着期间的临时值写回旧目录。
        restored.set_remember_view_state(true);
        restored.navigate(&books).unwrap();
        assert_eq!(restored.settings().view_mode, ViewMode::CoverGrid);
        restored.set_view_mode(ViewMode::Details);
        let dirty = restored.take_dirty_view_states();
        assert_eq!(dirty.len(), 1);
        assert_eq!(dirty[0].0, books_key);
        assert_eq!(dirty[0].1.view_mode, ViewMode::Details);
    }
