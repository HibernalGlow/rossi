// 泳道**运行时**行为的判据：激活泳道 / 非激活泳道第一下点击被吃掉 /
// 悬停驻留聚焦 / 边缘驻留揭示。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/workspace/swimlane_runtime_test.dart
//
// （本机必须解掉 `HTTP_PROXY`：沙箱代理会劫持 `flutter_tester` 的 WebSocket
//   握手，症状是 `Unable to connect to flutter_tester process:
//   Invalid WebSocket upgrade request`。这与被测代码无关。）
//
// 为什么这几条必须是 widget 判据：它们的**全部**内容就是「指针事件落到谁身上」
// 与「条带滚到哪儿」，由 `RenderObject` 的命中测试与 `ScrollController` 决定，
// 跟引擎的解码器 / 平台视图无关 —— 所以 `flutter_tester` 就够，不必真机。
//
// 两条纪律写在这里，因为它们是本文件能被信任的前提：
//
// 1. **驻留（dwell）必须用真实时钟等**。被测代码读的是 `Stopwatch`
//    （刻意不用 `DateTime.now()`：wall clock 被 NTP 校正会跳），而
//    `tester.pump(Duration)` 推的是**测试时钟**，推不动 `Stopwatch`。
//    所以这里用 `tester.runAsync` 真的等够延时，再 `pump` 一帧让 16ms 的
//    轮询定时器醒来。用假时钟「模拟」等够，验的是判据自己的算术。
// 2. **泳道内容用替身**（`debugLaneContentBuilder`）。真内容是上游
//    `BookshelfPage` / `ComicReadPage`，要 ObjectBox、图源注册表、应用数据
//    目录，在这里根本建不起来。替身只换「内容由谁构造」，泳道结构
//    （栏头、次序、吃点击、驻留）一字未动 —— 被测的正是后者。
//
// ignore_for_file: avoid_print
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/widgets/swimlane/swimlane_column.dart';
import 'package:zephyr/workspace/widgets/swimlane/swimlane_workspace.dart';

// ── 夹具 ────────────────────────────────────────────────────────────────────

/// 泳道宽度取接近应用默认值的档（左 380 / 右 360），三条要能**同时**在视口里
/// 看见 —— 否则「点右泳道」会点到视口外的坐标上，判据变成在验别的东西。
///
/// 刻意不用更窄的档：栏头那一行（把手 + 标题 + 宽度徽标 + 页签条 + 独占 + 折叠）
/// 在 280px 上下会挤到溢出，那是另一件事（见文件末尾的说明），不该混进来。
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

/// 替身内容收到的点击（泳道 id）。
final List<String> _contentTaps = <String>[];

/// 替身内容：一块可点的方块 + 一个可定位的 key。
Widget _probeContent(String laneId) {
  return Center(
    child: GestureDetector(
      key: ValueKey<String>('probe-$laneId'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _contentTaps.add(laneId),
      child: const SizedBox(width: 90, height: 52),
    ),
  );
}

Finder _probe(String laneId) => find.byKey(ValueKey<String>('probe-$laneId'));

/// 把 finder 收进某条泳道（按栏头标题认 —— 标题是夹具自己给的，稳定）。
Finder _laneScope(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(SwimlaneColumn));

Finder _laneIcon(String title, IconData icon) =>
    find.descendant(of: _laneScope(title), matching: find.byIcon(icon));

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
          body: SwimlaneWorkspace(debugLaneContentBuilder: _probeContent),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cubit;
}

/// 真的等够 [delayMs] + 一点余量，再推一帧让 16ms 的驻留轮询定时器醒来。
///
/// 两半缺一不可：`runAsync` 让真实时钟走（`Stopwatch` 才有得读），
/// `pump` 让被测代码里那个 `Timer.periodic` 真的触发一次并把结果落进状态。
Future<void> _waitDwell(WidgetTester tester, int delayMs) async {
  await tester.runAsync(
    () => Future<void>.delayed(Duration(milliseconds: delayMs + 120)),
  );
  await tester.pump(const Duration(milliseconds: 48));
  await tester.pumpAndSettle();
}

