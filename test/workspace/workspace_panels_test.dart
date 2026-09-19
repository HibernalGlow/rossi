// 面板操作栏的两件事：
//
//   1. **跨侧拖动的精确插入位** —— 面板被拖到另一条泳道的页签条上时，
//      必须落在光标底下那个位置，而不是永远追加到末尾；
//   2. **它自己怎么摆** —— 悬浮档摆在自己的百分比中心上（不是 `Align` 的语义），
//      拖动期间则跟随实时位置，并把**摆出来的**位置回报出去。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/workspace/workspace_panels_test.dart
//
// （本机必须解掉 `HTTP_PROXY`：沙箱代理会劫持 `flutter_tester` 的 WebSocket
//   握手，症状是 `Unable to connect to flutter_tester process:
//   Invalid WebSocket upgrade request`。这与被测代码无关。）
//
// 为什么这两件事值得单独断言：
// - 插入位是**纯记账**，但它的输入来自命中测试（指针落在哪个页签 / 哪个插缝），
//   所以只有把真实的 `DragTarget` 树搭起来、真的拖一次，才验得到；
// - 摆放位置则是**像素**：它错半个浮层宽是肉眼可见的，而错误写法
//   （`Align` / 在布局之外自己复算尺寸）都「看起来对」，只有量矩形才戳得穿。
//
// 这里只搭**页签条**、不搭泳道宿主：页签条画的是图标与标题，不需要
// ObjectBox、图源注册表、上游页面 —— 而拖动与摆放这两件事全在页签条里。
//
// ignore_for_file: avoid_print
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_panel_bar.dart';
import 'package:zephyr/workspace/registry/workspace_ids.dart';
import 'package:zephyr/workspace/registry/workspace_panel_registry.dart';
import 'package:zephyr/workspace/widgets/panels/panel_bar_positioner.dart';
import 'package:zephyr/workspace/widgets/panels/panel_tab_strip.dart';

// ── 夹具 ────────────────────────────────────────────────────────────────────

/// 页签上的图标 —— 用**注册表里那份定义**的图标来认页签。
/// 写死图标名会让「注册表换了图标」变成判据失败，而那不是我们想断言的事。
IconData _tabIcon(String panelId) {
  final panel = WorkspacePanelRegistry.I.find(panelId);
  expect(panel, isNotNull, reason: '夹具前提：$panelId 必须在注册表里');
  return panel!.icon;
}

/// 某一侧**当前**显示的面板序列（就是记账算给用户看的那个次序）。
List<String> _idsOn(WorkspaceCubit cubit, WorkspacePanelSide side) => [
  for (final panel in WorkspacePanelRegistry.I.panelsForSide(
    side,
    cubit.state.board,
  ))
    panel.id,
];

Future<WorkspaceCubit> _pumpStrips(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 620);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final cubit = WorkspaceCubit();
  addTearDown(cubit.close);

  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<WorkspaceCubit>.value(
        value: cubit,
        child: const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 两侧都按「内联」搭（`bounds` 留空）：摆放规则另有专门用例，
                // 这里只关心拖动落点，别把两件事混在一个失败里。
                PanelTabStrip(side: WorkspacePanelSide.left),
                SizedBox(height: 48),
                PanelTabStrip(side: WorkspacePanelSide.right),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cubit;
}

