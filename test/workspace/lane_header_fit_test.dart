// 泳道栏头的**让位**判据：面板图标必须完整，其余按顺序没有。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/workspace/lane_header_fit_test.dart
//
// （本机必须解掉 `HTTP_PROXY`：沙箱代理会劫持 `flutter_tester` 的 WebSocket 握手，
//   症状是 `Unable to connect to flutter_tester process:
//   Invalid WebSocket upgrade request`。这与被测代码无关。）
//
// 用户 2026-09-20 的原话：「lane 标题和 px 应该优先给面板的图标让位，优先保持
// 面板图标完整显示，包括右边的聚焦还有折叠更多菜单也都可以隐藏显示，因为可以
// 在右键通过更多菜单换出来打开」。
//
// 早先的实现是反着算的：先给标题预留 75px，剩下的封顶给页签条
// （`_panelStripBudget`）。389px 的泳道上那笔账只剩 158，而五个图标加
// 「已收起」入口要 210 上下 —— 最后一个图标被齐根裁掉，就是这张图报的缺陷。
//
// 所以这里断的是**五条不变量**，不是四个像素：
// 1. 页签**要么完整、要么右侧按钮已经全让开了** —— 反过来（图标被裁掉半截、
//    右边还占着三颗按钮）就是这次要修的那条缺陷。窄到连「把手 + 页签条」都
//    塞不下时让页签条自己滚，是最后一档而不是默认档；
// 2. 让位顺序「徽标 → 独占 → 折叠 → 更多」，越靠后越硬：于是「徽标还在」必然
//    意味着三颗按钮都还在，「独占还在」必然意味着折叠与更多都还在；
// 3. 整行不许溢出（`RenderFlex` 一溢出，flutter_test 就把黄黑斜纹当异常抛出来）；
// 4. 三颗按钮全让出去之后，**右键栏头**仍然打得开那份菜单 —— 这是「让出去不等于
//    失去功能」这句话的全部依据，也是那一档唯一还活着的入口；
// 5. **算账与画图同源**：`PanelTabStrip.titleMountedWidth` 报出来的宽必须盖得住
//    页签条实际画出来的宽。反向（算少了）就是这条缺陷的成因，而它只在
//    「图标数 × 每个图标的宽」刚好越过余量的那一档才露头，肉眼看不出来。
//
// 夹具与 `lane_more_menu_test.dart` 同源：泳道内容用替身
// （`debugLaneContentBuilder`），被测的是栏头与页签条，与内容无关。
//
// ignore_for_file: avoid_print
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/registry/workspace_panel_registry.dart';
import 'package:zephyr/workspace/widgets/panels/panel_tab_strip.dart';
import 'package:zephyr/workspace/widgets/swimlane/lane_more_menu.dart';
import 'package:zephyr/workspace/widgets/swimlane/swimlane_column.dart';
import 'package:zephyr/workspace/widgets/swimlane/swimlane_workspace.dart';

const String _leftTitle = '泳道-左';
const String _readerTitle = '泳道-中';
const String _rightTitle = '泳道-右';

