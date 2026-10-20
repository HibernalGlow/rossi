import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/library_viewport_anchor.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/comic_list/view/discover_library_entries.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_grid.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_info.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_book_details.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_legacy_focus.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';

/// 发现只适配数据与导航，原位详情、封面行为和展示偏好由通用展墙管理。
class DiscoverLibraryView extends StatelessWidget {
  const DiscoverLibraryView({
    super.key,
    required this.canvasKey,
    required this.scope,
    required this.entries,
    required this.legacyBuilder,
    required this.footerBuilder,
    required this.onReachEnd,
    this.viewportRegistry,
    this.scrollController,
    this.collectionTargetId,
    this.collectionTargetName,
  });

  final GlobalKey<LibraryEditorialCanvasState> canvasKey;
  final String scope;
  final List<LibraryEntry> entries;
  final WidgetBuilder legacyBuilder, footerBuilder;
  final VoidCallback onReachEnd;
  final String? collectionTargetId, collectionTargetName;
  final LibraryViewportRegistry? viewportRegistry;
  final ScrollController? scrollController;

  Widget _anchor(LibraryEntry row, Widget child, {int? index}) =>
      viewportRegistry == null
      ? child
      : LibraryViewportAnchor(
          registry: viewportRegistry!,
          entryKey: row.key,
          entryIndex: index,
          child: child,
        );

  void _open(BuildContext context, LibraryEntry row) => ComicSimplifyEntry(
    info: row.source! as ComicSimplifyEntryInfo,
    type: ComicEntryType.normal,
    collectionTargetId: collectionTargetId,
    collectionTargetName: collectionTargetName,
  ).openDetails(context);

  @override
  Widget build(BuildContext context) {
    // 页码上报要的是「条目在列表里的位置」，不是 key：插件把同一本漫画同时
    // 发在相邻两页时 key 会重复，按 key 反查只会一直落在后一页。用条目对象本身
    // 做键，重复 key 的两张卡也各自拿到自己的下标。
    final indexByEntry = <LibraryEntry, int>{
      for (var i = 0; i < entries.length; i++) entries[i]: i,
    };
    return LibraryEditorialCanvas(
      key: canvasKey,
      scrollController: scrollController,
      wrapCard: (_, row, child) =>
          _anchor(row, child, index: indexByEntry[row]),
      scope: scope,
      standalone: true,
      tapOpensDetail: false,
      initialPresentation: const LibraryPresentation(
        hero: false,
        weight: LibraryWeight.signals,
      ),
      weightSignals: discoverWeightSignals,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 96),
      entries: entries,
      onTap: (row) => _open(context, row),
      detailBuilder: (context, row, close) {
        final info = row.source! as ComicSimplifyEntryInfo;
        return LibraryBookDetails(
          entry: row,
          comicId: info.id,
          from: (info.source.trim().isEmpty ? info.from : info.source).trim(),
          onClose: close,
          collectionTargetId: collectionTargetId,
          collectionTargetName: collectionTargetName,
        );
      },
      onReachEnd: onReachEnd,
      footerBuilder: footerBuilder,
      legacyBuilder: legacyBuilder,
      legacyFocusBuilder: (context, details, toggle, onCoverTap) {
        if (entries.isEmpty) return legacyBuilder(context);
        final grid =
            buildComicSimplifyEntryGridDelegate()
                as SliverGridDelegateWithMaxCrossAxisExtent;
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 20).clamp(
              1.0,
              double.infinity,
            );
            final columns =
                (width / (grid.maxCrossAxisExtent + grid.crossAxisSpacing))
                    .ceil()
                    .clamp(1, 24);
            final cardWidth = libraryCardWidthForColumns(width, columns, 6);
            return NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.depth == 0 &&
                    notification.metrics.axis == Axis.vertical &&
                    notification.metrics.extentAfter < 400) {
                  onReachEnd();
                }
                return false;
              },
              child: LibraryLegacyFocus(
                controller: scrollController,
                count: entries.length,
                columns: columns,
                extent: cardWidth / grid.childAspectRatio,
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 96),
                footer: footerBuilder(context),
                physics: const AlwaysScrollableScrollPhysics(),
                details: {
                  for (var i = 0; i < entries.length; i++)
                    if (details.containsKey(entries[i].key))
                      i: details[entries[i].key]!,
                },
                itemBuilder: (context, index) {
                  final row = entries[index];
                  return _anchor(
                    row,
                    Stack(
                      fit: StackFit.expand,
                      children: [
                        ComicSimplifyEntry(
                          info: row.source! as ComicSimplifyEntryInfo,
                          type: ComicEntryType.normal,
                          onTapOverride: (_) => onCoverTap(row),
                          collectionTargetId: collectionTargetId,
                          collectionTargetName: collectionTargetName,
                        ),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: IconButton.filledTonal(
                            tooltip: '展开信息',
                            onPressed: () => toggle(row),
                            icon: const GlyphIcon(AppGlyphs.info),
                          ),
                        ),
                      ],
                    ),
                    index: index,
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
