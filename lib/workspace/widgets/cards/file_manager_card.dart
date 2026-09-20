import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/service/reader/local_book_navigation_controller.dart';
import 'package:zephyr/src/rust/api/file_manager.dart';
import 'package:zephyr/src/rust/api/file_ops.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/get_path.dart';
import 'package:zephyr/workspace/method/file_manager_actions.dart';
import 'package:zephyr/workspace/model/file_manager_entry_menu_spec.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/service/file_manager_tab_bridge.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_entry_context_menu.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_navigation_pad.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_thumbnail.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/toast.dart';

extension FileManagerViewModeX on FileManagerViewMode {
  /// 文案与图标只有一份，住在 `LibraryViewModeX`：文件管理器与书签/历史面板
  /// 共用同一套视图模式，工具栏 tooltip 与视图菜单不会长出两种叫法。
  String get label => fileManagerLibraryMode(this).label;

  IconData get icon => fileManagerLibraryMode(this).icon;
}

LibraryViewMode fileManagerLibraryMode(FileManagerViewMode mode) {
  return switch (mode) {
    FileManagerViewMode.compact => LibraryViewMode.compact,
    FileManagerViewMode.coverList => LibraryViewMode.coverList,
    FileManagerViewMode.mosaicList => LibraryViewMode.mosaicList,
    FileManagerViewMode.details => LibraryViewMode.details,
    FileManagerViewMode.coverGrid => LibraryViewMode.coverGrid,
    FileManagerViewMode.mosaicGrid => LibraryViewMode.mosaicGrid,
  };
}

/// Rust 驱动的文件浏览卡片。
///
/// 卡片不保存路径、页签、历史或穿透结果；这些状态都来自
/// `rossi_local_core::FileManagerState` 的快照。Flutter 这里只做布局、事件转发和
/// 把 Rust 返回的 `openedPath` 交给已有 Reader 路由。
class FileManagerCard extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final bool isStandalone;

  const FileManagerCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.isStandalone = false,
  });

  @override
  State<FileManagerCard> createState() => _FileManagerCardState();
}

class _FileManagerCardState extends State<FileManagerCard> {
  /// 增量搜索的防抖窗口。再短会让每敲一个字都发一次桥调用，再长打中文
  /// （拼音候选要来回改）会感觉没反应。
  static const _searchDebounceDuration = Duration(milliseconds: 180);

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _pathController = TextEditingController();
  final _homeButtonKey = GlobalKey();

  /// 面包屑的横向位置。路径放不下时滚到**末尾**（最深那层可见），放得下就停在开头 ——
  /// 用 `reverse` 达不到这个区别，它会把短路径也顶到右边，看着像整条右对齐。
  /// 目录列那一行同一个毛病，用同一套画法。
  final _breadcrumbScroll = ScrollController();
  final _directoryColumnScroll = ScrollController();
  String? _breadcrumbRevealedPath;
  String? _columnsRevealedPath;

  bool _editingPath = false;
  bool _searchExpanded = false;
  Timer? _searchDebounce;

  /// 最近一次**发给**核心的搜索原文。用来区分「核心把我的输入回显了」和
  /// 「核心自己改了查询」（切页签、导航会清空）—— 前者不能覆盖输入框里的原始文本。
  String? _pendingSearchQuery;
  bool _searchPending = false;

  /// 这一次搜索是否仍在遍历中。结果本身**不在**这里 —— 命中由 Rust 写进页签，
  /// 快照的 `entries` 就是它，UI 不另存一份（否则换布局重建卡片就会丢结果，
  /// 且列表出现两个真本）。
  bool _searchRunning = false;
  int _searchSerial = 0;

  /// 上一次为「搜索条件签名」跑过遍历的签名，见 [_searchSignatureOf]。
  String _searchSignature = '';

  /// 最近搜索词。正本在 `settings.db`，这里只是这一屏的缓存。
  List<String> _searchHistory = const [];
  bool _searchHistoryLoaded = false;
  static const _searchHistoryLimit = 8;
  BigInt? _sessionId;
  FileManagerSnapshot? _snapshot;
  String? _error;
  bool _busy = false;
  int _requestSerial = 0;
  bool _disposed = false;

  /// 选中态 / 内部剪贴板 / 撤销栈的投影。**正本在 Rust 的 `FileOpsSession` 里**
  /// ——和路径、页签、搜索命中一样，卡片不自己存一份（存了就会出现两个真本，
  /// 换布局重建卡片时其中一个会丢）。
  ///
  /// 它与 [_snapshot] 的 `generation` 是配套的：列表换代后（前进/后退/搜索/排序）
  /// 旧的选中下标就作废了，Rust 会在下一次读选中态时按路径重新绑定，
  /// 所以这里必须跟着重读（见 [_refreshOps]）。
  FileOpsSnapshot? _ops;

  /// [_ops] 里 `selectedPaths` 的集合形式。列表逐行问「我在不在选中集合里」，
  /// 用 List 的 `contains` 就成了每帧 O(行数 × 选中数)。
  Set<String> _selectedPaths = const {};

  /// 选中态有自己的请求序号：它和列表快照是两条独立的线，共用一个序号会
  /// 让「点一下选中」和「敲一下搜索」互相把对方的回包当陈旧结果丢掉。
  int _opsSerial = 0;

  /// 这一帧的「文件操作」总开关（全局设置）。
  ///
  /// 存成字段而不是每次现查：`context.select` 不去重，而列表里**每一行**都要问
  /// 一次「要不要挂右键菜单」——每行各订阅一次，一屏就是几十个订阅。
  /// 在 [build] 里订阅一次、同一个 build pass 里大家读它。
  bool _fileOpsEnabled = true;

