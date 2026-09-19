// 泳道栏头「更多」菜单的判据。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/workspace/lane_more_menu_test.dart
//
// （本机必须解掉 `HTTP_PROXY`：沙箱代理会劫持 `flutter_tester` 的 WebSocket
//   握手，症状是 `Unable to connect to flutter_tester process:
//   Invalid WebSocket upgrade request`。这与被测代码无关。）
//
// 这个菜单存在的**全部理由**是第 2 条：默认形态下面板栏挂进栏头、不画拖动把手
// （`PanelTabStrip(showHandle: false)`），于是「把它挪到别的边 / 转成悬浮」在界面上
// 没有任何入口 —— 那套记账（`panelBarMode / panelBarDock / panelBarConstrained`）
// 用户读得到、存得下，就是改不动。其余几条守住的是菜单与 cubit 之间别接错线。
//
// 项集对齐 neoview 的 `ReaderLaneMoreMenu`；**窗口控件那一节刻意不做**（用户要求）。
//
// 夹具与 `swimlane_runtime_test.dart` 同源：泳道内容用替身
// （`debugLaneContentBuilder`），真内容是上游 `BookshelfPage` / `ComicReadPage`，
// 在这里建不起来；被测的是栏头与记账，与内容无关。
//
// ignore_for_file: avoid_print
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
    ]) {
      expect(
        find.text(label),
        findsOneWidget,
        reason: '菜单少这一项，就等于这条能力在界面上没有入口',
      );
    }
  });

  testWidgets('页签条挂进栏头（没有把手）时，菜单能把面板栏挪到别的边', (
    tester,
  ) async {
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

  testWidgets('阅读器泳道：宽度写回**视口比例**，且没有面板栏那一节', (
    tester,
  ) async {
    final cubit = await _pumpWorkspace(tester);
    final before = cubit.state.layout.lanes[LaneId.reader]!;
    expect(before.widthRatio, 0.25, reason: '前置：阅读器泳道记的是比例');

    // 视口宽不写死：从栏头那个宽度徽标反推（徽标显示的就是条带算出来的
    // `resolveWidth(viewportWidth)`）。写死一个数的判据会在条带内边距
    // 被改动的那天开始假失败。
    final viewport =
        double.parse(_chipText(tester, _readerTitle)!.replaceAll('px', '')) /
        before.widthRatio!;

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
    expect(
      after.resolveWidth(viewport),
      closeTo(500, 1),
      reason: '比例换算回来必须还是 500',
    );
  });
}

/// 栏头那颗宽度徽标（`'${resolvedWidth.toInt()}px'`）。
String? _chipText(WidgetTester tester, String title) {
  final texts = tester.widgetList<Text>(
    find.descendant(of: _laneScope(title), matching: find.byType(Text)),
  );
  final hit = texts
      .map((t) => t.data)
      .whereType<String>()
      .where((d) => d.endsWith('px'))
      .toList();
  expect(hit, hasLength(1), reason: '一条泳道的栏头只该有一颗宽度徽标');
  return hit.single;
}
