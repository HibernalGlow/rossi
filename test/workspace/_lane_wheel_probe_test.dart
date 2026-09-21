// 临时探针：把「上游整页嵌进泳道面板」的真实结构装起来，看滚轮到底落到谁身上。
// 只为取机制，验完即删。
// ignore_for_file: avoid_print
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/widgets/swimlane/swimlane_workspace.dart';

const WorkspaceLayoutConfig _layout = WorkspaceLayoutConfig(
  laneOrder: LaneId.defaultOrder,
  lanes: <String, LaneConfig>{
    LaneId.left: LaneConfig(
      width: 520,
      minWidth: 300,
      maxWidth: 900,
      title: 'L',
    ),
    LaneId.reader: LaneConfig(
      width: 540,
      widthRatio: 0.3,
      minWidth: 300,
      maxWidth: 900,
      title: 'R',
    ),
    LaneId.right: LaneConfig(
      width: 520,
      minWidth: 300,
      maxWidth: 900,
      title: 'Rt',
    ),
  },
);

final WorkspaceLayoutSnapshot _snapshot = WorkspaceLayoutSnapshot(
  mode: WorkspaceMode.swimlane,
  layout: _layout,
);

final Map<String, ScrollController> _controllers = <String, ScrollController>{};

/// 上游整页（设置页那一类）：自带 Scaffold/AppBar + 一条纵向 ListView。
Widget _page(String laneId) {
  final controller = ScrollController();
  _controllers[laneId] = controller;
  return Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: ListView(
      key: ValueKey<String>('list:$laneId'),
      controller: controller,
      children: [
        for (int i = 0; i < 200; i++)
          SizedBox(height: 56, child: ListTile(title: Text('$laneId-项 $i'))),
      ],
    ),
  );
}

/// 嵌进面板的那一层：Listener（按下上报）+ 只放一页的局部 Navigator。
Widget _embedded(String laneId) {
  return Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) {},
    child: Navigator(
      key: ValueKey<String>('nav:$laneId'),
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => _page(laneId),
      ),
    ),
  );
}

