import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/path_util.dart';

/// 工作台里的卡片（收藏 / 历史 / 下载 / 本地）统一用它打开一本漫画。
///
/// 两条分支必须与 `ComicEntryWidget`、`ComicSimplifyEntry` 一致：
///
/// - **本地来源**（`from == 'local'`，或 comicId 本身就是路径 / 归档）**没有插件**。
///   送进详情页会被当成「插件 id = local」去问 qjs 运行时，拿到
///   `plugin_not_found:local`，界面上只剩一句「加载失败，请重试」——
///   所以本地直接进阅读器。
/// - **插件来源**走上游详情页，由详情页的「开始阅读」进阅读器。
///
/// 「直接进阅读器」推的仍是**上游的** `ComicReadRoute`：工作台在场时，根路由守卫会把它
/// 改派进阅读器泳道；工作台不在场时就是普通的全屏阅读。
/// 所以这里**不需要**知道工作台在不在 —— 判断只在守卫那一处。
void openComicItem(
  BuildContext context, {
  required String comicId,
  required String from,
  ComicEntryType type = ComicEntryType.normal,
}) {
  if (isLocalComicSource(from, comicId)) {
    context.pushRoute(
      ComicReadRoute(
        comicId: comicId,
        order: 0,
        from: 'local',
        epsNumber: 1,
        type: type,
        comicInfo: comicId,
        stringSelectCubit: StringSelectCubit(),
      ),
    );
    return;
  }

  context.pushRoute(ComicInfoRoute(comicId: comicId, from: from, type: type));
}