/// 左泳道的 `minWidth` 刻意压到 120：判据要把这条泳道一路收窄到
/// 「三颗按钮全让出去」那一档，而默认那份夹具的 300 还留得下两颗。
const WorkspaceLayoutConfig _testLayout = WorkspaceLayoutConfig(
  laneOrder: LaneId.defaultOrder,
  lanes: <String, LaneConfig>{
    LaneId.left: LaneConfig(
      width: 400,
      minWidth: 120,
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

const Size _windowSize = Size(1200, 900);

Widget _probeContent(String laneId) => const SizedBox.expand();

/// 左泳道**当前记账**该出现在页签条上的面板（不在测试里另数一遍图标）。
List<WorkspacePanelDefinition> _tabsOn(WorkspaceCubit cubit) =>
    WorkspacePanelRegistry.I.panelsForSide(
      WorkspacePanelSide.left,
      cubit.state.board,
    );

Future<WorkspaceCubit> _pumpWorkspace(WidgetTester tester) async {
  tester.view.physicalSize = _windowSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final cubit = WorkspaceCubit();
  addTearDown(cubit.close);
  cubit.restore(
    WorkspaceLayoutSnapshot(mode: WorkspaceMode.swimlane, layout: _testLayout),
  );

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

/// 把左泳道改成 [px] 宽（`setLaneWidth` 自己会夹到夹具记的 min/max）。
Future<void> _setWidth(
  WidgetTester tester,
  WorkspaceCubit cubit,
  double px,
) async {
  cubit.setLaneWidth(LaneId.left, px, _windowSize.width);
  await tester.pumpAndSettle();
}

/// 左泳道那一条容器本身。
Finder _leftLane() => find.ancestor(
  of: find.text(_leftTitle),
  matching: find.byType(SwimlaneColumn),
);

/// 限定在左泳道那一条里找 —— 三条泳道都有栏头，图标还会跟泳道把手撞名
/// （`menu_book_rounded` 既是左泳道的把手，也是「书架」面板的页签）。
Finder _inLeftLane(Finder matcher) =>
    find.descendant(of: _leftLane(), matching: matcher, matchRoot: true);

Finder _strip() => _inLeftLane(find.byType(PanelTabStrip));

/// 某个面板的页签。**限定在页签条里**：`menu_book_rounded` 既是左泳道的把手图标，
/// 也是「书架」面板的页签图标，按泳道那一条找会一颗命中两个。
Finder _tab(String panelId) => find.descendant(
  of: _strip(),
  matching: find.byIcon(WorkspacePanelRegistry.I.find(panelId)!.icon),
);

/// 栏头右侧那三颗，以及宽度徽标。
///
/// 独占只认 `center_focus_weak_rounded`：这几条判据从不把泳道设成独占，而图标
/// 换成 `strong` 恰恰是「它此刻是独占」的记账 —— 两种都认会把「根本没画」
/// 误判成「画了，只是另一颗图标」。
Finder _solo() => _inLeftLane(find.byIcon(Icons.center_focus_weak_rounded));
Finder _collapse() =>
    _inLeftLane(find.byIcon(Icons.vertical_align_center_rounded));
Finder _more() => _inLeftLane(find.byIcon(Icons.more_vert_rounded));
Finder _badge() => _inLeftLane(find.textContaining(RegExp(r'^\d+px$')));

bool _shown(Finder finder) => finder.evaluate().isNotEmpty;

void main() {
  testWidgets('够宽时什么都不让：徽标、三颗按钮、每个图标都在', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    await _setWidth(tester, cubit, 600);

    expect(_tabsOn(cubit), isNotEmpty, reason: '夹具前提：左泳道得有页签');
    for (final panel in _tabsOn(cubit)) {
      expect(_tab(panel.id), findsOneWidget, reason: '${panel.title} 的页签没画出来');
    }
    expect(_badge(), findsOneWidget);
    expect(_solo(), findsOneWidget);
    expect(_collapse(), findsOneWidget);
    expect(_more(), findsOneWidget);
  });

  // 这条就是用户报的那个症状：389px 的泳道上最后一个图标被裁掉半截。
  testWidgets('389px：页签条一个图标都不裁，压力落在标题与徽标上', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    await _setWidth(tester, cubit, 389);

    final lane = tester.getRect(_leftLane());
    for (final panel in _tabsOn(cubit)) {
      final rect = tester.getRect(_tab(panel.id));
      expect(
        rect.right,
        lessThanOrEqualTo(lane.right - 0.5),
        reason: '${panel.title} 的页签被泳道裁掉了 —— 面板图标必须完整',
      );
      expect(rect.left, greaterThanOrEqualTo(lane.left), reason: '页签滚出了左边界');
    }
    expect(tester.takeException(), isNull, reason: '栏头整行溢出（黄黑斜纹）');
  });

  testWidgets('一路收窄：让位顺序是徽标 → 独占 → 折叠 → 更多', (tester) async {
    final cubit = await _pumpWorkspace(tester);

    for (final px in <double>[
      600,
      520,
      440,
      389,
      340,
      300,
      260,
      220,
      180,
      120,
    ]) {
      await _setWidth(tester, cubit, px);
      final reason = '左泳道 ${px.toInt()}px';
      final lane = tester.getRect(_leftLane());

      // 1. 页签要么完整，要么说明按钮已经全让开了 —— 反过来（页签都被裁了
      //    还有按钮占着位）就是这次要修的那条缺陷。
      //    刻意**不**在这里复算「多窄算装得下」：那几个数是 `_LaneChrome` 的，
      //    测试再抄一份就成了第三处口径。
      final short = <String>[];
      for (final panel in _tabsOn(cubit)) {
        final tab = _tab(panel.id);
        if (!_shown(tab)) {
          short.add(panel.title);
          continue;
        }
        final rect = tester.getRect(tab);
        if (rect.right > lane.right - 0.5 || rect.left < lane.left) {
          short.add(panel.title);
        }
      }
      if (short.isNotEmpty) {
        expect(
          _shown(_solo()) || _shown(_collapse()) || _shown(_more()),
          isFalse,
          reason:
              '$reason：${short.join('、')} 的页签不完整，'
              '而右侧按钮还没让够位置',
        );
      }

      // 2. 越硬的越后走：后面那颗还在，前面那颗就不可能已经没了。
      final badge = _shown(_badge());
      final solo = _shown(_solo());
      final collapse = _shown(_collapse());
      final more = _shown(_more());
      expect(badge && !solo, isFalse, reason: '$reason：徽标比独占先让位，顺序写反了');
      expect(solo && !collapse, isFalse, reason: '$reason：独占还占着位，折叠却先没了');
      expect(
        collapse && !more,
        isFalse,
        reason:
            '$reason：折叠还占着位，「更多」却先没了 —— '
            '而菜单是折叠与独占唯一的退路',
      );

      // 3. 不许溢出。
      expect(tester.takeException(), isNull, reason: '$reason：栏头整行溢出');
    }
  });

  testWidgets('算出来的页签条宽盖得住画出来的宽', (tester) async {
    final cubit = await _pumpWorkspace(tester);
    // 给足宽度，让页签条按内容取宽（这一档它拿到的上限不等于它的实际需求）。
    await _setWidth(tester, cubit, 600);

    final computed = PanelTabStrip.titleMountedWidth(
      WorkspacePanelSide.left,
      cubit.state.board,
    );
    final rendered = tester.getSize(_strip());
    expect(
      rendered.width,
      lessThanOrEqualTo(computed),
      reason: '算少了：栏头按这个数留位置，最后一个图标就会被裁掉',
    );
    expect(
      computed - rendered.width,
      lessThanOrEqualTo(4),
      reason: '算多了：栏头白留一段空档，标题与按钮提前让位',
    );
  });

  testWidgets('三颗按钮全让出去之后，右键栏头仍然打得开那份菜单', (tester) async {
    final cubit = await _pumpWorkspace(tester);

    // 收到最窄：连「更多」都让出去了，栏头只剩泳道图标与页签条。
    await _setWidth(tester, cubit, 120);
    expect(_shown(_solo()), isFalse, reason: '夹具前提：这一档独占该让位');
    expect(_shown(_collapse()), isFalse, reason: '夹具前提：这一档折叠该让位');
    expect(
      _shown(_more()),
      isFalse,
      reason: '夹具前提：这一档连「更多」都该让位，否则下面那条右键判据没测到点上',
    );

    // 落点选在栏头最左边的内边距上：那里既不是页签（页签自己吃右键 = 收起面板），
    // 也不是把手，只有外层那个「右键 = 本泳道菜单」的 `GestureDetector`。
    final lane = tester.getRect(_leftLane());
    await tester.tapAt(
      Offset(lane.left + 4, lane.top + 23),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(laneWidthFieldKey),
      findsOneWidget,
      reason: '按钮让位之后，这条泳道的动作全靠右键这一条路',
    );
    for (final label in ['独占该栏', '折叠为紧凑条', '面板栏停靠左侧']) {
      expect(
        find.text(label),
        findsOneWidget,
        reason: '$label 只在菜单里有 —— 菜单打不开它就是永久不可达',
      );
    }
  });
}