Future<WorkspaceCubit> _pump(
  WidgetTester tester,
  Widget Function(String) builder, {
  required bool activate,
}) async {
  tester.view.physicalSize = const Size(1800, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  _controllers.clear();
  final cubit = WorkspaceCubit();
  addTearDown(cubit.close);
  cubit.restore(_snapshot);
  if (activate) cubit.activateLane(LaneId.right);

  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<WorkspaceCubit>.value(
        value: cubit,
        child: Scaffold(
          body: SwimlaneWorkspace(debugLaneContentBuilder: builder),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cubit;
}

Future<String> _wheel(WidgetTester tester, Offset delta, {Offset? at}) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  final finder = find.byKey(const ValueKey<String>('list:${LaneId.right}'));
  final target = at ?? tester.getCenter(finder);
  final controller = _controllers[LaneId.right]!;
  final before = controller.offset;
  await tester.sendEventToBinding(pointer.hover(target));
  await tester.sendEventToBinding(pointer.scroll(delta));
  await tester.pumpAndSettle();
  return 'offset ${before.toStringAsFixed(1)} → ${controller.offset.toStringAsFixed(1)}'
      ' (max ${controller.position.maxScrollExtent.toStringAsFixed(1)})';
}

// ── 截图里的形状：从「嵌在泳道里的设置页」打开阅读设置面板 ──────────────────

final List<ScrollController> _sheetControllers = <ScrollController>[];

void _openSheet(BuildContext context, {required bool root}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: root,
    builder: (_) => SizedBox(
      height: 420,
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'A'),
                Tab(text: 'B'),
                Tab(text: 'C'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final label in ['A', 'B', 'C'])
                    Builder(
                      builder: (_) {
                        final controller = ScrollController();
                        _sheetControllers.add(controller);
                        return SingleChildScrollView(
                          key: ValueKey<String>('sheet-tab-$label'),
                          controller: controller,
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            children: [
                              for (int i = 0; i < 120; i++)
                                SizedBox(height: 56, child: Text('$label-$i')),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 设置页（嵌进泳道的那一张）：整页 ListView + 一个「阅读设置」入口。
Widget _pageWithSheet(String laneId, {required bool root}) {
  final controller = ScrollController();
  _controllers[laneId] = controller;
  return Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: Column(
      children: [
        Builder(
          builder: (context) => ListTile(
            key: ValueKey<String>('open-sheet:$laneId'),
            title: const Text('阅读设置'),
            onTap: () => _openSheet(context, root: root),
          ),
        ),
        Expanded(
          child: ListView(
            key: ValueKey<String>('list:$laneId'),
            controller: controller,
            children: [
              for (int i = 0; i < 200; i++)
                SizedBox(height: 56, child: Text('$laneId-$i')),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _embeddedWithSheet(String laneId, {required bool root}) {
  return Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) {},
    child: Navigator(
      key: ValueKey<String>('nav:$laneId'),
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => _pageWithSheet(laneId, root: root),
      ),
    ),
  );
}

double _sheetOffset() {
  for (final controller in _sheetControllers.reversed) {
    if (controller.hasClients) return controller.offset;
  }
  return double.nan;
}

void main() {
  // ── 被吃掉的滚轮到底落在谁身上 ─────────────────────────────────────────

  Future<WorkspaceCubit> pumpNarrow(
    WidgetTester tester, {
    required bool activate,
  }) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    _controllers.clear();
    final cubit = WorkspaceCubit();
    addTearDown(cubit.close);
    cubit.restore(_snapshot);
    if (activate) cubit.activateLane(LaneId.right);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<WorkspaceCubit>.value(
          value: cubit,
          child: Scaffold(
            body: SwimlaneWorkspace(debugLaneContentBuilder: _embedded),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  Offset laneTopLeft(WidgetTester t) =>
      t.getTopLeft(find.byKey(const ValueKey<String>('list:${LaneId.right}')));

  testWidgets('探针 G：非激活泳道里，事件被送到**条带**（横向滚轮能滚条带）', (tester) async {
    final cubit = await pumpNarrow(tester, activate: false);
    print('G 前置：激活=${cubit.state.activeLaneId}');
    print('G 纵向滚轮：${await _wheel(tester, const Offset(0, 120))}');
    final afterVertical = laneTopLeft(tester);
    await _wheel(tester, const Offset(-200, 0));
    final afterHorizontal = laneTopLeft(tester);
    print('G 条带横移：纵向之后 dx=${afterVertical.dx} → 横向之后 dx=${afterHorizontal.dx}');
  });

  testWidgets('探针 H：同一条泳道**激活**之后，横向滚轮还会不会滚到条带', (tester) async {
    final cubit = await pumpNarrow(tester, activate: true);
    final before = laneTopLeft(tester);
    await _wheel(tester, const Offset(-200, 0));
    final after = laneTopLeft(tester);
    print(
      'H 激活=${cubit.state.activeLaneId} 条带横移 dx：${before.dx} → ${after.dx}',
    );
  });

  for (final root in [false, true]) {
    testWidgets('探针 F：从泳道里的设置页开面板（useRootNavigator=$root）', (tester) async {
      _sheetControllers.clear();
      final cubit = await _pump(
        tester,
        (laneId) => _embeddedWithSheet(laneId, root: root),
        activate: true,
      );
      await tester.tap(
        find.byKey(ValueKey<String>('open-sheet:${LaneId.right}')),
      );
      await tester.pumpAndSettle();
      print('F(root=$root) 面板已开 激活=${cubit.state.activeLaneId}');

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      final at = tester.getCenter(
        find.byKey(const ValueKey<String>('sheet-tab-A')),
      );
      final before = _sheetOffset();
      await tester.sendEventToBinding(pointer.hover(at));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
      await tester.pumpAndSettle();
      print(
        'F(root=$root) 面板内滚轮：${before.toStringAsFixed(1)} → '
        '${_sheetOffset().toStringAsFixed(1)}',
      );
    });
  }

  testWidgets('探针 A：普通页面（无局部 Navigator）', (tester) async {
    final cubit = await _pump(tester, _page, activate: true);
    print(
      'A 激活=${cubit.state.activeLaneId} ${await _wheel(tester, const Offset(0, 120))}',
    );
  });

  testWidgets('探针 B：嵌进面板（Listener + 局部 Navigator）+ 泳道已激活', (tester) async {
    final cubit = await _pump(tester, _embedded, activate: true);
    print(
      'B 激活=${cubit.state.activeLaneId} ${await _wheel(tester, const Offset(0, 120))}',
    );
  });

  testWidgets('探针 C：嵌进面板 + 泳道**未激活**（AbsorbPointer 生效中）', (tester) async {
    final cubit = await _pump(tester, _embedded, activate: false);
    print(
      'C 激活=${cubit.state.activeLaneId} ${await _wheel(tester, const Offset(0, 120))}',
    );
  });

  testWidgets('探针 D：嵌进面板 + 激活，滚轮落在视口右边缘的揭示带内', (tester) async {
    final cubit = await _pump(tester, _embedded, activate: true);
    final edge = Offset(tester.view.physicalSize.width - 6, 400);
    print(
      'D 激活=${cubit.state.activeLaneId} ${await _wheel(tester, const Offset(0, 120), at: edge)}',
    );
  });

  testWidgets('探针 E：嵌进面板，先真的点一下再滚（模拟用户路径）', (tester) async {
    final cubit = await _pump(tester, _embedded, activate: false);
    await tester.tapAt(
      tester.getCenter(
        find.byKey(const ValueKey<String>('list:${LaneId.right}')),
      ),
    );
    await tester.pumpAndSettle();
    print(
      'E 点过之后激活=${cubit.state.activeLaneId} ${await _wheel(tester, const Offset(0, 120))}',
    );
  });
}
