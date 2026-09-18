import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/src/rust/api/file_manager.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';

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

  const FileManagerCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
  });

  @override
  State<FileManagerCard> createState() => _FileManagerCardState();
}

class _FileManagerCardState extends State<FileManagerCard> {
  BigInt? _sessionId;
  FileManagerSnapshot? _snapshot;
  String? _error;
  bool _busy = false;
  int _requestSerial = 0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  @override
  void dispose() {
    _disposed = true;
    final id = _sessionId;
    if (id != null) fileManagerClose(id: id);
    super.dispose();
  }

  Future<void> _startSession() async {
    try {
      final id = await fileManagerCreate();
      if (_disposed) {
        fileManagerClose(id: id);
        return;
      }
      _sessionId = id;
      await _reload();
    } catch (error) {
      _showError(error);
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
        _snapshot = snapshot;
        _error = null;
        _busy = false;
      });
    } catch (error) {
      if (!mounted || serial != _requestSerial) return;
      _showError(error);
    }
  }

  Future<void> _apply(
    Future<FileManagerSnapshot> Function(BigInt id) action,
  ) async {
    final id = _sessionId;
    if (id == null || _busy) return;
    final serial = ++_requestSerial;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snapshot = await action(id);
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _snapshot = snapshot;
        _busy = false;
      });
    } catch (error) {
      if (!mounted || serial != _requestSerial) return;
      _showError(error);
    }
  }

  Future<void> _openEntry(
    FileManagerEntry entry, {
    bool forceEnter = false,
  }) async {
    if (!entry.isDir && !entry.isArchive && !entry.isImage) {
      _showError('当前 Reader 暂不支持直接打开 ${entry.name}');
      return;
    }
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
    final serial = ++_requestSerial;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await action(id);
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _snapshot = result.snapshot;
      });
      final openedPath = result.openedPath;
      if (openedPath != null && mounted && serial == _requestSerial) {
        // Keep the card busy while the reader route is on top. This makes the
        // second pointer-up of a double-click unable to enqueue another route.
        await _openReader(openedPath);
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
      hasChildren: false,
      childNames: const [],
    );
  }

  Future<void> _openReader(String path) async {
    if (!mounted) return;
    await context.pushRoute(
      ComicReadRoute(
        comicId: path,
        order: 0,
        from: 'local_file_manager',
        epsNumber: 1,
        type: ComicEntryType.normal,
        comicInfo: path,
        stringSelectCubit: StringSelectCubit(),
      ),
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
              '${snapshot.tabs.length}/8',
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
      return SizedBox(
        height: 180,
        child: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : _ErrorState(message: _error!, onRetry: _startSession),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTabs(context, snapshot),
        const SizedBox(height: 6),
        _buildToolbar(context, snapshot),
        _buildRoots(context, snapshot),
        if (_error != null) _buildInlineError(context),
        const SizedBox(height: 6),
        _buildEntries(context, snapshot),
      ],
    );
  }

  Widget _buildTabs(BuildContext context, FileManagerSnapshot snapshot) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 34,
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
                return InputChip(
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
                  onPressed: () => _apply(
                    (id) => fileManagerActivateTab(id: id, tabId: tab.id),
                  ),
                  onDeleted: snapshot.tabs.length > 1
                      ? () => _apply(
                          (id) => fileManagerCloseTab(id: id, tabId: tab.id),
                        )
                      : null,
                  deleteIcon: const Icon(Icons.close, size: 13),
                );
              },
            ),
          ),
          IconButton(
            tooltip: '新建页签',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: _busy
                ? null
                : () => _apply((id) => fileManagerNewTab(id: id)),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, FileManagerSnapshot snapshot) {
    final theme = Theme.of(context);
    Widget action({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
    }) {
      return IconButton(
        icon: Icon(icon, size: 18),
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        onPressed: _busy ? null : onPressed,
      );
    }

    return Row(
      children: [
        action(
          icon: Icons.arrow_back_rounded,
          tooltip: '后退',
          onPressed:
              snapshot.tabs
                  .firstWhere((tab) => tab.id == snapshot.activeTabId)
                  .canGoBack
              ? () => _apply((id) => fileManagerGoBack(id: id))
              : null,
        ),
        action(
          icon: Icons.arrow_forward_rounded,
          tooltip: '前进',
          onPressed:
              snapshot.tabs
                  .firstWhere((tab) => tab.id == snapshot.activeTabId)
                  .canGoForward
              ? () => _apply((id) => fileManagerGoForward(id: id))
              : null,
        ),
        action(
          icon: Icons.arrow_upward_rounded,
          tooltip: '上一级',
          onPressed: () => _apply((id) => fileManagerGoUp(id: id)),
        ),
        action(
          icon: Icons.refresh_rounded,
          tooltip: '刷新',
          onPressed: () => _apply((id) => fileManagerRefresh(id: id)),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            snapshot.activePath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        IconButton(
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          tooltip: snapshot.viewMode == FileManagerViewMode.list
              ? '网格视图'
              : '列表视图',
          onPressed: _busy
              ? null
              : () => _apply(
                  (id) => fileManagerSetViewMode(
                    id: id,
                    mode: snapshot.viewMode == FileManagerViewMode.list
                        ? FileManagerViewMode.grid
                        : FileManagerViewMode.list,
                  ),
                ),
          icon: Icon(
            snapshot.viewMode == FileManagerViewMode.list
                ? Icons.grid_view_rounded
                : Icons.view_list_rounded,
          ),
        ),
        PopupMenuButton<String>(
          tooltip: '文件浏览设置',
          enabled: !_busy,
          icon: const Icon(Icons.tune_rounded, size: 18),
          onSelected: (value) {
            switch (value) {
              case 'penetration':
                _apply(
                  (id) => fileManagerSetPenetration(
                    id: id,
                    enabled: !snapshot.penetrationEnabled,
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
                  _apply((id) => fileManagerSetMaxDepth(id: id, depth: depth));
                }
            }
          },
          itemBuilder: (context) => [
            CheckedPopupMenuItem(
              value: 'penetration',
              checked: snapshot.penetrationEnabled,
              child: const Text('穿透模式'),
            ),
            CheckedPopupMenuItem(
              value: 'children',
              checked: snapshot.showChildNames,
              child: const Text('显示子文件名'),
            ),
            PopupMenuItem(
              value: 'mode',
              child: Text(
                snapshot.internalItemsMode ==
                        FileManagerInternalItemsMode.single
                    ? '子文件：显示一个'
                    : '子文件：显示全部',
              ),
            ),
            const PopupMenuDivider(),
            for (final depth in [1, 2, 3, 5, 10, 32])
              CheckedPopupMenuItem(
                value: '$depth',
                checked: snapshot.maxDepth == depth,
                child: Text(depth == 32 ? '穿透深度：最多 32 层' : '穿透深度：$depth 层'),
              ),
          ],
        ),
      ],
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

  Widget _buildEntries(BuildContext context, FileManagerSnapshot snapshot) {
    if (snapshot.entries.isEmpty) {
      return SizedBox(
        height: 170,
        child: Center(
          child: Text(
            '当前目录没有可浏览的漫画或媒体文件',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    final list = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 120, maxHeight: 440),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: snapshot.viewMode == FileManagerViewMode.grid
            ? GridView.builder(
                padding: const EdgeInsets.all(6),
                primary: false,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  mainAxisExtent: 104,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemCount: snapshot.entries.length,
                itemBuilder: (context, index) =>
                    _buildGridEntry(context, snapshot.entries[index]),
              )
            : ListView.separated(
                primary: false,
                itemCount: snapshot.entries.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) =>
                    _buildListEntry(context, snapshot.entries[index]),
              ),
      ),
    );
    return Stack(
      children: [
        list,
        if (_busy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x33000000),
              child: Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildListEntry(BuildContext context, FileManagerEntry entry) {
    final theme = Theme.of(context);
    final icon = _entryIcon(entry);
    return InkWell(
      onTap: _busy ? null : () => _openEntry(entry),
      onDoubleTap: entry.isArchive && !_busy ? () => _openArchive(entry) : null,
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        leading: Icon(icon, size: 21, color: _entryColor(context, entry)),
        title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: entry.childNames.isEmpty
            ? (entry.isArchive ||
                      entry.isImage ||
                      entry.isVideo ||
                      entry.isAudio
                  ? Text(
                      _formatSize(entry.size),
                      style: theme.textTheme.labelSmall,
                    )
                  : null)
            : _buildChildNames(context, entry.childNames),
        trailing: entry.isDir
            ? IconButton(
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                tooltip: '进入文件夹',
                visualDensity: VisualDensity.compact,
                onPressed: _busy
                    ? null
                    : () => _openEntry(entry, forceEnter: true),
              )
            : const Icon(Icons.play_circle_outline_rounded, size: 18),
      ),
    );
  }

  Widget _buildGridEntry(BuildContext context, FileManagerEntry entry) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: _busy ? null : () => _openEntry(entry),
      onDoubleTap: entry.isArchive && !_busy ? () => _openArchive(entry) : null,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.35,
          ),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _entryIcon(entry),
              color: _entryColor(context, entry),
              size: 22,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (entry.childNames.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    _buildChildNames(context, entry.childNames),
                  ] else if (!entry.isDir)
                    Text(
                      _formatSize(entry.size),
                      style: theme.textTheme.labelSmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChildNames(
    BuildContext context,
    List<FileManagerChild> children,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final child in children)
          InkWell(
            onTap: _busy ? null : () => _openChild(child),
            onDoubleTap: child.isArchive && !_busy
                ? () => _openArchiveChild(child)
                : null,
            child: Row(
              children: [
                Icon(
                  child.isDir
                      ? Icons.folder_outlined
                      : Icons.subdirectory_arrow_right,
                  size: 12,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    child.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  IconData _entryIcon(FileManagerEntry entry) {
    if (entry.isDir) return Icons.folder_rounded;
    if (entry.isArchive) return Icons.auto_stories_rounded;
    if (entry.isImage) return Icons.image_outlined;
    if (entry.isVideo) return Icons.movie_outlined;
    if (entry.isAudio) return Icons.audio_file_outlined;
    return Icons.insert_drive_file_outlined;
  }

  Color _entryColor(BuildContext context, FileManagerEntry entry) {
    final colors = Theme.of(context).colorScheme;
    if (entry.isDir) return colors.tertiary;
    if (entry.isArchive) return colors.primary;
    if (entry.isImage) return colors.secondary;
    if (entry.isVideo || entry.isAudio) return colors.secondary;
    return colors.outline;
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
