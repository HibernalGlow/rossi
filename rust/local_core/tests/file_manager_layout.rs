use rossi_local_core::file_manager::{
    FileManagerSettings, FileManagerState, LayoutMode, NewTabPolicy, ViewMode, search_entries,
};
use std::{fs, sync::atomic::AtomicBool};

#[test]
fn layouts_are_tab_local_and_preserve_styles() {
    let tmp = tempfile::tempdir().unwrap();
    let deep = tmp.path().join("a/b/c/d");
    fs::create_dir_all(&deep).unwrap();
    let mut state = FileManagerState::new(Some(deep.clone())).unwrap();
    state.set_view_mode(ViewMode::MosaicGrid);
    state.set_layout_mode(LayoutMode::Columns);
    assert!(state.directory_columns().len() > 3);
    assert_eq!(state.directory_columns().last().unwrap().path, deep);
    state.set_layout_mode(LayoutMode::Tree);
    assert_eq!(state.settings().view_mode, ViewMode::MosaicGrid);
    state.new_tab(None).unwrap();
    assert_eq!(state.settings().layout_mode, LayoutMode::Content);
    state.activate_tab(1);
    assert_eq!(state.settings().layout_mode, LayoutMode::Tree);
    assert_eq!(state.settings().view_mode, ViewMode::MosaicGrid);
}

#[test]
fn policies_choose_defaults_recent_or_inactive_trigger() {
    let tmp = tempfile::tempdir().unwrap();
    let mut state = FileManagerState::new(Some(tmp.path().into())).unwrap();
    state.set_layout_mode(LayoutMode::Tree);
    state.set_view_mode(ViewMode::CoverGrid);
    state.new_tab(None).unwrap();
    state.set_layout_mode(LayoutMode::Columns);
    state.set_view_mode(ViewMode::Details);
    state.set_search_query("do not copy");
    state.configure_new_tabs(NewTabPolicy::Triggering, FileManagerSettings::default());
    state.new_tab_from(None, 1).unwrap();
    assert_eq!(state.settings().layout_mode, LayoutMode::Tree);
    assert_eq!(state.settings().view_mode, ViewMode::CoverGrid);
    assert!(state.settings().search_query.is_empty());
    state.activate_tab(2);
    state.configure_new_tabs(NewTabPolicy::Recent, FileManagerSettings::default());
    state.new_tab_from(None, 1).unwrap();
    assert_eq!(state.settings().view_mode, ViewMode::Details);
    assert_eq!(state.settings().layout_mode, LayoutMode::Columns);
    let mut defaults = FileManagerSettings::default();
    defaults.view_mode = ViewMode::MosaicList;
    defaults.search_include_subfolders = true;
    defaults.show_hidden_files = true;
    state.configure_new_tabs(NewTabPolicy::Defaults, defaults);
    assert_eq!(state.settings().view_mode, ViewMode::Details);
    state.new_tab_from(None, 1).unwrap();
    assert_eq!(state.settings().view_mode, ViewMode::MosaicList);
    assert!(state.settings().search_include_subfolders);
    assert!(state.settings().show_hidden_files);
}

#[test]
fn search_confirmation_keeps_origin_and_fails_atomically_at_tab_limit() {
    let tmp = tempfile::tempdir().unwrap();
    fs::write(tmp.path().join("match.png"), []).unwrap();
    let mut state = FileManagerState::new(Some(tmp.path().into())).unwrap();
    state.set_search_query("match");
    state.search_in_new_tab("match".into()).unwrap();
    let found = search_entries(&state.search_request(), &AtomicBool::new(false)).into_listing();
    state.set_search_listing(found);
    assert_eq!(state.entries().unwrap().len(), 1);
    assert!(state.active_tab().title().starts_with("搜索:"));
    state.activate_tab(1);
    assert!(state.settings().search_query.is_empty());
    assert!(state.search_listing().is_none());
    while state.can_create_tab() {
        state.new_tab(None).unwrap();
    }
    state.set_search_query("keep");
    let id = state.active_tab_id();
    assert!(state.search_in_new_tab("new".into()).is_err());
    assert_eq!(state.active_tab_id(), id);
    assert_eq!(state.settings().search_query, "keep");
}

#[test]
fn search_hierarchy_and_columns_need_no_io_and_keep_duplicate_names() {
    let tmp = tempfile::tempdir().unwrap();
    for dir in ["author/short", "author/long", "other"] {
        fs::create_dir_all(tmp.path().join(dir)).unwrap();
        fs::write(tmp.path().join(dir).join("match.png"), []).unwrap();
    }
    let mut state = FileManagerState::new(Some(tmp.path().into())).unwrap();
    state.set_search_include_subfolders(true);
    state.set_search_query("match");
    let found = search_entries(&state.search_request(), &AtomicBool::new(false)).into_listing();
    state.set_search_listing(found);
    fs::remove_dir_all(tmp.path().join("author")).unwrap();
    fs::remove_dir_all(tmp.path().join("other")).unwrap();
    let rows = state.search_hierarchy();
    assert_eq!(rows.iter().filter(|r| r.entry.is_some()).count(), 3);
    assert_eq!(rows.iter().filter(|r| r.name == "match.png").count(), 3);
    let author = tmp.path().join("author");
    state.toggle_search_tree(&author);
    assert!(
        !state
            .search_hierarchy()
            .iter()
            .any(|r| r.path == author.join("short"))
    );
    state.set_layout_mode(LayoutMode::Columns);
    state.select_search_directory(author.join("short")).unwrap();
    let columns = state.directory_columns();
    assert_eq!(columns.len(), 3);
    assert_eq!(columns[2].path, author.join("short"));
    assert_eq!(state.entries().unwrap().len(), 3);
    state.save_search_as_tab().unwrap();
    assert!(
        !state
            .search_hierarchy()
            .iter()
            .any(|r| r.path == author.join("short"))
    );
}

