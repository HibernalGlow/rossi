// 「一切持久化（重启回默认）」的判据。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/workspace/layout_persistence_test.dart
//
// （本机必须解掉 `HTTP_PROXY`：沙箱代理会劫持 `flutter_tester` 的 WebSocket
//   握手，症状是 `Unable to connect to flutter_tester process:
//   Invalid WebSocket upgrade request`。这与被测代码无关。）
//
// 这一组判据要回答的是**三个不同层**的问题，缺一个都会漏：
//
// 1. **去抖**（`WorkspaceLayoutPersistence`）：拖分隔条时状态每帧都在变，
//    落盘必须合并成一次；但退出前的 `flush` 必须真的立刻写掉。
// 2. **重置的两半**：状态回默认**以及**磁盘上那份作废。只做前一半的症状是
//    「重置了，重启之后又变回去了」—— 一个用户没法解释的现象。
// 3. **页面这层的接线**（`BreezeWorkspacePage`）：启动真的去读盘、变化真的
//    去落盘、刚读回来的东西**不会**被立刻原样写回去。
//
// 第 3 层必须把这一页真的挂起来才验得到，所以这里复用页面上那个
// `debugLaneContentBuilder` 口子给泳道塞轻量替身（真内容是上游
// `BookshelfPage` / `ComicReadPage`，要 ObjectBox、图源注册表、应用数据目录）。
//
// 时间怎么走：这些用例只依赖 `Timer`（去抖窗口），不依赖 `Stopwatch`，
// 所以 `tester.pump(Duration)`（推**测试**时钟）就够，不必像驻留那组判据
// 那样真等 —— 但**必须**有 `pump`，否则定时器不触发、判据会「绿得莫名其妙」。
//
// ignore_for_file: avoid_print
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/breeze_workspace_page.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_interaction_settings.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/model/workspace_panel_bar.dart';
import 'package:zephyr/workspace/service/workspace_layout_store.dart';
import 'package:zephyr/workspace/widgets/swimlane/swimlane_column.dart';

// ── 夹具 ────────────────────────────────────────────────────────────────────

/// 出厂默认里那条左泳道的标题（`WorkspaceLayoutConfig.defaults()`）。
/// 「重置回默认」这条判据靠它区分「读回来的那份」与「刚刚被重置的那份」。
const String _defaultLeftTitle = '书架 (Bookshelf)';

/// 一份「用户改过」的快照：每一项都取**非默认**值，于是「读回来了没有」
/// 在界面上、在字段上一眼可辨。
const String _restoredLeftTitle = 'RESTORED-LEFT';
const String _defaultReaderTitle = '阅读器 (Reader)';

const String _restoredRightTitle = 'RESTORED-RIGHT';

const Size _windowSize = Size(1200, 900);

WorkspaceLayoutSnapshot _customSnapshot() => WorkspaceLayoutSnapshot(
  mode: WorkspaceMode.swimlane,
  layout: const WorkspaceLayoutConfig(
    laneOrder: LaneId.defaultOrder,
    lanes: <String, LaneConfig>{
      LaneId.left: LaneConfig(
        width: 400,
        minWidth: 300,
        maxWidth: 600,
        title: _restoredLeftTitle,
      ),
      LaneId.reader: LaneConfig(
        width: 300,
        widthRatio: 0.25,
        minWidth: 300,
        maxWidth: 900,
        title: _defaultReaderTitle,
      ),
      LaneId.right: LaneConfig(
        width: 400,
        minWidth: 300,
        maxWidth: 600,
        title: _restoredRightTitle,
      ),
    },
  ),
  activeLaneId: LaneId.right,
  // `showTopChrome: true`：最后一例是从**顶栏**按「重置布局」的，而顶栏默认不画
  // （`WorkspaceInteractionSettings.showTopChrome`）—— 那一档本身由
  // `top_chrome_test.dart` 第 4 节管，这里只要按钮在。
  interaction: const WorkspaceInteractionSettings(
    edgeRevealDelayMs: 111,
    showTopChrome: true,
  ),
);

/// 泳道内容的轻量替身 —— 页面的持久化接线与泳道内容无关，别让真内容挡路。
Widget _probeContent(String laneId) => Center(child: Text('content-$laneId'));