void main() {
  setUp(_contentTaps.clear);

  // ── 1 / 2：激活泳道 + 第一下点击被吃掉 ────────────────────────────────────

  testWidgets('非激活泳道的第一下点击被吃掉，同时完成激活', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    expect(
      cubit.state.activeLaneId,
      isNull,
      reason: '冷启动「还没定过」是刻意的：不该因为一个默认激活项就把用户第一下点击吃掉',
    );

    await tester.tapAt(tester.getCenter(_probe(LaneId.right)));
    await tester.pumpAndSettle();

    expect(
      cubit.state.activeLaneId,
      LaneId.right,
      reason: '这一下点击的**全部**作用就是把交互交给这条泳道',
    );
    expect(
      _contentTaps,
      isEmpty,
      reason:
          '契约：`That click is consumed by the workspace and must not reach '
          'Reader area bindings, page navigation, video controls, or the radial menu`',
    );
  });

  testWidgets('激活之后，落在这条泳道上的点击恢复正常派发', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    final spot = tester.getCenter(_probe(LaneId.right));

    await tester.tapAt(spot);
    await tester.pumpAndSettle();
    expect(_contentTaps, isEmpty, reason: '前置：第一下确实被吃掉了');

    await tester.tapAt(spot);
    await tester.pumpAndSettle();

    expect(
      _contentTaps,
      <String>[LaneId.right],
      reason:
          '吃掉只该发生**一次**：激活之后内容必须照常收到点击，'
          '否则用户每点两下才生效一下',
    );
    expect(cubit.state.activeLaneId, LaneId.right);
  });

  testWidgets('非激活泳道**栏头**的按钮第一下就生效（栏头不进吸收范围）', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    expect(cubit.state.activeLaneId, isNull, reason: '前置：右泳道此刻是非激活的');

    expect(
      find.descendant(of: _laneScope(_rightTitle), matching: find.text('44px')),
      findsNothing,
      reason: '前置：还没折叠',
    );

    await tester.tap(
      _laneIcon(_rightTitle, Icons.vertical_align_center_rounded),
    );
    await tester.pumpAndSettle();

    expect(
      cubit.state.layout.lanes[LaneId.right]!.collapsed,
      isTrue,
      reason:
          '栏头的折叠按钮是这条泳道**自己的**控件，第一下就该生效 —— '
          'UserModel 按了「折叠」而什么都没发生，比「先激活了泳道」难解释得多',
    );
    expect(
      cubit.state.activeLaneId,
      LaneId.right,
      reason: '同一次按下也顺带完成激活（栏头点击同样算「交互交给这条泳道」）',
    );
  });

  // ── 3 / 4：悬停驻留聚焦（Reader 与面板两颗开关，紧凑轨不参与） ─────────────

  testWidgets('指针在非激活的阅读器泳道上停留够久，就把它激活', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    expect(
      cubit.state.interaction.hoverFocusEnabled,
      isTrue,
      reason: '这一项默认必须开着，否则这条判据验的是空气',
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    // 先在条带内边距里（不属于任何泳道）落下指针，再横移到阅读器泳道 ——
    // 这样必然产生一次 enter，不是靠「恰好落在里面」。
    await gesture.addPointer(location: const Offset(4, 4));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(_probe(LaneId.reader)));
    await tester.pump();

    expect(
      cubit.state.activeLaneId,
      isNull,
      reason: '刚进去还不能激活：`an optional, configurable **dwell**` 的重音在驻留上',
    );

    await _waitDwell(tester, cubit.state.interaction.hoverFocusDelayMs);

    expect(
      cubit.state.activeLaneId,
      LaneId.reader,
      reason: '停留超过 hoverFocusDelayMs 就该激活它',
    );
  });

  testWidgets('指针停在**面板**泳道里够久也激活（这颗开关默认开）', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    expect(
      cubit.state.interaction.panelHoverFocusEnabled,
      isTrue,
      reason: '面板那侧默认必须开着，否则这条判据验的是空气',
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: const Offset(4, 4));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(_probe(LaneId.left)));
    await tester.pump();

    expect(
      cubit.state.activeLaneId,
      isNull,
      reason: '刚进去还不能激活：重音在**驻留**上，面板那侧也不例外',
    );

    await _waitDwell(tester, cubit.state.interaction.hoverFocusDelayMs);

    expect(
      cubit.state.activeLaneId,
      LaneId.left,
      reason: '面板泳道吃悬停聚焦，且与 Reader **共用**同一段延时（多一套延时就是第四个要对着表的旋钮）',
    );
  });

  testWidgets('面板那颗关掉只影响面板：Reader 的悬停聚焦照旧', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    cubit.setInteraction(
      cubit.state.interaction.copyWith(panelHoverFocusEnabled: false),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: const Offset(4, 4));
    await tester.pump();

    await gesture.moveTo(tester.getCenter(_probe(LaneId.left)));
    await tester.pump();
    await _waitDwell(tester, cubit.state.interaction.hoverFocusDelayMs);
    expect(cubit.state.activeLaneId, isNull, reason: '关掉之后面板只剩点击这一条路');

    // 两颗开关是**独立**的：把面板那侧关掉不该顺手把 Reader 也弄哑。
    await gesture.moveTo(tester.getCenter(_probe(LaneId.reader)));
    await tester.pump();
    await _waitDwell(tester, cubit.state.interaction.hoverFocusDelayMs);
    expect(
      cubit.state.activeLaneId,
      LaneId.reader,
      reason: 'Reader 那侧仍然吃悬停聚焦（`hoverFocusEnabled` 一字未动）',
    );
  });

  testWidgets('折叠成 44px 紧凑轨的泳道**不**吃悬停聚焦', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    cubit.toggleLaneCollapsed(LaneId.left);
    await tester.pumpAndSettle();

    expect(
      cubit.state.layout.lanes[LaneId.left]!.collapsed,
      isTrue,
      reason: '前置：左泳道已折叠成轨',
    );

    // 轨这一档**不渲染内容**（`_buildCollapsedRail`），所以只能按栏头认这块矩形。
    final rail = _laneScope(_leftTitle);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: const Offset(4, 4));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(rail));
    await tester.pump();

    await _waitDwell(tester, cubit.state.interaction.hoverFocusDelayMs);

    expect(
      cubit.state.activeLaneId,
      isNull,
      reason:
          '轨只有 44px，读数时指针扫过去是常事 —— 停一下就跳焦点会把「切换把手」变成陷阱。'
          '点它仍然激活（见 `_buildLane` 的 `onToggleCollapse`），只是不自动。',
    );
  });

  testWidgets('悬停聚焦关掉之后，停多久都不激活', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    cubit.setInteraction(
      cubit.state.interaction.copyWith(hoverFocusEnabled: false),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: const Offset(4, 4));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(_probe(LaneId.reader)));
    await tester.pump();

    await _waitDwell(tester, cubit.state.interaction.hoverFocusDelayMs);

    expect(
      cubit.state.activeLaneId,
      isNull,
      reason: '开关关掉之后只剩点击这一条路（否则「悬停即聚焦」这个偏好是假的）',
    );
  });

  // ── 5 / 6：边缘驻留揭示（`revealFocusesLane` 决定它到此为止还是接管交互） ──

  testWidgets('Reader 独占且激活时，视口左边缘驻留会揭示左泳道并接管交互', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    cubit.toggleSoloLane(LaneId.reader);
    await tester.pumpAndSettle();

    expect(
      cubit.state.layout.soloLaneId,
      LaneId.reader,
      reason: '前置：Reader 独占',
    );
    expect(cubit.state.activeLaneId, LaneId.reader, reason: '前置：Reader 激活');
    expect(
      tester.getCenter(_probe(LaneId.left)).dx,
      lessThan(0),
      reason:
          '前置：独占让 Reader 占满可用宽，左泳道被挤出视口 —— '
          'reveal 这条能力（「显出一条泳道靠移动条带」）只在有得滚的时候才谈得上',
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: const Offset(600, 450));
    await tester.pump();
    await gesture.moveTo(const Offset(3, 450)); // 视口左边缘的揭示带内
    await tester.pump();

    await _waitDwell(tester, cubit.state.interaction.edgeRevealDelayMs);

    expect(
      tester.getCenter(_probe(LaneId.left)).dx,
      greaterThan(0),
      reason: '驻留够久就必须把左泳道推进视口（否则「揭示」只是日志里的一句话）',
    );
    expect(
      cubit.state.activeLaneId,
      LaneId.left,
      reason:
          '默认口径：`revealFocusesLane` 开着 ⇒ 揭示到点即把交互交出去。'
          '契约原本是 `does not change the active lane`，这一项是**按用户口径覆盖**的（见 ADR-0014 的后续修订）。',
    );
  });

  testWidgets('自动聚焦开着时，揭示之后不存在「延时收回 Reader」', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    cubit.toggleSoloLane(LaneId.reader);
    await tester.pumpAndSettle();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: const Offset(600, 450));
    await tester.pump();
    await gesture.moveTo(const Offset(3, 450));
    await tester.pump();
    await _waitDwell(tester, cubit.state.interaction.edgeRevealDelayMs);
    expect(cubit.state.activeLaneId, LaneId.left, reason: '前置：揭示已经接管了交互');

    // 指针**不动**，再等一整个「收回」的延时。
    await _waitDwell(tester, cubit.state.interaction.edgeRevealRestoreDelayMs);

    expect(
      cubit.state.activeLaneId,
      LaneId.left,
      reason:
          '「离开未激活的揭示就收回」是为了不留下一个没人认领的**瞬态**；'
          '它已经是激活泳道了，再收回就是把用户正在用的那条路抢走。',
    );
    expect(
      tester.getCenter(_probe(LaneId.left)).dx,
      greaterThan(0),
      reason: '条带留在原地（回 Reader 交给悬停聚焦或点那条窄缝，不是自动跳）',
    );
  });

  testWidgets('揭示是瞬态的：关掉自动聚焦后，指针离开会延时把条带收回 Reader', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    cubit.toggleSoloLane(LaneId.reader);
    // 这一条验的是契约原味（`Dwell alone is transient and does not change the
    // active lane` + `Leaving an unactivated reveal restores Reader`），所以
    // 先把自动聚焦关掉；**同时**关掉 Reader 悬停聚焦 —— 否则指针落回 Reader
    // 之后「收回」到底是恢复计时干的还是驻留聚焦干的，这条判据答不上来。
    cubit.setInteraction(
      cubit.state.interaction.copyWith(
        revealFocusesLane: false,
        hoverFocusEnabled: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      cubit.state.interaction.revealFocusesLane,
      isFalse,
      reason: '前置：这一条走的是「揭示不改激活」那条分支',
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: const Offset(600, 450));
    await tester.pump();
    await gesture.moveTo(const Offset(3, 450));
    await tester.pump();
    await _waitDwell(tester, cubit.state.interaction.edgeRevealDelayMs);
    expect(
      tester.getCenter(_probe(LaneId.left)).dx,
      greaterThan(0),
      reason: '前置：揭示已经发生',
    );
    expect(
      cubit.state.activeLaneId,
      LaneId.reader,
      reason: '这条分支上揭示**只是看清楚**：交互还留在 Reader',
    );

    // 移出去（落回 Reader 泳道里）—— 不是「离开被揭示的那条」，而是「离开它」。
    await gesture.moveTo(tester.getCenter(_probe(LaneId.reader)));
    await tester.pump();
    await _waitDwell(tester, cubit.state.interaction.edgeRevealRestoreDelayMs);

    expect(
      tester.getCenter(_probe(LaneId.left)).dx,
      lessThan(0),
      reason:
          '揭示是**瞬态**的：指针不在旁边了，它就该消失，'
          '否则「上次它自己动过」会变成一个用户没法关掉的状态',
    );
    expect(
      cubit.state.activeLaneId,
      LaneId.reader,
      reason: '收回的是**条带位置**，激活泳道自始至终没换过',
    );
  });
}
