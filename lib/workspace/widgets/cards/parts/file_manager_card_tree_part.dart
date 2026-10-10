part of '../file_manager_card.dart';

// 从 class _FileManagerCardState 搬出的方法组；extension 与宿主类同库，可直接访问私有成员。

/// 树列表的垂直内边距（上下各这么多）。
///
/// 定位那一步要从「内容总高」里把它扣掉才能反推行高，所以不能让这个数只写在
/// `_buildFileTree` 的那一句 `EdgeInsets` 里 —— 两边改一边忘的后果是定位偏半行。
const _treeListVerticalPadding = 4.0;

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
        // 记号跟着树一起清掉：收起再展开时当前目录多半没变，
        // 留着它的话第二次打开就不会定位，等于回到「展开了却看不见」那个毛病。
        _treeRevealedPath = null;
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
  /// 把「当前目录」那一行搬进视口。
  ///
  /// 核心已经替我们把祖先链整条展开、并在投影里标好 `isActive`，剩下的问题是行
  /// 按 `ListView.builder` 的需要才建：目录一深，那一行连建都没被建出来，看上去
  /// 就成了「树展开了，却没定位到当前目录」。
  ///
  /// 挂在 `build` 上而不是挂在「取投影」那一次（口径同 `_breadcrumbRevealedPath`）：
  /// 帧后回调要等的是**这一帧把行建出来**之后的几何，而卡片收起再展开、换布局重建
  /// 都不会再取一次投影 —— 只挂在取投影上，那些场合照样看不见当前目录。
  ///
  /// 行高不在这里写死：它跟着主题字阶与 `visualDensity` 变。等布局完成后视口的
  /// 几何里就带着真值 —— 内容总高 = 上下内边距 + 行数 × 行高，而
  /// `maxScrollExtent + viewportDimension` 就是内容总高，反推一次即可。
  /// 行与行等高是成立的：缩进只加在水平方向（`contentPadding.left`），标题 `maxLines: 1`。
  void _revealActiveTreeRow(FileManagerTreeSnapshot tree) {
    final index = tree.rows.indexWhere((row) => row.isActive);
    if (index < 0) return;
    final path = tree.rows[index].path;
    if (_treeRevealedPath == path) return;
    _treeRevealedPath = path;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_treeEnabled || !_treeScroll.hasClients) return;
      final position = _treeScroll.position;
      // 放得下就没有可滚的量（`maxScrollExtent` 被夹在 0），此时反推行高会把
      // 空出来的视口一起摊进每一行，越算越偏 —— 直接不动。
      if (position.maxScrollExtent <= 0) return;
      final contentExtent =
          position.maxScrollExtent + position.viewportDimension;
      final rowExtent =
          (contentExtent - _treeListVerticalPadding * 2) / tree.rows.length;
      final rowTop = _treeListVerticalPadding + index * rowExtent;
      // 整行已经都在视口里就别动：突然搬一次视口，比它停在边上更打扰人。
      if (rowTop >= position.pixels &&
          rowTop + rowExtent <= position.pixels + position.viewportDimension) {
        return;
      }
      // 停在视口中线：反推的行高哪怕差一两像素，误差也只让它偏出中线一点，
      // 出不了视口。
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
    if (tree != null) _revealActiveTreeRow(tree);
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
                key: const ValueKey('file-manager-tree-list'),
                controller: _treeScroll,
                padding: const EdgeInsets.symmetric(
                  vertical: _treeListVerticalPadding,
                ),
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
                // 展开/收起是同一颗箭头转 90°（chevronForward → chevronDown），
                // 不是两颗图标 —— 词表铁律：同一语义只许一颗。
                icon: MorphingGlyph(
                  on: row.expanded,
                  glyph: AppGlyphs.chevronForward,
                  turns: 0.25,
                  size: 16,
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
          : GlyphIcon(
              AppGlyphs.error,
              size: 14,
              color: theme.colorScheme.error,
            ),
      onTap: _busy
          ? null
          : () => _apply((id) => fileManagerNavigate(id: id, path: row.path)),
    );
  }
}