Future<void> _pumpPage(
  WidgetTester tester, {
  required WorkspaceLayoutStore store,
}) async {
  tester.view.physicalSize = _windowSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // 先把整棵树换成空 widget，**逼上一棵树整体卸载**：`pumpWidget` 之间
  // Element 会按类型复用，于是第二个用例里 `BreezeWorkspacePage.initState`
  // 不再执行、启动读盘那条线根本没跑，而判据还以为在验它。
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MaterialApp(
      home: BreezeWorkspacePage(
        store: store,
        debugLaneContentBuilder: _probeContent,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _laneButton(String laneTitle, IconData icon) => find.descendant(
  of: find.ancestor(
    of: find.text(laneTitle),
    matching: find.byType(SwimlaneColumn),
  ),
  matching: find.byIcon(icon),
);

void main() {
  // ── 1：去抖与 flush ─────────────────────────────────────────────────────

  testWidgets('去抖：连续改动只落最后一次盘', (tester) async {
    final store = WorkspaceLayoutMemoryStore();
    final persistence = WorkspaceLayoutPersistence(store: store);
    addTearDown(persistence.dispose);

    // 模拟「一边拖分隔条一边变状态」：三次改动都落在去抖窗口内。
    for (var i = 1; i <= 3; i++) {
      persistence.schedule(_customSnapshot().copyWithLeftWidth(300 + i * 10.0));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(store.writes, 0, reason: '三次改动都还在去抖窗口（420ms）内，一次盘都不该写');

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(store.writes, 1, reason: '去抖做错时的症状就是「写入次数跟着状态变化次数走」');
    expect(
      (await store.load())!.layout.lanes[LaneId.left]!.width,
      330.0,
      reason: '写下去的必须是**最后一次**，不是第一次（否则拖到一半的中间态会被存住）',
    );
  });

  testWidgets('flush：窗口没到也立刻写掉；没有压着的东西时一次都不写', (tester) async {
    final store = WorkspaceLayoutMemoryStore();
    final persistence = WorkspaceLayoutPersistence(store: store);
    addTearDown(persistence.dispose);

    persistence.schedule(_customSnapshot());
    expect(store.writes, 0, reason: '前置：还没到窗口');

    await persistence.flush();
    expect(
      store.writes,
      1,
      reason: '「拖完立刻关窗口」这一下正落在去抖窗口里 —— 退出前的 flush 必须真的写掉',
    );

    await persistence.flush();
    expect(
      store.writes,
      1,
      reason:
          '没有压着的改动时 flush 应当什么都不做：它会被无条件调用，'
          '白写一次盘在慢盘上是一次可感的卡顿',
    );
  });

  // ── 2：重置的两半 ───────────────────────────────────────────────────────

  testWidgets('resetLayout：激活泳道与交互设置也一并回默认', (tester) async {
    final cubit = WorkspaceCubit();
    addTearDown(cubit.close);

    cubit.activateLane(LaneId.reader);
    cubit.setInteraction(
      const WorkspaceInteractionSettings(
        hoverFocusEnabled: false,
        hoverFocusDelayMs: 900,
        edgeRevealDelayMs: 900,
        edgeRevealRestoreDelayMs: 900,
        readerPeekWidth: 20,
      ),
    );
    cubit.setLanePanelBar(
      LaneId.left,
      const PanelBarLayout(mode: PanelBarMode.floating, positionX: 12),
    );
    cubit.toggleLaneCollapsed(LaneId.left);

    cubit.resetLayout();

    expect(cubit.state.activeLaneId, isNull, reason: '激活泳道属于「用户的布局偏好」');
    expect(
      cubit.state.interaction,
      const WorkspaceInteractionSettings(),
      reason: '留下「延时还是我改的那个」比不重置更难解释',
    );
    expect(cubit.state.layout.lanes[LaneId.left]!.collapsed, isFalse);
    expect(
      cubit.state.layout.lanes[LaneId.left]!.panelBar,
      const PanelBarLayout(),
      reason: '面板栏记账也回默认（钉回顶部、限制在泳道内）',
    );
    expect(cubit.state.layout.soloLaneId, isNull);
  });

  // ── 3：页面这一层的接线 ─────────────────────────────────────────────────

  testWidgets('冷启动：读回上次那一份，而且不会刚读完就原样写回去', (tester) async {
    final store = WorkspaceLayoutMemoryStore();
    await store.save(_customSnapshot());
    final before = store.writes;

    await _pumpPage(tester, store: store);

    expect(
      find.text(_restoredLeftTitle),
      findsOneWidget,
      reason: '界面用的是快照里那份布局 ⇒ 启动读盘这条线是通的',
    );
    expect(
      find.text(_defaultLeftTitle),
      findsNothing,
      reason: '出厂默认那一份已经被替换掉了（不是「读过但没用」）',
    );

    await tester.pump(const Duration(milliseconds: 600));
    expect(
      store.writes,
      before,
      reason:
          '刚读回来的东西不该被立刻原样写回去：纯浪费，而且在慢盘上会与'
          '下一次真实改动抢同一个文件',
    );
  });

  testWidgets('全新安装：用出厂默认，也没有无端写盘', (tester) async {
    final store = WorkspaceLayoutMemoryStore();

    await _pumpPage(tester, store: store);

    expect(find.text(_defaultLeftTitle), findsOneWidget);
    expect(store.writes, 0, reason: '什么都没改 —— 启动不该产生一次写盘（没有存过 ≠ 需要存一份默认的）');
  });

  testWidgets('界面上改一下：去抖之后落盘，存的是改后的那一份', (tester) async {
    final store = WorkspaceLayoutMemoryStore();
    // 先存一份**宽度可控**的快照：出厂默认的阅读器比例是 0.5，在 1200 宽的
    // 窗口下整条带会比视口宽，右泳道的栏头按钮就落到屏幕外了 ——
    // 那样判据变成在验「点没点到」，而不是在验落盘。
    await store.save(_customSnapshot());
    await _pumpPage(tester, store: store);
    final before = store.writes;

    // 真的在界面上改：点右泳道栏头的折叠按钮。
    await tester.tap(
      _laneButton(_restoredRightTitle, Icons.vertical_align_center_rounded),
    );
    await tester.pump();

    expect(store.writes, before, reason: '还没过去抖窗口，不该已经写盘（拖分隔条时每帧都在变）');

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(store.writes, before + 1, reason: '改动必须落盘');
    expect(
      (await store.load())!.layout.lanes[LaneId.right]!.collapsed,
      isTrue,
      reason: '而且落下去的必须是**这一下改动**，不是别的什么',
    );
  });

  testWidgets('「重置布局」把磁盘上那份一起作废，否则重启又变回去', (tester) async {
    final store = WorkspaceLayoutMemoryStore();
    await store.save(_customSnapshot());

    await _pumpPage(tester, store: store);
    expect(
      find.text(_restoredLeftTitle),
      findsOneWidget,
      reason: '前置：这一轮启动读的是自定义那份',
    );

    // 从**顶栏**按「重置布局」。顶栏是悬停揭示的：先把鼠标贴到窗口最顶端
    // 召唤它（x 取 2 —— 落在那 8px 内边距里，不算「进了某条泳道」，
    // 免得顺带触发悬停驻留，把这条判据变得取决于真实时间走多快）。
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer(location: const Offset(2, 300));
    await tester.pump();
    await pointer.moveTo(const Offset(2, 5));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // 淡入动画

    await tester.tap(find.byTooltip('重置布局（不影响当前正在读的这一本）'));
    await tester.pumpAndSettle();

    expect(
      await store.load(),
      isNull,
      reason:
          '只重置内存状态的话，重启之后旧快照会把它覆盖回来 —— '
          '用户看到的是「重置了，但重启又变回来了」',
    );
    expect(
      find.text(_defaultLeftTitle),
      findsOneWidget,
      reason: '界面同时回到出厂默认（状态那一半也要生效）',
    );
  });
}

/// 只为了造出「一次次略有不同的快照」——去抖判据要能分辨「写的是最后一次」。
extension on WorkspaceLayoutSnapshot {
  WorkspaceLayoutSnapshot copyWithLeftWidth(double width) {
    final lane = layout.lanes[LaneId.left]!;
    return WorkspaceLayoutSnapshot(
      mode: mode,
      layout: layout.copyWith(
        lanes: <String, LaneConfig>{
          ...layout.lanes,
          LaneId.left: lane.copyWith(width: width),
        },
      ),
      board: board,
      activePanel: activePanel,
      activeLaneId: activeLaneId,
      interaction: interaction,
    );
  }
}
