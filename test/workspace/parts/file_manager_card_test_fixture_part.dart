part of '../file_manager_card_test.dart';
// 快照与条目的构造替身

FileManagerTreeSnapshot _treeSnapshot() => const FileManagerTreeSnapshot(
  rows: [
    FileManagerTreeRow(
      path: '/',
      name: '/',
      depth: 0,
      expanded: true,
      loading: false,
      mayHaveChildren: true,
      isActive: false,
    ),
    FileManagerTreeRow(
      path: '/books',
      name: 'books',
      depth: 1,
      expanded: true,
      loading: false,
      mayHaveChildren: true,
      isActive: true,
    ),
    FileManagerTreeRow(
      path: '/books/series',
      name: 'series',
      depth: 2,
      expanded: false,
      loading: true,
      mayHaveChildren: true,
      isActive: false,
    ),
    FileManagerTreeRow(
      path: '/books/loose',
      name: 'loose',
      depth: 2,
      expanded: false,
      loading: false,
      mayHaveChildren: false,
      isActive: false,
    ),
  ],
  hasPending: false,
);


FileManagerTab _tab(
  int id,
  String title, {
  bool canClose = true,
  bool canGoBack = false,
  bool canGoForward = false,
}) => FileManagerTab(
  id: BigInt.from(id),
  title: title,
  path: '/books/$title',
  canGoBack: canGoBack,
  canGoForward: canGoForward,
  pinned: false,
  canClose: canClose,
  canCloseOthers: false,
  canCloseLeft: false,
  canCloseRight: canClose,
);


FileManagerEntry _entry(
  String name, {
  bool directory = false,
  int children = 0,
  String? searchDirectory,
}) => FileManagerEntry(
  path: '/books/$name',
  name: name,
  isDir: directory,
  isArchive: !directory,
  isImage: false,
  isVideo: false,
  isAudio: false,
  size: BigInt.from(1024),
  modifiedSecs: 1700000000,
  hasChildren: directory,
  searchDirectory: searchDirectory,
  childNames: List.generate(
    children,
    (i) => FileManagerChild(
      path: '/books/$name/$i.cbz',
      name: '$i.cbz',
      isDir: false,
      isArchive: true,
      isImage: false,
      isVideo: false,
      isAudio: false,
    ),
  ),
);


FileManagerSnapshot _snapshot({
  FileManagerViewMode viewMode = FileManagerViewMode.coverList,
  String query = '',
  bool canCreate = true,
  bool canClose = true,
  bool canGoBack = false,
  bool canGoForward = false,
  bool columnsEnabled = false,
  String? homePath,
  bool isHome = false,
  bool canSetHome = true,
  bool sortTemporary = false,
  bool canSortPreference = true,
  bool rememberViewState = true,
  bool subfolders = false,
  bool searchActive = false,
  int tabCount = 2,
}) => FileManagerSnapshot(
  sessionId: BigInt.one,
  maxTabs: 8,
  canCreateTab: canCreate,
  generation: BigInt.one,
  activeTabId: BigInt.one,
  activePath: '/books',
  canGoUp: true,
  breadcrumbs: const [
    FileManagerBreadcrumb(path: '/', name: '/', isRoot: true, isCurrent: false),
    FileManagerBreadcrumb(
      path: '/books',
      name: 'books',
      isRoot: false,
      isCurrent: true,
    ),
  ],
  directoryColumnsEnabled: columnsEnabled,
  directoryColumns: columnsEnabled
      ? const [
          FileManagerDirectoryColumn(
            path: '/books',
            name: 'books',
            entries: [
              FileManagerDirectoryChoice(
                path: '/books/series',
                name: 'series',
                selected: false,
              ),
            ],
          ),
        ]
      : const [],
  tabs: [
    _tab(
      1,
      'books',
      canClose: canClose,
      canGoBack: canGoBack,
      canGoForward: canGoForward,
    ),
    if (tabCount > 1) _tab(2, 'pictures'),
  ],
  recentlyClosed: [_tab(3, 'closed')],
  entries: searchActive
      ? [
          // 搜索结果页签：同名条目只有靠相对目录才分得开。
          _entry('001.jpg', searchDirectory: '春组/本子'),
          _entry('cover.cbz', searchDirectory: '春组'),
        ]
      : [
          _entry('book.cbz'),
          _entry('series with a long name', directory: true, children: 8),
        ],
  roots: const [LocalRootLocation(label: '主目录', path: '/home')],
  penetrationEnabled: true,
  showChildNames: true,
  internalItemsMode: FileManagerInternalItemsMode.all,
  maxDepth: 3,
  viewMode: viewMode,
  showHiddenFiles: false,
  searchQuery: query,
  searchInPath: true,
  searchOrMode: false,
  searchIncludeSubfolders: subfolders,
  searchMaxDepth: 6,
  searchActive: searchActive,
  searchResultQuery: searchActive ? query : '',
  searchScanned: searchActive ? 120 : 0,
  searchMatched: searchActive ? 2 : 0,
  searchTruncated: false,
  searchCancelled: false,
  canSaveSearchTab: searchActive,
  entryFilter: FileManagerEntryFilter.all,
  sortField: FileManagerSortField.name,
  sortOrder: FileManagerSortOrder.ascending,
  directoriesFirst: true,
  homePath: homePath,
  isHome: isHome,
  canSetHome: canSetHome,
  sortTemporary: sortTemporary,
  canSortPreference: canSortPreference,
  rememberViewState: rememberViewState,
);


/// 文件操作那一份会话快照的替身（选中集合 / 剪贴板 / 撤销栈）。
///
/// `generation` 与 [_snapshot] 取同一个值不是随手写的：卡片只在「管理器快照的
/// 版本号变了」时才回头问这一份（见 `_acceptSnapshot`），两个数一样时它只在建
/// 会话那一次问，测试里不会凭空多出一串待收的问询。
FileOpsSnapshot _opsSnapshot({
  int total = 2,
  int selectedCount = 0,
  List<String> selectedPaths = const [],
  bool selectionHasDirectory = false,
  bool canPaste = false,
  FileOpsClipboardMode? clipboardMode,
  int clipboardCount = 0,
  bool canUndo = false,
  int undoCount = 0,
  bool trashRestoreSupported = true,
}) => FileOpsSnapshot(
  sessionId: BigInt.one,
  generation: BigInt.one,
  total: total,
  selectedCount: selectedCount,
  allSelected: selectedCount > 0 && selectedCount == total,
  selectedPaths: selectedPaths,
  selectionHasDirectory: selectionHasDirectory,
  canPaste: canPaste,
  clipboardMode: clipboardMode,
  clipboardCount: clipboardCount,
  canUndo: canUndo,
  undoCount: undoCount,
  trashRestoreSupported: trashRestoreSupported,
);


/// 一次文件操作的回执替身。默认「什么都没做」：判据要的是卡片**收到回执之后**
/// 怎么刷新，而不是替身自己编一份结果。
FileOpsReport _opsReport(
  FileOpsSnapshot snapshot, {
  String kind = 'copy',
  int succeeded = 0,
  int failed = 0,
  int undoable = 0,
  String summary = '',
  List<FileOpsItemResult> items = const [],
}) => FileOpsReport(
  kind: kind,
  succeeded: succeeded,
  failed: failed,
  cancelled: 0,
  undoable: undoable,
  summary: summary,
  items: items,
  snapshot: snapshot,
);
