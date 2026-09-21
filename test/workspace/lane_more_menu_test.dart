// 泳道栏头「更多」菜单的判据。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/workspace/lane_more_menu_test.dart
//
// （本机必须解掉 `HTTP_PROXY`：沙箱代理会劫持 `flutter_tester` 的 WebSocket
//   握手，症状是 `Unable to connect to flutter_tester process:
//   Invalid WebSocket upgrade request`。这与被测代码无关。）
//
// 这个菜单存在的**全部理由**是「页签条挂进栏头（没有把手）时，菜单能把面板栏
// 挪到别的边」那一条：默认形态下面板栏挂进栏头、不画拖动把手
// （`PanelTabStrip(showHandle: false)`），于是「把它挪到别的边 / 转成悬浮」在界面上
// 没有任何入口 —— 那套记账（`panelBarMode / panelBarDock / panelBarConstrained`）
// 用户读得到、存得下，就是改不动。其余几条守住的是菜单与 cubit 之间别接错线。
//
// 这份清单有**两个入口**：栏头那颗按钮，以及右键栏头 / 右键紧凑轨（同一份菜单）。
// 后者守的是「那颗按钮被挤没之后怎么办」—— 紧凑轨那一档压根不画按钮。
//
// 项集对齐 neoview 的 `ReaderLaneMoreMenu`；**窗口控件那一节刻意不做**（用户要求）。
// 末尾那一节（顶栏开关 + 退出工作台）不是从参考搬的：工作台顶栏默认不画，
// 「退出」在鼠标侧就只剩这里一个入口 —— 出口本身按没按到，由
// `top_chrome_test.dart` 第 4 节在**真实路由**上验（这一份夹具里没有工作台那一页）。
//
// 夹具与 `swimlane_runtime_test.dart` 同源：泳道内容用替身
// （`debugLaneContentBuilder`），真内容是上游 `BookshelfPage` / `ComicReadPage`，
// 在这里建不起来；被测的是栏头与记账，与内容无关。
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
import 'package:zephyr/workspace/model/workspace_panel_bar.dart';
import 'package:zephyr/workspace/widgets/swimlane/lane_more_menu.dart';
import 'package:zephyr/workspace/widgets/swimlane/swimlane_column.dart';
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

Widget _probeContent(String laneId) => const SizedBox.expand();

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

/// 打开某条泳道栏头的「更多」菜单。
Future<void> _openMenu(WidgetTester tester, String title) async {
  await tester.tap(_laneIcon(title, Icons.more_vert_rounded));
  await tester.pumpAndSettle();
}

/// **右键**某条泳道（栏头 / 紧凑轨都算）打开同一份菜单。
Future<void> _openMenuByRightClick(WidgetTester tester, String title) async {
  await tester.tap(find.text(title), buttons: kSecondaryButton);
  await tester.pumpAndSettle();
  // 「确实开起来了」的锚点：全仓库只有「常规宽度」那一项里住着这个输入框。
  expect(find.byKey(laneWidthFieldKey), findsOneWidget);
}

/// 关掉菜单（点遮罩，不走任何一项）。
Future<void> _dismissMenu(WidgetTester tester) async {
  await tester.tapAt(const Offset(6, 880));
  await tester.pumpAndSettle();
}

/// 在「常规宽度」里填一个数，然后点别处关掉菜单。
///
/// 刻意**不按回车**：用户打完数字最常见的收尾就是随手点到菜单外面，
/// 而那时焦点不一定还在文本框上 —— 「失焦即落账」这条路走不到，
/// 落账靠的是输入框销毁时补的那一次。
Future<void> _typeWidth(WidgetTester tester, String px) async {
  await tester.enterText(find.byKey(laneWidthFieldKey), px);
  await tester.pump();
  await _dismissMenu(tester);
}

