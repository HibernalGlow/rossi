import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/workspace/router/workspace_reader_guard.dart';

@AutoRouterConfig(replaceInRouteName: 'Screen|Page,Route')
class AppRouter extends RootStackRouter {
  @override
  RouteType get defaultRouteType =>
      RouteType.material(enablePredictiveBackGesture: false);

  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: AppBootstrapRoute.page, initial: true),
    AutoRoute(page: CoreMLUpscaleDebugRoute.page),
    AutoRoute(page: NavigationBar.page),
    AutoRoute(page: LoginRoute.page),
    AutoRoute(page: ComicListRoute.page),
    AutoRoute(page: DiscoverRoute.page),
    AutoRoute(page: SearchResultRoute.page),
    AutoRoute(page: SearchAggregateResultRoute.page),
    AutoRoute(page: ComicInfoRoute.page),
    AutoRoute(page: DownloadRoute.page),
    AutoRoute(page: CommentsRoute.page),
    AutoRoute(page: PluginCommentsScaffoldRoute.page),
    AutoRoute(page: ComicReadRoute.page),
    AutoRoute(page: WebViewRoute.page),
    AutoRoute(page: GlobalSettingRoute.page),
    AutoRoute(page: AppearanceSettingRoute.page),
    AutoRoute(page: ContentNetworkSettingRoute.page),
    AutoRoute(page: SyncSettingRoute.page),
    AutoRoute(page: AppBehaviorSettingRoute.page),
    AutoRoute(page: StorageSettingRoute.page),
    AutoRoute(page: DebugSettingRoute.page),
    AutoRoute(page: ThemeColorRoute.page),
    AutoRoute(page: WebDavSyncRoute.page),
    AutoRoute(page: ShowColorRoute.page),
    AutoRoute(page: AboutRoute.page),
    AutoRoute(page: FullRouteImageRoute.page),
    AutoRoute(page: ChangelogRoute.page),
    AutoRoute(page: SearchRoute.page),
    AutoRoute(page: DownloadTaskRoute.page),
    AutoRoute(page: PluginStoreRoute.page),
    AutoRoute(page: PluginSettingsRoute.page),
    AutoRoute(page: PluginFunctionRoute.page),
    AutoRoute(page: OldHomeRoute.page),
    AutoRoute(page: OldRankingRoute.page),
    AutoRoute(page: MoreRoute.page),
    AutoRoute(page: QjsRuntimeDebugRoute.page),
    AutoRoute(page: CacheSettingRoute.page),
    AutoRoute(page: RealSrSettingRoute.page),
    AutoRoute(page: BookshelfSettingRoute.page),
    AutoRoute(page: DataBackupRoute.page),
    AutoRoute(page: ComicFollowRoute.page),
  ];

  /// 全站仅此一个守卫：[WorkspaceReaderGuard]。
  ///
  /// 它只在**工作台挂载期间**生效，把 `ComicReadRoute` 的推入改派进工作台的阅读器泳道，
  /// 于是「中央泳道 = Reader」这件事不需要改动任何一个上游页面
  /// （书架 / 发现 / 历史推阅读器的方式一个字都没动）。
  /// 工作台不在场时它原样放行，全屏阅读器的行为完全不变。
  @override
  List<AutoRouteGuard> get guards => const [WorkspaceReaderGuard()];
}

void popToRoot(BuildContext context) {
  context.router.popUntil((route) => route.settings.name == 'NavigationBar');
}
