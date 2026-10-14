import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/src/rust/api/file_manager/types.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_tile.dart';
import 'package:zephyr/i18n/strings.g.dart';

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
                  tooltip: t.workspace.collapseInformation,
                  onPressed: widget.onClose,
                  icon: const GlyphIcon(AppGlyphs.close),
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
                  icon: GlyphIcon(
                    entry.isDir ? AppGlyphs.folder : AppGlyphs.openExternal,
                  ),
                  label: Text(entry.isDir ? t.workspace.enterFolder : '打开'),
                ),
                if (entry.isDir) ...[
                  FilterChip(
                    label: Text(t.workspace.internalThumbnails),
                    selected: _thumbnails,
                    onSelected: (v) => setState(() => _thumbnails = v),
                  ),
                  if (parent != null)
                    TextButton.icon(
                      onPressed: () => widget.onToggle(entry.path),
                      icon: MorphingGlyph(
                        on: parent.expanded,
                        glyph: AppGlyphs.chevronDown,
                        turns: 0.5,
                      ),
                      label: Text(
                        parent.expanded
                            ? t.workspace.collapseChildren
                            : t.workspace.expandChildren,
                      ),
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
                Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(t.workspace.folderNotInSnapshot),
                ),
              if (parent?.error case final error?)
                Text(error, style: TextStyle(color: theme.colorScheme.error)),
              if (parent != null &&
                  parent.expanded &&
                  !parent.loading &&
                  children.isEmpty &&
                  parent.error == null)
                Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(t.workspace.folderNoChildren),
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
                                                ? t.workspace.collapseSubfolders
                                                : t.workspace.expandSubfolders,
                                            onPressed: () =>
                                                widget.onToggle(row.path),
                                            // 展开 = 同一颗 chevronForward 转 90°
                                            // （朝右 → 朝上，所以是 -0.25）。
                                            icon: MorphingGlyph(
                                              on: row.expanded,
                                              glyph: AppGlyphs.chevronForward,
                                              turns: -0.25,
                                            ),
                                          )
                                        : GlyphIcon(
                                            row.entry!.isDir
                                                ? AppGlyphs.folder
                                                : AppGlyphs.article,
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