/// 真的把一个页签拖到另一个页签上。
///
/// 三步都不能省：`LongPressDraggable` 要先过它自己的长按延时（220ms）；
/// 延时过后还得有一次超过 slop 的位移才会真的开始拖
/// （`DelayedMultiDragGestureRecognizer` 认的是「延时到了 **且** 指针动过」）；
/// 最后落到目标上再松手。
Future<void> _dragTabOnto(
  WidgetTester tester, {
  required String panelId,
  required String ontoPanelId,
}) async {
  // 先把两个坐标取好：拖动期间浮层里也有一份图标，事后再找会找到两个。
  final from = tester.getCenter(find.byIcon(_tabIcon(panelId)));
  final onto = tester.getCenter(find.byIcon(_tabIcon(ontoPanelId)));

  final gesture = await tester.startGesture(from);
  await tester.pump(const Duration(milliseconds: 280));
  await gesture.moveBy(const Offset(0, -24));
  await tester.pump();
  await gesture.moveTo(onto);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  // ── 1 / 2：插入位 ────────────────────────────────────────────────────────

  testWidgets('跨侧拖动落在光标底下那个位置，不是永远追加到末尾', (tester) async {
    final cubit = await _pumpStrips(tester);
    expect(_idsOn(cubit, WorkspacePanelSide.right), <String>[
      WorkspacePanelId.discover,
      WorkspacePanelId.fileManager,
      WorkspacePanelId.pageList,
      WorkspacePanelId.plugins,
      WorkspacePanelId.tools,
    ], reason: '前置：右泳道的默认次序');

    // 左泳道的「下载」拖到右泳道「文件管理」那个页签上 = 插到它**前面**。
    await _dragTabOnto(
      tester,
      panelId: WorkspacePanelId.download,
      ontoPanelId: WorkspacePanelId.fileManager,
    );

    expect(
      _idsOn(cubit, WorkspacePanelSide.right),
      <String>[
        WorkspacePanelId.discover,
        WorkspacePanelId.download,
        WorkspacePanelId.fileManager,
        WorkspacePanelId.pageList,
        WorkspacePanelId.plugins,
        WorkspacePanelId.tools,
      ],
      reason:
          '契约：拖到哪儿就落在哪儿。早先版本把跨侧拖入固定写成 '
          '`insertIndex: siblings.length`（永远追加），'
          '于是无论往哪儿放，面板都跑到最后一位 —— '
          '「插在「工具」前面」与「排在「工具」后面」在结果上是两件不同的事',
    );
    expect(_idsOn(cubit, WorkspacePanelSide.left), <String>[
      WorkspacePanelId.bookshelf,
      WorkspacePanelId.favorite,
      WorkspacePanelId.history,
    ], reason: '搬走了就真的从原来那侧消失（成员关系只有一处可改）');
  });

  testWidgets('不可移动的页签也是落点：插到它前面，而不是掉回「追加」', (tester) async {
    final cubit = await _pumpStrips(tester);

    // 「工具」是 `canMove: false` 的上游整页面板 —— 它自己不能被拖走，
    // 但「插到它前面」是一个合法的落点。
    await _dragTabOnto(
      tester,
      panelId: WorkspacePanelId.download,
      ontoPanelId: WorkspacePanelId.tools,
    );

    expect(
      _idsOn(cubit, WorkspacePanelSide.right),
      <String>[
        WorkspacePanelId.discover,
        WorkspacePanelId.fileManager,
        WorkspacePanelId.pageList,
        WorkspacePanelId.plugins,
        WorkspacePanelId.download,
        WorkspacePanelId.tools,
      ],
      reason:
          '「不能移动」只说明它不能被拖走，**不**说明别的东西不能插到它前面。'
          '把这两件事混起来的话，5 个面板里有 3 个（书架 / 发现 / 工具）'
          '会落在拖放系统之外 —— 往它们身上拖一律掉回「追加到末尾」，'
          '而那正是这次要修掉的那个症状',
    );
  });

  testWidgets('轨内换位：拖到左边那个位置就真的插到那儿', (tester) async {
    final cubit = await _pumpStrips(tester);

    // 「文件管理」是右泳道第 1 位，「发现（上游原版）」是第 0 位 ——
    // 拖到它身上 = 插到它前面。
    await _dragTabOnto(
      tester,
      panelId: WorkspacePanelId.fileManager,
      ontoPanelId: WorkspacePanelId.discover,
    );

    expect(
      cubit.state.activePanel[WorkspacePanelSide.right.laneId],
      WorkspacePanelId.fileManager,
      reason:
          '先证明这一拖**真的被接住了**：落点接受之后会把面板切成当前面板。'
          '只看「次序对不对」是不够的 —— 整个手势什么都没发生时，'
          '「次序没变」和「次序按预期变了」一样容易蒙对',
    );
    expect(
      _idsOn(cubit, WorkspacePanelSide.right),
      <String>[
        WorkspacePanelId.fileManager,
        WorkspacePanelId.discover,
        WorkspacePanelId.pageList,
        WorkspacePanelId.plugins,
        WorkspacePanelId.tools,
      ],
      reason:
          '轨内换位必须真的能动。早先 `_shouldAcceptAt` 写的是 '
          '`draggedId != _dragging`，而被拖的那个页签的 id **就是** `_dragging` —— '
          '于是每个落点都把「本条自己正在拖」这一支拒掉，整条轨内换位不可达',
    );
  });

  testWidgets('轨内换位：拖到自己右侧紧邻的那个位置 = 次序不变', (tester) async {
    final cubit = await _pumpStrips(tester);

    // 「文件管理」是右泳道第 1 位，「页面导航」是第 2 位 ——
    // 「插到页面导航前面」而它本来就紧挨在页面导航前面，所以结果应当是原地不动。
    await _dragTabOnto(
      tester,
      panelId: WorkspacePanelId.fileManager,
      ontoPanelId: WorkspacePanelId.pageList,
    );

    expect(
      cubit.state.activePanel[WorkspacePanelSide.right.laneId],
      WorkspacePanelId.fileManager,
      reason:
          '先证明这一拖**真的被接住了**（落点接受后会把面板切成当前面板）——'
          '否则下面那条「次序不变」在「什么都没发生」时也会通过（变异体 M26 就是这么漏掉的）',
    );
    expect(
      _idsOn(cubit, WorkspacePanelSide.right),
      <String>[
        WorkspacePanelId.discover,
        WorkspacePanelId.fileManager,
        WorkspacePanelId.pageList,
        WorkspacePanelId.plugins,
        WorkspacePanelId.tools,
      ],
      reason:
          '同一序列里换位要把**自己那一格**扣掉（拖动时自己还在序列里，'
          '不扣就偏一格）。不扣的话它会原地后移一位跑到末尾，'
          '用户看到的是「轻轻拖了一下，它自己跳到后面去了」',
    );
  });

  // ── 3：悬浮档的摆放 ──────────────────────────────────────────────────────

  testWidgets('悬浮的面板栏摆在自己的百分比中心上（CSS 语义，不是 Align）', (tester) async {
    const barKey = ValueKey<String>('bar');
    const containerKey = ValueKey<String>('container');
    const containerSize = Size(800, 600);
    Offset? reported;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              key: containerKey,
              width: containerSize.width,
              height: containerSize.height,
              child: PanelBarPositioner(
                layout: const PanelBarLayout(
                  mode: PanelBarMode.floating,
                  positionX: 25,
                  positionY: 75,
                ),
                boundsOf: (_) => const PanelBarBounds(
                  left: 0,
                  top: 0,
                  width: 800,
                  height: 600,
                ),
                onPositioned: (offset) => reported = offset,
                child: const SizedBox(key: barKey, width: 100, height: 30),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 用**相对容器原点**的位移断言：容器落在窗口哪儿与这条判据无关。
    final containerRect = tester.getRect(find.byKey(containerKey));
    final barRect = tester.getRect(find.byKey(barKey));
    final topLeft = barRect.topLeft - containerRect.topLeft;
    final center = barRect.center - containerRect.topLeft;

    expect(
      center,
      const Offset(200, 450),
      reason:
          '契约（neoview 的 barStyle）：`left: p%` 配合 `translate(-50%, -50%)` '
          '⇒ 浮层的**中心**落在容器的 p% 处。25% → 200、75% → 450。'
          '换成 `Align` 会算成 (175, 435)：`Align` 是「把子节点的左边缘从容器左边 '
          '扫到右边」，两者只在 50% 处重合，在 10% / 90% 处差半个浮层宽',
    );
    expect(
      topLeft,
      const Offset(150, 435),
      reason: '中心对上了还不够 —— 左上角也要对（半宽 50 / 半高 15）',
    );
    expect(
      reported,
      topLeft,
      reason:
          'onPositioned 报的必须是**摆出来的**那个位置：拖动起点就是它。'
          '报成按公式复算的近似值，表现是「一开始拖它就跳一下」',
    );
  });

  testWidgets('拖动期间按实时位置摆，规则让位', (tester) async {
    const barKey = ValueKey<String>('bar');
    const containerKey = ValueKey<String>('container');
    const live = Offset(320, 210);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              key: containerKey,
              width: 800,
              height: 600,
              child: PanelBarPositioner(
                // 钉在顶部：若实时位置没生效，它会跑到顶部居中（x=350, y=4）
                layout: const PanelBarLayout(
                  mode: PanelBarMode.pinned,
                  dock: PanelBarDock.top,
                ),
                boundsOf: (_) => const PanelBarBounds(
                  left: 0,
                  top: 0,
                  width: 800,
                  height: 600,
                ),
                liveOffset: live,
                child: const SizedBox(key: barKey, width: 100, height: 30),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final containerRect = tester.getRect(find.byKey(containerKey));
    expect(
      tester.getRect(find.byKey(barKey)).topLeft - containerRect.topLeft,
      live,
      reason:
          '拖动期间浮层跟的是**光标**，不是任何一条规则算出来的位置；'
          '让规则赢的表现是「拖到一半它自己弹回边上」',
    );
  });
}
