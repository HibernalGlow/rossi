part of '../file_manager_card.dart';

// 从 class _FileManagerCardState 搬出的方法组；extension 与宿主类同库，可直接访问私有成员。
extension _FileManagerCardFileOpsPart on _FileManagerCardState {
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
      // ignore: invalid_use_of_protected_member
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
  Future<void> _runOps(
    Future<FileOpsSnapshot> Function(BigInt id) action,
  ) async {
    final id = _sessionId;
    if (id == null || _disposed) return;
    final serial = ++_opsSerial;
    try {
      final ops = await action(id);
      if (!mounted || _disposed || serial != _opsSerial) return;
      // ignore: invalid_use_of_protected_member
      setState(() => _applyOps(ops));
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  int _entryIndexOf(FileManagerEntry entry) {
    final entries = _snapshot?.entries ?? const <FileManagerEntry>[];
    final index = entries.indexWhere(
      (candidate) => candidate.path == entry.path,
    );
    // 找不到（列表刚好换了代）就报 0：Rust 那边还有 `path` 这条轨兜底，
    // 抛异常只会让用户看见一个本可以避免的红条。
    return index < 0 ? 0 : index;
  }

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
  Future<void> _invertSelection() =>
      _runOps((id) => fileOpsInvertSelection(id: id));
  Future<void> _clearSelection() =>
      _runOps((id) => fileOpsClearSelection(id: id));

  /// 现在**是不是**多选模式。口径与书架一致：模式是一个明确的状态，不是「碰巧有
  /// 几点选中」。
  ///
  /// 「手里正拿着东西」也算在模式里：操作条已经显示了、行上也画着选中壳，此时若
  /// 还按「不在模式」裁决单击，用户看见一个挂着的多选状态点进了文件夹 ——
  /// 那就是当初那条 bug。（右键**不**再把选中态立起来，所以它只能从工具栏那颗
  /// 开关或修饰键点选进来。）
  bool get _selectionModeOn =>
      _selectionModeRequested || _selectedPaths.isNotEmpty;

  /// 工具栏那颗「多选」开关。
  ///
  /// 退出模式时把集合一起清掉：留着高亮却宣布「不在模式里」，就又回到了那条 bug。
  /// 反过来进入模式**不动集合** —— 空着集合进模式、然后一家一家点着选，
  /// 正是这颗开关存在的理由（书架那颗 checklist 同一条路）。
  void _toggleSelectionMode() {
    final next = !_selectionModeOn;
    // ignore: invalid_use_of_protected_member
    setState(() => _selectionModeRequested = next);
    if (!next && _selectedPaths.isNotEmpty) unawaited(_clearSelection());
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
      selectionMode: _fileOpsEnabled && _selectionModeOn,
    );
    switch (gesture) {
      case FileManagerEntryTapGesture.open:
        // 打开是对**这一个**的动作。留着一批高亮的行会让人以为打开的是那一批，
        // 所以顺手把选中集合清掉（桌面文件管理器的单击即打开模式也是这么做的）。
        // 有了模式位之后能走到这一格几乎只剩「一个都没选」；这句仍留着，是因为
        // 「文件操作」总开关刚关掉时可能带着上一轮的选中。
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
      // 「在访达/资源管理器里显示」要请外部程序做事：桌面三家有，移动端没有。
      // 读的是 `Platform` 的常量，不发 I/O，符合上面那条「必须 O(1)」。
      canReveal: currentRevealHost() != RevealHost.unsupported,
    );
  }

  /// 走一次菜单动作。
  Future<void> _runEntryAction(
    FileManagerEntry entry,
    FileManagerEntryAction action,
  ) async {
    final id = _sessionId;
    if (id == null || _snapshot == null || _busy || _disposed) return;
    // 目标在这一次动作开始时算一次，往下带到执行处 —— 右键**不会**改动选中集合，
    // 所以「这一批是哪些」不能等到执行时再从集合里读。
    final targets = _actionTargets(entry);

    // 不改盘、也不用问参数的那几个先处理掉：它们与「点一下列表」同级，
    // 绕一圈忙状态只会让手感变钝。
    if (await _runInlineAction(id, entry, action, targets)) return;
    // 打开一个目录会把整张卡片换掉（也可能把面板整个收起来）。
    if (!mounted || _disposed) return;

    final call = await planFileManagerEntryAction(
      context,
      action: action,
      target: FileManagerEntryTarget(
        path: entry.path,
        name: entry.name,
        isDirectory: entry.isDir,
        count: targets.length,
        restoreSupported: _ops?.trashRestoreSupported ?? false,
      ),
    );
    // `null` = 用户在对话框里取消了。
    if (call == null || !mounted) return;

    final dispatch = _dispatchFor(id, call, targets);
    if (dispatch == null) return;
    await _runMutation(dispatch);
  }

  /// 打开、复制到剪贴板、复制路径这类动作。返回 `true` = 已经处理掉了。
  Future<bool> _runInlineAction(
    BigInt id,
    FileManagerEntry entry,
    FileManagerEntryAction action,
    List<String> targets,
  ) async {
    switch (action) {
      case FileManagerEntryAction.open:
        await _openEntry(entry);
        return true;
      case FileManagerEntryAction.openInNewTab:
        await _openPathInNewTab(entry.path);
        return true;
      case FileManagerEntryAction.copyPath:
        await copyFileManagerPathsToClipboard(context, paths: targets);
        return true;
      case FileManagerEntryAction.revealInFileManager:
        // 只对**右键的那一项**生效：菜单项在多选时是灰的，`targets` 到了这里
        // 必定只有一条。走外部程序，不动盘，所以不占 `_busy` 也不进撤销栈。
        await revealFileManagerEntry(context, path: entry.path);
        return true;
      case FileManagerEntryAction.copy:
      case FileManagerEntryAction.cut:
        // 与操作条走同一个方法，只是目标由调用方算好带进来：在选中集合里右键
        // 是对整批，在集合外右键是对这一个。
        await _copyToClipboard(
          cut: action == FileManagerEntryAction.cut,
          paths: targets,
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
    List<String> targets,
  ) {
    switch (call.action) {
      case FileManagerEntryAction.trash:
        return () => fileOpsTrashPaths(id: id, paths: targets);
      case FileManagerEntryAction.deletePermanently:
        return () => fileOpsDeletePaths(id: id, paths: targets);
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
        return () => fileOpsCreateDirectory(id: id, name: name, parent: parent);
      case FileManagerEntryAction.open:
      case FileManagerEntryAction.openInNewTab:
      case FileManagerEntryAction.revealInFileManager:
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
    // ignore: invalid_use_of_protected_member
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final report = await dispatch();
      if (!mounted || _disposed || serial != _requestSerial) return;
      // ignore: invalid_use_of_protected_member
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

  /// 多选时贴着列表上沿的操作条。
  ///
  /// 只在**有选中**时出现 —— 它不是常驻工具条，而是「你正拿着一批东西」的提示
  /// 加一个出口。没有它，用户想删 12 个文件得回到某一个条目上右键：右键菜单
  /// 一次只能从一个条目进，批量动作没有入口。它同时是**唯一**能撤销的地方。
  Widget _buildSelectionBar(
    BuildContext context,
    FileManagerSnapshot snapshot,
  ) {
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
            t.workspace.selectedCount(n: count),
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
      _selectionAction(AppGlyphs.selectAll, '全选', _selectAll),
      _selectionAction(AppGlyphs.flip, '反选', _invertSelection),
      _selectionAction(
        AppGlyphs.copy,
        '复制',
        () => unawaited(
          _copyToClipboard(cut: false, paths: _selectedPaths.toList()),
        ),
      ),
      _selectionAction(
        AppGlyphs.cut,
        t.workspace.cut,
        () => unawaited(
          _copyToClipboard(cut: true, paths: _selectedPaths.toList()),
        ),
      ),
      // 粘贴的入口只在这条上（右键菜单那条要落到某个目录上，而「粘到当前目录」
      // 没有可右键的落点）。所以它只在剪贴板非空时出现。
      if (ops?.canPaste ?? false)
        _selectionAction(
          AppGlyphs.paste,
          t.workspace.pasteHere,
          () => unawaited(_pasteInto(null)),
        ),
      if (ops?.canUndo ?? false)
        _selectionAction(
          AppGlyphs.undo,
          t.workspace.undoLastStep,
          () => unawaited(_undoLastOperation()),
        ),
      _selectionAction(
        AppGlyphs.delete,
        (_ops?.trashRestoreSupported ?? false)
            ? t.workspace.moveToTrash
            : t.workspace.moveToTrashNoUndo,
        () => unawaited(_trashSelection()),
        color: scheme.error,
      ),
      _selectionAction(
        AppGlyphs.delete,
        t.workspace.deleteForever,
        () => unawaited(_deleteSelectionPermanently()),
        color: scheme.error,
      ),
      _selectionAction(AppGlyphs.deselect, '取消选择', _clearSelection),
    ];
  }

  Widget _selectionAction(
    Glyph icon,
    String tooltip,
    VoidCallback onPressed, {
    Color? color,
  }) {
    return IconButton(
      icon: GlyphIcon(icon, size: 18, color: color),
      tooltip: tooltip,
      // 与工具栏其余图标键同一套密度，别让这一条比上面那排胖一圈。
      visualDensity: VisualDensity.compact,
      onPressed: _busy ? null : onPressed,
    );
  }

  /// 把[paths]这批放进内部剪贴板（两步式的第一步）。
  Future<void> _copyToClipboard({
    required bool cut,
    required List<String> paths,
  }) async {
    // 一条都没有就什么都不做：空剪贴板会把 `canPaste` 弄成假，
    // 然后用户会发现「粘贴」项莫名消失了。
    if (paths.isEmpty) return;
    await _runOps(
      (id) => fileOpsCopyToClipboard(id: id, cut: cut, paths: paths),
    );
    if (!mounted) return;
    showInfoToast(
      fileManagerClipboardHint(cut: cut, count: paths.length),
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
    final targets = _selectedPaths.toList();
    if (id == null || targets.isEmpty || _busy || _disposed) return;
    // 走同一个 `planFileManagerEntryAction`：回收站**不问**确认（它的保护是撤销
    // 通道），但这个「问不问」的规则必须只有一处，否则操作条与右键菜单会分叉。
    final call = await planFileManagerEntryAction(
      context,
      action: FileManagerEntryAction.trash,
      target: _selectionTarget(targets.length),
    );
    if (call == null || !mounted) return;
    await _runMutation(() => fileOpsTrashPaths(id: id, paths: targets));
  }

  Future<void> _deleteSelectionPermanently() async {
    final id = _sessionId;
    final targets = _selectedPaths.toList();
    if (id == null || targets.isEmpty || _busy || _disposed) return;
    final call = await planFileManagerEntryAction(
      context,
      action: FileManagerEntryAction.deletePermanently,
      target: _selectionTarget(targets.length),
    );
    if (call == null || !mounted) return;
    await _runMutation(() => fileOpsDeletePaths(id: id, paths: targets));
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
  /// 菜单宿主靠 `GestureDetector` 收次键，选中态那一层是 `IgnorePointer`
  /// 的画，谁在里面都行，但「菜单在外面」让菜单的手势区覆盖**整行**，
  /// 包括选中态的描边。
  ///
  /// 菜单**只弹菜单**：它不改选中集合。动作落在哪些条目上由 [_actionTargets]
  /// 在动作开始时算一次 —— 「在集合外右键 = 对这一个」是目标口径，
  /// 不是把选中态搬过去的理由。
  Widget _wrapEntryRow(BuildContext context, LibraryEntry row, Widget child) {
    final entry = row.source;
    // 共享行模型的 `source` 是 `Object?`：别的卡片（书签/历史）也走这条壳子，
    // 它们的 `source` 不是文件条目，直通即可。
    if (entry is! FileManagerEntry) return child;
    return FileManagerEntryContextMenuRegion(
      enabled: !_busy,
      inputBuilder: () => _menuInputFor(entry),
      onAction: (_, action) => unawaited(_runEntryAction(entry, action)),
      child: FileManagerEntrySelectionShell(
        selected: _isEntrySelected(entry.path),
        child: child,
      ),
    );
  }
}
