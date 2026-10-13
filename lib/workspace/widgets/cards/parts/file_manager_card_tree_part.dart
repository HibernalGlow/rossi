part of '../file_manager_card.dart';

// 从 class _FileManagerCardState 搬出的方法组；extension 与宿主类同库，可直接访问私有成员。

extension _FileManagerCardTreePart on _FileManagerCardState {
  /// 当前目录一变，树就重新对齐一次。
  ///
  /// 挂在 `generation` 上而不是逐个导航动作里：改当前目录的入口有七八个
  /// （页签、面包屑、导航掌、根目录、条目双击、收藏/历史卡片的「新页签打开」），
  /// 而核心保证每个生效的动作都推进 `generation`。
  void _followTreeOn(BigInt generation) {
    if (!_treeRequested || _treeGeneration == generation) return;
    _treeGeneration = generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _treeRequested) _loadTree();
    });
  }

  Future<void> _loadTree() async {
    final id = _sessionId;
    if (id == null || _disposed || !_treeRequested) return;
    final serial = ++_treeSerial;
    try {
      final tree = await fileManagerTreeSnapshot(id: id);
      if (!mounted || serial != _treeSerial || !_treeRequested) return;
      // ignore: invalid_use_of_protected_member
      setState(() => _tree = tree);
      _scheduleTreePoll(tree);
      _ensurePreviewExpanded(tree);
    } catch (error) {
      if (!mounted || serial != _treeSerial) return;
      // ignore: invalid_use_of_protected_member
      setState(() => _tree = null);
      _showError(error);
    }
  }

  void _revealActiveTreeRow((String, double, double) active) {
    final (path, rowTop, rowExtent) = active;
    final stylePath = '$path:${_snapshot?.viewMode.name}';
    if (_treeRevealedPath == stylePath) return;
    _treeRevealedPath = stylePath;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_treeEnabled || !_treeScroll.hasClients) return;
      final position = _treeScroll.position;
      if (position.maxScrollExtent <= 0) return;
      if (rowTop >= position.pixels &&
          rowTop + rowExtent <= position.pixels + position.viewportDimension)
        return;
      final target = (rowTop - (position.viewportDimension - rowExtent) / 2)
          .clamp(0.0, position.maxScrollExtent);
      _treeScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _toggleTreeNode(String path) async {
    final id = _sessionId;
    if (id == null || _disposed || _busy) return;
    final serial = ++_treeSerial;
    try {
      final tree = await fileManagerTreeToggle(id: id, path: path);
      if (!mounted || serial != _treeSerial || !_treeRequested) return;
      // ignore: invalid_use_of_protected_member
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

  Widget _buildContent(BuildContext context, FileManagerSnapshot snapshot) {
    if (snapshot.layoutMode == FileManagerLayoutMode.content) {
      return _buildEntries(context, snapshot);
    }
    final content = snapshot.layoutMode == FileManagerLayoutMode.columns
        ? _buildColumnsContent(context, snapshot)
        : _buildHierarchy(context, snapshot);
    return widget.isStandalone
        ? content
        : SizedBox(height: 440, child: content);
  }

  Widget _buildHierarchy(BuildContext context, FileManagerSnapshot snapshot) {
    final mode = fileManagerLibraryMode(snapshot.viewMode);
    final extent = switch (mode) {
      LibraryViewMode.compact => 40.0,
      LibraryViewMode.details => 40.0,
      LibraryViewMode.coverList => 110.0,
      LibraryViewMode.mosaicList => 92.0,
      LibraryViewMode.coverGrid => 180.0,
      LibraryViewMode.mosaicGrid => 130.0,
    };
    final tree = _tree;
    final hierarchy = FileManagerHierarchyView(
      tree: tree,
      controller: _treeScroll,
      enabled: !_busy,
      entryExtent: extent,
      mode: mode,
      onToggle: _toggleTreeNode,
      onActiveOffset: snapshot.searchActive ? null : _revealActiveTreeRow,
      entryBuilder: (context, entry) {
        final row = _libraryEntry(context, entry, mode);
        Widget surface = LibraryEntrySurface(
          mode: mode,
          entry: row,
          wrapTitle: context
              .read<GlobalSettingCubit>()
              .state
              .fileManagerSetting
              .wrapGridTitle,
          onTap: _busy
              ? null
              : () => entry.isDir && !_selectionModeOn
                    ? _toggleTreeNode(entry.path)
                    : _onEntryTap(entry),
          onDoubleTap: !_busy && (entry.isArchive || entry.isDir)
              ? () => entry.isDir
                    ? _openEntry(entry, forceEnter: true)
                    : _openArchive(entry)
              : null,
        );
        if (_fileOpsEnabled) surface = _wrapEntryRow(context, row, surface);
        return surface;
      },
    );
    // 深层搜索祖先与详细信息列需要横向空间。滚动交给标准视口，不压缩名称列。
    final maxDepth =
        tree?.rows.fold(
          0,
          (value, row) => row.depth > value ? row.depth : value,
        ) ??
        0;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: constraints.maxWidth.clamp(
            (mode == LibraryViewMode.details ? 500.0 : 280.0) + maxDepth * 18,
            double.infinity,
          ),
          height: constraints.maxHeight,
          child: hierarchy,
        ),
      ),
    );
  }

  Widget _buildColumnsContent(
    BuildContext context,
    FileManagerSnapshot snapshot,
  ) {
    final columns = snapshot.directoryColumns;
    final cursor = snapshot.searchActive && columns.isNotEmpty
        ? columns.last.path
        : snapshot.activePath;
    if (_columnsRevealedPath != '${snapshot.activeTabId}:$cursor') {
      _columnsRevealedPath = '${snapshot.activeTabId}:$cursor';
      _revealTail(_directoryColumnScroll);
    }
    // 当前目录只画一次；前面的目录和当前目录都走同一个六档条目宿主。
    final parents = columns
        .where((column) => !p.equals(column.path, cursor))
        .toList();
    final visible = snapshot.searchActive
        ? snapshot.entries
              .where((entry) => p.equals(p.dirname(entry.path), cursor))
              .toList()
        : snapshot.entries;
    final current = columns
        .where((column) => p.equals(column.path, cursor))
        .firstOrNull;
    // 搜索祖先分组也属于当前栏的内容；仅根据命中投影，不重新枚举目录。
    final currentEntries = <FileManagerEntry>[
      if (snapshot.searchActive && current != null)
        for (final choice in current.entries)
          if (!visible.any((entry) => p.equals(entry.path, choice.path)))
            _columnEntry(choice),
      ...visible,
    ];
    return FileManagerSplitContent(
      key: ValueKey('column-layout:${snapshot.activeTabId}'),
      controller: _directoryColumnScroll,
      contentMinWidth: snapshot.viewMode == FileManagerViewMode.details
          ? 460
          : 260,
      ids: [...parents.map((column) => column.path), cursor],
      children: [
        for (final column in parents)
          _buildDirectoryColumn(
            context,
            snapshot,
            column.path,
            column.name,
            [for (final choice in column.entries) _columnEntry(choice)],
            selected: {
              for (final choice in column.entries)
                if (choice.selected) choice.path,
            },
            error: column.error,
          ),
        _buildDirectoryColumn(
          context,
          snapshot,
          cursor,
          current?.name ?? p.basename(cursor),
          currentEntries,
        ),
      ],
    );
  }

  FileManagerEntry _columnEntry(FileManagerDirectoryChoice choice) =>
      choice.entry ??
      FileManagerEntry(
        path: choice.path,
        name: choice.name,
        isDir: true,
        isArchive: false,
        isImage: false,
        isVideo: false,
        isAudio: false,
        size: BigInt.zero,
        modifiedSecs: 0,
        hasChildren: true,
        penetratable: false,
        childNames: const [],
      );

  Widget _buildDirectoryColumn(
    BuildContext context,
    FileManagerSnapshot snapshot,
    String path,
    String name,
    List<FileManagerEntry> entries, {
    Set<String> selected = const {},
    String? error,
  }) => Column(
    key: ValueKey('file-manager-column-pane:$path'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Tooltip(
        message: path,
        child: TextButton(
          onPressed: _busy ? null : () => _selectColumnPath(snapshot, path),
          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
      Expanded(
        child: error != null
            ? SingleChildScrollView(child: Text(error))
            : _buildEntries(
                context,
                snapshot,
                entries: entries,
                standalone: true,
                onEntryTap: (entry) => entry.isDir && !_selectionModeOn
                    ? _selectColumnPath(snapshot, entry.path)
                    : _onEntryTap(entry),
                decorateRow: (context, row, child) => DecoratedBox(
                  key: ValueKey('file-manager-column:${row.key}'),
                  decoration: BoxDecoration(
                    color: selected.contains(row.key)
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : null,
                  ),
                  child: child,
                ),
              ),
      ),
    ],
  );

  void _selectColumnPath(FileManagerSnapshot snapshot, String path) {
    _apply(
      (id) => snapshot.searchActive
          ? fileManagerSelectSearchDirectory(id: id, path: path)
          : fileManagerNavigate(id: id, path: path),
    );
  }
}