void main() {
  testWidgets('栏头的「更多」菜单是这条泳道动作的完整清单', (tester) async {
    await _pumpWorkspace(tester);
    await _openMenu(tester, _leftTitle);

    for (final label in [
      '独占该栏',
      '常规宽度',
      '恢复默认宽度',
      '面板栏改为悬浮',
      '允许面板栏移出泳道',
      '面板栏停靠顶部',
      '恢复面板栏默认位置',
      '折叠为紧凑条',
      '显示工作台顶栏',
      '退出工作台',
    ]) {
      expect(
        find.text(label),
        findsOneWidget,
        reason: '菜单少这一项，就等于这条能力在界面上没有入口',
      );
    }
  });

  testWidgets('顶栏开关是往返的：开一次换标签，再按一次关回去', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    expect(
      cubit.state.interaction.showTopChrome,
      isFalse,
      reason: '前置：默认不画顶栏（菜单里那句「显示工作台顶栏」说的是这件事）',
    );

    await _openMenu(tester, _leftTitle);
    await tester.tap(find.text('显示工作台顶栏'));
    await tester.pumpAndSettle();
    expect(cubit.state.interaction.showTopChrome, isTrue);

    // 再开一次菜单：标签必须跟着账翻过去，否则第二下按的是「又开一遍」。
    await _openMenu(tester, _leftTitle);
    expect(find.text('显示工作台顶栏'), findsNothing);
    await tester.tap(find.text('隐藏工作台顶栏'));
    await tester.pumpAndSettle();
    expect(cubit.state.interaction.showTopChrome, isFalse);
  });

  // 右键这条路的全部理由：栏头是一行 `Row`，泳道又裁溢出，那颗按钮一旦被
  // 标题与页签条挤没，上面这一整份清单就同时不可达了 —— 而这正是用户
  // 「改坏了却改不回来」的那个时刻。
  testWidgets('右键栏头打开的是同一份菜单，不只是看看', (tester) async {
    final cubit = await _pumpWorkspace(tester);

    await _openMenuByRightClick(tester, _leftTitle);
    for (final label in ['独占该栏', '常规宽度', '面板栏停靠左侧', '恢复面板栏默认位置', '折叠为紧凑条']) {
      expect(
        find.text(label),
        findsOneWidget,
        reason: '右键这条路给出的是缩水版菜单：那条能力仍然没有入口',
      );
    }

    await tester.tap(find.text('折叠为紧凑条'));
    await tester.pumpAndSettle();
    expect(
      cubit.state.layout.lanes[LaneId.left]!.collapsed,
      isTrue,
      reason: '菜单开起来了但分派接错线，对用户来说就是「按了没反应」',
    );
  });

  testWidgets('右键栏头里的按钮也要能开菜单（那颗按钮本身可能看不见）', (tester) async {
    await _pumpWorkspace(tester);

    await tester.tap(
      _laneIcon(_leftTitle, Icons.vertical_align_center_rounded),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    expect(
      find.text('恢复默认宽度'),
      findsOneWidget,
      reason: '右键落在按钮上就被按钮吃掉的话，栏头只剩一小块能用的区域',
    );
  });

  testWidgets('折叠成紧凑轨后，右键这条轨能把泳道改回来', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    cubit.toggleLaneCollapsed(LaneId.left);
    await tester.pumpAndSettle();

    expect(
      _laneIcon(_leftTitle, Icons.more_vert_rounded),
      findsNothing,
      reason: '前置：紧凑轨这一档根本没有那颗按钮（44px 塞不下）',
    );

    await _openMenuByRightClick(tester, _leftTitle);
    expect(
      find.text('展开泳道'),
      findsOneWidget,
      reason: '折叠态下这一项必须说「展开」，与那条泳道记的状态一致',
    );

    await tester.tap(find.text('展开泳道'));
    await tester.pumpAndSettle();
    expect(cubit.state.layout.lanes[LaneId.left]!.collapsed, isFalse);
  });

  testWidgets('页签条挂进栏头（没有把手）时，菜单能把面板栏挪到别的边', (tester) async {
    final cubit = await _pumpWorkspace(tester);

    expect(
      cubit.state.layout.lanes[LaneId.left]!.panelBar,
      const PanelBarLayout(mode: PanelBarMode.pinned, dock: PanelBarDock.top),
      reason: '前置：默认钉在顶部，于是页签条被挂进栏头',
    );
    expect(
      _laneIcon(_leftTitle, Icons.drag_indicator_rounded),
      findsNothing,
      reason: '前置：挂进栏头的形态**不画拖动把手** —— 右键那条路走不通',
    );

    await _openMenu(tester, _leftTitle);
    await tester.tap(find.text('面板栏停靠左侧'));
    await tester.pumpAndSettle();

    final bar = cubit.state.layout.lanes[LaneId.left]!.panelBar;
    expect(bar.mode, PanelBarMode.pinned);
    expect(bar.dock, PanelBarDock.left);
    expect(
      _laneIcon(_leftTitle, Icons.drag_indicator_rounded),
      findsOneWidget,
      reason:
          '挪出栏头之后把手必须回来：否则用户只是**又**把自己关进一个「改不动」'
          '的形态，而这次连菜单里的那一节都看不见了',
    );
  });

  testWidgets('恢复面板栏默认位置 = 回到「挂进栏头」', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    cubit.setLanePanelBar(
      LaneId.left,
      const PanelBarLayout(mode: PanelBarMode.pinned, dock: PanelBarDock.left),
    );
    await tester.pumpAndSettle();

    await _openMenu(tester, _leftTitle);
    await tester.tap(find.text('恢复面板栏默认位置'));
    await tester.pumpAndSettle();

    expect(
      cubit.state.layout.lanes[LaneId.left]!.panelBar,
      const PanelBarLayout(),
      reason: '「默认」是本项目的默认（钉顶 = 挂进栏头），不是参考里的悬浮默认',
    );
    expect(
      _laneIcon(_leftTitle, Icons.drag_indicator_rounded),
      findsNothing,
      reason: '挂回栏头之后把手再次消失，与初始形态一致',
    );
  });

  testWidgets('独占项读的是记账，不是生效值', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    cubit.toggleSoloLane(LaneId.left);
    await tester.pumpAndSettle();
    // 激活别的泳道会让左泳道的 solo **不再生效**，但偏好仍然记着。
    cubit.activateLane(LaneId.right);
    await tester.pumpAndSettle();

    expect(cubit.state.layout.soloLaneId, LaneId.left, reason: '前置：solo 记在左泳道');
    expect(
      cubit.state.effectiveSoloLaneId,
      isNull,
      reason: '前置：它此刻不是生效的 solo（激活的是右泳道）',
    );

    await _openMenu(tester, _leftTitle);
    expect(
      find.text('退出独占'),
      findsOneWidget,
      reason:
          '标签必须与按下要做的事一致：读生效值会显示「独占该栏」，'
          '而按下却是**关掉**它',
    );

    await tester.tap(find.text('退出独占'));
    await tester.pumpAndSettle();
    expect(cubit.state.layout.soloLaneId, isNull);
  });

  testWidgets('常规宽度：随手点到菜单外面也要落账', (tester) async {
    final cubit = await _pumpWorkspace(tester);

    await _openMenu(tester, _leftTitle);
    await _typeWidth(tester, '500');

    expect(cubit.state.layout.lanes[LaneId.left]!.width, 500);

    // 再开一次：输入框必须按**当前**宽度起稿，而不是打开菜单那一刻之前的旧值。
    await _openMenu(tester, _leftTitle);
    expect(
      tester.widget<TextField>(find.byKey(laneWidthFieldKey)).controller!.text,
      '500',
      reason: '栏头徽标之外，这是用户唯一的反馈：菜单自己得承认账已经落了',
    );

    // 超范围：夹到这条泳道自己记的 maxWidth（600），而不是窗口宽。
    await _typeWidth(tester, '9999');
    expect(cubit.state.layout.lanes[LaneId.left]!.width, 600);
  });

  testWidgets('阅读器泳道：菜单改宽度会改写**视口比例**，且没有面板栏那一节', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    expect(
      cubit.state.layout.lanes[LaneId.reader]!.widthRatio,
      0.25,
      reason: '前置：阅读器泳道记的是比例',
    );

    await _openMenu(tester, _readerTitle);
    expect(
      find.text('面板栏停靠顶部'),
      findsNothing,
      reason: '阅读器泳道没有面板栏（`panelSide == null`），给了就是一条按了没用的菜单',
    );
    await _typeWidth(tester, '500');

    final after = cubit.state.layout.lanes[LaneId.reader]!;
    expect(after.width, 500);
    expect(
      after.widthRatio,
      isNot(0.25),
      reason:
          '阅读器泳道的宽度是**视口比例**（见 `LaneConfig`）：只改那个标称的像素值，'
          '改窗口大小时它会被比例重新算回去，用户输入的 500 就白丢了',
    );
    // 刻意**不**拿徽标反推视口去验「比例换算回 500」：条带会把剩余宽分给阅读器
    // 泳道（`WorkspaceStripMetrics`），所以徽标那个数不等于 `ratio * 视口` ——
    // 拿它推出来的是一条错账。换算本身由下面那条纯判据钉住。
  });

  test('setLaneWidth：像素进、比例出，并且只夹自己记的 min/max', () {
    final cubit = WorkspaceCubit();
    addTearDown(cubit.close);
    cubit.restore(
      WorkspaceLayoutSnapshot(
        mode: WorkspaceMode.swimlane,
        layout: _testLayout,
      ),
    );

    cubit.setLaneWidth(LaneId.reader, 500, 1000);
    final reader = cubit.state.layout.lanes[LaneId.reader]!;
    expect(reader.width, 500);
    expect(reader.widthRatio, closeTo(0.5, 1e-9));
    expect(reader.resolveWidth(1000), closeTo(500, 1e-9));

    // 面板泳道没有比例，只记像素；超范围夹到**自己**的 max（600），不是窗口宽。
    cubit.setLaneWidth(LaneId.left, 9999, 1000);
    expect(cubit.state.layout.lanes[LaneId.left]!.width, 600);
    expect(cubit.state.layout.lanes[LaneId.left]!.widthRatio, isNull);
    cubit.setLaneWidth(LaneId.left, 100, 1000);
    expect(cubit.state.layout.lanes[LaneId.left]!.width, 300);
  });
}
