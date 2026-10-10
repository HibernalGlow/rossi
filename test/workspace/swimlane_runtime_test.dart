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
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/model/workspace_dwell.dart';
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

/// 按 glyph 找（栏头图标 glyph 化之后的 finder）。
Finder _laneGlyph(String title, Glyph glyph) => find.descendant(
  of: _laneScope(title),
  matching: find.byWidgetPredicate((w) => w is GlyphIcon && w.glyph == glyph),
);

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

/// 找到条带那一层的 `ScrollPosition`。
///
/// 按「左泳道探针的祖先」认条带，而不是按轴向扫全部 `Scrollable`：夹具里
/// 横向可滚件**不止一条**（每条泳道栏头的页签条也是横向的），扫轴向会挑错人。
ScrollPosition _stripPosition(WidgetTester tester) {
  final states = tester.stateList<ScrollableState>(
    find.ancestor(of: _probe(LaneId.left), matching: find.byType(Scrollable)),
  );
  expect(states.length, 1, reason: '左泳道只该被条带这一条可滚件包住，否则不知道在量谁');
  final position = states.single.position;
  expect(position.axis, Axis.horizontal, reason: '条带是横向的');
  return position;
}

/// 条带上「左泳道探针」的屏幕横坐标 —— 条带动没动，看这个最直接。
double _leftProbeDx(WidgetTester tester) =>
    tester.getCenter(_probe(LaneId.left)).dx;

/// 全屏判据的**共同前置**：条带得真的有向右拖的余量。
///
/// 余量为 0 时「拖了没动」是空转而不是被闸口拦住，那种 PASS 什么也没验。
/// 拖向右 ⇒ 偏移变小 ⇒ 左泳道进入视口，所以要问的是 `pixels` 而不是
/// `maxScrollExtent`（方向反了同样会假绿：向左拖只会把左泳道推得更远）。
void _expectCanDragRight(WidgetTester tester, double delta) {
  final position = _stripPosition(tester);
  expect(
    position.pixels,
    greaterThan(delta),
    reason: '前置：向右拖 $delta 的余量都不够，判据无从谈起',
  );
}

/// Reader **独占且激活** —— 桌面那一档下两条面板泳道被推出视口的前置状态。
Future<WorkspaceCubit> _pumpSoloActiveReader(WidgetTester tester) async {
  final cubit = await _pumpWorkspace(tester);
  cubit.activateLane(LaneId.reader);
  cubit.toggleSoloLane(LaneId.reader);
  await tester.pumpAndSettle();
  expect(cubit.state.layout.soloLaneId, LaneId.reader, reason: '前置：Reader 独占');
  expect(
    cubit.state.effectiveSoloLaneId,
    LaneId.reader,
    reason: '前置：独占已经生效，**与谁被激活无关**（见 `WorkspaceState.effectiveSoloLaneId`）',
  );
  expect(
    cubit.state.interaction.showLaneNavigatorInSolo,
    isFalse,
    reason:
        '前置：这颗开关**没开** —— 判据验的是「触屏上不给开关也照样给把手」，'
        '开着的话这条判据就只是在验用户自己设的那一下。',
  );
  return cubit;
}

/// 在**指定平台**下跑一条 widget 判据。
///
/// 为什么必须钉平台，而不是靠 `flutter test` 的默认值：
/// `debugDefaultTargetPlatformOverride` 在测试里默认是 **android**，而工作台的
/// 条带几何现在按「这台设备有没有悬停指针」分流（触屏 ⇒ Reader 独占时左右两条
/// 收成 44px 切换轨，见 `WorkspacePointerMode`）。不钉住就会全部量到触屏那一档，
/// 那些讲桌面行为的判据会红成「像是回归」，而真正该红的没人看得见。
///
/// 复位只能写在**测试体内**（这里的 `finally`）：`_verifyInvariants` 在测试体
/// 结束时就要看到 foundation 变量已清回原值，`addTearDown` 排得比它晚，
/// 症状是每一条判据都以「The value of a foundation debug variable was changed
/// by the test.」收场。
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

/// 有悬停指针的那一档 —— 本文件绝大多数判据描述的就是它。
const TargetPlatform _pointerPlatform = TargetPlatform.macOS;

