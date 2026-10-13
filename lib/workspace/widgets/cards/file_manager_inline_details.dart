import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/src/rust/api/file_manager/types.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_tile.dart';

/// 树行是核心快照，展开箭头与正文打开分开；不保存第二份目录展开状态。
class FileManagerInlineDetails extends StatefulWidget {
  const FileManagerInlineDetails({
    super.key,
    required this.entry,
    required this.tree,
    required this.onClose,
    required this.onToggle,
    required this.onOpen,
    required this.rowBuilder,
    this.statisticsLabel,
  });
  final FileManagerEntry entry;
  final FileManagerTreeSnapshot? tree;
  final VoidCallback onClose;
  final ValueChanged<String> onToggle;
  final ValueChanged<FileManagerEntry> onOpen;
  final LibraryEntry Function(FileManagerEntry) rowBuilder;
  final String? statisticsLabel;
  @override
  State<FileManagerInlineDetails> createState() =>
      _FileManagerInlineDetailsState();
}

class _FileManagerInlineDetailsState extends State<FileManagerInlineDetails> {
  bool _thumbnails = false;
  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final tree = widget.tree;
    final parent = tree?.rows
        .where((r) => p.equals(r.path, entry.path))
        .firstOrNull;
    final children = <FileManagerTreeRow>[];
    if (tree != null && parent != null && parent.expanded) {
      final start = tree.rows.indexOf(parent);
      for (var i = start + 1; i < tree.rows.length; i++) {
        final row = tree.rows[i];
        if (row.depth <= parent.depth) break;
        if (row.entry != null) children.add(row);
      }
    }
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(entry.name, style: theme.textTheme.titleLarge),
                ),
                IconButton(
                  tooltip: '收起信息',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            SelectableText(entry.path, style: theme.textTheme.bodySmall),
            if (widget.statisticsLabel != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  widget.statisticsLabel!,
                  style: theme.textTheme.labelLarge,
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => widget.onOpen(entry),
                  icon: Icon(
                    entry.isDir
                        ? Icons.folder_open_rounded
                        : Icons.open_in_new_rounded,
                  ),
                  label: Text(entry.isDir ? '进入文件夹' : '打开'),
                ),
                if (entry.isDir) ...[
                  FilterChip(
                    label: const Text('内部缩略图'),
                    selected: _thumbnails,
                    onSelected: (v) => setState(() => _thumbnails = v),
                  ),
                  if (parent != null)
                    TextButton.icon(
                      onPressed: () => widget.onToggle(entry.path),
                      icon: Icon(
                        parent.expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                      ),
                      label: Text(parent.expanded ? '收起子项' : '展开子项'),
                    ),
                ],
              ],
            ),
            if (entry.isDir) ...[
              const Divider(height: 24),
              if (tree == null ||
                  (parent == null && tree.hasPending) ||
                  (parent?.loading ?? false))
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (tree != null && parent == null && !tree.hasPending)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('当前搜索或目录快照未包含此文件夹。可进入文件夹查看内部内容。'),
                ),
              if (parent?.error case final error?)
                Text(error, style: TextStyle(color: theme.colorScheme.error)),
              if (parent != null &&
                  parent.expanded &&
                  !parent.loading &&
                  children.isEmpty &&
                  parent.error == null)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('当前文件夹没有可显示的子项'),
                ),
              if (children.isNotEmpty)
                SizedBox(
                  height: (children.length * (_thumbnails ? 180.0 : 52.0))
                      .clamp(80.0, 380.0),
                  child: _thumbnails
                      ? GridView.builder(
                          primary: false,
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 200,
                                mainAxisExtent: 240,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                          itemCount: children.length,
                          itemBuilder: (context, i) {
                            final row = children[i];
                            return LibraryEditorialTile(
                              entry: widget.rowBuilder(row.entry!),
                              onTap: () => widget.onOpen(row.entry!),
                              onInfo: row.mayHaveChildren
                                  ? () => widget.onToggle(row.path)
                                  : null,
                            );
                          },
                        )
                      : ListView.builder(
                          primary: false,
                          itemCount: children.length,
                          itemBuilder: (context, i) {
                            final row = children[i];
                            return Padding(
                              padding: EdgeInsets.only(
                                left: ((row.depth - parent!.depth - 1) * 16.0)
                                    .clamp(0.0, 96.0),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 48,
                                    child: row.loading
                                        ? const Padding(
                                            padding: EdgeInsets.all(16),
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : row.mayHaveChildren
                                        ? IconButton(
                                            tooltip: row.expanded
                                                ? '收起子文件夹'
                                                : '展开子文件夹',
                                            onPressed: () =>
                                                widget.onToggle(row.path),
                                            icon: Icon(
                                              row.expanded
                                                  ? Icons.expand_less_rounded
                                                  : Icons.chevron_right_rounded,
                                            ),
                                          )
                                        : Icon(
                                            row.entry!.isDir
                                                ? Icons.folder_outlined
                                                : Icons
                                                      .insert_drive_file_outlined,
                                            size: 20,
                                          ),
                                  ),
                                  Expanded(
                                    child: ListTile(
                                      dense: true,
                                      title: Text(
                                        row.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: row.error == null
                                          ? null
                                          : Text(
                                              row.error!,
                                              style: TextStyle(
                                                color: theme.colorScheme.error,
                                              ),
                                            ),
                                      onTap: () => widget.onOpen(row.entry!),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
