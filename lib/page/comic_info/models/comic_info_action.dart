import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_list/models/comic_list_scene.dart';
import 'package:zephyr/page/comic_list/view/comic_list_page.dart';
import 'package:zephyr/page/discover/service/discover_tab_scope.dart';
import 'package:zephyr/page/download/method/comic_download_entry.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/page/search_result/bloc/search_bloc.dart';
import 'package:zephyr/page/search_result/view/search_result_page.dart';
import 'package:zephyr/page/webview_page.dart';
import 'package:zephyr/util/json/json_value.dart';
import 'package:zephyr/widgets/toast.dart';

/// 详情页里一颗胶囊/画师卡被点下去之后做什么。
///
/// 三种跳页动作（搜索、网页、漫画列表）都先问一句 [DiscoverTabScope]：详情页
/// 自己可能就开在发现页的一条标签里，那时路由推出去会落在标签条**外面**
/// （工作台里压进所在面板的局部栈、手机上压上根栈），眼前这本书被盖掉。
/// 口径与 `on_search.dart`、`DiscoverRouter` 一致：在标签里就开成一条新标签。
Future<void> handleComicInfoAction(
  BuildContext context,
  Map<String, dynamic> action, {
  required String fallbackPluginId,
}) async {
  final type = action['type']?.toString().trim() ?? '';
  final payload = asJsonMap(action['payload']);
  final tabs = DiscoverTabScope.maybeOf(context);

  if (type.isEmpty || type == 'none') {
    return;
  }

  if (type == 'copyText') {
    final text = payload['text']?.toString() ?? '';
    if (text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) {
      return;
    }
    showSuccessToast(
      t.comicInfo.copiedToClipboard(name: text),
      context: context,
    );
    return;
  }

  if (type == 'openSearch') {
    final pluginId = _sourceIdFromString(
      payload['source']?.toString(),
      fallbackPluginId,
    );
    final keyword = payload['keyword']?.toString() ?? '';
    final externPatch = asJsonMap(payload['extern']);

    final searchStates = SearchStates.initial().copyWith(
      from: pluginId,
      searchKeyword: keyword,
      pluginExtern: externPatch,
    );

    final event = SearchEvent().copyWith(searchStates: searchStates);
    if (tabs != null) {
      final trimmed = keyword.trim();
      tabs.openPage(
        label: trimmed.isEmpty ? t.discover.search : trimmed,
        source: pluginId,
        content: (context) =>
            SearchResultPage(searchEvent: event).wrappedRoute(context),
      );
      return;
    }

    context.pushRoute(SearchResultRoute(searchEvent: event));
    return;
  }

  if (type == 'openWeb') {
    final title = payload['title']?.toString() ?? '';
    final url = payload['url']?.toString() ?? '';
    if (url.isEmpty) {
      return;
    }

    if (tabs != null) {
      tabs.openPage(
        label: title.isEmpty ? t.discover.webPage : title,
        source: _sourceIdFromString(
          payload['source']?.toString(),
          fallbackPluginId,
        ),
        content: (context) => WebViewPage(info: [title, url]),
      );
      return;
    }

    context.pushRoute(WebViewRoute(info: [title, url]));

    return;
  }

  if (type == 'openComicList') {
    final sceneMap = Map<String, dynamic>.from(asJsonMap(payload['scene']));
    if ((sceneMap['source']?.toString().trim() ?? '').isEmpty) {
      sceneMap['source'] = fallbackPluginId;
    }
    final scene = ComicListScene.fromMap(sceneMap);
    if (tabs != null) {
      tabs.openPage(
        label: scene.title.isEmpty ? t.comicList.defaultTitle : scene.title,
        source: scene.from,
        content: (context) => ComicListPage(scene: scene, title: scene.title),
      );
      return;
    }
    context.pushRoute(ComicListRoute(scene: scene, title: scene.title));
  }

  if (type == 'downloadComic') {
    final comicId = payload['comicId']?.toString().trim() ?? '';
    if (comicId.isEmpty) {
      return;
    }
    final source = _sourceIdFromString(
      payload['source']?.toString(),
      fallbackPluginId,
    );
    // 胶囊点一下就按这条入口指定的方式整本下载：章节列表缺省时
    // startComicDownloadAll 会自己回源问插件详情，调用方不必先备好数据。
    // payload.extern 会并进任务章节 extern，最终原样带回插件的 getChapter。
    await startComicDownloadAll(
      context: context,
      from: source,
      comicId: comicId,
      comicName: payload['title']?.toString().trim() ?? '',
      taskExtern: asJsonMap(payload['extern']),
    );
    return;
  }
}

String _sourceIdFromString(String? source, String fallbackPluginId) {
  final resolved = (source ?? '').trim();
  return resolved.isEmpty ? fallbackPluginId : resolved;
}
