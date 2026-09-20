import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_info/view/comic_info.dart';
import 'package:zephyr/page/comic_list/models/comic_list_scene.dart';
import 'package:zephyr/page/comic_list/view/comic_list_page.dart';
import 'package:zephyr/page/discover/cubit/discover_tab_cubit.dart';
import 'package:zephyr/page/plugin_function/view/plugin_function_page.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/page/search_result/bloc/search_bloc.dart';
import 'package:zephyr/page/search_result/view/search_result_page.dart';
import 'package:zephyr/page/webview_page.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/json/json_value.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/widgets/toast.dart';

import 'package:zephyr/page/discover/view/plugin_function_dialog.dart';

/// Discover 页插件动作路由。
///
/// 把插件返回的 action 协议转换为具体页面跳转，与 UI 解耦，方便集中维护。
///
/// 两种落点，由调用方给不给 [DiscoverTabCubit] 决定：
/// - 给了 ⇒ 开成**一条标签**（发现页现在的形态）；
/// - 没给 ⇒ 照旧 `context.pushRoute` 推一整页。
/// 保留后一条不是因为还有别人在用它（没有），而是因为
/// `presentation: 'dialog'` 那一档本来就不该占一条标签。
class DiscoverRouter {
  DiscoverRouter._();

  static Future<void> route(
    BuildContext context, {
    required Map<String, dynamic> action,
    required String currentFrom,
    DiscoverTabCubit? tabs,
  }) async {
    final type = action['type']?.toString() ?? '';

    if (type == 'none' || type.isEmpty) {
      return;
    }

    switch (type) {
      case 'openSearch':
        await _openSearch(context, asJsonMap(action['payload']), tabs: tabs);
      case 'openWeb':
        await _openWeb(context, asJsonMap(action['payload']), tabs: tabs);
      case 'openPluginFunction':
        await _openPluginFunction(
          context,
          asJsonMap(action['payload']),
          currentFrom: currentFrom,
          tabs: tabs,
        );
      case 'openCloudFavorite':
        await _openCloudFavorite(
          context,
          asJsonMap(action['payload']),
          currentFrom: currentFrom,
          tabs: tabs,
        );
      case 'openComicList':
        await _openComicList(context, asJsonMap(action['payload']), tabs: tabs);
      case 'openComicInfo':
        await _openComicInfo(context, asJsonMap(action['payload']), tabs: tabs);
    }
  }

  /// 为需要插件来源的动作自动补全 source。
  static Map<String, dynamic> attachSource(
    Map<String, dynamic> action,
    String from,
  ) {
    final type = action['type']?.toString().trim() ?? '';
    if (type != 'openPluginFunction' &&
        type != 'openCloudFavorite' &&
        type != 'openSearch' &&
        type != 'openComicList' &&
        type != 'openComicInfo') {
      return action;
    }

    final payload = Map<String, dynamic>.from(asJsonMap(action['payload']));
    payload['source'] = from;

    if (type == 'openComicList') {
      final scene = Map<String, dynamic>.from(asJsonMap(payload['scene']));
      scene['source'] = from;
      payload['scene'] = scene;
    }

    return Map<String, dynamic>.from(action)..['payload'] = payload;
  }

  static Future<void> _openSearch(
    BuildContext context,
    Map<String, dynamic> payload, {
    DiscoverTabCubit? tabs,
  }) async {
    final source = _sourceFromString(payload['source']?.toString());
    final extern = _normalizeOpenSearchExtern(payload);
    final keywordFromPayload = payload['keyword']?.toString() ?? '';
    final keywordFromExtern = extern['keyword']?.toString() ?? '';
    final keyword = keywordFromPayload.isNotEmpty
        ? keywordFromPayload
        : keywordFromExtern;

    final searchStates = SearchStates.initial().copyWith(
      from: source,
      searchKeyword: keyword,
      pluginExtern: extern,
    );

    if (!context.mounted) {
      return;
    }
    final event = SearchEvent().copyWith(searchStates: searchStates);
    if (tabs != null) {
      // 标签标题用关键词：同时开几个搜索各查一个词，靠标题才分得开。
      tabs.open(
        label: keyword.trim().isEmpty ? t.discover.search : keyword.trim(),
        source: source,
        content: (context) =>
            SearchResultPage(searchEvent: event).wrappedRoute(context),
      );
      return;
    }
    context.pushRoute(SearchResultRoute(searchEvent: event));
  }

  static Future<void> _openWeb(
    BuildContext context,
    Map<String, dynamic> payload, {
    DiscoverTabCubit? tabs,
  }) async {
    final title = payload['title']?.toString() ?? '';
    final url = payload['url']?.toString() ?? '';
    if (url.isEmpty) {
      return;
    }

    if (!context.mounted) {
      return;
    }
    if (tabs != null) {
      tabs.open(
        label: title.isEmpty ? t.discover.webPage : title,
        source: _sourceFromString(payload['source']?.toString()),
        content: (context) => WebViewPage(info: [title, url]),
      );
      return;
    }
    context.pushRoute(WebViewRoute(info: [title, url]));
  }