void main() {
  setUp(_contentTaps.clear);

  // ── 1 / 2：激活泳道 + 第一下点击被吃掉 ────────────────────────────────────

  testWidgetsOn(_pointerPlatform, '非激活泳道的第一下点击被吃掉，同时完成激活', (tester) async {
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

  testWidgetsOn(_pointerPlatform, '激活之后，落在这条泳道上的点击恢复正常派发', (tester) async {
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

  testWidgetsOn(_pointerPlatform, '非激活泳道**栏头**的按钮第一下就生效（栏头不进吸收范围）', (
    tester,
  ) async {
    final cubit = await _pumpWorkspace(tester);
    expect(cubit.state.activeLaneId, isNull, reason: '前置：右泳道此刻是非激活的');

    expect(
      find.descendant(of: _laneScope(_rightTitle), matching: find.text('44px')),
      findsNothing,
      reason: '前置：还没折叠',
    );

    await tester.tap(
      _laneGlyph(_rightTitle, AppGlyphs.fold),
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

  testWidgetsOn(_pointerPlatform, '指针在非激活的阅读器泳道上停留够久，就把它激活', (tester) async {
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

  testWidgetsOn(_pointerPlatform, '指针停在**面板**泳道里够久也激活（这颗开关默认开）', (
    tester,
  ) async {
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

  testWidgetsOn(_pointerPlatform, '停住之后先进入预备态（边框亮），交互随后才交出；一路动则什么都不亮', (
    tester,
  ) async {
    final cubit = await _pumpWorkspace(tester);
    const settle = WorkspaceDwell.settleMs;

    Future<void> advance(int realMs) async {
      await tester.runAsync(
        () => Future<void>.delayed(Duration(milliseconds: realMs)),
      );
      // 被测那个 16ms 轮询挂在**测试时钟**上（`Stopwatch` 才是真实时钟），
      // 所以每段真实等待之后必须推一帧，它才有机会去看到点没有。
      await tester.pump(const Duration(milliseconds: 20));
    }

    bool armed() =>
        tester
            .widget<SwimlaneColumn>(
              _laneScope(_leftTitle).first,
            )
            .focusArmed;

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: const Offset(4, 4));
    await tester.pump();
    final spot = tester.getCenter(_probe(LaneId.left));
    await gesture.moveTo(spot);
    await tester.pump();

    expect(armed(), isFalse, reason: '刚进去还没静够：不该亮');
    expect(cubit.state.activeLaneId, isNull, reason: '刚进去绝不激活');

    // 一路动：每 30ms 挪一下，累计时间早就超过 settle —— 但「静够」这件事从没发生。
    for (int i = 0; i < 5; i++) {
      await gesture.moveTo(spot + Offset(i * 3.0, 0));
      await advance(30);
      expect(armed(), isFalse, reason: '路过（一直在动）不该闪预备态，第 $i 步');
    }
    expect(cubit.state.activeLaneId, isNull, reason: '路过也不该激活');

    // 停下来：先静够 settle ⇒ 预备态亮；此时 delay 那一段还没走完，交互还没交出。
    await advance(settle + 20);
    expect(armed(), isTrue, reason: '静够 settleMs 就该亮 —— 那 100 多毫秒要「有回应」');
    expect(
      cubit.state.activeLaneId,
      isNull,
      reason: '预备态**不是**激活：边框亮了不等于交互已经交出去',
    );

    // 再等满 delay：交互交出来，预备态让位给真正的激活态。
    await advance(cubit.state.interaction.hoverFocusDelayMs);
    expect(
      cubit.state.activeLaneId,
      LaneId.left,
      reason: '停住 settle+delay 之后就该真的聚焦',
    );
    expect(armed(), isFalse, reason: '已经是激活态了，不该还挂着预备高亮');
  });

  testWidgetsOn(_pointerPlatform, '面板那颗关掉只影响面板：Reader 的悬停聚焦照旧', (tester) async {
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

  testWidgetsOn(_pointerPlatform, '折叠成 44px 紧凑轨的泳道**不**吃悬停聚焦', (tester) async {
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

  testWidgetsOn(_pointerPlatform, '悬停聚焦关掉之后，停多久都不激活', (tester) async {
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

  testWidgetsOn(_pointerPlatform, 'Reader 独占且激活时，视口左边缘驻留会揭示左泳道并接管交互', (
    tester,
  ) async {
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

  testWidgetsOn(_pointerPlatform, '自动聚焦开着时，揭示之后不存在「延时收回 Reader」', (
    tester,
  ) async {
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

  testWidgetsOn(_pointerPlatform, '揭示是瞬态的：关掉自动聚焦后，指针离开会延时把条带收回 Reader', (
    tester,
  ) async {
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

  // ── A：聚焦不改宽度（条带只平移）──────────────────────────────────────────

  testWidgetsOn(_pointerPlatform, '独占的 Reader 把交互交给左泳道之后，宽度一字不变', (
    tester,
  ) async {
    final cubit = await _pumpWorkspace(tester);
    cubit.activateLane(LaneId.reader);
    cubit.toggleSoloLane(LaneId.reader);
    await tester.pumpAndSettle();

    final readerScope = _laneScope(_readerTitle);
    final before = tester.getSize(readerScope).width;
    expect(before, greaterThan(1000), reason: '前置：Reader 独占 ≈ 占满可用宽（夹具 1200）');

    cubit.activateLane(LaneId.left);
    await tester.pumpAndSettle();

    // 这一条是「鼠标移过去卡一下」里最贵那下的正面判据：宽度一变，
    // `ImageSurface` 的物理尺寸就变，已上屏的纹理被判废并按新宽重解
    // （`lib/reader/image_surface.dart` 自己记的 300–400 ms/页）。
    expect(
      tester.getSize(readerScope).width,
      moreOrLessEquals(before, epsilon: 0.5),
      reason: '聚焦只该移动条带，不该重新排版 Reader',
    );
    expect(_leftProbeDx(tester), greaterThan(0), reason: '条带确实把左泳道移进来了');
    expect(
      cubit.state.layout.soloLaneId,
      LaneId.reader,
      reason: '独占偏好没被这次聚焦改掉（契约：激活别的泳道不清除 solo）',
    );
  });

  testWidgetsOn(_pointerPlatform, '生效值分档：Reader 的独占不随激活失效，面板的独占仍然随', (
    tester,
  ) async {
    final cubit = await _pumpWorkspace(tester);

    cubit.toggleSoloLane(LaneId.reader);
    cubit.activateLane(LaneId.left);
    await tester.pumpAndSettle();
    expect(
      cubit.state.effectiveSoloLaneId,
      LaneId.reader,
      reason:
          'Reader 这一档解绑了：激活左泳道不该把 Reader 打回常规宽度 '
          '（那是一次几百像素的重排 + 重解码，见 `WorkspaceState.activeLaneId`）',
    );

    cubit.toggleSoloLane(LaneId.reader); // 关掉 Reader 的独占
    cubit.toggleSoloLane(LaneId.left); // 打开左泳道的独占（它会顺带激活自己）
    cubit.activateLane(LaneId.right);
    await tester.pumpAndSettle();
    expect(
      cubit.state.layout.soloLaneId,
      LaneId.left,
      reason: '前置：独占偏好记在左泳道',
    );
    expect(
      cubit.state.effectiveSoloLaneId,
      isNull,
      reason:
          '面板那一档**保留**老契约，不是漏改：边缘驻留只对 Reader 独占开放，'
          '解绑之后「独占一条面板泳道 + 在别处干活」会把其余泳道挤到呼不回来的位置',
    );
  });

  // ── 7：Reader 全屏时的那道横向拖动闸 ──────────────────────────────────────

  testWidgetsOn(_pointerPlatform, 'Reader 全屏时横向拖动不拽动条带（开关默认开）', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    cubit.setReaderFullscreen(true);
    await tester.pumpAndSettle();

    expect(cubit.state.isReaderFullscreen, isTrue, reason: '前置：已进入全屏');
    expect(
      cubit.state.interaction.blockManualScrollInReaderFullscreen,
      isTrue,
      reason: '前置：新开关出厂就是开的（用户要的默认行为）',
    );
    _expectCanDragRight(tester, 240);
    final before = _leftProbeDx(tester);

    await tester.dragFrom(const Offset(600, 450), const Offset(240, 0));
    await tester.pumpAndSettle();

    expect(
      _leftProbeDx(tester),
      moreOrLessEquals(before, epsilon: 0.5),
      reason: '纹丝不动：全屏下的横向手势只该翻页，不该把条带拽出来',
    );
  });

  testWidgetsOn(_pointerPlatform, '关掉开关后全屏时又能拖 —— 证明上一判据拦它的就是这颗开关', (
    tester,
  ) async {
    final cubit = await _pumpWorkspace(tester);
    cubit.setReaderFullscreen(true);
    cubit.setInteraction(
      cubit.state.interaction.copyWith(
        blockManualScrollInReaderFullscreen: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      cubit.state.interaction.blockManualScrollInReaderFullscreen,
      isFalse,
      reason: '前置：这一条走的是「全屏也照旧可拖」那条分支',
    );
    _expectCanDragRight(tester, 240);
    final before = _leftProbeDx(tester);

    await tester.dragFrom(const Offset(600, 450), const Offset(240, 0));
    await tester.pumpAndSettle();

    expect(
      _leftProbeDx(tester),
      greaterThan(before + 100),
      reason: '拖得动 —— 否则上一条的「拖不动」可能来自别的原因（例如整条根本不能滚）',
    );
  });

  // ── 7：触摸屏上没有悬停指针 ⇒ 左右泳道必须有等价的把手 ─────────────────────
  //
  // 桌面把左右泳道「叫回来」的两条路，在触屏上一条都走不到：
  // ① 边缘驻留揭示吃的是 `PointerHoverEvent`（手指没有 hover，回调永不触发）；
  // ② 横扫条带在阅读器泳道里会被翻页的横向拖拽吃掉。
  // 于是 Reader 独占时，用户看得见 Reader、看不见左右两条，且没有任何手势能把
  // 它们推回来 —— 这就是「进得去出不来」的那个洞。补法是给出那条 44px 切换轨
  // （点它 = `activateLane`，`_buildLane` 的 `onToggleCollapse` 早就实现了这条语义）。

  testWidgetsOn(TargetPlatform.android, '触屏：Reader 独占时左右泳道收成 44px 轨，点它就交出交互', (
    tester,
  ) async {
    final cubit = await _pumpSoloActiveReader(tester);

    for (final title in [_leftTitle, _rightTitle]) {
      // 按「远小于一条面板泳道（夹具给的是 400）」判，而不是死磕 44.0：
      // 栏头那圈 `AnimatedContainer` 的边框各占 1.5，量到的矩形会是 41。
      // 差这 3px 与这条判据要问的问题无关（「有没有把手」），
      // 写成等式反而会让人以为边框宽度是契约的一部分。
      expect(
        tester.getSize(_laneScope(title)).width,
        lessThan(100),
        reason: '没有指针 ⇒ 这条轨必须出现，否则那两条泳道在触屏上不可达',
      );
    }

    final railCenter = tester.getCenter(_laneScope(_leftTitle));
    await tester.tapAt(railCenter);
    await tester.pumpAndSettle();

    expect(
      cubit.state.activeLaneId,
      LaneId.left,
      reason:
          '点轨的语义是「把交互交给这条泳道」，不是折叠 '
          '（`_buildLane`：`isRail && !config.collapsed` 那一支）。',
    );
    expect(
      cubit.state.layout.lanes[LaneId.left]!.collapsed,
      isFalse,
      reason: '不该把「显示切换栏」变成「把这条泳道永久折起来」',
    );
  });

  testWidgetsOn(_pointerPlatform, '桌面：同一份设置**不**给切换轨 —— 证明上一判据量的是平台而不是别的', (
    tester,
  ) async {
    await _pumpSoloActiveReader(tester);
    expect(
      tester.getSize(_laneScope(_leftTitle)).width,
      greaterThan(300),
      reason: '桌面保持原样：那边有边缘驻留，不该凭空多两条占位的轨',
    );
    expect(
      tester.getCenter(_probe(LaneId.left)).dx,
      lessThan(0),
      reason: '左泳道整条在视口外 —— 触屏上那条判据要解决的就是这个状态',
    );
  });
}
