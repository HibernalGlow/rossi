part of '../file_manager_card.dart';

extension _FileManagerCardEditorialPart on _FileManagerCardState {
  void _queueFileStatistics(
    FileManagerSnapshot snapshot,
    List<FileManagerEntry> entries,
  ) {
    final revision =
        '${snapshot.activeTabId}:${snapshot.activePath}:${snapshot.generation}:$_recursiveStatistics';
    if (_statisticsRevision == revision) return;
    _statisticsRevision = revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _statisticsRevision != revision) return;
      unawaited(
        _fileStatistics.prepare(
          entries.where((e) => e.isDir).map((e) => e.path).toList(),
          recursive: _recursiveStatistics,
          showHidden: snapshot.showHiddenFiles,
          revision: revision,
          onReady: () {
            if (!mounted || _statisticsRevision != revision) return;
            // ignore: invalid_use_of_protected_member
            setState(() {});
          },
        ),
      );
    });
  }

  void _onFilePresentationChanged(LibraryPresentation value) {
    if (_recursiveStatistics == value.recursiveStats) return;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _recursiveStatistics = value.recursiveStats;
      _statisticsRevision = null;
    });
  }

  String _directoryStatisticsLabel(String path) {
    final stats = _fileStatistics.values[path];
    if (stats == null) return '统计中';
    return '${stats.complete ? '' : '至少 '}${stats.count} 项 · ${_formatSize(BigInt.from(stats.bytes))}';
  }

  void _onFileDetailChanged(LibraryEntry? row) {
    // ignore: invalid_use_of_protected_member
    setState(() {
      _previewPath = row?.key;
      final open =
          _canvasKey.currentState?.expandedEntries.map((e) => e.key).toSet() ??
          <String>{};
      _previewAutoExpanded.removeWhere((path) => !open.contains(path));
    });
    if (_previewPath != null)
      _loadTree();
    else if (!_treeEnabled)
      _treePoll?.cancel();
  }

  Future<void> _ensurePreviewExpanded(FileManagerTreeSnapshot tree) async {
    if (_previewExpanding) return;
    _previewExpanding = true;
    try {
      // 树操作逐个执行，避免同时展开多个目录时 serial 门禁只留下最后一次结果。
      while (mounted) {
        final paths =
            (_canvasKey.currentState?.expandedEntries ?? const <LibraryEntry>[])
                .map((entry) => entry.key)
                .toSet();
        final row = (_tree ?? tree).rows
            .where(
              (row) =>
                  paths.contains(row.path) &&
                  !_previewAutoExpanded.contains(row.path),
            )
            .firstOrNull;
        if (row == null) break;
        _previewAutoExpanded.add(row.path);
        if (!row.expanded && row.mayHaveChildren) {
          await _toggleTreeNode(row.path);
        }
      }
    } finally {
      _previewExpanding = false;
    }
  }

  Widget _fileInlineDetails(
    BuildContext context,
    LibraryEntry row,
    VoidCallback close,
  ) {
    final entry = row.source! as FileManagerEntry;
    return FileManagerInlineDetails(
      key: ValueKey('file-inline:${row.key}'),
      entry: entry,
      tree: _tree,
      statisticsLabel: entry.isDir
          ? _directoryStatisticsLabel(entry.path)
          : row.metaText,
      onClose: close,
      onToggle: _toggleTreeNode,
      onOpen: (child) => _openEntry(child, forceEnter: child.isDir),
      rowBuilder: (child) =>
          _libraryEntry(context, child, LibraryViewMode.coverGrid),
    );
  }
}