#[test]
fn another_search_preserves_a_committed_search_tab() {
    let tmp = tempfile::tempdir().unwrap();
    fs::write(tmp.path().join("first.png"), []).unwrap();
    let mut state = FileManagerState::new(Some(tmp.path().into())).unwrap();
    let first = state.search_in_new_tab("first".into()).unwrap();
    let listing = search_entries(&state.search_request(), &AtomicBool::new(false)).into_listing();
    state.set_search_listing(listing);
    state.set_search_query("second");
    let second = state.search_in_new_tab("second".into()).unwrap();
    assert_ne!(first, second);
    assert!(state.search_listing().is_none());
    state.activate_tab(first);
    assert_eq!(state.settings().search_query, "first");
    assert_eq!(state.search_listing().unwrap().entries.len(), 1);
    assert_eq!(state.search_listing().unwrap().query, "first");
}

#[test]
fn first_tab_uses_presets_without_an_inheritance_source() {
    let tmp = tempfile::tempdir().unwrap();
    let mut state = FileManagerState::new(Some(tmp.path().into())).unwrap();
    let mut defaults = FileManagerSettings::default();
    defaults.view_mode = ViewMode::Details;
    defaults.layout_mode = LayoutMode::Tree;
    defaults.show_hidden_files = true;
    state.configure_new_tabs(NewTabPolicy::Triggering, defaults);
    state.initialize_tab_defaults();
    assert_eq!(state.settings().view_mode, ViewMode::Details);
    assert_eq!(state.settings().layout_mode, LayoutMode::Tree);
    state.navigate(tmp.path()).unwrap();
    assert!(state.settings().show_hidden_files);
}

#[test]
fn hierarchical_navigation_keeps_the_chosen_style_and_rich_parent_entries() {
    let tmp = tempfile::tempdir().unwrap();
    let child = tmp.path().join("child");
    fs::create_dir(&child).unwrap();
    fs::write(tmp.path().join("parent10.cbz"), [1, 2, 3]).unwrap();
    fs::write(tmp.path().join("parent2.cbz"), [1]).unwrap();
    fs::write(child.join("inside.png"), [4]).unwrap();
    for layout in [LayoutMode::Tree, LayoutMode::Columns] {
        for style in [
            ViewMode::Compact,
            ViewMode::CoverList,
            ViewMode::MosaicList,
            ViewMode::Details,
            ViewMode::CoverGrid,
            ViewMode::MosaicGrid,
        ] {
            let mut state = FileManagerState::new(Some(tmp.path().into())).unwrap();
            state.set_remember_view_state(true);
            state.set_layout_mode(layout);
            state.set_view_mode(style);
            state.navigate(&child).unwrap();
            assert_eq!(state.settings().view_mode, style);
            state.navigate(tmp.path()).unwrap();
            assert_eq!(state.settings().view_mode, style);
            if layout == LayoutMode::Columns {
                state.navigate(&child).unwrap();
                let columns = state.directory_columns();
                let parent = columns
                    .iter()
                    .find(|column| column.path == tmp.path())
                    .unwrap();
                let names: Vec<_> = parent
                    .entries
                    .iter()
                    .map(|entry| entry.name.as_str())
                    .collect();
                assert_eq!(names, ["child", "parent2.cbz", "parent10.cbz"]);
                let file = parent
                    .entries
                    .iter()
                    .find(|entry| entry.name == "parent10.cbz")
                    .unwrap();
                assert!(file.entry.as_ref().unwrap().node.is_archive);
                assert_eq!(file.entry.as_ref().unwrap().node.size, 3);
                assert!(
                    parent
                        .entries
                        .iter()
                        .find(|entry| entry.name == "child")
                        .unwrap()
                        .selected
                );
            }
        }
    }
}

#[test]
fn search_parent_columns_keep_their_own_hits_without_reading_directories() {
    let tmp = tempfile::tempdir().unwrap();
    let child = tmp.path().join("branch");
    fs::create_dir(&child).unwrap();
    fs::write(tmp.path().join("match.png"), [1]).unwrap();
    fs::write(child.join("match.png"), [2]).unwrap();
    let mut state = FileManagerState::new(Some(tmp.path().into())).unwrap();
    state.set_search_include_subfolders(true);
    state.set_search_query("match");
    state.set_search_listing(
        search_entries(&state.search_request(), &AtomicBool::new(false)).into_listing(),
    );
    state.set_layout_mode(LayoutMode::Columns);
    state.select_search_directory(child.clone()).unwrap();
    fs::remove_dir_all(&child).unwrap();
    fs::remove_file(tmp.path().join("match.png")).unwrap();
    let columns = state.directory_columns();
    assert!(
        columns[0]
            .entries
            .iter()
            .any(|entry| entry.name == "match.png" && entry.entry.is_some())
    );
    assert!(
        columns[1]
            .entries
            .iter()
            .any(|entry| entry.name == "match.png" && entry.entry.is_some())
    );
    assert_eq!(state.entries().unwrap().len(), 2);
}
