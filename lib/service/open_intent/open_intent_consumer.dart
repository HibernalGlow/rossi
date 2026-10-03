import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/service/open_intent/open_intents.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/widgets/toast.dart';

/// 把 [OpenIntents] 里递来的路径接进阅读器。**必须在首页挂载**（`NavigationBar`）。
///
/// 为什么不是 `main()` 里直接开：`ComicReadRoute` 走的是 `context.pushRoute`，
/// 而那个查询要求 context 已经在 `AutoRoutePage` 之下（工作台里「搜索」标签就是这么
/// 炸成红屏的，见 `lib/workspace/router/workspace_route_guard.dart` 的说明）。
/// 首页是唯一保证已经在那之下的时机。
///
/// 返回订阅句柄，由首页的 `dispose` 取消 —— 首页重建时旧订阅还在的话，
/// 一条路径会被两个 context 各开一次。
StreamSubscription<List<String>> bindOpenIntents(BuildContext context) {
  void open(List<String> paths) {
    if (paths.isEmpty || !context.mounted) return;

    final target = paths.first;
    if (paths.length > 1) {
      showInfoToast(t.settings.openIntentMultiSkipped(count: paths.length - 1));
    }

    if (FileSystemEntity.typeSync(target) == FileSystemEntityType.notFound) {
      showErrorToast(t.settings.openIntentMissing(path: target));
      return;
    }

    // 参数表与首页那枚「打开本地漫画」按钮逐字一致（`navigation_bar.dart` 的
    // folder_open 那一项）：同一个入口的两条来路不该走到两个不同的阅读器配置上。
    context.pushRoute(
      ComicReadRoute(
        comicId: target,
        order: 0,
        from: 'local',
        epsNumber: 1,
        type: ComicEntryType.normal,
        comicInfo: target,
        stringSelectCubit: StringSelectCubit(),
      ),
    );
  }

  final subscription = OpenIntents.instance.arrivals.listen(open);
  // 冷启动攒下的那一条：等首页真挂上之后再来取。macOS 这里还要**再向原生要一次** ——
  // 原生挂通道的时机可能比 Dart 的 `main()` 晚，那批路径只有现在才取得到。
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await OpenIntents.instance.pullMacQueue();
    open(OpenIntents.instance.takeAll());
  });
  return subscription;
}
