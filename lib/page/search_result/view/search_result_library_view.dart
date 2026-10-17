import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_list/view/discover_library_entries.dart';
import 'package:zephyr/page/comic_list/view/discover_library_view.dart';
import 'package:zephyr/page/comic_list/view/plugin_comic_grid_sliver.dart';
import 'package:zephyr/page/search_result/bloc/search_bloc.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_mapper.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';

/// 搜索只适配结果与分页状态，封面、信息按钮和原位详情沿用发现展墙。
class SearchResultLibraryView extends StatelessWidget {
  const SearchResultLibraryView({
    super.key,
    required this.state,
    required this.canvasKey,
    required this.controller,
    required this.source,
    required this.onLoadMore,
    required this.onRetryLoadMore,
  });

  final SearchState state;
  final GlobalKey<LibraryEditorialCanvasState> canvasKey;
  final ScrollController controller;
  final String source;
  final VoidCallback onLoadMore, onRetryLoadMore;

  @override
  Widget build(BuildContext context) {
    // 搜索历史更新不应重新计算整面的高亮信号。
    final (artists, tags, chineseMode) = context.select(
      (GlobalSettingCubit cubit) => (
        cubit.state.favoriteArtistSetting,
        cubit.state.favoriteTagSetting,
        cubit.state.chineseConvertMode,
      ),
    );
    final settings = GlobalSettingState(
      favoriteArtistSetting: artists,
      favoriteTagSetting: tags,
      chineseConvertMode: chineseMode,
    );
    final entries = mapToUnifiedComicSimplifyEntryInfoList(
      state.comics.map((item) => item.comic),
    );
    return DiscoverLibraryView(
      canvasKey: canvasKey,
      scrollController: controller,
      scope: 'search:$source',
      entries: [
        for (final info in entries) discoverLibraryEntry(info, settings),
      ],
      onReachEnd: () {
        if (state.status == SearchStatus.success && !state.hasReachedMax) {
          onLoadMore();
        }
      },
      footerBuilder: (_) => _footer(),
      legacyBuilder: (_) => PluginComicGridSliver(
        controller: controller,
        entries: entries,
        hasReachedMax: state.hasReachedMax,
        isLoadingMore: state.status == SearchStatus.loadingMore,
        loadMoreFailed: state.status == SearchStatus.getMoreFailure,
        onRetryLoadMore: onRetryLoadMore,
        onLoadMore: onLoadMore,
      ),
    );
  }

  Widget _footer() => Padding(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: switch (state.status) {
        SearchStatus.loadingMore => const CircularProgressIndicator(),
        SearchStatus.getMoreFailure => FilledButton.tonal(
          onPressed: onRetryLoadMore,
          child: Text(t.oldHome.loadMoreFailed),
        ),
        _ when state.hasReachedMax => Text(t.oldHome.noMore),
        _ => TextButton(onPressed: onLoadMore, child: Text(t.oldHome.loadMore)),
      },
    ),
  );
}
