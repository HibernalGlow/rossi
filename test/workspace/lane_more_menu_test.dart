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
// （`PanelTabStrip(showHandle: false)`），于是「把它挪到别的边 / 转成悬浮」
// 在界面上没有任何入口 —— 那套记账（`panelBarMode / panelBarDock`）用户读得到、
// 存得下，就是改不动。其余几条守住的是菜单与 cubit 之间别接错线。
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

/// 菜单里的那一项（`find.text` 命中的是项内的文本，往上找到菜单项本体）。
Finder _menuItem(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byType(PopupMenuItem<String>),
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

/// 打开某条泳道栏头的「更多」菜单。
Future<void> _openMenu(WidgetTester tester, String title) async {
  await tester.tap(_laneIcon(title, Icons.more_vert_rounded));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('栏头的「更多」菜单是这条泳道动作的完整清单', (tester) async {
    await _pumpWorkspace(tester);
    await _openMenu(tester, _leftTitle);

    for (final label in [
      '重置该栏宽度',
      '左移一位',
      '右移一位',
      '独占该栏',
      '折叠为紧凑条',
      '面板栏改为悬浮',
      '允许面板栏移出泳道',
      '面板栏停靠顶部',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '菜单少这一项就等于这条能力没有入口');
    }

    // 次序动作要按**当前位置**决定能不能按：最左那条没有「左移一位」。
    expect(
      tester.widget<PopupMenuItem<String>>(_menuItem('左移一位')).enabled,
      isFalse,
      reason: '左泳道已经是第一条，往左移没有落点 —— 该置灰而不是按了没反应',
    );
    expect(
      tester.widget<PopupMenuItem<String>>(_menuItem('右移一位')).enabled,
      isTrue,
    );
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
      reason: '前置：挂进栏头的形态**不画拖动把手** —— 右键菜单那条路走不通',
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
          '挪出栏头之后把手必须回来：否则用户只是**又**把自己关进一个'
          '「改不动」的形态，这次连菜单都找不回去了',
    );
  });

  testWidgets('独占项读的是记账，不是生效值', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    cubit.toggleSoloLane(LaneId.left);
    await tester.pumpAndSettle();
    // 激活别的泳道会让左泳道的 solo **不再生效**，但偏好仍然记着。
    cubit.activateLane(LaneId.right);
    await tester.pumpAndSettle();

    expect(
      cubit.state.layout.soloLaneId,
      LaneId.left,
      reason: '前置：solo 记在左泳道上',
    );
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

  testWidgets('左移 / 右移一位改的是泳道次序', (tester) async {
    final cubit = await _pumpWorkspace(tester);

    await _openMenu(tester, _readerTitle);
    await tester.tap(find.text('左移一位'));
    await tester.pumpAndSettle();

    expect(
      cubit.state.layout.laneOrder,
      const <String>[LaneId.reader, LaneId.left, LaneId.right],
      reason: '与「按住栏头图标拖到邻泳道」同一套记账（reorderLane）',
    );
  });

  testWidgets('阅读器泳道不出现面板栏那一节', (tester) async {
    await _pumpWorkspace(tester);
    await _openMenu(tester, _readerTitle);

    expect(find.text('重置该栏宽度'), findsOneWidget);
    expect(
      find.text('面板栏停靠顶部'),
      findsNothing,
      reason: '阅读器泳道没有面板栏（`panelSide == null`），给了就是一条按了没用的菜单',
    );
  });
}
