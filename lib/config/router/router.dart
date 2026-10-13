import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/page/setting/common/setting_route.dart';
import 'package:zephyr/workspace/router/workspace_back_interception.dart';
import 'package:zephyr/workspace/router/workspace_route_guard.dart';

/// 无动画路由过渡：直接返回页面本身，不消费动画值。
Widget instantRouteTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  return child;
}

@AutoRouterConfig(replaceInRouteName: 'Screen|Page,Route')
class AppRouter extends RootStackRouter with WorkspaceBackInterceptor {
  @override
  RouteType get defaultRouteType {
    // 墨水屏：路由直接出图，不留 300ms 的滑动/淡入中间帧。
    if (eInkInstantRoutes) {
      return RouteType.custom(
        opaque: true,
        transitionsBuilder: instantRouteTransition,
        duration: Duration.zero,
        reverseDuration: Duration.zero,
      );
    }
    return RouteType.material(enablePredictiveBackGesture: false);
  }

  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: AppBootstrapRoute.page, initial: true),
    AutoRoute(page: CoreMLUpscaleDebugRoute.page),
    AutoRoute(page: NavigationBar.page),
    // 工作台必须走路由表注册：它摊的是上游原版页面，而那些页面按 auto_route 的
    // 常规写法查自己所在的路由（`context.routeData`，见上游 `SearchQueryField` 用的
    // `AutoRouteAwareStateMixin`）。手工 `Navigator.push` 的一页不在 `AutoRoutePage`
    // 之下，那个查询会直接抛成红屏（工作台里的「搜索」标签就是这么炸的）。
    AutoRoute(page: BreezeWorkspaceRoute.page),
    AutoRoute(page: LoginRoute.page),
    AutoRoute(page: ComicListRoute.page),
    AutoRoute(page: DiscoverRoute.page),
    AutoRoute(page: SearchResultRoute.page),
    AutoRoute(page: SearchAggregateResultRoute.page),
    AutoRoute(page: ComicInfoRoute.page),
    AutoRoute(page: CommentsRoute.page),
    AutoRoute(page: PluginCommentsScaffoldRoute.page),
    AutoRoute(page: ComicReadRoute.page),
    AutoRoute(page: WebViewRoute.page),
    CustomRoute(
      page: GlobalSettingRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    CustomRoute(
      page: AppearanceSettingRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    CustomRoute(
      page: ToastSettingRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    CustomRoute(
      page: NotifySettingRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    CustomRoute(
      page: WorkspaceLayoutSettingRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    CustomRoute(
      page: FileManagerSettingRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    CustomRoute(
      page: ContentNetworkSettingRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    CustomRoute(
      page: FavoriteArtistSettingRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    CustomRoute(
      page: FavoriteTagSettingRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    CustomRoute(
      page: SyncSettingRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    CustomRoute(
      page: AppBehaviorSettingRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    CustomRoute(
      page: EInkSettingRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    CustomRoute(
      page: StorageSettingRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    CustomRoute(
      page: DebugSettingRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    CustomRoute(
      page: ThemeColorRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    CustomRoute(
      page: WebDavSyncRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    CustomRoute(
      page: ShowColorRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    AutoRoute(page: AboutRoute.page),
    AutoRoute(page: FullRouteImageRoute.page),
    AutoRoute(page: ChangelogRoute.page),
    AutoRoute(page: SearchRoute.page),
    AutoRoute(page: DownloadRoute.page),
    AutoRoute(page: DownloadTaskRoute.page),
    AutoRoute(page: PluginStoreRoute.page),
    AutoRoute(page: PluginSettingsRoute.page),
    AutoRoute(page: PluginDetailRoute.page),
    AutoRoute(page: PluginFunctionRoute.page),
    AutoRoute(page: OldHomeRoute.page),
    AutoRoute(page: OldRankingRoute.page),
    AutoRoute(page: MoreRoute.page),
    AutoRoute(page: QjsRuntimeDebugRoute.page),
    CustomRoute(
      page: CacheSettingRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    CustomRoute(
      page: RealSrSettingRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    CustomRoute(
      page: OcrSettingRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    CustomRoute(
      page: BookshelfSettingRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    CustomRoute(
      page: OperationBindingSettingRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    CustomRoute(
      page: DataBackupRoute.page,
      customRouteBuilder: settingAutoRoute,
    ),
    AutoRoute(page: ComicFollowRoute.page),
  ];

  /// 全站仅此一个守卫：[WorkspaceRouteGuard]。
  ///
  /// 它只在**工作台挂载期间**生效，做两件事：
  /// - `ComicReadRoute` 的推入改派进工作台的**中央阅读器泳道**（「中央泳道 = Reader」）；
  /// - 其余推入落进**发起交互的那个面板**自己的局部导航栈，于是「在工作台里点设置」
  ///   开的是一块卡片，而不是盖住整个应用。
  ///
  /// 工作台不在场时它逐字放行，全屏推入的行为完全不变。
  ///
  /// 另有一条**不由守卫承担**的接线：[WorkspaceBackInterceptor]（mixin）——
  /// 守卫拦推入，它拦**回退**（`context.pop()` / `context.maybePop()` 走的是
  /// `AutoRouter.of(context)`，根本不过守卫）。两者合起来才是「泳道里的东西
  /// 开在泳道里、也退在泳道里」。
  @override
  List<AutoRouteGuard> get guards => const [WorkspaceRouteGuard()];
}

void popToRoot(BuildContext context) {
  context.router.popUntil((route) => route.settings.name == 'NavigationBar');
}