  /// 文件树面板。展开/懒扫描/游标的正本在 Rust 的 `FolderPaneState` 里，
  /// 这里只有「开没开」与最近一次投影。
  bool _treeEnabled = false;
  FileManagerTreeSnapshot? _tree;
  BigInt? _treeGeneration;
  Timer? _treePoll;
  int _treeSerial = 0;

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchDebounce?.cancel();
    _treePoll?.cancel();
    // 先摘登记再关会话：反过来的话，两个动作之间有一个窗口期，
    // 别人正好在这时候请求「新页签」会拿到一个马上要消失的会话。
    FileManagerTabBridge.instance.detach(this);
    _searchController.dispose();
    _searchFocus.dispose();
    _pathController.dispose();
    _breadcrumbScroll.dispose();
    _directoryColumnScroll.dispose();
    final id = _sessionId;
    if (id != null) {
      fileManagerClose(id: id);
      // 与 `file_manager_close` 成对：选中态 / 剪贴板 / 撤销栈住在另一张表里，
      // 只关前者会留下一份没人再用的会话状态（以及一个还挂着的取消旗子）。
      fileOpsClose(id: id);
    }
    super.dispose();
  }

  /// 落盘的主页路径（全局设置）。空串 = 用户还没设过。
  ///
  /// 这是「跨重启」的唯一来源：Rust 会话里的 `home_path` 只活在这一次会话里，
  /// 卡片重建（换布局、收起再展开）或重启应用都会重新问这里要。
  String get _persistedHomePath =>
      context.read<GlobalSettingCubit>().state.fileManagerSetting.homePath;

  /// 「记住每个目录的视图与排序」的落盘开关（全局设置）。
  bool get _persistedRememberViewState => context
      .read<GlobalSettingCubit>()
      .state
      .fileManagerSetting
      .rememberViewState;

  /// 新建会话该落在哪个目录，`null` = 交给核心选默认目录。
  ///
  /// 「启动时默认打开主页」是一条**用户主动要**的行为，而主页键开着与否是他对
  /// 「主页」这一节的总表态 —— 关掉主页键后还偷偷把启动落点挪到主页目录，
  /// 就成了一个没处解释的第三条路径，所以这里与主页键同源。
  /// 失效路径不必在这里挡：核心的 `resolve_openable_path` 认不出目录时会向上找到
  /// 最近的、还在的父目录（一个都没有才落到默认目录），
  /// 于是「主页目录被删了」表现为「停在它原来的位置」，而不是开卡即报错。
  String? get _startPath {
    final setting = context.read<GlobalSettingCubit>().state.fileManagerSetting;
    if (!setting.openHomeOnStart || !setting.homeEnabled) return null;
    return setting.homePath.isEmpty ? null : setting.homePath;
  }

  /// 已经提交给会话的「记忆视图」开关值。
  ///
  /// 守卫的意义：同步是发在 build 之后的，判据来自快照；如果这一次提交没有生效
  /// （比如会话刚好出错），两边会一直不一致 —— 没有这个守卫就是每帧重发一次桥调用。
  /// 有它以后语义变成「每次用户改动最多补发一次」：要重试得等用户再改。
  bool? _syncedRememberViewState;

  /// 把全局开关的当前值同步到**活着的会话**上。
  ///
  /// 开关有两个入口（设置页、这张卡片），只在新建会话时注入的话，用户在设置里
  /// 关掉之后会「点了没反应」，要重启才生效。所以每次两者不一致就补一次设置，
  /// 由会话把新的值回写到快照里。
  Future<void> _syncRememberViewState(bool remember) async {
    final id = _sessionId;
    if (id == null || _disposed || _busy) return;
    if (_snapshot?.rememberViewState == remember) return;
    _syncedRememberViewState = remember;
    await _apply(
      (session) =>
          fileManagerSetRememberViewState(id: session, enabled: remember),
    );
  }

  Future<void> _startSession() async {
    if (_busy) return;
    if (_sessionId != null) {
      await _reload();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final home = _persistedHomePath;
      final remember = _persistedRememberViewState;
      final id = await fileManagerCreate(
        // 「启动时默认打开主页」：开着时首个页签直接落在主页目录，
        // 关掉 / 没设主页时不传这个参数（判据见 [_startPath]）。
        initialPath: _startPath,
        homePath: home.isEmpty ? null : home,
        // 目录级视图状态的正本在 Rust 的 `settings.db`，路径在启动期就解析好了
        // （`prepareSettingsDbPath`）；为 null ＝ 本次不记忆，浏览照常。
        settingsDbPath: preparedSettingsDbPath,
        rememberViewState: remember,
      );
      if (_disposed) {
        fileManagerClose(id: id);
        return;
      }
      // 会话已经带着这个值建起来了，别再补发一次。
      _syncedRememberViewState = remember;
      _sessionId = id;
      // 会话一就绪就登记进「新页签」通道：别的地方（收藏 / 历史卡片的右键菜单）
      // 只有从这里才能拿到这个会话。登记的是 `this`，`dispose` 时按同一个对象注销。
      FileManagerTabBridge.instance.attach(this, _openPathInNewTab);
      await _reload();
    } catch (error) {
      _showError(error);
    }
  }

  /// 把某个目录设为主页：**先让核心确认，再落盘**。
  ///
  /// 顺序有意义 —— 核心（`set_home_path`）只接受真实存在的目录，落盘的必须是
  /// 它真正接受的那个路径。否则全局设置里会留下一个核心拒绝的路径，重启后
  /// 又被 `_startSession` 静默忽略，表现为「设置页写着有主页、卡片上却按不动」。
  ///
  /// 持久化里仍可能留着一个后来失效的路径（目录被删 / 移动盘没插），那种情况
  /// 由 UI 用「`_persistedHomePath` 非空但 `snapshot.homePath` 为空」判定失效。
  Future<void> _setHomePath(String path) async {
    final ok = await _apply((id) => fileManagerSetHomePath(id: id, path: path));
    if (!ok || !mounted) return;
    final applied = _snapshot?.homePath;
    if (applied == null) return;
    context.read<GlobalSettingCubit>().updateFileManagerSetting(
      (current) => current.copyWith(homePath: applied),
    );
    showSuccessToast(applied, title: '主页已设为', context: context);
  }

  Future<void> _clearHomePath() async {
    final ok = await _apply((id) => fileManagerSetHomePath(id: id, path: null));
    if (!ok || !mounted || _snapshot?.homePath != null) return;
    context.read<GlobalSettingCubit>().updateFileManagerSetting(
      (current) => current.copyWith(homePath: ''),
    );
    showInfoToast('已清除主页', context: context);
  }

  /// 文件操作的总开关（全局设置，跨重启保持）。
  ///
  /// 落盘之后立刻生效：卡片下一帧就会重建 —— [build] 里 `select` 了它。
  /// 关掉时顺手清空选中集合：留着它，下次打开开关会「复活」一批用户早就忘了的
  /// 选中项，而那时他多半只想重新选。
  Future<void> _setFileOperationsEnabled(bool enabled) async {
    context.read<GlobalSettingCubit>().updateFileManagerSetting(
      (current) => current.copyWith(fileOperations: enabled),
    );
    if (!enabled) await _clearSelection();
  }

  /// 主页菜单：把「回主页 / 设为主页 / 清除主页」三个动作收在主页键自己身上。
  ///
  /// 为什么不直接把右键当「设为主页」：那样「回主页」和「清除主页」在卡片上
  /// 都没有入口，用户只能去设置页里翻。菜单让三个动作都出现在它们作用的那个按钮上，
  /// 并且每一项按当前能力置灰（已在主页时不能重复设、没设过时不能清除）。
  Future<void> _openHomeMenu(FileManagerSnapshot snapshot) async {
    if (_busy) return;
    final box = _homeButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final hasHome = snapshot.homePath != null;
    final selected = await FluentPopupMenu.show<_HomeAction>(
      context: context,
      anchor: box.localToGlobal(Offset.zero) & box.size,
      items: [
        FluentPopupMenuItem(
          value: _HomeAction.goHome,
          enabled: hasHome && !snapshot.isHome,
          title: const Text('回到主页'),
        ),
        FluentPopupMenuItem(
          value: _HomeAction.setHome,
          enabled: snapshot.canSetHome,
          title: const Text('把当前目录设为主页'),
        ),
        const FluentPopupMenuItem.divider(),
        FluentPopupMenuItem(
          value: _HomeAction.clearHome,
          enabled: hasHome,
          title: const Text('清除主页'),
        ),
      ],
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case _HomeAction.goHome:
        await _apply((id) => fileManagerGoHome(id: id));
      case _HomeAction.setHome:
        await _setHomePath(snapshot.activePath);
      case _HomeAction.clearHome:
        await _clearHomePath();
    }
  }

  Future<void> _reload() async {
    final id = _sessionId;
    if (id == null) return;
    final serial = ++_requestSerial;
    setState(() => _busy = true);
    try {
      final snapshot = await fileManagerSnapshot(id: id);
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _acceptSnapshot(snapshot);
        _error = null;
        _busy = false;
      });
    } catch (error) {
      if (!mounted || serial != _requestSerial) return;
      _showError(error);
    }
  }

  /// 「在文件管理新页签里打开 [path]」落到这张卡片上。
  ///
  /// 有意**不走** [_apply]：那个口径里有 `_busy` 与请求序号两道闸，是给
  /// 「用户在这张卡片上连续点」准备的。这里的调用方在**另一张卡片**上，
  /// 它既看不见也不该受这里的忙状态影响 —— 尤其 `_busy` 为真时 [_apply] 静默
  /// 返回 `false`，那会让调用方以为「文件管理面板没起来」，而它明明开着。
  ///
  /// 失败时由**这里**弹具体错误（只有这一层知道异常是什么），并回
  /// [FileManagerTabOpenOutcome.failed] 让调用方别再补一句笼统的失败提示。
  Future<FileManagerTabOpenOutcome> _openPathInNewTab(String path) async {
    final id = _sessionId;
    if (id == null || _disposed) return FileManagerTabOpenOutcome.noSession;
    try {
      final snapshot = await fileManagerNewTab(id: id, path: path);
      if (!mounted || _disposed) return FileManagerTabOpenOutcome.failed;
      setState(() => _acceptSnapshot(snapshot));
      return FileManagerTabOpenOutcome.opened;
    } catch (error) {
      if (mounted) _showError(error);
      return FileManagerTabOpenOutcome.failed;
    }
  }

  Future<bool> _apply(
    Future<FileManagerSnapshot> Function(BigInt id) action,
  ) async {
    final id = _sessionId;
    if (id == null || _busy) return false;
    _cancelPendingSearch();
    final serial = ++_requestSerial;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snapshot = await action(id);
      if (!mounted || serial != _requestSerial) return false;
      setState(() {
        _acceptSnapshot(snapshot);
        _busy = false;
      });
      return true;
    } catch (error) {
      if (!mounted || serial != _requestSerial) return false;
      _showError(error);
      return false;
    }
  }

  // ── 多选与文件操作 ────────────────────────────────────────────────────────
  //
  // 三层分工，与卡片其余部分同构：
  //
  // - **有哪些项、哪一项可用、点一下算打开还是选上** —— 纯函数，见
  //   `lib/workspace/model/file_manager_entry_menu_spec.dart`（判据
  //   `dart run test/workspace/file_manager_entry_menu_check.dart`）；
  // - **问用户要参数、把结果说给他听** —— `lib/workspace/method/file_manager_actions.dart`；
  // - **把动作发给核心** —— 只有这里知道会话 id、忙状态与请求序号，所以桥调用留在这一层。

  /// 一个条目在不在选中集合里。
  bool _isEntrySelected(String path) => _selectedPaths.contains(path);

  /// 这个动作作用在哪几条路径上。
  ///
  /// 右键的那一项**在选中集合里**就是对整批，否则只对它 —— 与菜单那边
  /// [FileManagerEntryMenuInput.inSelection] 的口径必须是同一个，否则会出现
  /// 「菜单写着这 3 项、实际只删了 1 项」这种最糟的组合。
  List<String> _actionTargets(FileManagerEntry entry) =>
      _isEntrySelected(entry.path) ? _selectedPaths.toList() : [entry.path];

  /// 把选中的下标轨同步到最新一代。
  ///
  /// 只在**换代之后**才重读：列表前进/后退/搜索/排序都会让 Rust 的 generation 加一，
  /// 那时下标已经作废（Rust 会在这次读的时候按路径把能救的救回来）。同一代内不再
  /// 补读 —— 代内的选中变化都由 `fileOps*` 的返回值自己带回来了，每帧补一次读
  /// 会让「边打边搜」这类路径白白多跑一倍桥调用。
  void _scheduleOpsRefresh() => unawaited(_refreshOps());

  Future<void> _refreshOps() async {
    final id = _sessionId;
    if (id == null || _disposed) return;
    final serial = ++_opsSerial;
    try {
      final ops = await fileOpsSnapshot(id: id);
      if (!mounted || _disposed || serial != _opsSerial) return;
      setState(() => _applyOps(ops));
    } catch (_) {
      // 读不到选中态不该让整张列表冒红条：它是**附加信息**，列表本身已经拿到了。
      // 真出问题（会话没了）下一次动作会报得更准。
    }
  }

  void _applyOps(FileOpsSnapshot ops) {
    _ops = ops;
    _selectedPaths = ops.selectedPaths.toSet();
  }

  /// 选中态的改动。**都不走 [_busy]**：多选本来就是「连着点几下」，
  /// 中间插一个转圈会让第二下点在灰掉的列表上。
  Future<void> _runOps(Future<FileOpsSnapshot> Function(BigInt id) action) async {
    final id = _sessionId;
    if (id == null || _disposed) return;
    final serial = ++_opsSerial;
    try {
      final ops = await action(id);
      if (!mounted || _disposed || serial != _opsSerial) return;
      setState(() => _applyOps(ops));
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  int _entryIndexOf(FileManagerEntry entry) {
    final entries = _snapshot?.entries ?? const <FileManagerEntry>[];
    final index = entries.indexWhere((candidate) => candidate.path == entry.path);
    // 找不到（列表刚好换了代）就报 0：Rust 那边还有 `path` 这条轨兜底，
    // 抛异常只会让用户看见一个本可以避免的红条。
    return index < 0 ? 0 : index;
  }

  Future<void> _selectSingle(FileManagerEntry entry) => _runOps(
    (id) => fileOpsSelectSingle(
      id: id,
      path: entry.path,
      index: _entryIndexOf(entry),
    ),
  );

  Future<void> _toggleSelected(FileManagerEntry entry) => _runOps(
    (id) => fileOpsSelectToggle(
      id: id,
      path: entry.path,
      index: _entryIndexOf(entry),
    ),
  );

  Future<void> _extendSelectionTo(FileManagerEntry entry) => _runOps(
    (id) => fileOpsSelectChain(
      id: id,
      endIndex: _entryIndexOf(entry),
      // 锚点不在这里记一份：它的正本在 Rust 的选中模型里，Dart 再存一个副本
      // 会和「全选/反选/撤销后清空选中」这些核心侧的状态变化对不上。
      endPath: entry.path,
    ),
  );

  Future<void> _selectAll() => _runOps((id) => fileOpsSelectAll(id: id));

  Future<void> _invertSelection() => _runOps((id) => fileOpsInvertSelection(id: id));

  Future<void> _clearSelection() => _runOps((id) => fileOpsClearSelection(id: id));

  /// 右键（长按）一行时把选中态收敛到它。
  ///
  /// 由菜单宿主的 `onBeforeOpen` 驱动，**在菜单弹出来之前**做完：不收敛的话，
  /// 右键一个没选中的文件会看见菜单以「这 3 项」为主语，而用户一项都没选过。
  Future<void> _convergeSelectionFor(FileManagerEntry entry) async {
    if (_isEntrySelected(entry.path)) return;
    await _selectSingle(entry);
  }

  /// 单击一行。三种含义由纯函数决定（见 [resolveFileManagerEntryTapGesture]）。
  void _onEntryTap(FileManagerEntry entry) {
    final keys = HardwareKeyboard.instance;
    final gesture = resolveFileManagerEntryTapGesture(
      // macOS 的习惯键是 Cmd、Windows/Linux 是 Ctrl，两个都认：代价只是
      // 「在 macOS 上按 Ctrl 也能多选」，比「按错键就没反应」划算。
      // 总开关关掉时两个修饰键都当没按 —— 多选本身也是「文件操作」的一部分。
      toggleModifier:
          _fileOpsEnabled && (keys.isControlPressed || keys.isMetaPressed),
      extendModifier: _fileOpsEnabled && keys.isShiftPressed,
    );
    switch (gesture) {
      case FileManagerEntryTapGesture.open:
        // 打开是对**这一个**的动作。留着一批高亮的行会让人以为打开的是那一批，
        // 所以顺手把选中集合清掉（桌面文件管理器的单击即打开模式也是这么做的）。
        if (_selectedPaths.isNotEmpty) unawaited(_clearSelection());
        unawaited(_openEntry(entry));
      case FileManagerEntryTapGesture.toggle:
        unawaited(_toggleSelected(entry));
      case FileManagerEntryTapGesture.extend:
        unawaited(_extendSelectionTo(entry));
    }
  }

  /// 菜单要用的输入。**必须 O(1)** —— 它随每一行、每一帧重建
  /// （`MenuAnchor.menuChildren` 是普通字段），所以只读手里已有的缓存，
  /// 一次库、一次桥都不发。
  FileManagerEntryMenuInput _menuInputFor(FileManagerEntry entry) {
    final ops = _ops;
    return FileManagerEntryMenuInput(
      isDirectory: entry.isDir,
      selectionCount: ops?.selectedCount ?? 0,
      inSelection: _isEntrySelected(entry.path),
      // 「打开」只对认得出来的东西可用。真正的裁决在核心的 `resolve_openable_path`
      // 里（它还会处理「目录里没有可读内容」这类情况），这里给的是一份保守的近似。
      canOpen: entry.isDir || entry.isArchive || entry.isImage || entry.isVideo,
      // 新建与粘贴的落点就是被右键的那个目录，所以它得是个目录、而且当前不忙。
      canCreateFolder: !_busy,
      canPaste: ops?.canPaste ?? false,
      trashRestoreSupported: ops?.trashRestoreSupported ?? false,
    );
  }

  /// 走一次菜单动作。
  Future<void> _runEntryAction(
    FileManagerEntry entry,
    FileManagerEntryAction action,
  ) async {
    final id = _sessionId;
    if (id == null || _snapshot == null || _busy || _disposed) return;

    // 不改盘、也不用问参数的那几个先处理掉：它们与「点一下列表」同级，
    // 绕一圈忙状态只会让手感变钝。
    if (await _runInlineAction(id, entry, action)) return;
    // 打开一个目录会把整张卡片换掉（也可能把面板整个收起来）。
    if (!mounted || _disposed) return;

    final call = await planFileManagerEntryAction(
      context,
      action: action,
      target: FileManagerEntryTarget(
        path: entry.path,
        name: entry.name,
        isDirectory: entry.isDir,
        count: _actionTargets(entry).length,
        restoreSupported: _ops?.trashRestoreSupported ?? false,
      ),
    );
    // `null` = 用户在对话框里取消了。
    if (call == null || !mounted) return;

    final dispatch = _dispatchFor(id, call);
    if (dispatch == null) return;
    await _runMutation(dispatch);
  }

  /// 打开、复制到剪贴板、复制路径这类动作。返回 `true` = 已经处理掉了。
  Future<bool> _runInlineAction(
    BigInt id,
    FileManagerEntry entry,
    FileManagerEntryAction action,
  ) async {
    switch (action) {
      case FileManagerEntryAction.open:
        await _openEntry(entry);
        return true;
      case FileManagerEntryAction.openInNewTab:
        await _openPathInNewTab(entry.path);
        return true;
      case FileManagerEntryAction.copyPath:
        await copyFileManagerPathsToClipboard(
          context,
          paths: _actionTargets(entry),
        );
        return true;
      case FileManagerEntryAction.copy:
      case FileManagerEntryAction.cut:
        // 与操作条走同一个方法。右键那一刻选中态已经被 `onBeforeOpen` 收敛过了
        // （在集合里就是对整批，在集合外就是收敛成这一项），所以这里作用的对象
        // 就是「这一批」，不需要把 [entry] 再传一遍。
        await _copySelectionToClipboard(
          cut: action == FileManagerEntryAction.cut,
        );
        return true;
      case FileManagerEntryAction.paste:
      case FileManagerEntryAction.rename:
      case FileManagerEntryAction.createFolder:
      case FileManagerEntryAction.trash:
      case FileManagerEntryAction.deletePermanently:
        return false;
    }
  }

  /// 动作 → 桥调用。返回 `null` = 这个动作不改盘（由 [_runInlineAction] 处理）。
  ///
  /// 参数缺失时也返回 `null` 而不是硬解包：`call` 的字段是「对话框给的」，
  /// 用 `!` 会把一次本该安静的失败变成崩溃。
  Future<FileOpsReport> Function()? _dispatchFor(
    BigInt id,
    FileManagerActionCall call,
  ) {
    switch (call.action) {
      case FileManagerEntryAction.trash:
        return () => fileOpsTrashSelection(id: id);
      case FileManagerEntryAction.deletePermanently:
        return () => fileOpsDeleteSelection(id: id);
      case FileManagerEntryAction.paste:
        return () => fileOpsPaste(id: id, destination: call.path);
      case FileManagerEntryAction.rename:
        final path = call.path;
        final newName = call.newName;
        if (path == null || newName == null) return null;
        return () => fileOpsRenameEntry(id: id, path: path, newName: newName);
      case FileManagerEntryAction.createFolder:
        final parent = call.path;
        final name = call.newName;
        if (name == null) return null;
        return () =>
            fileOpsCreateDirectory(id: id, name: name, parent: parent);
      case FileManagerEntryAction.open:
      case FileManagerEntryAction.openInNewTab:
      case FileManagerEntryAction.copy:
      case FileManagerEntryAction.cut:
      case FileManagerEntryAction.copyPath:
        return null;
    }
  }

  /// 撤销最近一批。
  Future<void> _undoLastOperation() async {
    final id = _sessionId;
    if (id == null || _busy || _disposed) return;
    await _runMutation(() => fileOpsUndo(id: id));
  }

  /// 一次真的动盘的动作。
  ///
  /// **走 [_busy]** —— 与选中相反，这一类会换掉整个目录的内容，期间再点一下别的
  /// 只会让两个动作赛跑。跑完必须 [_reload]：回包只带了选中态与逐条结果，
  /// **条目列表**还在核心那边（它已经把 generation 加过一了）。
  Future<void> _runMutation(Future<FileOpsReport> Function() dispatch) async {
    final id = _sessionId;
    if (id == null || _busy || _disposed) return;
    _cancelPendingSearch();
    final serial = ++_requestSerial;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final report = await dispatch();
      if (!mounted || _disposed || serial != _requestSerial) return;
      setState(() {
        _applyOps(report.snapshot);
        _busy = false;
      });
      showFileManagerReport(context, report);
      await _reload();
    } catch (error) {
      if (!mounted || serial != _requestSerial) return;
      _showError(error);
    }
  }

  /// 丢掉还没发出的那一次搜索。
  ///
  /// 必须是任何显式动作的第一步：防抖里的搜索一旦晚于用户的点击发出，
  /// 它就会成为「最后发请求的人」，把点击那份快照当成陈旧结果丢掉 ——
  /// 表现是双击归档后 Reader 没起来。
  void _cancelPendingSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = null;
  }

  /// 搜索专用的提交通道：**不走 [_apply] 的 `_busy` 门控**。
  ///
  /// `_busy` 会同时禁用输入框、列表和整排工具键，那是给「一次动作把目录换掉」
  /// 准备的。增量搜索每敲一个字都要跑一遍，套用同一道闸就打不了字。
  /// 陈旧守卫（[_requestSerial]）仍然共用 —— 快照是全量状态，后发优先。
  /// [commit] 为真表示这是用户**主动**定下的搜索（回车、点历史词），才进历史；
  /// 防抖那一路只是边打边看，进历史会让下拉变成前缀垃圾堆。
  Future<void> _submitSearch(String query, {bool commit = false}) async {
    final id = _sessionId;
    if (id == null || _disposed) return;
    _cancelPendingSearch();
    _pendingSearchQuery = query;
    final serial = ++_requestSerial;
    if (!_searchPending) setState(() => _searchPending = true);
    try {
      final snapshot = await fileManagerSetSearchQuery(id: id, query: query);
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _searchPending = false;
        _acceptSnapshot(snapshot);
      });
      if (commit && query.trim().isNotEmpty) {
        await _recordSearchHistory(query);
      }
    } catch (error) {
      if (!mounted || serial != _requestSerial) return;
      setState(() => _searchPending = false);
      _showError(error);
    }
  }

  Future<void> _recordSearchHistory(String query) async {
    try {
      final history = await fileManagerRecordSearchHistory(query: query);
      if (!mounted || history.isEmpty) return;
      setState(() {
        _searchHistory = history;
        _searchHistoryLoaded = true;
      });
    } catch (_) {
      // 历史是辅助信息：写不进去（SQLite 被占、路径没解析出来）不该让刚出结果的
      // 搜索冒一个红条，更不该把已经拿到的命中丢掉。
    }
  }

  Future<void> _loadSearchHistory() async {
    if (_searchHistoryLoaded || _disposed) return;
    _searchHistoryLoaded = true;
    try {
      final history = await fileManagerSearchHistory(
        limit: _searchHistoryLimit,
      );
      if (!mounted || history.isEmpty) return;
      setState(() => _searchHistory = history);
    } catch (_) {
      // 同上：读不到就当这次没有历史。
    }
  }

  Future<void> _clearSearchHistory() async {
    try {
      await fileManagerClearSearchHistory();
      if (!mounted) return;
      setState(() => _searchHistory = const []);
      showInfoToast('已清空搜索历史', context: context);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  /// 输入即搜：防抖到 [_searchDebounceDuration]，回车走 `_submitSearch` 立即提交。
  void _scheduleSearch(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      _searchDebounceDuration,
      () => _submitSearch(query),
    );
  }

  /// 「递归搜索模式」：只在**确实有查询**且**开了含子目录**时成立。
  ///
  /// 只搜当前一层时不需要另一套结果列表 —— 那一层的过滤已经由 Rust 的 `entries`
  /// 做完并带着子文件名/穿透投影，另起一份只会让两种视图各说各话。
  bool _isRecursiveSearch(FileManagerSnapshot snapshot) =>
      snapshot.searchQuery.isNotEmpty && snapshot.searchIncludeSubfolders;

  /// 会让一次递归搜索作废的条件集合。
  ///
  /// 逐项去挂触发点（类型筛选、排序、隐藏项、层数……）一定会漏，改成「条件变了
  /// 就跑一次」：签名一致时什么都不发，用户连续敲字也只在他真正改动的时刻重扫。
  String _searchSignatureOf(FileManagerSnapshot snapshot) {
    return [
      snapshot.activePath,
      snapshot.activeTabId,
      snapshot.searchQuery,
      snapshot.searchIncludeSubfolders,
      snapshot.searchMaxDepth,
      snapshot.searchInPath,
      snapshot.searchOrMode,
      snapshot.entryFilter.name,
      snapshot.sortField.name,
      snapshot.sortOrder.name,
      snapshot.directoriesFirst,
      snapshot.showHiddenFiles,
    ].join('\x1F');
  }

  /// 跑一次搜索。返回的是**快照**：命中由 Rust 写进当前页签，卡片只负责画它。
  ///
  /// 不参与 [_requestSerial]：那个序号管的是「别用旧快照盖掉新目录」，而遍历不改
  /// 目录。它用自己的序号，配合 [_searchSignature] 决定这一次还要不要画出来。
  Future<void> _runSearch(FileManagerSnapshot snapshot) async {
    final id = _sessionId;
    if (id == null || _disposed) return;
    final serial = ++_searchSerial;
    setState(() => _searchRunning = true);
    try {
      final next = await fileManagerSearch(id: id);
      if (!mounted || serial != _searchSerial) return;
      // 遍历期间用户可能已经改了词或切走：条件签名一变，这批结果就不是现在要看的了。
      if (_searchSignatureOf(next) != _searchSignature) {
        setState(() => _searchRunning = false);
        return;
      }
      setState(() {
        _searchRunning = false;
        _acceptSnapshot(next);
      });
    } catch (error) {
      if (!mounted || serial != _searchSerial) return;
      setState(() => _searchRunning = false);
      _showError(error);
    }
  }

  Future<void> _cancelSearch() async {
    final id = _sessionId;
    if (id == null) return;
    // 只发中止请求：剩下的交给 `_runSearch` 那条 future，它会带着
    // `cancelled` 标记正常返回，界面据此说明结果是部分扫过的。
    await fileManagerCancelSearch(id: id);
  }

  /// 搜索行上的动作（条件开关、存为页签、回到目录）。
  ///
  /// 先丢掉还在排队的那一次键入：这些动作是用户**决定**下来的，不能让一个
  /// 晚到的防抖请求把它们的结果当成陈旧数据丢掉。
  Future<void> _applySearchAction(
    Future<FileManagerSnapshot> Function(BigInt id) action,
  ) async {
    _cancelPendingSearch();
    await _apply(action);
  }

  Future<void> _openEntry(
    FileManagerEntry entry, {
    bool forceEnter = false,
  }) async {
    await _openAction(
      (id) => fileManagerOpenEntry(
        id: id,
        path: entry.path,
        forceEnter: forceEnter,
      ),
    );
  }

  Future<void> _openArchive(FileManagerEntry entry) async {
    if (!entry.isArchive) return;
    await _openAction((id) => fileManagerOpenArchive(id: id, path: entry.path));
  }

  Future<void> _openAction(
    Future<FileManagerActionResult> Function(BigInt id) action,
  ) async {
    final id = _sessionId;
    if (id == null || _busy) return;
    _cancelPendingSearch();
    final serial = ++_requestSerial;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await action(id);
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _acceptSnapshot(result.snapshot);
      });
      final openedPath = result.openedPath;
      if (openedPath != null && mounted && serial == _requestSerial) {
        // Keep the card busy while the reader route is on top. This makes the
        // second pointer-up of a double-click unable to enqueue another route.
        await _openReader(openedPath, result.bookNavigationJson);
      }
      if (!mounted || serial != _requestSerial) return;
      setState(() => _busy = false);
    } catch (error) {
      if (!mounted || serial != _requestSerial) return;
      _showError(error);
    }
  }

  Future<void> _openChild(FileManagerChild child) async {
    await _openEntry(_entryFromChild(child));
  }

  Future<void> _openArchiveChild(FileManagerChild child) async {
    if (!child.isArchive) return;
    await _openArchive(_entryFromChild(child));
  }

  FileManagerEntry _entryFromChild(FileManagerChild child) {
    return FileManagerEntry(
      path: child.path,
      name: child.name,
      isDir: child.isDir,
      isArchive: child.isArchive,
      isImage: child.isImage,
      isVideo: child.isVideo,
      isAudio: child.isAudio,
      size: BigInt.zero,
      modifiedSecs: 0,
      hasChildren: false,
      childNames: const [],
    );
  }

  Future<void> _openReader(String path, String? navigationJson) async {
    if (!mounted) return;
    await context.pushRoute(
      ComicReadRoute(
        comicId: path,
        order: 0,
        from: 'local_file_manager',
        epsNumber: 1,
        type: ComicEntryType.normal,
        comicInfo: path,
        chapterExtern: {
          LocalBookNavigationController.contextKey: ?navigationJson,
        },
        stringSelectCubit: StringSelectCubit(),
      ),
    );
  }

  void _acceptSnapshot(FileManagerSnapshot snapshot) {
    _snapshot = snapshot;
    // 列表换代了，选中态要跟着重读 —— 否则界面上会拿旧代的下标去标新代的行。
    if (_ops?.generation != snapshot.generation) _scheduleOpsRefresh();
    _syncSearchField(snapshot);
    final signature = _searchSignatureOf(snapshot);
    if (signature == _searchSignature) return;
    _searchSignature = signature;
    if (!_isRecursiveSearch(snapshot)) {
      // 条件已不成立：把还在跑的遍历也停下，否则它的结果会落在一屏无关的画面上。
      if (_searchRunning) {
        fileManagerCancelSearch(id: snapshot.sessionId);
      }
      return;
    }
    // 搜索条件的正本全在快照里，所以「变了就跑一次」覆盖到了查询、层数、类型
    // 筛选、排序、隐藏项与切页签，不需要在每个控件后面各挂一次。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _searchSignature != signature) return;
      _runSearch(snapshot);
    });
  }

  /// 输入框的文本以「谁最后改了查询」为准，而不是无条件跟随快照。
  ///
  /// 核心收到查询会 `trim`。边打边搜时若无条件回显，用户刚敲下的空格会被吃掉，
  /// 表现为「输入框拒绝空格」。所以只要框还拿着焦点、而核心给出的正是我们刚
  /// 提交的那一份（去掉首尾空白之后），就不动它。
  /// 反之 —— 核心自己改了查询（切页签与导航会清空搜索）—— 必须盖回输入框，
  /// 否则框里留着一个已经不再生效的词。
  void _syncSearchField(FileManagerSnapshot snapshot) {
    final server = snapshot.searchQuery;
    final asked = _pendingSearchQuery;
    if (_searchFocus.hasFocus && asked != null && server == asked.trim()) {
      return;
    }
    _pendingSearchQuery = null;
    if (_searchController.text == server) return;
    _searchController.value = TextEditingValue(
      text: server,
      selection: TextSelection.collapsed(offset: server.length),
    );
  }

  void _showError(Object error) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final theme = Theme.of(context);
    // 设置页改开关时这张卡片不会重建，所以在这里对齐一次；排到帧后是因为
    // 同步本身会 `setState`，在 build 期间发起会撞上「构建期间改状态」。
    final remember = context.select<GlobalSettingCubit, bool>(
      (cubit) => cubit.state.fileManagerSetting.rememberViewState,
    );
    // 写操作总开关。订阅放在这里（而不是逐行 `select`）的理由见 [_fileOpsEnabled]。
    _fileOpsEnabled = context.select<GlobalSettingCubit, bool>(
      (cubit) => cubit.state.fileManagerSetting.fileOperations,
    );
    if (snapshot != null &&
        !_busy &&
        _syncedRememberViewState != remember &&
        snapshot.rememberViewState != remember) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncRememberViewState(remember);
      });
    }
    if (snapshot != null) {
      _followTreeOn(snapshot.generation);
    }
    if (widget.isStandalone) {
      return Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: _buildBody(context, snapshot),
        ),
      );
    }
    return CollapsibleCard(
      cardId: WorkspaceCardRegistry.localFolder,
      title: '文件浏览',
      icon: Icons.folder_copy_rounded,
      isExpanded: widget.isExpanded,
      onToggle: widget.onToggle,
      onMoveUp: widget.onMoveUp,
      onMoveDown: widget.onMoveDown,
      onHide: widget.onHide,
      trailing: snapshot == null
          ? null
          : Text(
              '${snapshot.tabs.length}/${snapshot.maxTabs}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
      child: _buildBody(context, snapshot),
    );
  }

  Widget _buildBody(BuildContext context, FileManagerSnapshot? snapshot) {
    if (snapshot == null) {
      final loadingWidget = Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : _ErrorState(message: _error!, onRetry: _startSession),
      );
      if (widget.isStandalone) {
        return loadingWidget;
      }
      return SizedBox(height: 180, child: loadingWidget);
    }
    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 只有一个页签时整行没有信息量（对齐 neo 的 tabs-single-hidden）：
        // 新建与恢复改由面包屑的「路径操作」菜单承担，见 [_buildPathActionsMenu]。
        if (snapshot.tabs.length > 1) ...[
          _buildTabs(context, snapshot),
          const SizedBox(height: 6),
        ],
        _buildToolbar(context, snapshot),
        _buildBreadcrumbs(context, snapshot),
        if (snapshot.directoryColumnsEnabled)
          _buildDirectoryColumns(context, snapshot),
        if (_treeEnabled) _buildFileTree(context),
        const SizedBox(height: 6),
        if (_searchExpanded || snapshot.searchQuery.isNotEmpty) ...[
          _buildSearchField(context, snapshot),
          const SizedBox(height: 4),
          _buildSearchOptions(context, snapshot),
          const SizedBox(height: 6),
        ],
        _buildRoots(context, snapshot),
        if (_error != null) _buildInlineError(context),
        // 操作条紧贴列表上方：它管的就是下面那一批行。
        if (_fileOpsEnabled && _selectedPaths.isNotEmpty) ...[
          const SizedBox(height: 6),
          _buildSelectionBar(context, snapshot),
        ],
        const SizedBox(height: 6),
      ],
    );
    if (!widget.isStandalone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [controls, _buildEntries(context, snapshot)],
      );
    }
    // 上/下边栏可能很矮：控件区域可滚动，始终给目录内容保留可用高度。
    return LayoutBuilder(
      builder: (context, constraints) {
        final reservedListHeight = (constraints.maxHeight * 0.4).clamp(
          0.0,
          120.0,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight - reservedListHeight,
              ),
              child: SingleChildScrollView(child: controls),
            ),
            Expanded(child: _buildEntries(context, snapshot)),
          ],
        );
      },
    );
  }

  void _editPath(FileManagerSnapshot snapshot) {
    _pathController.value = TextEditingValue(
      text: snapshot.activePath,
      selection: TextSelection(
        baseOffset: 0,
        extentOffset: snapshot.activePath.length,
      ),
    );
    setState(() => _editingPath = true);
  }

  Future<void> _submitPath() async {
    final accepted = await _apply(
      (id) => fileManagerNavigateText(id: id, text: _pathController.text),
    );
    if (accepted && mounted) setState(() => _editingPath = false);
  }

  /// 把一条横向滚动的行停在「开头，除非放不下才滚到末尾」。
  ///
  /// 帧后是因为要等布局完成才知道 `maxScrollExtent` 是多少；内容放得下时它是 0，
  /// 于是这一句等价于「保持左对齐」。
  void _revealTail(ScrollController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      controller.jumpTo(controller.position.maxScrollExtent);
    });
  }

  Widget _buildBreadcrumbs(BuildContext context, FileManagerSnapshot snapshot) {
    if (_editingPath) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (!_busy) setState(() => _editingPath = false);
          },
        },
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('file-manager-path-input'),
                controller: _pathController,
                autofocus: true,
                enabled: !_busy,
                textInputAction: TextInputAction.go,
                style: Theme.of(context).textTheme.bodySmall,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '目录路径',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submitPath(),
              ),
            ),
            IconButton(
              tooltip: '转到目录',
              onPressed: _busy ? null : _submitPath,
              icon: const Icon(Icons.check, size: 18),
            ),
            IconButton(
              tooltip: '取消路径编辑',
              onPressed: _busy
                  ? null
                  : () => setState(() => _editingPath = false),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      );
    }
    if (_breadcrumbRevealedPath != snapshot.activePath) {
      _breadcrumbRevealedPath = snapshot.activePath;
      _revealTail(_breadcrumbScroll);
    }
    return Row(
      children: [
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              key: const ValueKey('file-manager-breadcrumb-scroll'),
              controller: _breadcrumbScroll,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final part in snapshot.breadcrumbs) ...[
                    if (!part.isRoot) const Icon(Icons.chevron_right, size: 14),
                    Tooltip(
                      message: part.path,
                      child: TextButton(
                        key: ValueKey('file-manager-breadcrumb:${part.path}'),
                        onPressed: _busy
                            ? null
                            : part.isCurrent
                            ? () => _editPath(snapshot)
                            : () => _apply(
                                (id) => fileManagerNavigate(
                                  id: id,
                                  path: part.path,
                                ),
                              ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            part.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        _buildPathActionsMenu(
          context,
          snapshot,
          showTabActions: snapshot.tabs.length <= 1,
        ),
      ],
    );
  }

  /// 面包屑行尾唯一的那颗键：路径与（页签行收起时的）页签动作都收在这里，
  /// 对齐 neo 的「路径操作」菜单。
  ///
  /// 「目录列」的开关只有这一处 —— 工具栏上曾经也有一颗，同一件事就有了两个入口。
  /// [showTabActions] 为真表示页签行被收掉了（单页签），这时新建与恢复已关闭页签
  /// 也搬进这颗菜单，否则它们就没有入口。
  Widget _buildPathActionsMenu(
    BuildContext context,
    FileManagerSnapshot snapshot, {
    required bool showTabActions,
  }) {
    final withTabActions = showTabActions && snapshot.canCreateTab;
    return FluentPopupMenuButton<String>(
      tooltip: '路径操作',
      visualDensity: VisualDensity.compact,
      enabled: !_busy,
      icon: const Icon(Icons.more_horiz_rounded, size: 18),
      onSelected: (value) {
        if (value.startsWith('reopen:')) {
          final tabId = BigInt.tryParse(value.substring('reopen:'.length));
          if (tabId == null) return;
          _apply((id) => fileManagerReopenClosedTab(id: id, tabId: tabId));
          return;
        }
        switch (value) {
          case 'new-tab':
            _apply((id) => fileManagerNewTab(id: id));
          case 'columns':
            _apply(
              (id) => fileManagerSetDirectoryColumns(
                id: id,
                enabled: !snapshot.directoryColumnsEnabled,
              ),
            );
          case 'edit':
            _editPath(snapshot);
        }
      },
      itemBuilder: (_) => [
        if (withTabActions) ...[
          const FluentPopupMenuItem(
            value: 'new-tab',
            leading: Icon(Icons.add_rounded, size: 16),
            title: Text('新建页签'),
          ),
          for (final tab in snapshot.recentlyClosed.reversed)
            FluentPopupMenuItem(
              value: 'reopen:${tab.id}',
              leading: const Icon(Icons.history_rounded, size: 16),
              title: Text('恢复页签：${tab.title}'),
            ),
          const FluentPopupMenuItem.divider(),
        ],
        FluentPopupMenuItem(
          value: 'columns',
          leading: const Icon(Icons.view_column_outlined, size: 16),
          title: Text(snapshot.directoryColumnsEnabled ? '收起目录列' : '展开目录列'),
        ),
        const FluentPopupMenuItem(
          value: 'edit',
          leading: Icon(Icons.edit_outlined, size: 16),
          title: Text('编辑路径'),
        ),
      ],
    );
  }

  Widget _buildDirectoryColumns(
    BuildContext context,
    FileManagerSnapshot snapshot,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth / 2).clamp(150.0, 240.0);
        if (_columnsRevealedPath != snapshot.activePath) {
          _columnsRevealedPath = snapshot.activePath;
          _revealTail(_directoryColumnScroll);
        }
        return SizedBox(
          height: 200,
          child: SingleChildScrollView(
            controller: _directoryColumnScroll,
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final column in snapshot.directoryColumns)
                  SizedBox(
                    width: width,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _apply(
                                    (id) => fileManagerNavigate(
                                      id: id,
                                      path: column.path,
                                    ),
                                  ),
                            child: Text(
                              column.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            child: column.error != null
                                ? SingleChildScrollView(
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(
                                        column.error!,
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                        ),
                                      ),
                                    ),
                                  )
                                : column.entries.isEmpty
                                ? const Center(child: Text('没有子目录'))
                                : ListView.builder(
                                    itemCount: column.entries.length,
                                    itemBuilder: (context, index) {
                                      final entry = column.entries[index];
                                      return ListTile(
                                        key: ValueKey(
                                          'file-manager-column:${entry.path}',
                                        ),
                                        dense: true,
                                        selected: entry.selected,
                                        leading: const Icon(
                                          Icons.folder_outlined,
                                          size: 18,
                                        ),
                                        title: Text(
                                          entry.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onTap: _busy
                                            ? null
                                            : () => _apply(
                                                (id) => fileManagerNavigate(
                                                  id: id,
                                                  path: entry.path,
                                                ),
                                              ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 开关文件树。
  ///
  /// 打开时顺手关掉目录列：两者回答的是同一个问题（「我在这棵目录树的哪儿」），
  /// 同时开着只是把本来就不高的卡片挤成两半。
  Future<void> _setTreeEnabled(bool enabled) async {
    if (!enabled) {
      _treePoll?.cancel();
      setState(() {
        _treeEnabled = false;
        _tree = null;
        _treeGeneration = null;
      });
      return;
    }
    final snapshot = _snapshot;
    if (snapshot != null && snapshot.directoryColumnsEnabled) {
      await _apply(
        (id) => fileManagerSetDirectoryColumns(id: id, enabled: false),
      );
    }
    if (!mounted) return;
    setState(() {
      _treeEnabled = true;
      // 清掉上一次的对齐记号，让本帧后的 `_followTreeOn` 一定问一次。
      _treeGeneration = null;
    });
  }

  /// 当前目录一变，树就重新对齐一次。
  ///
  /// 挂在 `generation` 上而不是逐个导航动作里：改当前目录的入口有七八个
  /// （页签、面包屑、导航掌、根目录、条目双击、收藏/历史卡片的「新页签打开」），
  /// 而核心保证每个生效的动作都推进 `generation`。
  void _followTreeOn(BigInt generation) {
    if (!_treeEnabled || _treeGeneration == generation) return;
    _treeGeneration = generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _treeEnabled) _loadTree();
    });
  }

  Future<void> _loadTree() async {
    final id = _sessionId;
    if (id == null || _disposed || !_treeEnabled) return;
    final serial = ++_treeSerial;
    try {
      final tree = await fileManagerTreeSnapshot(id: id);
      if (!mounted || serial != _treeSerial || !_treeEnabled) return;
      setState(() => _tree = tree);
      _scheduleTreePoll(tree);
    } catch (error) {
      if (!mounted || serial != _treeSerial) return;
      setState(() => _tree = null);
      _showError(error);
    }
  }

  Future<void> _toggleTreeNode(String path) async {
    final id = _sessionId;
    if (id == null || _disposed || _busy) return;
    final serial = ++_treeSerial;
    try {
      final tree = await fileManagerTreeToggle(id: id, path: path);
      if (!mounted || serial != _treeSerial || !_treeEnabled) return;
      setState(() => _tree = tree);
      _scheduleTreePoll(tree);
    } catch (error) {
      if (!mounted || serial != _treeSerial) return;
      _showError(error);
    }
  }

  /// 后台扫描没有帧循环可挂，只能自己隔一会儿再问一次。核心在每次被问时
  /// 收一轮 `poll_pending`，所以这里只负责「什么时候再问」。
  void _scheduleTreePoll(FileManagerTreeSnapshot tree) {
    _treePoll?.cancel();
    if (!tree.hasPending) return;
    _treePoll = Timer(const Duration(milliseconds: 80), _loadTree);
  }

  Widget _buildFileTree(BuildContext context) {
    final tree = _tree;
    return SizedBox(
      height: 200,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: tree == null
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : tree.rows.isEmpty
            ? const Center(child: Text('没有可显示的目录'))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: tree.rows.length,
                itemBuilder: (context, index) =>
                    _buildTreeRow(context, tree.rows[index]),
              ),
      ),
    );
  }

  Widget _buildTreeRow(BuildContext context, FileManagerTreeRow row) {
    final theme = Theme.of(context);
    return ListTile(
      key: ValueKey('file-manager-tree:${row.path}'),
      dense: true,
      selected: row.isActive,
      selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.08),
      contentPadding: EdgeInsets.only(left: 4.0 + row.depth * 14, right: 8),
      leading: SizedBox(
        width: 24,
        child: !row.mayHaveChildren
            ? null
            : row.loading
            ? const Center(
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                key: ValueKey('file-manager-tree-toggle:${row.path}'),
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: EdgeInsets.zero,
                ),
                iconSize: 16,
                tooltip: row.expanded ? '收起' : '展开',
                onPressed: _busy ? null : () => _toggleTreeNode(row.path),
                icon: Icon(
                  row.expanded
                      ? Icons.expand_more_rounded
                      : Icons.chevron_right_rounded,
                ),
              ),
      ),
      title: Text(
        row.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: row.isActive
            ? const TextStyle(fontWeight: FontWeight.bold)
            : null,
      ),
      trailing: row.error == null
          ? null
          : Icon(
              Icons.error_outline_rounded,
              size: 14,
              color: theme.colorScheme.error,
            ),
      onTap: _busy
          ? null
          : () => _apply((id) => fileManagerNavigate(id: id, path: row.path)),
    );
  }

  Widget _buildTabs(BuildContext context, FileManagerSnapshot snapshot) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: snapshot.tabs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final tab = snapshot.tabs[index];
                final selected = tab.id == snapshot.activeTabId;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTabMenu(snapshot, tab),
                    InputChip(
                      selected: selected,
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 130),
                        child: Text(tab.title, overflow: TextOverflow.ellipsis),
                      ),
                      labelStyle: TextStyle(
                        fontSize: 11,
                        color: selected
                            ? theme.colorScheme.onSecondaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: _busy
                          ? null
                          : () => _apply(
                              (id) =>
                                  fileManagerActivateTab(id: id, tabId: tab.id),
                            ),
                      onDeleted: !_busy && tab.canClose
                          ? () => _apply(
                              (id) =>
                                  fileManagerCloseTab(id: id, tabId: tab.id),
                            )
                          : null,
                      deleteIcon: const Icon(Icons.close, size: 13),
                    ),
                  ],
                );
              },
            ),
          ),
          FluentPopupMenuButton<BigInt>(
            tooltip: '恢复已关闭页签',
            visualDensity: VisualDensity.compact,
            enabled:
                !_busy &&
                snapshot.canCreateTab &&
                snapshot.recentlyClosed.isNotEmpty,
            icon: const Icon(Icons.history_rounded, size: 18),
            onSelected: (tabId) => _apply(
              (id) => fileManagerReopenClosedTab(id: id, tabId: tabId),
            ),
            itemBuilder: (_) => [
              for (final tab in snapshot.recentlyClosed.reversed)
                FluentPopupMenuItem(
                  value: tab.id,
                  title: Text(
                    tab.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: '新建页签',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: _busy || !snapshot.canCreateTab
                ? null
                : () => _apply((id) => fileManagerNewTab(id: id)),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildTabMenu(FileManagerSnapshot snapshot, FileManagerTab tab) {
    return FluentPopupMenuButton<String>(
      tooltip: '页签操作：${tab.title}',
      visualDensity: VisualDensity.compact,
      enabled: !_busy,
      icon: Icon(
        tab.pinned ? Icons.push_pin_rounded : Icons.more_vert_rounded,
        size: 16,
      ),
      onSelected: (action) => _apply(
        (id) => switch (action) {
          'pin' => fileManagerToggleTabPinned(id: id, tabId: tab.id),
          'duplicate' => fileManagerDuplicateTab(id: id, tabId: tab.id),
          'others' => fileManagerCloseOtherTabs(id: id, tabId: tab.id),
          'left' => fileManagerCloseTabsLeft(id: id, tabId: tab.id),
          'right' => fileManagerCloseTabsRight(id: id, tabId: tab.id),
          _ => fileManagerCloseTab(id: id, tabId: tab.id),
        },
      ),
      itemBuilder: (_) => [
        FluentPopupMenuItem(
          value: 'pin',
          title: Text(tab.pinned ? '取消固定' : '固定页签'),
        ),
        FluentPopupMenuItem(
          value: 'duplicate',
          enabled: snapshot.canCreateTab,
          title: const Text('复制页签'),
        ),
        const FluentPopupMenuItem.divider(),
        FluentPopupMenuItem(
          value: 'close',
          enabled: tab.canClose,
          title: const Text('关闭页签'),
        ),
        FluentPopupMenuItem(
          value: 'others',
          enabled: tab.canCloseOthers,
          title: const Text('关闭其他页签'),
        ),
        FluentPopupMenuItem(
          value: 'left',
          enabled: tab.canCloseLeft,
          title: const Text('关闭左侧页签'),
        ),
        FluentPopupMenuItem(
          value: 'right',
          enabled: tab.canCloseRight,
          title: const Text('关闭右侧页签'),
        ),
      ],
    );
  }

  /// 可折叠搜索框：由工具栏的搜索键展开；已有生效查询时强制显示。
  ///
  /// 输入即搜（防抖 [_searchDebounceDuration]），回车只是把这一次提前提交。
  /// 匹配语法由 Rust 侧的 `search_query` 定义：空格分词求交、`-词` 排除、
  /// `"带空格"` 当一个词。
  Widget _buildSearchField(BuildContext context, FileManagerSnapshot snapshot) {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocus,
      autofocus: snapshot.searchQuery.isEmpty,
      textInputAction: TextInputAction.search,
      style: Theme.of(context).textTheme.bodySmall,
      decoration: InputDecoration(
        isDense: true,
        hintText: '名称与路径 · 空格分词 · -排除 · “短语”',
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: _searchRunning
            ? IconButton(
                tooltip: '中止递归搜索（保留已找到的结果）',
                icon: const Icon(Icons.stop_rounded, size: 16),
                onPressed: _cancelSearch,
              )
            : _searchPending
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                tooltip: '清除搜索并收起',
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () {
                  _submitSearch('');
                  setState(() => _searchExpanded = false);
                },
              ),
        border: const OutlineInputBorder(),
      ),
      onChanged: _scheduleSearch,
      onSubmitted: _submitSearch,
    );
  }

  /// 搜索选项行：递归开关 + 命中统计。窄卡片下横向滚动，与工具栏同一策略。
  Widget _buildSearchOptions(
    BuildContext context,
    FileManagerSnapshot snapshot,
  ) {
    final theme = Theme.of(context);
    final searching = snapshot.searchQuery.isNotEmpty;
    // 统计读的是快照：命中的正本在页签里，重建卡片也还在。
    final status = !searching || !snapshot.searchIncludeSubfolders
        ? null
        : _searchRunning
        ? '正在递归搜索…'
        : snapshot.searchActive
        ? [
            '命中 ${snapshot.searchMatched}',
            '已看 ${snapshot.searchScanned}',
            if (snapshot.searchTruncated) '已达上限',
            if (snapshot.searchCancelled) '已中止',
          ].join(' · ')
        : null;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // 还没下查询时，这一行先当历史下拉用；一旦开始打字就让位给条件开关，
          // 否则边打边看会被一排旧词挤掉。
          if (snapshot.searchQuery.isEmpty && _searchHistory.isNotEmpty) ...[
            for (final history in _searchHistory) ...[
              ChoiceChip(
                label: Text(history),
                tooltip: '再搜一次「$history」',
                selected: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => _submitSearch(history, commit: true),
              ),
              const SizedBox(width: 6),
            ],
            ChoiceChip(
              label: const Text('清空历史'),
              selected: false,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => _clearSearchHistory(),
            ),
            const SizedBox(width: 6),
          ],
          ChoiceChip(
            label: const Text('含子目录'),
            tooltip: '向下递归搜索，层数上限由 Rust 侧夹紧',
            selected: snapshot.searchIncludeSubfolders,
            visualDensity: VisualDensity.compact,
            onSelected: (enabled) => _applySearchAction(
              (id) => fileManagerSetSearchIncludeSubfolders(
                id: id,
                enabled: enabled,
              ),
            ),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('匹配路径'),
            tooltip: '除条目名外，连同它在搜索根之下的相对路径一起匹配',
            selected: snapshot.searchInPath,
            visualDensity: VisualDensity.compact,
            onSelected: (enabled) => _applySearchAction(
              (id) => fileManagerSetSearchInPath(id: id, enabled: enabled),
            ),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('任一词元'),
            tooltip: '多个词元之间取并集（默认全部都要命中）',
            selected: snapshot.searchOrMode,
            visualDensity: VisualDensity.compact,
            onSelected: (enabled) => _applySearchAction(
              (id) => fileManagerSetSearchOrMode(id: id, enabled: enabled),
            ),
          ),
          if (status != null) ...[
            const SizedBox(width: 8),
            Text(
              status,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          // 结果模式下这一屏画的不是目录：给一条明确的原路返回，以及 NeoView 的
          // 「保存搜索到页签」—— 把这次搜索留在一个受保护的页签里反复看。
          if (snapshot.searchActive) ...[
            const SizedBox(width: 6),
            ChoiceChip(
              label: const Text('回到目录'),
              tooltip: '退出搜索结果，回到这个页签自己的目录',
              selected: false,
              visualDensity: VisualDensity.compact,
              onSelected: (_) =>
                  _applySearchAction((id) => fileManagerClearSearch(id: id)),
            ),
          ],
          if (snapshot.canSaveSearchTab) ...[
            const SizedBox(width: 6),
            ChoiceChip(
              label: const Text('存为页签'),
              tooltip: '把这次搜索结果另存一个页签',
              selected: false,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => _applySearchAction(
                (id) => fileManagerSaveSearchAsTab(id: id),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 工具栏对齐 neoview 文件卡：单行三段 —— 导航掌 / 主工具组 / 更多组。
  Widget _buildToolbar(BuildContext context, FileManagerSnapshot snapshot) {
    final theme = Theme.of(context);
    // 只订阅本功能自己的开关，别的设置变了不重建这张卡片。
    final homeEnabled = context.select<GlobalSettingCubit, bool>(
      (cubit) => cubit.state.fileManagerSetting.homeEnabled,
    );
    final activeTab = snapshot.tabs.firstWhere(
      (tab) => tab.id == snapshot.activeTabId,
    );
    const filters = {
      FileManagerEntryFilter.all: '全部',
      FileManagerEntryFilter.folders: '文件夹',
      FileManagerEntryFilter.archives: '归档',
      FileManagerEntryFilter.images: '图片',
      FileManagerEntryFilter.video: '视频',
      FileManagerEntryFilter.audio: '音频',
    };
    const fields = {
      FileManagerSortField.name: '名称',
      FileManagerSortField.type: '类型',
      FileManagerSortField.size: '大小',
      FileManagerSortField.date: '修改日期',
      FileManagerSortField.random: '随机',
    };

    Widget action({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
      bool active = false,
    }) {
      return IconButton(
        icon: Icon(
          icon,
          size: 18,
          color: active ? theme.colorScheme.primary : null,
        ),
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        onPressed: _busy ? null : onPressed,
      );
    }

    // 隐藏滚动条：窄卡片下主工具组横向滚动，但不显示滚动条本身。
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // —— 导航掌 ——
            // 五个方向合成一个 32px 的掌形控件（对齐 NeoView 的 FolderNavigationPad），
            // 而不是五颗 32px 的独立按钮：窄卡片上省掉 4/5 的宽度。
            FileManagerNavigationPad(
              busy: _busy,
              loading: _busy,
              canGoBack: activeTab.canGoBack,
              canGoForward: activeTab.canGoForward,
              canGoUp: snapshot.canGoUp,
              homeKey: _homeButtonKey,
              homeEnabled: homeEnabled,
              hasHome: snapshot.homePath != null,
              atHome: snapshot.isHome,
              onNavigateBack: () => _apply((id) => fileManagerGoBack(id: id)),
              onNavigateForward: () =>
                  _apply((id) => fileManagerGoForward(id: id)),
              onNavigateUp: () => _apply((id) => fileManagerGoUp(id: id)),
              // 设过主页 = 单击回主页；没设过 = 单击把当前目录设为主页，
              // 这样第一次用的人不必先猜「要长按/右键」。
              onGoHome: snapshot.homePath != null
                  ? () => _apply((id) => fileManagerGoHome(id: id))
                  : () => _setHomePath(snapshot.activePath),
              onHomeMenu: () => _openHomeMenu(snapshot),
              onRefresh: () => _apply((id) => fileManagerRefresh(id: id)),
            ),
            const SizedBox(width: 2),

            // —— 主工具组 ——
            FluentPopupMenuButton<FileManagerViewMode>(
              tooltip: '视图模式：${snapshot.viewMode.label}',
              visualDensity: VisualDensity.compact,
              enabled: !_busy,
              icon: Icon(snapshot.viewMode.icon, size: 18),
              onSelected: (mode) =>
                  _apply((id) => fileManagerSetViewMode(id: id, mode: mode)),
              itemBuilder: (_) => [
                for (final mode in FileManagerViewMode.values)
                  FluentPopupMenuItem(
                    value: mode,
                    leading: Icon(mode.icon, size: 16),
                    selected: mode == snapshot.viewMode,
                    title: Text(mode.label),
                  ),
              ],
            ),
            FluentPopupMenuButton<String>(
              tooltip: '排序：${fields[snapshot.sortField]}',
              visualDensity: VisualDensity.compact,
              enabled: !_busy,
              icon: const Icon(Icons.sort_rounded, size: 18),
              onSelected: (value) {
                if (value == 'order') {
                  _apply(
                    (id) => fileManagerSetSort(
                      id: id,
                      field: snapshot.sortField,
                      order:
                          snapshot.sortOrder == FileManagerSortOrder.ascending
                          ? FileManagerSortOrder.descending
                          : FileManagerSortOrder.ascending,
                    ),
                  );
                  return;
                }
                if (value == 'temporary') {
                  _apply(
                    (id) => fileManagerSetSortTemporary(
                      id: id,
                      enabled: !snapshot.sortTemporary,
                    ),
                  );
                  return;
                }
                if (value.startsWith('field:')) {
                  final name = value.substring('field:'.length);
                  final field = FileManagerSortField.values.firstWhere(
                    (field) => field.name == name,
                  );
                  _apply(
                    (id) => fileManagerSetSort(
                      id: id,
                      field: field,
                      order: snapshot.sortOrder,
                    ),
                  );
                }
              },
              itemBuilder: (_) => [
                for (final field in fields.entries)
                  FluentPopupMenuItem(
                    value: 'field:${field.key.name}',
                    selected: field.key == snapshot.sortField,
                    title: Text(field.value),
                  ),
                const FluentPopupMenuItem.divider(),
                FluentPopupMenuItem(
                  value: 'order',
                  title: Text(
                    snapshot.sortOrder == FileManagerSortOrder.ascending
                        ? '切换为降序'
                        : '切换为升序',
                  ),
                ),
                FluentPopupMenuItem(
                  value: 'temporary',
                  selected: snapshot.sortTemporary,
                  enabled: snapshot.canSortPreference,
                  title: const Text('临时排序（不记住本目录）'),
                ),
              ],
            ),
            // 搜索键不参与 _busy 门控：展开/收起只是 UI 状态切换。
            IconButton(
              icon: Icon(
                Icons.search_rounded,
                size: 18,
                color: _searchExpanded || snapshot.searchQuery.isNotEmpty
                    ? theme.colorScheme.primary
                    : null,
              ),
              tooltip: _searchExpanded ? '收起搜索' : '搜索（空格分词，-排除）',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                setState(() => _searchExpanded = !_searchExpanded);
                if (_searchExpanded) _loadSearchHistory();
              },
            ),
            action(
              icon: Icons.account_tree_outlined,
              tooltip: _treeEnabled ? '关闭文件树' : '文件树',
              active: _treeEnabled,
              onPressed: () => _setTreeEnabled(!_treeEnabled),
            ),
            action(
              icon: Icons.alt_route_rounded,
              tooltip: snapshot.penetrationEnabled ? '关闭穿透模式' : '穿透模式',
              active: snapshot.penetrationEnabled,
              onPressed: () => _apply(
                (id) => fileManagerSetPenetration(
                  id: id,
                  enabled: !snapshot.penetrationEnabled,
                ),
              ),
            ),

            // —— 更多组 ——
            FluentPopupMenuButton<String>(
              tooltip: '更多',
              visualDensity: VisualDensity.compact,
              enabled: !_busy,
              icon: const Icon(Icons.more_horiz_rounded, size: 18),
              onSelected: (value) {
                if (value.startsWith('filter:')) {
                  final name = value.substring('filter:'.length);
                  final filter = FileManagerEntryFilter.values.firstWhere(
                    (filter) => filter.name == name,
                  );
                  _apply(
                    (id) => fileManagerSetEntryFilter(id: id, filter: filter),
                  );
                  return;
                }
                switch (value) {
                  case 'fileOps':
                    _setFileOperationsEnabled(!_fileOpsEnabled);
                  case 'hidden':
                    _apply(
                      (id) => fileManagerSetShowHiddenFiles(
                        id: id,
                        enabled: !snapshot.showHiddenFiles,
                      ),
                    );
                  case 'directories':
                    _apply(
                      (id) => fileManagerSetDirectoriesFirst(
                        id: id,
                        enabled: !snapshot.directoriesFirst,
                      ),
                    );
                  case 'children':
                    _apply(
                      (id) => fileManagerSetShowChildNames(
                        id: id,
                        enabled: !snapshot.showChildNames,
                      ),
                    );
                  case 'mode':
                    _apply(
                      (id) => fileManagerSetInternalItemsMode(
                        id: id,
                        mode:
                            snapshot.internalItemsMode ==
                                FileManagerInternalItemsMode.single
                            ? FileManagerInternalItemsMode.all
                            : FileManagerInternalItemsMode.single,
                      ),
                    );
                  default:
                    final depth = int.tryParse(value);
                    if (depth != null) {
                      _apply(
                        (id) => fileManagerSetMaxDepth(id: id, depth: depth),
                      );
                    }
                }
              },
              itemBuilder: (context) => [
                FluentPopupMenuItem(
                  value: 'fileOps',
                  selected: _fileOpsEnabled,
                  title: const Text('文件操作（复制 / 移动 / 删除）'),
                ),
                const FluentPopupMenuItem.divider(),
                FluentPopupMenuItem(
                  value: 'hidden',
                  selected: snapshot.showHiddenFiles,
                  title: const Text('显示隐藏文件'),
                ),
                FluentPopupMenuItem(
                  value: 'directories',
                  selected: snapshot.directoriesFirst,
                  title: const Text('文件夹优先'),
                ),
                FluentPopupMenuItem(
                  value: 'children',
                  selected: snapshot.showChildNames,
                  title: const Text('显示子文件名'),
                ),
                FluentPopupMenuItem(
                  value: 'mode',
                  title: Text(
                    snapshot.internalItemsMode ==
                            FileManagerInternalItemsMode.single
                        ? '子文件：显示一个'
                        : '子文件：显示全部',
                  ),
                ),
                const FluentPopupMenuItem.divider(),
                for (final depth in [1, 2, 3, 5, 10, 32])
                  FluentPopupMenuItem(
                    value: '$depth',
                    selected: snapshot.maxDepth == depth,
                    title: Text(depth == 32 ? '穿透深度：最多 32 层' : '穿透深度：$depth 层'),
                  ),
                const FluentPopupMenuItem.divider(),
                for (final filter in filters.entries)
                  FluentPopupMenuItem(
                    value: 'filter:${filter.key.name}',
                    selected: filter.key == snapshot.entryFilter,
                    title: Text('类型：${filter.value}'),
                  ),
              ],
            ),
            const SizedBox(width: 4),
            Text(
              '${snapshot.entries.length} 项',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoots(BuildContext context, FileManagerSnapshot snapshot) {
    if (snapshot.roots.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: snapshot.roots.length,
        separatorBuilder: (_, _) => const SizedBox(width: 5),
        itemBuilder: (context, index) {
          final root = snapshot.roots[index];
          final selected = snapshot.activePath == root.path;
          return ActionChip(
            label: Text(root.label, style: const TextStyle(fontSize: 11)),
            avatar: Icon(
              selected ? Icons.storage_rounded : Icons.folder_outlined,
              size: 15,
            ),
            visualDensity: VisualDensity.compact,
            onPressed: _busy
                ? null
                : () => _apply(
                    (id) => fileManagerNavigate(id: id, path: root.path),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildInlineError(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 15,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 15),
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _error = null),
          ),
        ],
      ),
    );
  }

  /// 视图模式映射。渲染全部走 `LibraryEntryList`，这一层只剩
  /// 「把 `FileManagerEntry` 说成共享行模型听得懂的话」。
  static const _thumbModes = {
    LibraryViewMode.coverList,
    LibraryViewMode.mosaicList,
    LibraryViewMode.coverGrid,
    LibraryViewMode.mosaicGrid,
  };

  static const _detailsTitleColumn = LibraryColumn(
    key: 'name',
    label: '名称',
    flex: LibraryViewLayout.detailsTitleFlex,
  );

  static const _detailsColumns = [
    LibraryColumn(key: 'type', label: '类型', width: 70),
    LibraryColumn(key: 'size', label: '大小', width: 75, alignRight: true),
    LibraryColumn(key: 'date', label: '修改时间', width: 110),
  ];

  Widget _buildEntries(BuildContext context, FileManagerSnapshot snapshot) {
    final mode = fileManagerLibraryMode(snapshot.viewMode);
    final searching =
        snapshot.searchQuery.isNotEmpty ||
        snapshot.entryFilter != FileManagerEntryFilter.all;
    // `snapshot.entries` 就是该画的东西：普通浏览时是当前目录，搜索结果页签时
    // 是命中列表。这一层不需要知道这两种情况的存在。
    final query = snapshot.searchQuery;
    return LibraryEntryList(
      mode: mode,
      entries: [
        for (final entry in snapshot.entries)
          _libraryEntry(context, entry, mode),
      ],
      emptyText: snapshot.searchActive && query.isNotEmpty
          ? '子目录里没有匹配「$query」的条目'
          : searching
          ? '没有符合搜索或类型筛选的条目'
          : '当前目录没有可浏览的漫画或媒体文件',
      enabled: !_busy,
      busy: _busy,
      standalone: widget.isStandalone,
      // 关掉「文件操作」时整块不挂：连右键手势都没有，列表回到纯浏览。
      wrapRow: _fileOpsEnabled ? _wrapEntryRow : null,
      onTap: (row) => _onEntryTap(row.source! as FileManagerEntry),
      canDoubleTap: (row) => (row.source! as FileManagerEntry).isArchive,
      onDoubleTap: (row) => _openArchive(row.source! as FileManagerEntry),
      titleColumn: _detailsTitleColumn,
      columns: _detailsColumns,
      sortKey: snapshot.sortField.name,
      sortAscending: snapshot.sortOrder == FileManagerSortOrder.ascending,
      onSort: (key) =>
          _toggleSort(snapshot, FileManagerSortField.values.byName(key)),
    );
  }

  /// 多选时贴着列表上沿的操作条。
  ///
  /// 只在**有选中**时出现 —— 它不是常驻工具条，而是「你正拿着一批东西」的提示
  /// 加一个出口。没有它，用户想删 12 个文件得回到某一个条目上右键：右键菜单
  /// 一次只能从一个条目进，批量动作没有入口。它同时是**唯一**能撤销的地方。
  Widget _buildSelectionBar(BuildContext context, FileManagerSnapshot snapshot) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = _ops?.selectedCount ?? 0;
    return Container(
      decoration: BoxDecoration(
        // MD3：状态类的容器面用 secondaryContainer，与「主行动」的主色区分开。
        color: scheme.secondaryContainer,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      padding: const EdgeInsets.only(left: 10, right: 2),
      child: Row(
        children: [
          Text(
            '已选 $count 项',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            // 面板可以被拖得很窄。操作条是**一行图标**，横着滚比换行好：
            // 换行会把列表往下顶一大截，而用户正看着那一批行。
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(children: _selectionActions(context, snapshot)),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _selectionActions(
    BuildContext context,
    FileManagerSnapshot snapshot,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final ops = _ops;
    return [
      _selectionAction(Icons.select_all_rounded, '全选', _selectAll),
      _selectionAction(Icons.swap_horiz_rounded, '反选', _invertSelection),
      _selectionAction(
        Icons.content_copy_rounded,
        '复制',
        () => unawaited(_copySelectionToClipboard(cut: false)),
      ),
      _selectionAction(
        Icons.content_cut_rounded,
        '剪切',
        () => unawaited(_copySelectionToClipboard(cut: true)),
      ),
      // 粘贴的入口只在这条上（右键菜单那条要落到某个目录上，而「粘到当前目录」
      // 没有可右键的落点）。所以它只在剪贴板非空时出现。
      if (ops?.canPaste ?? false)
        _selectionAction(
          Icons.content_paste_rounded,
          '粘贴到当前目录',
          () => unawaited(_pasteInto(null)),
        ),
      if (ops?.canUndo ?? false)
        _selectionAction(
          Icons.undo_rounded,
          '撤销上一步',
          () => unawaited(_undoLastOperation()),
        ),
      _selectionAction(
        Icons.delete_outline_rounded,
        (_ops?.trashRestoreSupported ?? false) ? '移到回收站' : '移到回收站（无法撤销）',
        () => unawaited(_trashSelection()),
        color: scheme.error,
      ),
      _selectionAction(
        Icons.delete_forever_rounded,
        '永久删除',
        () => unawaited(_deleteSelectionPermanently()),
        color: scheme.error,
      ),
      _selectionAction(Icons.deselect_rounded, '取消选择', _clearSelection),
    ];
  }

  Widget _selectionAction(
    IconData icon,
    String tooltip,
    VoidCallback onPressed, {
    Color? color,
  }) {
    return IconButton(
      icon: Icon(icon, size: 18, color: color),
      tooltip: tooltip,
      // 与工具栏其余图标键同一套密度，别让这一条比上面那排胖一圈。
      visualDensity: VisualDensity.compact,
      onPressed: _busy ? null : onPressed,
    );
  }

  /// 把选中的一批放进内部剪贴板（两步式的第一步）。
  Future<void> _copySelectionToClipboard({required bool cut}) async {
    final count = _ops?.selectedCount ?? 0;
    // 一条都没选就什么都不做：空剪贴板会把 `canPaste` 弄成假，
    // 然后用户会发现「粘贴」项莫名消失了。
    if (count == 0) return;
    await _runOps((id) => fileOpsCopyToClipboard(id: id, cut: cut));
    if (!mounted) return;
    showInfoToast(
      fileManagerClipboardHint(cut: cut, count: count),
      context: context,
    );
  }

  Future<void> _pasteInto(String? destination) async {
    final id = _sessionId;
    if (id == null || _busy || _disposed) return;
    await _runMutation(() => fileOpsPaste(id: id, destination: destination));
  }

  Future<void> _trashSelection() async {
    final id = _sessionId;
    final count = _ops?.selectedCount ?? 0;
    if (id == null || count == 0 || _busy || _disposed) return;
    // 走同一个 `planFileManagerEntryAction`：回收站**不问**确认（它的保护是撤销
    // 通道），但这个「问不问」的规则必须只有一处，否则操作条与右键菜单会分叉。
    final call = await planFileManagerEntryAction(
      context,
      action: FileManagerEntryAction.trash,
      target: _selectionTarget(count),
    );
    if (call == null || !mounted) return;
    await _runMutation(() => fileOpsTrashSelection(id: id));
  }

  Future<void> _deleteSelectionPermanently() async {
    final id = _sessionId;
    final count = _ops?.selectedCount ?? 0;
    if (id == null || count == 0 || _busy || _disposed) return;
    final call = await planFileManagerEntryAction(
      context,
      action: FileManagerEntryAction.deletePermanently,
      target: _selectionTarget(count),
    );
    if (call == null || !mounted) return;
    await _runMutation(() => fileOpsDeleteSelection(id: id));
  }

  /// 整批动作的目标。批量删除 / 复制不落在某一个条目上，所以 `path` / `name`
  /// 留空 —— 它们只有重命名与新建文件夹用得上，而那两个动作本来就是单选的。
  FileManagerEntryTarget _selectionTarget(int count) => FileManagerEntryTarget(
    path: _snapshot?.activePath ?? '',
    name: '',
    isDirectory: false,
    count: count,
    restoreSupported: _ops?.trashRestoreSupported ?? false,
  );

  /// 给整行套一层壳子：外面是右键菜单宿主，里面是选中态。顺序不能换 ——
  /// 菜单宿主靠 `GestureDetector` 收次键与长按，选中态那一层是 `IgnorePointer`
  /// 的画，谁在里面都行，但「菜单在外面」让菜单的手势区覆盖**整行**，
  /// 包括选中态的描边。
  Widget _wrapEntryRow(BuildContext context, LibraryEntry row, Widget child) {
    final entry = row.source;
    // 共享行模型的 `source` 是 `Object?`：别的卡片（书签/历史）也走这条壳子，
    // 它们的 `source` 不是文件条目，直通即可。
    if (entry is! FileManagerEntry) return child;
    return FileManagerEntryContextMenuRegion(
      enabled: !_busy,
      inputBuilder: () => _menuInputFor(entry),
      onBeforeOpen: () => _convergeSelectionFor(entry),
      onAction: (_, action) => unawaited(_runEntryAction(entry, action)),
      child: FileManagerEntrySelectionShell(
        selected: _isEntrySelected(entry.path),
        child: child,
      ),
    );
  }

  LibraryEntry _libraryEntry(
    BuildContext context,
    FileManagerEntry entry,
    LibraryViewMode mode,
  ) {
    final hasSize = !entry.isDir && entry.size > BigInt.zero;
    return LibraryEntry(
      key: entry.path,
      title: entry.name,
      source: entry,
      subtitle: _subtitle(entry, mode),
      metaText: hasSize ? _formatSize(entry.size) : null,
      media:
          (
            context, {
            required width,
            required height,
            required radius,
            required fit,
          }) => FileManagerThumbnailWidget(
            entry: entry,
            width: width,
            height: height,
            borderRadius: radius,
            fit: fit,
          ),
      badge: _semanticIcon(context, entry),
      thumbModes: _thumbModes,
      subLines: [for (final child in entry.childNames) _subLine(child)],
      detailCells: [
        _formatType(entry),
        _formatSize(entry.size),
        _formatDate(entry.modifiedSecs.toInt()),
      ],
      overlayText: entry.childNames.isEmpty
          ? null
          : '${entry.childNames.length} 项',
      trailing: _trailing(context, entry, mode),
    );
  }

  /// 封面列表的第二行带修改日期，横幅那一行不带 —— 沿用原来两档各自的写法。
  ///
  /// 搜索结果里的同名条目只能靠**来自哪个子目录**区分，所以那段相对路径排在
  /// 副标题最前面；普通浏览时它是 null，不会出现。
  String _subtitle(FileManagerEntry entry, LibraryViewMode mode) {
    final type = _formatType(entry);
    final hasSize = !entry.isDir && entry.size > BigInt.zero;
    final searchDirectory = entry.searchDirectory;
    final buffer = StringBuffer();
    if (searchDirectory != null && searchDirectory.isNotEmpty) {
      buffer.write('$searchDirectory · ');
    }
    if (mode != LibraryViewMode.coverList) {
      buffer.write(hasSize ? '$type · ${_formatSize(entry.size)}' : type);
      return buffer.toString();
    }
    buffer.write(type);
    if (hasSize) buffer.write(' · ${_formatSize(entry.size)}');
    if (entry.modifiedSecs.toInt() > 0) {
      buffer.write(' · ${_formatDate(entry.modifiedSecs.toInt())}');
    }
    return buffer.toString();
  }

  Widget? _trailing(
    BuildContext context,
    FileManagerEntry entry,
    LibraryViewMode mode,
  ) {
    if (mode == LibraryViewMode.compact) {
      if (!entry.isDir) return null;
      return IconButton(
        icon: const Icon(Icons.folder_open_rounded, size: 16),
        tooltip: '进入文件夹',
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        onPressed: _busy ? null : () => _openEntry(entry, forceEnter: true),
      );
    }
    if (mode == LibraryViewMode.coverList) {
      if (entry.isDir) {
        return IconButton(
          icon: const Icon(Icons.folder_open_rounded, size: 18),
          tooltip: '进入文件夹',
          visualDensity: VisualDensity.compact,
          onPressed: _busy ? null : () => _openEntry(entry, forceEnter: true),
        );
      }
      return const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Icon(Icons.play_circle_outline_rounded, size: 18),
      );
    }
    return null;
  }

  LibrarySubLine _subLine(FileManagerChild child) {
    return LibrarySubLine(
      label: child.name,
      icon: child.isDir
          ? Icons.folder_outlined
          : Icons.subdirectory_arrow_right,
      onTap: _busy ? null : () => _openChild(child),
      onDoubleTap: child.isArchive && !_busy
          ? () => _openArchiveChild(child)
          : null,
    );
  }

  /// 语义图标不带尺寸：每档视图要多大由 `LibraryViewLayout.badgeSize` 决定。
  Widget _semanticIcon(BuildContext context, FileManagerEntry entry) {
    final colors = Theme.of(context).colorScheme;
    final (IconData icon, Color color) = switch (entry) {
      _ when entry.isDir => (Icons.folder_rounded, colors.tertiary),
      _ when entry.isArchive => (Icons.auto_stories_rounded, colors.primary),
      _ when entry.isImage => (Icons.image_outlined, colors.secondary),
      _ when entry.isVideo => (Icons.movie_outlined, colors.secondary),
      _ when entry.isAudio => (Icons.audio_file_outlined, colors.secondary),
      _ => (Icons.insert_drive_file_outlined, colors.outline),
    };
    return Icon(icon, color: color);
  }

  Future<void> _toggleSort(
    FileManagerSnapshot snapshot,
    FileManagerSortField field,
  ) async {
    final order =
        snapshot.sortField == field &&
            snapshot.sortOrder == FileManagerSortOrder.ascending
        ? FileManagerSortOrder.descending
        : FileManagerSortOrder.ascending;
    await _apply(
      (id) => fileManagerSetSort(id: id, field: field, order: order),
    );
  }

  String _formatDate(int secs) {
    if (secs <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
    final year = dt.year.toString();
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$year/$month/$day $hour:$min';
  }

  String _formatType(FileManagerEntry entry) {
    if (entry.isDir) return '文件夹';
    final lower = entry.name.toLowerCase();
    if (entry.isArchive) {
      if (lower.endsWith('.zip')) return 'ZIP 归档';
      if (lower.endsWith('.cbz')) return 'CBZ 归档';
      if (lower.endsWith('.rar')) return 'RAR 归档';
      if (lower.endsWith('.cbr')) return 'CBR 归档';
      if (lower.endsWith('.7z')) return '7Z 归档';
      if (lower.endsWith('.tar') || lower.endsWith('.tar.gz')) return 'TAR 归档';
      return '压缩归档';
    }
    if (entry.isImage) return '图片';
    if (entry.isVideo) return '视频';
    if (entry.isAudio) return '音频';
    final dot = entry.name.lastIndexOf('.');
    if (dot != -1 && dot < entry.name.length - 1) {
      return '${entry.name.substring(dot + 1).toUpperCase()} 文件';
    }
    return '文件';
  }

  String _formatSize(BigInt bytes) {
    if (bytes <= BigInt.zero) return '';
    const suffixes = ['B', 'KiB', 'MiB', 'GiB'];
    var index = 0;
    var value = bytes.toDouble();
    while (value >= 1024 && index < suffixes.length - 1) {
      value /= 1024;
      index++;
    }
    return '${value.toStringAsFixed(index == 0 ? 0 : 1)} ${suffixes[index]}';
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline_rounded, color: Colors.amber),
        const SizedBox(height: 6),
        Text(
          message,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('重试'),
        ),
      ],
    );
  }
}

/// 主页键长按 / 右键菜单的三个动作。
enum _HomeAction { goHome, setHome, clearHome }
