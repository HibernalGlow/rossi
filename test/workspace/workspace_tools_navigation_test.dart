import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_follow/cubit/comic_follow_cubit.dart';
import 'package:zephyr/workspace/model/workspace_reader_target.dart';
import 'package:zephyr/workspace/router/workspace_lane_dispatch.dart';
import 'package:zephyr/workspace/router/workspace_navigation_bridge.dart';
import 'package:zephyr/workspace/router/workspace_route_guard.dart';
import 'package:zephyr/workspace/widgets/containers/embedded_auxiliary_lane.dart';
import 'package:zephyr/workspace/widgets/containers/embedded_upstream_page.dart';
import 'package:zephyr/workspace/widgets/tools/workspace_tools_panel.dart';

class _Settings extends GlobalSettingCubit {
  @override
  void updateState(GlobalSettingState Function(GlobalSettingState) updates) =>
      emit(updates(state));
}

class _Follow extends ComicFollowCubit {
  @override
  Future<void> loadFromDatabase() async {}
}

class _Router extends RootStackRouter {
  _Router(this.settings, this.follow);
  final GlobalSettingCubit settings;
  final ComicFollowCubit follow;

  @override
  List<AutoRouteGuard> get guards => const [WorkspaceRouteGuard()];

  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      initial: true,
      page: PageInfo(
        'ToolsTestHost',
        builder: (_) => Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: settings),
              BlocProvider.value(value: follow),
            ],
            child: const Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 380,
                height: 500,
                child: EmbeddedUpstreamPage(
                  key: ValueKey('tools-host'),
                  host: WorkspaceLaneHost('tools-test', 'tools'),
                  instanceKey: 'tools-test',
                  isVisible: true,
                  builder: _panel,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    for (final tool in WorkspaceTool.values)
      if (workspaceToolRoute(tool) case final route?)
        AutoRoute(
          page: PageInfo(
            route.routeName,
            builder: (_) => _Target(route.routeName),
          ),
        ),
  ];
}

Widget _panel(BuildContext context) => const EmbeddedAuxiliaryLane();

class _Target extends StatelessWidget {
  const _Target(this.name);
  final String name;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(name)),
    body: Text('target:$name'),
  );
}

void main() {
  testWidgets('工作台入口留在所属面板，返回后摘要读取最新设置', (tester) async {
    final settings = _Settings();
    final follow = _Follow();
    final router = _Router(settings, follow);
    void reader(WorkspaceReaderTarget _) {}
    WorkspaceNavigationBridge.instance.attachReader(reader);
    addTearDown(() async {
      WorkspaceNavigationBridge.instance.detachReader(reader);
      WorkspaceLaneDispatch.instance.reset();
      router.dispose();
      await settings.close();
      await follow.close();
    });
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config()));
    await tester.pumpAndSettle();
    final host = tester.getRect(find.byKey(const ValueKey('tools-host')));
    for (final tool in WorkspaceTool.values) {
      final route = workspaceToolRoute(tool);
      if (route == null) continue;
      final entry = find.byKey(ValueKey('workspace-tool:${tool.name}'));
      await tester.ensureVisible(entry);
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.text('target:${route.routeName}'), findsOneWidget);
      expect(tester.getRect(find.byType(_Target)), host);
      expect(router.stack.length, 1);
      settings.updateState(
        (state) => state.copyWith(themeMode: ThemeMode.dark),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(WorkspaceToolsPanel), findsOneWidget);
      expect(
        tester
            .widget<WorkspaceToolsPanel>(find.byType(WorkspaceToolsPanel))
            .settingsSummary,
        contains(t.common.darkMode),
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
