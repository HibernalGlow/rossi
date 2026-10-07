// 一次 emit 到底重建了谁 —— **泳道内容子树**的 build 预算。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/workspace/lane_rebuild_budget_test.dart
//
// # 为什么需要这条判据
//
// 悬停驻留聚焦（`activateLane`）在设计上只是**一次记账变化**：谁被激活、边框亮不亮、
// 条带停在哪儿。可它落地的下一刻，界面会「卡一下」。中间那段"只是记账的变化"
// 与"整棵阅读器重建"之间的鸿沟，肉眼看不出来在代码里也不显眼 ——
// `SwimlaneWorkspace` 外面那层 `BlocBuilder` 没有 `buildWhen`，于是**任何**一次
// emit 都会重跑整棵条带的 builder，把 `WorkspaceReaderHost` 当成一个新 widget
// 交下去；那条路上 `Navigator.didUpdateWidget ⇒ route.changedExternalState ⇒
// _forceRebuildPage`，上游 `ComicReadPage` **整页**重 build。
//
// # 为什么数「内容自己的 build」而不是数外层 builder 被调了几次
//
// Flutter 在 `Element.updateChild`（`framework.dart:4027`）里见到
// `child.widget == newWidget` 时**整棵子树直接跳过**。所以「把同一个实例交下去」
// 是真的不重建；而数外层调用既会漏报（外层重跑但子树被跳过）也会误报
// （外层没重跑但内容被别的依赖弄脏）。计数器必须由替身内容**在自己的 build 里**加。
//
// # 两条纪律
//
// 1. 每一条「不该重建」都配一条「必须重建」的对照。计数器坏了也是绿的，
//    那种绿没有意义 —— 对照就是 `openReader` / `setActivePanel` 之后它必须涨。
// 2. 内容用替身（`debugLaneContentBuilder`）。真内容要整个应用的依赖，在这里建不起来；
//    替身只换「内容由谁构造」，被测的是**内容槽位收到的是不是同一个实例**。
//
// ignore_for_file: avoid_print
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/model/workspace_reader_target.dart';
import 'package:zephyr/workspace/widgets/swimlane/swimlane_workspace.dart';

const String _leftTitle = '泳道-左';
const String _readerTitle = '泳道-中';
const String _rightTitle = '泳道-右';

const WorkspaceLayoutConfig _testLayout = WorkspaceLayoutConfig(
  laneOrder: LaneId.defaultOrder,
  lanes: <String, LaneConfig>{
    LaneId.left: LaneConfig(
      width: 400,
      minWidth: 300,
      maxWidth: 600,
      title: _leftTitle,
    ),
    LaneId.reader: LaneConfig(
      width: 300,
      widthRatio: 0.25,
      minWidth: 300,
      maxWidth: 900,
      title: _readerTitle,
    ),
    LaneId.right: LaneConfig(
      width: 400,
      minWidth: 300,
      maxWidth: 600,
      title: _rightTitle,
    ),
  },
);

final WorkspaceLayoutSnapshot _testSnapshot = WorkspaceLayoutSnapshot(
  mode: WorkspaceMode.swimlane,
  layout: _testLayout,
);

const Size _windowSize = Size(1200, 900);

/// **替身内容自己**数自己的 build。
///
/// 它是 `StatefulWidget` 而不是 `Builder`，为的是让「这个实例被跳过」与
/// 「这个实例被更新」在计数上区分得干净：同一个 widget 实例交下来时
/// element 根本不会被 update，`build` 一次都不会跑。
class _CountedLaneContent extends StatefulWidget {
  _CountedLaneContent({required this.laneId})
    : super(key: ValueKey<String>('counted:$laneId'));

  final String laneId;

  /// laneId → build 次数。
  static final Map<String, int> builds = <String, int>{};

  static void reset() => builds.clear();

  @override
  State<_CountedLaneContent> createState() => _CountedLaneContentState();
}

class _CountedLaneContentState extends State<_CountedLaneContent> {
  @override
  Widget build(BuildContext context) {
    _CountedLaneContent.builds[widget.laneId] =
        (_CountedLaneContent.builds[widget.laneId] ?? 0) + 1;
    return Center(
      child: SizedBox(
        width: 90,
        height: 52,
        child: Text(widget.laneId, textAlign: TextAlign.center),
      ),
    );
  }
}

Widget _probe(String laneId) => _CountedLaneContent(laneId: laneId);

int _count(String laneId) => _CountedLaneContent.builds[laneId] ?? 0;

/// 快照三条泳道此刻的计数，返回之后「涨了多少」的差值函数。
Map<String, int> _snapshotCounts() => <String, int>{
  LaneId.left: _count(LaneId.left),
  LaneId.reader: _count(LaneId.reader),
  LaneId.right: _count(LaneId.right),
};

Map<String, int> _delta(Map<String, int> before) => <String, int>{
  LaneId.left: _count(LaneId.left) - before[LaneId.left]!,
  LaneId.reader: _count(LaneId.reader) - before[LaneId.reader]!,
  LaneId.right: _count(LaneId.right) - before[LaneId.right]!,
};

