import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/network/http/plugin/unauthorized_payload.dart';
import 'package:zephyr/network/http/plugin/unified_comic_plugin.dart';
import 'package:zephyr/network/http/plugin/unified_plugin_envelope.dart';
import 'package:zephyr/page/comic_list/cubit/plugin_paged_comic_list_state.dart';
import 'package:zephyr/util/error_filter.dart';
import 'package:zephyr/util/json/json_dispose.dart';
import 'package:zephyr/util/json/json_value.dart';
import 'package:zephyr/widgets/comic_entry/models/models.dart';

typedef PluginPageCoreBuilder = Map<String, dynamic> Function(int page);
typedef PluginPageExternBuilder = Map<String, dynamic> Function(int page);

Map<String, dynamic> _sanitizePluginItemMap(dynamic item) {
  return asJsonMap(replaceNestedNullList(asJsonMap(item)));
}

class PluginPagedComicListCubit extends Cubit<PluginPagedComicListState> {
  PluginPagedComicListCubit({
    required this.pluginId,
    required this.fnPath,
    required this.coreBuilder,
    required this.externBuilder,
    this.pageFetcher,
    // 新两页内的列表传 true：登录错误不出全局弹窗，由外层出登录/刷新按钮。
    this.suppressNeedLoginEvent = false,
  }) : super(const PluginPagedComicListState());

  final String pluginId;
  final String fnPath;
  final PluginPageCoreBuilder coreBuilder;
  final PluginPageExternBuilder externBuilder;
  final bool suppressNeedLoginEvent;

  /// 可注入请求消费者，分页策略测试不需要启动 QuickJS。
  final Future<Map<String, dynamic>> Function(int page)? pageFetcher;
  final _pageStarts = <int, int>{};
  int _generation = 0;
  int? totalPages;

  int pageForIndex(int index) {
    var page = _pageStarts.keys.firstOrNull ?? state.page;
    for (final entry in _pageStarts.entries) {
      if (index < entry.value) break;
      page = entry.key;
    }
    return page;
  }

  /// 单次遍历生成条目所属页，避免累计多页后逐项重扫所有分页边界。
  Map<String, int> get entryPages {
    final starts = _pageStarts.entries.toList();
    final pages = <String, int>{};
    var boundary = 0;
    for (var i = 0; i < state.list.length; i++) {
      while (boundary + 1 < starts.length && starts[boundary + 1].value <= i) {
        boundary++;
      }
      final item = state.list[i];
      pages['${item.source.trim()}:${item.id}'] = starts.isEmpty
          ? state.page
          : starts[boundary].key;
    }
    return pages;
  }

  Future<void> loadInitial() => jumpToPage(1);

  Future<void> jumpToPage(int page) async {
    if (isClosed || page < 1 || (totalPages != null && page > totalPages!)) {
      return;
    }
    final generation = ++_generation;
    _pageStarts.clear();
    totalPages = null;
    _safeEmit(
      state.copyWith(
        status: PluginPagedComicListStatus.initial,
        list: const <UnifiedComicListItem>[],
        hasReachedMax: false,
        page: page,
        result: '',
        loginPluginId: '',
      ),
    );
    await _fetchPage(page: page, append: false, generation: generation);
  }

  Future<void> loadMore() async {
    if (isClosed ||
        state.hasReachedMax ||
        (state.status != PluginPagedComicListStatus.success &&
            state.status != PluginPagedComicListStatus.loadingMoreFailure)) {
      return;
    }

    _safeEmit(state.copyWith(status: PluginPagedComicListStatus.loadingMore));
    await _fetchPage(
      page: state.page + 1,
      append: true,
      generation: _generation,
    );
  }

  Future<void> retryLoadMore() async {
    await loadMore();
  }

  Future<void> _fetchPage({
    required int page,
    required bool append,
    required int generation,
  }) async {
    final currentList = append ? state.list : const <UnifiedComicListItem>[];
    final resolvedFnPath = fnPath.trim();

    try {
      if (resolvedFnPath.isEmpty) {
        throw StateError('插件列表请求缺少 fnPath: pluginId=$pluginId');
      }
      final pluginResponse = pageFetcher != null
          ? await pageFetcher!(page)
          : await callUnifiedComicPlugin(
              pluginId: pluginId,
              fnPath: resolvedFnPath,
              core: coreBuilder(page),
              extern: externBuilder(page),
              suppressNeedLoginEvent: suppressNeedLoginEvent,
            );
      if (isClosed || generation != _generation) return;
      final envelope = UnifiedPluginEnvelope.fromMap(pluginResponse);
      final data = asJsonMap(envelope.data);
      final source = envelope.source.trim().isNotEmpty
          ? envelope.source.trim()
          : pluginId;
      final items = asJsonList(
        data['items'],
      ).map(_sanitizePluginItemMap).toList();
      final raw = replaceNestedNullList(asJsonMap(data['raw']));
      final listLikeKeys = ['content', 'list'];

      List<UnifiedComicListItem> nextItems = items
          .map((item) => unifiedComicFromPluginListMap(item, source: source))
          .toList();
      if (nextItems.isEmpty) {
        for (final key in listLikeKeys) {
          final rawList = asJsonList(
            raw[key],
          ).map(_sanitizePluginItemMap).toList();
          if (rawList.isNotEmpty) {
            nextItems = rawList
                .map(
                  (item) => unifiedComicFromPluginListMap(item, source: source),
                )
                .toList();
            break;
          }
        }
      }

      final mergedList = [...currentList, ...nextItems];
      final rawTotal =
          data['totalPages'] ??
          data['pageCount'] ??
          raw['totalPages'] ??
          raw['pageCount'];
      final parsedTotal = int.tryParse(rawTotal?.toString() ?? '');
      if (parsedTotal != null && parsedTotal > 0) totalPages = parsedTotal;
      final hasReachedMax =
          data['hasReachedMax'] == true ||
          nextItems.isEmpty ||
          (totalPages != null && page >= totalPages!);
      _pageStarts[page] = currentList.length;

      _safeEmit(
        state.copyWith(
          status: PluginPagedComicListStatus.success,
          list: mergedList,
          hasReachedMax: hasReachedMax,
          page: page,
          result: page.toString(),
        ),
      );
    } catch (e, stackTrace) {
      if (isClosed || generation != _generation) return;
      logger.e(e, stackTrace: stackTrace);

      // 只认类型化错误（callUnifiedComicPlugin 已识别好），不做二次解析。
      var loginPluginId = '';
      if (e is PluginUnauthorizedException) {
        final id = e.pluginId.trim();
        loginPluginId = id.isNotEmpty ? id : pluginId;
      }
      _safeEmit(
        state.copyWith(
          status: currentList.isNotEmpty
              ? PluginPagedComicListStatus.loadingMoreFailure
              : PluginPagedComicListStatus.failure,
          list: currentList,
          result: normalizeSearchErrorMessage(e),
          loginPluginId: loginPluginId,
        ),
      );
    }
  }

  void _safeEmit(PluginPagedComicListState nextState) {
    if (isClosed) {
      return;
    }
    emit(nextState);
  }
}