  static Future<void> _openPluginFunction(
    BuildContext context,
    Map<String, dynamic> payload, {
    required String currentFrom,
    DiscoverTabCubit? tabs,
  }) async {
    final source = _sourceFromString(payload['source']?.toString());
    if (source.isEmpty) {
      showErrorToast(t.error.missingPluginSource(action: t.oldHome.function));
      return;
    }

    final functionId = payload['id']?.toString().trim() ?? '';
    if (functionId.isEmpty) {
      return;
    }
    final title = payload['title']?.toString().trim() ?? t.oldHome.function;
    final presentation = payload['presentation']?.toString().trim() ?? 'page';

    Future<void> onAction(Map<String, dynamic> action) => route(
      context,
      action: attachSource(action, source),
      currentFrom: currentFrom,
      tabs: tabs,
    );

    if (presentation != 'dialog') {
      if (!context.mounted) {
        return;
      }
      if (tabs != null) {
        tabs.open(
          label: title,
          source: source,
          content: (context) => PluginFunctionPage(
            from: source,
            functionId: functionId,
            title: title,
            onAction: onAction,
          ),
        );
        return;
      }
      await context.pushRoute(
        PluginFunctionRoute(
          from: source,
          functionId: functionId,
          title: title,
          onAction: onAction,
        ),
      );
      return;
    }

    if (!context.mounted) {
      return;
    }
    final mediaSize = MediaQuery.sizeOf(context);
    final dialogWidth = (mediaSize.width * 0.9).clamp(280.0, 560.0).toDouble();

    await showDialog<void>(
      context: context,
      builder: (context) => PluginFunctionDialog(
        from: source,
        functionId: functionId,
        title: title,
        onAction: onAction,
        dialogWidth: dialogWidth,
      ),
    );
  }

  static Future<void> _openCloudFavorite(
    BuildContext context,
    Map<String, dynamic> payload, {
    required String currentFrom,
    DiscoverTabCubit? tabs,
  }) async {
    final parsed = _sourceFromString(payload['source']?.toString());
    final source = parsed.isEmpty ? currentFrom : parsed;
    if (source.isEmpty) {
      showErrorToast(
        t.error.missingPluginSource(action: t.oldHome.cloudFavorite),
      );
      return;
    }

    final title = payload['title']?.toString();

    if (!context.mounted) {
      return;
    }
    if (tabs != null) {
      tabs.open(
        label: title ?? t.oldHome.cloudFavorite,
        source: source,
        content: (context) => ComicListPage(
          title: title ?? t.oldHome.cloudFavorite,
          sceneSource: source,
          sceneBundleFnPath: 'getCloudFavoriteSceneBundle',
          sceneBundleFnPathFallback: 'get_cloud_favorite_scene_bundle',
        ),
      );
      return;
    }
    context.pushRoute(
      ComicListRoute(
        title: title ?? t.oldHome.cloudFavorite,
        sceneSource: source,
        sceneBundleFnPath: 'getCloudFavoriteSceneBundle',
        sceneBundleFnPathFallback: 'get_cloud_favorite_scene_bundle',
      ),
    );
  }

  static Future<void> _openComicList(
    BuildContext context,
    Map<String, dynamic> payload, {
    DiscoverTabCubit? tabs,
  }) async {
    final scene = ComicListScene.fromMap(asJsonMap(payload['scene']));

    if (!context.mounted) {
      return;
    }
    if (tabs != null) {
      tabs.open(
        label: scene.title.isEmpty ? t.comicList.defaultTitle : scene.title,
        source: scene.from,
        content: (context) => ComicListPage(scene: scene, title: scene.title),
      );
      return;
    }
    context.pushRoute(ComicListRoute(scene: scene, title: scene.title));
  }

  static Future<void> _openComicInfo(
    BuildContext context,
    Map<String, dynamic> payload, {
    DiscoverTabCubit? tabs,
  }) async {
    final comicId = payload['comicId']?.toString().trim() ?? '';
    if (comicId.isEmpty) {
      return;
    }

    final source = _sourceFromString(payload['source']?.toString());
    if (source.isEmpty) {
      return;
    }

    if (!context.mounted) {
      return;
    }
    if (tabs != null) {
      openComicInfoTab(
        tabs,
        comicId: comicId,
        from: source,
        title: payload['title']?.toString().trim() ?? '',
      );
      return;
    }
    context.pushRoute(
      ComicInfoRoute(
        comicId: comicId,
        from: source,
        type: ComicEntryType.normal,
      ),
    );
  }

  /// 开一条漫画详情标签。发现页的标签体系与漫画卡片共用这一个口子。
  static void openComicInfoTab(
    DiscoverTabCubit tabs, {
    required String comicId,
    required String from,
    required String title,
    String? collectionTargetId,
    String? collectionTargetName,
  }) {
    tabs.open(
      label: title.isEmpty ? t.discover.comicDetail : title,
      source: from,
      content: (context) => ComicInfoPage(
        comicId: comicId,
        from: from,
        type: ComicEntryType.normal,
        collectionTargetId: collectionTargetId,
        collectionTargetName: collectionTargetName,
      ),
    );
  }

  static Map<String, dynamic> _normalizeOpenSearchExtern(
    Map<String, dynamic> payload,
  ) {
    final extern = Map<String, dynamic>.from(asJsonMap(payload['extern']));
    for (final entry in payload.entries) {
      final key = entry.key.toString();
      if (key == 'source' || key == 'extern' || extern.containsKey(key)) {
        continue;
      }
      final value = entry.value;
      if (value == null) {
        continue;
      }
      if (value is String && value.trim().isEmpty) {
        continue;
      }
      extern[key] = value;
    }

    return extern;
  }

  static String _sourceFromString(String? source) {
    return (source ?? '').trim();
  }
}
