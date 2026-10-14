import 'dart:math' as math;
import 'package:zephyr/workspace/widgets/library_view/library_view.dart';
import 'package:flutter/rendering.dart' show TreeSliverIndentationType;
import 'package:material_ui/material_ui.dart';
import 'package:multi_split_view/multi_split_view.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/src/rust/api/file_manager/types.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 官方树视口的数据适配。目录展开来自 Rust，网格档把连续叶子节点排进同一行。
class FileManagerHierarchyView extends StatelessWidget {
  const FileManagerHierarchyView({
    super.key,
    required this.tree,
    required this.onToggle,
    this.onActiveOffset,
    required this.entryBuilder,
    required this.entryExtent,
    this.mode = LibraryViewMode.compact,
    this.enabled = true,
    this.controller,
  });

  final FileManagerTreeSnapshot? tree;
  final ValueChanged<String> onToggle;
  final ValueChanged<(String, double, double)>? onActiveOffset;
  final Widget Function(BuildContext, FileManagerEntry) entryBuilder;
  final double entryExtent;
  final LibraryViewMode mode;
  final bool enabled;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final snapshot = tree;
    if (snapshot == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (snapshot.rows.isEmpty)
      return Center(child: Text(t.workspace.nothingToDisplay));
    final roots = <TreeSliverNode<FileManagerTreeRow>>[];
    final parents = <TreeSliverNode<FileManagerTreeRow>>[];
    for (final row in snapshot.rows) {
      while (parents.length > row.depth) {
        parents.removeLast();
      }
      final node = TreeSliverNode(row, expanded: row.expanded);
      if (parents.isEmpty) {
        roots.add(node);
      } else {
        parents.last.children.add(node);
      }
      parents.add(node);
    }
    final geometry = LibraryViewLayout.list(mode);
    return LayoutBuilder(
      builder: (context, constraints) {
        int capacity(int depth) => math.max(
          1,
          ((constraints.maxWidth - depth * 18 - 32) /
                  ((geometry.maxCrossAxisExtent ?? constraints.maxWidth) +
                      geometry.crossAxisSpacing))
              .ceil(),
        );
        List<TreeSliverNode<_TreeCards>> project(
          List<TreeSliverNode<FileManagerTreeRow>> nodes,
        ) {
          final result = <TreeSliverNode<_TreeCards>>[];
          for (var i = 0; i < nodes.length;) {
            final node = nodes[i];
            final row = node.content;
            final group = <FileManagerTreeRow>[row];
            i++;
            if (geometry.isGrid && row.entry != null && !row.entry!.isDir) {
              while (i < nodes.length &&
                  group.length < capacity(row.depth) &&
                  nodes[i].content.entry != null &&
                  !nodes[i].content.entry!.isDir) {
                group.add(nodes[i++].content);
              }
            }
            result.add(
              TreeSliverNode(
                _TreeCards(group, capacity(row.depth)),
                expanded: row.expanded,
                children: project(node.children),
              ),
            );
          }
          return result;
        }

        double extent(_TreeCards cards) {
          if (geometry.isGrid) return entryExtent + geometry.mainAxisSpacing;
          final entry = cards.rows.first.entry;
          final subLines = entry?.childNames.length ?? 0;
          // 子文件名继续使用现有卡片；它们占的高度也纳入官方树的行度量。
          return switch (mode) {
            LibraryViewMode.compact => math.max(40, 26 + subLines * 18.0),
            LibraryViewMode.coverList => math.max(60, 52 + subLines * 18.0),
            LibraryViewMode.details => 40,
            _ => entryExtent,
          };
        }

        final projected = project(roots);
        var offset = mode == LibraryViewMode.details ? 20.0 : 0.0;
        void reportActive(List<TreeSliverNode<_TreeCards>> nodes) {
          for (final node in nodes) {
            final height = extent(node.content);
            for (final row in node.content.rows) {
              if (row.isActive) {
                onActiveOffset?.call((row.path, offset, height));
              }
            }
            offset += height;
            if (node.isExpanded) reportActive(node.children);
          }
        }

        reportActive(projected);
        return CustomScrollView(
          key: const ValueKey('file-manager-tree-list'),
          controller: controller,
          slivers: [
            if (mode == LibraryViewMode.details)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(left: 32),
                  child: Row(
                    children: [
                      Expanded(child: Text(t.workspace.nameLabel)),
                      SizedBox(width: 74, child: Text('类型')),
                      SizedBox(width: 79, child: Text(t.workspace.sizeLabel)),
                      SizedBox(
                        width: 114,
                        child: Text(t.workspace.modifiedTime),
                      ),
                    ],
                  ),
                ),
              ),
            TreeSliver<_TreeCards>(
              key: ObjectKey(snapshot),
              tree: projected,
              indentation: TreeSliverIndentationType.none,
              treeRowExtentBuilder: (node, _) =>
                  extent(node.content as _TreeCards),
              treeNodeBuilder: (context, node, _) {
                final cards = node.content as _TreeCards;
                final row = cards.rows.first;
                final multi = cards.rows.length > 1;
                return Padding(
                  padding: EdgeInsets.only(left: row.depth * 18.0),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: multi
                            ? null
                            : row.loading
                            ? const Center(
                                child: SizedBox.square(
                                  dimension: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : row.mayHaveChildren
                            ? IconButton(
                                key: ValueKey(
                                  'file-manager-tree-toggle:${row.path}',
                                ),
                                tooltip: row.expanded
                                    ? '收起'
                                    : t.workspace.expandLabel,
                                padding: EdgeInsets.zero,
                                icon: GlyphIcon(
                                  row.expanded
                                      ? AppGlyphs.chevronDown
                                      : AppGlyphs.chevronForward,
                                  size: 16,
                                ),
                                onPressed: enabled
                                    ? () => onToggle(row.path)
                                    : null,
                              )
                            : null,
                      ),
                      Expanded(
                        child: geometry.isGrid
                            ? GridView.builder(
                                physics: const NeverScrollableScrollPhysics(),
                                padding: EdgeInsets.zero,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: cards.capacity,
                                      mainAxisExtent: entryExtent,
                                      crossAxisSpacing:
                                          geometry.crossAxisSpacing,
                                    ),
                                itemCount: cards.rows.length,
                                itemBuilder: (context, index) =>
                                    _card(context, cards.rows[index]),
                              )
                            : DetailsColumns(
                                columns: [
                                  LibraryColumn(
                                    key: 'type',
                                    label: '类型',
                                    width: 70,
                                  ),
                                  LibraryColumn(
                                    key: 'size',
                                    label: t.workspace.sizeLabel,
                                    width: 75,
                                    alignRight: true,
                                  ),
                                  LibraryColumn(
                                    key: 'date',
                                    label: t.workspace.modifiedTime,
                                    width: 110,
                                  ),
                                ],
                                child: _card(context, row),
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _card(BuildContext context, FileManagerTreeRow row) => Container(
    key: ValueKey('file-manager-tree:${row.path}'),
    color: row.isActive
        ? Theme.of(context).colorScheme.secondaryContainer
        : null,
    child: entryBuilder(
      context,
      row.entry ??
          FileManagerEntry(
            path: row.path,
            name: row.name,
            isDir: true,
            isArchive: false,
            isImage: false,
            isVideo: false,
            isAudio: false,
            size: BigInt.zero,
            modifiedSecs: 0,
            hasChildren: row.mayHaveChildren,
            penetratable: false,
            childNames: const [],
          ),
    ),
  );
}

class _TreeCards {
  const _TreeCards(this.rows, this.capacity);
  final List<FileManagerTreeRow> rows;
  final int capacity;
}

/// 现成分栏容器负责分隔线与拖动。窄面板横向滚动，目录列不被挤成不可读的窄条。
class FileManagerSplitContent extends StatefulWidget {
  const FileManagerSplitContent({
    super.key,
    required this.ids,
    required this.children,
    this.controller,
    this.contentMinWidth = 260,
  });
  final List<String> ids;
  final List<Widget> children;
  final ScrollController? controller;
  final double contentMinWidth;
  @override
  State<FileManagerSplitContent> createState() =>
      _FileManagerSplitContentState();
}

class _FileManagerSplitContentState extends State<FileManagerSplitContent> {
  final _panes = MultiSplitViewController();
  @override
  void initState() {
    super.initState();
    _syncPanes();
  }

  @override
  void didUpdateWidget(covariant FileManagerSplitContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ids.join('\x1f') != widget.ids.join('\x1f')) {
      _syncPanes();
    }
  }

  void _syncPanes() {
    final previous = {for (final area in _panes.areas) area.id: area.size};
    _panes.areas = [
      for (var i = 0; i < widget.ids.length; i++)
        i == widget.ids.length - 1
            ? Area(id: widget.ids[i], flex: 1)
            : Area(
                id: widget.ids[i],
                size: previous[widget.ids[i]] ?? 210,
                min: 150,
              ),
    ];
  }

  @override
  void dispose() {
    _panes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final preceding = _panes.areas
          .take(widget.ids.length - 1)
          .fold(0.0, (sum, area) => sum + (area.size ?? 210));
      final width =
          (preceding + widget.contentMinWidth + (widget.ids.length - 1) * 10)
              .clamp(constraints.maxWidth, double.infinity);
      return SingleChildScrollView(
        controller: widget.controller,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          height: constraints.maxHeight,
          child: MultiSplitView(
            controller: _panes,
            onDividerDragEnd: (_) {
              if (mounted) setState(() {});
            },
            builder: (context, area) => widget.children[area.index],
          ),
        ),
      );
    },
  );
}
