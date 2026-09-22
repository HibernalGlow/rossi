part of '../file_manager_card.dart';

// 从 class _FileManagerCardState 搬出的方法组；extension 与宿主类同库，可直接访问私有成员。
extension _FileManagerCardTreePart on _FileManagerCardState {
  /// 开关文件树。
  ///
  /// 打开时顺手关掉目录列：两者回答的是同一个问题（「我在这棵目录树的哪儿」），
  /// 同时开着只是把本来就不高的卡片挤成两半。
  Future<void> _setTreeEnabled(bool enabled) async {
    if (!enabled) {
      _treePoll?.cancel();
      // ignore: invalid_use_of_protected_member
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
    // ignore: invalid_use_of_protected_member
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
      // ignore: invalid_use_of_protected_member
      setState(() => _tree = tree);
      _scheduleTreePoll(tree);
    } catch (error) {
      if (!mounted || serial != _treeSerial) return;
      // ignore: invalid_use_of_protected_member
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
      selectedTileColor: theme.colorScheme.secondaryContainer,
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
}
