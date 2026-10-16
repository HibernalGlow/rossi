import 'package:material_ui/material_ui.dart';
import 'package:zephyr/type/pipe.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/util/debouncer.dart';
import 'package:zephyr/util/json/json_value.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_grid.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_mapper.dart';
import 'package:zephyr/widgets/comic_simplify_entry/cover.dart';
import 'package:zephyr/widgets/section_header.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/type/enum.dart';

class DiscoverSchemeRenderer {
  const DiscoverSchemeRenderer();

  String title(Map<String, dynamic> scheme, String fallback) {
    return scheme['title']?.toString() ?? fallback;
  }

  Widget buildPage(
    BuildContext context, {
    required String from,
    required Map<String, dynamic> scheme,
    required Map<String, dynamic> data,
    required Future<void> Function() onReachBottom,
    required Future<void> Function(Map<String, dynamic> action) onAction,
    required bool isLoadingMore,
    required bool showLoadMoreRetry,
    required VoidCallback onRetryLoadMore,
    bool shrinkWrap = false,
    ScrollPhysics? physics,
  }) {
    final body = asJsonMap(scheme['body']);
    final content = _buildSlivers(
      context,
      node: body,
      data: data,
      from: from,
      onAction: onAction,
    );

    final children = <Widget>[...content];
    if (isLoadingMore) {
      children.add(
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    } else if (showLoadMoreRetry) {
      children.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ElevatedButton(
                onPressed: onRetryLoadMore,
                child: Text(t.searchResult.retry),
              ),
            ),
          ),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0 ||
            notification.metrics.axis != Axis.vertical ||
            notification.metrics.maxScrollExtent <= 0) {
          return false;
        }
        if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent * 0.9) {
          onReachBottom();
        }
        return false;
      },
      child: CustomScrollView(
        physics: physics ?? const AlwaysScrollableScrollPhysics(),
        shrinkWrap: shrinkWrap,
        slivers: children,
      ),
    );
  }

  // 所有纵向节点共用一个 viewport；不能在列表里嵌 shrinkWrap 网格，
  // 否则分页累计的封面会全部创建、布局和订阅下载状态。
  Iterable<Widget> _buildSlivers(
    BuildContext context, {
    required Map<String, dynamic> node,
    required Map<String, dynamic> data,
    required String from,
    required Future<void> Function(Map<String, dynamic> action) onAction,
  }) sync* {
    switch (node['type']?.toString() ?? '') {
      case 'list':
        for (final item in asJsonList(node['children'])) {
          yield* _buildSlivers(
            context,
            node: asJsonMap(item),
            data: data,
            from: from,
            onAction: onAction,
          );
        }
      case 'chip-list':
        yield SliverToBoxAdapter(
          child: _buildChipList(context, _resolveItems(node, data), onAction),
        );
      case 'action-grid':
        yield _buildActionGrid(
          context,
          _resolveItems(node, data),
          from,
          onAction,
        );
      case 'comic-section-list':
        yield _buildComicSectionList(
          context,
          _resolveItems(node, data),
          from,
          onAction,
        );
      case 'comic-grid':
        final items = _resolveItems(node, data);
        if (items.isEmpty) return;
        final title = node['title']?.toString() ?? '';
        final action = asJsonMap(node['action']);
        if (title.trim().isNotEmpty) {
          yield SliverToBoxAdapter(
            child: SectionHeader(
              title: title.let(convertChineseForDisplay),
              onTap: _isActionable(action) ? () => onAction(action) : null,
            ),
          );
        }
        yield BaseComicGridSliver(
          entries: mapToUnifiedComicSimplifyEntryInfoList(items),
          type: ComicEntryType.normal,
        );
    }
  }

  Widget _buildChipList(
    BuildContext context,
    List<Map<String, dynamic>> items,
    Future<void> Function(Map<String, dynamic> action) onAction,
  ) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Wrap(
        spacing: 10,
        runSpacing: 5,
        children: items.map((item) {
          final label = item['label']?.toString() ?? '';
          return GestureDetector(
            onTap: () => onAction(asJsonMap(item['action'])),
            child: Chip(
              backgroundColor: context.backgroundColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              label: Text(
                label.let(convertChineseForDisplay),
                style: TextStyle(
                  fontSize: 12,
                  color: context.theme.colorScheme.primary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActionGrid(
    BuildContext context,
    List<Map<String, dynamic>> items,
    String from,
    Future<void> Function(Map<String, dynamic> action) onAction,
  ) {
    if (items.isEmpty) {
      return const SliverToBoxAdapter();
    }

    const spacing = 12.0;

    return SliverPadding(
      padding: const EdgeInsets.all(spacing),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 150,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          childAspectRatio: 0.8,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final item = items[index];
          final title = item['title']?.toString() ?? '';
          final cover = asJsonMap(item['cover']);
          final coverUrl = cover['url']?.toString().trim() ?? '';
          final coverPath = cover['path']?.toString().trim() ?? '';

          return GestureDetector(
            onTap: () => onAction(asJsonMap(item['action'])),
            child: Column(
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LayoutBuilder(
                      builder: (context, constraints) => CoverWidget(
                        fileServer: coverUrl,
                        path: coverPath,
                        id: title,
                        pictureType: PictureType.category,
                        from: from,
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  title.let(convertChineseForDisplay),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.textColor, fontSize: 14),
                ),
              ],
            ),
          );
        }, childCount: items.length),
      ),
    );
  }

  Widget _buildComicSectionList(
    BuildContext context,
    List<Map<String, dynamic>> sections,
    String from,
    Future<void> Function(Map<String, dynamic> action) onAction,
  ) {
    if (sections.isEmpty) {
      return const SliverToBoxAdapter();
    }

    return SliverList.builder(
      itemCount: sections.length,
      itemBuilder: (context, index) {
        final section = sections[index];
        final title = section['title']?.toString() ?? '';
        final subtitle = section['subtitle']?.toString() ?? '';
        final items = asJsonList(
          section['items'],
        ).map((item) => asJsonMap(item)).toList();
        final entries = mapToUnifiedComicSimplifyEntryInfoList(items);

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: title.let(convertChineseForDisplay),
                subtitle: subtitle.let(convertChineseForDisplay),
                onTap: _isActionable(section['action'])
                    ? () => onAction(asJsonMap(section['action']))
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: ComicFixedSizeHorizontalList(
                  entries: entries,
                  spacing: 10,
                  itemWidth: (isTabletWithOutContext() ? 200 : 150) * 0.75,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _resolveItems(
    Map<String, dynamic> node,
    Map<String, dynamic> data,
  ) {
    final key = node['key']?.toString() ?? '';
    if (key.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    return asJsonList(data[key]).map((item) => asJsonMap(item)).toList();
  }

  bool _isActionable(dynamic value) {
    final action = asJsonMap(value);
    final type = action['type']?.toString().trim() ?? '';
    return type.isNotEmpty && type != 'none';
  }
}