Future<WorkspaceCubit> _pumpWorkspace(WidgetTester tester) async {
  tester.view.physicalSize = _windowSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final cubit = WorkspaceCubit();
  addTearDown(cubit.close);
  cubit.restore(_testSnapshot);

  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<WorkspaceCubit>.value(
        value: cubit,
        child: const Scaffold(
          body: SwimlaneWorkspace(debugLaneContentBuilder: _probe),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cubit;
}

/// 真的等够驻留延时（被测代码读 `Stopwatch`，测试时钟推不动它）。
Future<void> _waitDwell(WidgetTester tester, int delayMs) async {
  await tester.runAsync(
    () => Future<void>.delayed(Duration(milliseconds: delayMs + 150)),
  );
  await tester.pump(const Duration(milliseconds: 48));
  await tester.pumpAndSettle();
}

/// 钉平台跑一条判据（工作台按「这台设备有没有悬停指针」分流）。
///
/// 复位只能写在测试体内：`addTearDown` 排在 `_verifyInvariants` 之后。
void testWidgetsOn(
  TargetPlatform platform,
  String description,
  WidgetTesterCallback body,
) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

const TargetPlatform _pointerPlatform = TargetPlatform.macOS;

WorkspaceReaderTarget _target(String comicId) => WorkspaceReaderTarget(
  comicId: comicId,
  from: 'test',
  stringSelectCubit: StringSelectCubit(),
);

void main() {
  setUp(_CountedLaneContent.reset);

  testWidgetsOn(_pointerPlatform, '前置：三条泳道各自至少 build 过一次（计数器不是坏的）', (
    tester,
  ) async {
    await _pumpWorkspace(tester);
    expect(
      _snapshotCounts().values.every((n) => n >= 1),
      isTrue,
      reason: '挂载时三条内容各建一次，否则后面所有「delta=0」都是计数器坏了',
    );
  });

  testWidgetsOn(_pointerPlatform, '对照：**换书**（readerTarget 变了）必须重建阅读器内容', (
    tester,
  ) async {
    final cubit = await _pumpWorkspace(tester);
    cubit.openReader(_target('comic-A'));
    await tester.pumpAndSettle();
    final before = _snapshotCounts();

    cubit.openReader(_target('comic-B'));
    await tester.pumpAndSettle();

    final delta = _delta(before);
    expect(
      delta[LaneId.reader],
      greaterThan(0),
      reason: '内容真的换了，必须重建 —— 这条不涨就说明这把尺子看不见真变化',
    );
  });

  testWidgetsOn(_pointerPlatform, '对照：**换面板**（activePanel 变了）必须重建那条泳道的内容', (
    tester,
  ) async {
    final cubit = await _pumpWorkspace(tester);
    cubit.setActivePanel(LaneId.left, 'panel-A');
    await tester.pumpAndSettle();
    final before = _snapshotCounts();

    cubit.setActivePanel(LaneId.left, 'panel-B');
    await tester.pumpAndSettle();

    expect(
      _delta(before)[LaneId.left],
      greaterThan(0),
      reason: '面板换了就是「中央内容是什么」变了，必须重建',
    );
  });

  testWidgetsOn(_pointerPlatform, '把交互交给另一条泳道**不重建任何**泳道内容', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    cubit.openReader(_target('comic-A'));
    await tester.pumpAndSettle();

    // 从左交给右、再从右交回左：两次都是「只是记账变了」。
    for (final lane in [LaneId.left, LaneId.right, LaneId.left]) {
      final before = _snapshotCounts();
      cubit.activateLane(lane);
      await tester.pumpAndSettle();
      final delta = _delta(before);
      expect(
        delta[LaneId.reader],
        0,
        reason: '聚焦换了人，阅读器不该被重 build 一次（$lane 被激活这一下）',
      );
      expect(
        delta.values.fold<int>(0, (a, b) => a + b),
        0,
        reason: '三条内容都不该重建，实际 $delta',
      );
    }
  });

  testWidgetsOn(_pointerPlatform, '悬停驻留聚焦那一落点：内容零重建，条带照常平移', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    cubit.openReader(_target('comic-A'));
    cubit.activateLane(LaneId.reader);
    await tester.pumpAndSettle();
    final before = _snapshotCounts();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: const Offset(4, 4));
    await tester.pump();
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey<String>('counted:${LaneId.left}'))),
    );
    await tester.pump();

    await _waitDwell(tester, cubit.state.interaction.hoverFocusDelayMs);

    expect(
      cubit.state.activeLaneId,
      LaneId.left,
      reason: '前置：驻留聚焦确实发生了（否则「零重建」是空转）',
    );
    final delta = _delta(before);
    expect(
      delta.values.fold<int>(0, (a, b) => a + b),
      0,
      reason: '用户感知的那一下就是这条路径：内容重建次数必须是 0，实际 $delta',
    );
  });
}
