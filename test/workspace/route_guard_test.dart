// 「面板里点开的东西开在面板里」的判据。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/workspace/route_guard_test.dart
//
// （本机必须解掉 `HTTP_PROXY`：沙箱代理会劫持 `flutter_tester` 的 WebSocket
//   握手，症状是 `Unable to connect to flutter_tester process:
//   Invalid WebSocket upgrade request`。这与被测代码无关。）
//
// 为什么可以是 widget test（而不必真机引擎）：这条链路全是**框架层**行为 ——
// 守卫拦不拦、局部 `Navigator` 收不收得住、页面落在哪个矩形里，全由
// `RenderObject` 与 `Navigator` 决定，跟引擎的解码器/平台视图无关。
// （这与「判解码能力只能用真机引擎」不矛盾：那条是解码，这条是布局与导航。）
//
// 判别落点的办法是**位置与尺寸**：卡片 A 是 300×400、B 是 220×300，窗口是
// 1200×900，所以「开在卡片里」与「铺满整个应用」在矩形上一眼可分。
//
// ignore_for_file: avoid_print
import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/router/router.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_reader_target.dart';
import 'package:zephyr/workspace/router/workspace_back_interception.dart';
import 'package:zephyr/workspace/router/workspace_lane_dispatch.dart';
import 'package:zephyr/workspace/router/workspace_navigation_bridge.dart';
import 'package:zephyr/workspace/router/workspace_route_guard.dart';
import 'package:zephyr/workspace/widgets/containers/embedded_upstream_page.dart';

void main() {
  // 与真工作台一样：`attachReader` 登记了才算「工作台在场」。
  late void Function(WorkspaceReaderTarget) onOpenReader;

  setUp(() => onOpenReader = (_) {});

  tearDown(() {
    WorkspaceNavigationBridge.instance.detachReader(onOpenReader);
    WorkspaceLaneDispatch.instance.reset();
  });

  testWidgets('面板里点开的页面开在面板里，不铺满整个应用', (tester) async {
    WorkspaceNavigationBridge.instance.attachReader(onOpenReader);
    await _pumpHost(tester);

    final boxA = tester.getRect(find.byKey(_boxAKey));
    expect(find.text(_targetText), findsNothing, reason: '还没点，不该有目标页');

    await tester.tap(find.text(_openLabelA));
    await tester.pumpAndSettle();

    expect(find.text(_targetText), findsOneWidget, reason: '页面必须真的被渲染出来');
    expect(
      tester.getRect(find.byType(_LaneTargetPage)),
      boxA,
      reason:
          '页面的矩形必须与卡片 A 严丝合缝 —— 尺寸和位置都对得上，'
          '才是「开在这块卡片里」而不是「铺满整个应用」',
    );
    expect(
      find.byType(BackButton),
      findsOneWidget,
      reason: '卡片里出现返回箭头 ⇒ 退得回卡片原来的内容（局部 Navigator 能 pop）',
    );
  });

  testWidgets('两块卡片各落各的：在哪块里点就开在哪块', (tester) async {
    WorkspaceNavigationBridge.instance.attachReader(onOpenReader);
    await _pumpHost(tester);

    final boxB = tester.getRect(find.byKey(_boxBKey));
    final boxA = tester.getRect(find.byKey(_boxAKey));
    expect(boxA.width, isNot(boxB.width), reason: '两块卡片尺寸不同，落点才可分辨');

    await tester.tap(find.text(_openLabelB));
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byType(_LaneTargetPage)),
      boxB,
      reason: '必须落进被点的那块，不能落进上半秒还在交互的那块',
    );
  });

  testWidgets('没有工作台时逐字不变：推入照旧铺满整个应用', (tester) async {
    // 不 attachReader ⇒ 守卫必须原样放行
    await _pumpHost(tester);

    await tester.tap(find.text(_openLabelA));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(_LaneTargetPage));
    expect(rect.topLeft, Offset.zero, reason: '没有工作台时行为与改造前一致 —— 全屏');
    expect(rect.width, _windowSize.width);
    expect(rect.height, _windowSize.height);
  });

  testWidgets('落点不明（面板不可见）时宁可全屏，也不开进看不见的地方', (tester) async {
    WorkspaceNavigationBridge.instance.attachReader(onOpenReader);
    await _pumpHost(tester, boxAVisible: false);

    await tester.tap(find.text(_openLabelA));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(_LaneTargetPage));
    expect(
      rect.topLeft,
      Offset.zero,
      reason: '不可见的面板不是落点 ⇒ 不接管 ⇒ 全屏（比「点了没反应」好）',
    );
  });

  testWidgets('点到第二块卡片后，第一块不再是落点', (tester) async {
    WorkspaceNavigationBridge.instance.attachReader(onOpenReader);
    await _pumpHost(tester);

    await tester.tap(find.text(_openLabelA));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(_LaneTargetPage)),
      tester.getRect(find.byKey(_boxAKey)),
    );

    // 回到卡片 A 的原内容（局部栈 pop），再去点 B。
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(_targetText), findsNothing, reason: '返回后目标页应当消失');

    await tester.tap(find.text(_openLabelB));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(_LaneTargetPage)),
      tester.getRect(find.byKey(_boxBKey)),
      reason: '落点要跟着**最后一次交互**走，不能锁死在先点的那块',
    );
  });

  // 插件界面（`SearchRoute` 那条链：图源卡片 → 该插件的搜索界面）顶部那个返回
  // 箭头是**上游自己画的** `IconButton(onPressed: () => context.maybePop())`。
  // `context.maybePop()` → `AutoRouter.of(context)` → 就近的 `StackRouterScope`；
  // 面板里那条局部 `Navigator` 上方如果没有自己的 scope，就近的就是**根路由**，
  // 于是这一下弹掉的是根栈顶页 = 整个工作台 —— 用户看到的就是「退出整个泳道」。
  testWidgets('插件界面里自己画的返回键退的是面板里那一页，不是整个工作台', (tester) async {
    WorkspaceNavigationBridge.instance.attachReader(onOpenReader);
    final router = await _pumpHost(tester, startAtHome: true);
    expect(find.text(_homeText), findsOneWidget, reason: '首屏是工作台下面那一页');

    // 真实进入方式：工作台是**裸 `Navigator.push`** 上来的整页
    // （`auto_route` 自己的栈里没有它，见 `_handleOpenInLane` 的说明）。
    // 必须摆出这一层 —— 根栈只有一页时 `Navigator.maybePop` 会 bubble 而不弹，
    // 那样这里就没法复现「退出整个泳道」。
    unawaited(
      router.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const _LaneHostPage(boxAVisible: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(_hostChromeText), findsOneWidget, reason: '工作台已经在根栈顶上');

    // 在面板里点开一页 —— 它就站在「插件的界面」那个位置。
    await tester.tap(find.text(_openLabelA));
    await tester.pumpAndSettle();
    expect(find.text(_targetText), findsOneWidget);

    await tester.tap(find.text(_upstreamBackLabel));
    await tester.pumpAndSettle();

    expect(find.text(_targetText), findsNothing, reason: '面板里那一页必须真的退掉');
    expect(
      find.text(_hostChromeText),
      findsOneWidget,
      reason: '工作台必须还在 —— 退的是面板里那一页，不是整个泳道',
    );
  });

  // 接管不能**过**头。工作台上面压着别的东西时，那一下「返回」想弹的是**它自己**
  // （`showDialog` 默认落在根 Navigator 上），泳道必须让开 —— 否则症状是
  // 「对话框关不掉，反而把面板里那一页退掉了」。
  testWidgets('工作台上面压着对话框时，对话框里的返回只关对话框', (tester) async {
    WorkspaceNavigationBridge.instance.attachReader(onOpenReader);
    final router = await _pumpHost(tester, startAtHome: true);

    unawaited(
      router.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const _LaneHostPage(boxAVisible: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(_openLabelA));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_openDialogLabel));
    await tester.pumpAndSettle();
    expect(find.text(_closeDialogLabel), findsOneWidget, reason: '对话框开出来了');

    await tester.tap(find.text(_closeDialogLabel));
    await tester.pumpAndSettle();

    expect(find.text(_closeDialogLabel), findsNothing, reason: '对话框必须关掉');
    expect(
      find.text(_targetText),
      findsOneWidget,
      reason: '面板里那一页不能被连坐退掉 —— 那一下不是冲它来的',
    );
    expect(find.text(_hostChromeText), findsOneWidget, reason: '工作台更不能被连坐');
  });

  // 接管的**下界**：把 `Esc` / 鼠标侧键那条出口留着（两者走的都是根路由的
  // `maybePop`）。面板里已经没得更退时，这一下必须还回根栈。
  testWidgets('面板里已经没得更退时，这一下返回仍然退出工作台', (tester) async {
    WorkspaceNavigationBridge.instance.attachReader(onOpenReader);
    final router = await _pumpHost(tester, startAtHome: true);

    unawaited(
      router.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const _LaneHostPage(boxAVisible: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(_hostChromeText), findsOneWidget, reason: '工作台在根栈顶上');

    // 面板首页上的返回：局部栈里只有摊在屏幕上的那一页。
    // （两块面板各有一个同名按钮，点第一块 —— 落点就是它。）
    await tester.tap(find.text(_laneRootBackLabel).first);
    await tester.pumpAndSettle();

    expect(
      find.text(_hostChromeText),
      findsNothing,
      reason: '没得更退 ⇒ 还回根栈 —— 这条出口丢了，键盘侧就出不去工作台',
    );
    expect(find.text(_homeText), findsOneWidget, reason: '退回了工作台下面那一页');
  });

  // 阅读器泳道那块内容**没有自己的局部栈**（不上报导航器），但必须参与落点记账 ——
  // 否则用户在阅读器里按下之后落点还停在旧面板上，那边的一下「返回」会退错对象。
  test('阅读器泳道登记之后就能成为落点，注销之后不再是', () {
    final bridge = WorkspaceNavigationBridge.instance;
    const reader = WorkspaceLaneHost(LaneId.reader, 'reader');
    addTearDown(() => bridge.detachLaneContent(reader));

    bridge.attachLaneContent(reader);
    bridge.noteLaneInteraction(reader);
    expect(
      WorkspaceLaneDispatch.instance.resolveTarget(),
      reader,
      reason: '登记过的内容才算活主机，交互才记得住',
    );

    bridge.detachLaneContent(reader);
    expect(
      WorkspaceLaneDispatch.instance.resolveTarget(),
      isNull,
      reason: '空画布 / 卸载之后不能再当落点（那会从真面板手里抢走落点）',
    );
  });

  // 上面几条验的是**接缝本身**（mixin 的覆写）。但「生产路由真的挂了它」是另一件事：
  // 判据里用的是缩微路由，`AppRouter` 少写一个 `with` 的时候，上面每一条**照样全绿**。
  // 所以这条单独钉住那一行接线。
  test('生产路由真的挂了回退接线', () {
    expect(
      AppRouter(),
      isA<WorkspaceBackInterceptor>(),
      reason:
          '`AppRouter` 必须 `with WorkspaceBackInterceptor` —— 少了这一行，'
          '面板里的一下「返回」又会弹掉整个工作台（用户报的那个 bug）',
    );
  });
}

// ── 测试用最小的宿主 ────────────────────────────────────────────────────────

const _hostName = 'LaneHostRoute';
const _targetName = 'LaneTargetRoute';

/// 「工作台下面那一页」（真实里是 `NavigationBar` 首页）。只在复现「工作台被
/// 裸 push 在别人上面」时才用到 —— 它得有个名字，才判得出工作台有没有被连坐弹掉。
const _homeName = 'LaneHomeRoute';

const _hostChromeText = 'HOST-CHROME';
const _homeText = 'HOME-PAGE';
const _openLabelA = 'OPEN-A';
const _openLabelB = 'OPEN-B';
const _targetText = 'TARGET-PAGE';

/// 上游那种**自己画的**返回键的标签（见 `_LaneTargetPage`）。
const _upstreamBackLabel = 'UPSTREAM-BACK';

/// 面板首页上那种 `context.maybePop()`（见 `_FakeUpstreamPage`）。
const _laneRootBackLabel = 'LANE-ROOT-BACK';

/// 对话框：开它 / 关它（关那一下也是 `context.pop()`，见 `_LaneTargetPage`）。
const _openDialogLabel = 'OPEN-DIALOG';
const _closeDialogLabel = 'CLOSE-DIALOG';

const Size _boxA = Size(300, 400);
const Size _boxB = Size(220, 300);

/// 测试窗口：远比两块卡片大，「全屏」与「开在卡片里」才分得开。
const Size _windowSize = Size(1200, 900);

const _boxAKey = ValueKey<String>('box-a');
const _boxBKey = ValueKey<String>('box-b');

/// 真 `AppRouter` 的缩微版：**继承** `RootStackRouter` 并覆写 `routes` / `guards`
/// （与 `lib/config/router/router.dart` 同一写法 —— `routes` / `guards` 在
/// `RootStackRouter` 上是**要覆写的 getter**，不是构造参数）。
/// 判据用的缩微路由：与真 `AppRouter` 用**同一个** [WorkspaceBackInterceptor]。
///
/// 这一点是判据成立的前提 —— 接缝若写在 `AppRouter` 里，这里就只能再造一个同款
/// 覆写，那时候验的是判据自己的实现。
class _TestRouter extends RootStackRouter with WorkspaceBackInterceptor {
  _TestRouter({required this.boxAVisible, this.startAtHome = false});

  final bool boxAVisible;

  /// 首屏是不是那一页「工作台下面的页面」。
  ///
  /// 默认（false）首屏就是泳道宿主，与之前一致；置真时首屏换成 [_HomePage]，
  /// 于是用例可以自己用**裸 `Navigator.push`** 把泳道宿主压上去 ——
  /// 这正是真实工作台的进入方式（`auto_route` 栈里根本没有它这一页）。
  final bool startAtHome;

  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      page: PageInfo(_homeName, builder: (_) => const _HomePage()),
      initial: startAtHome,
    ),
    AutoRoute(
      page: PageInfo(
        _hostName,
        builder: (_) => _LaneHostPage(boxAVisible: boxAVisible),
      ),
      initial: !startAtHome,
    ),
    AutoRoute(
      page: PageInfo(_targetName, builder: (_) => const _LaneTargetPage()),
    ),
  ];

  /// 被测对象：全站唯一的那个守卫。
  @override
  List<AutoRouteGuard> get guards => const [WorkspaceRouteGuard()];
}

Future<_TestRouter> _pumpHost(
  WidgetTester tester, {
  bool boxAVisible = true,
  bool startAtHome = false,
}) async {
  tester.view.physicalSize = _windowSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = _TestRouter(
    boxAVisible: boxAVisible,
    startAtHome: startAtHome,
  );

  // 先把它换成一块空 widget，**逼上一棵树整体卸载**。
  //
  // 不是仪式：`AutoRoutePage` 的 key 由路由名推出，两次 `_pumpHost` 之间是稳定的，
  // 于是 Element 会被**复用**、`EmbeddedUpstreamPage.initState` 不再执行 ——
  // 而每个用例的 `tearDown` 清过登记，复用就会让新用例里的卡片**从未登记过**，
  // 判据于是变成「全屏」而测试还以为在验卡片。卸载一次再挂，登记必然重做。
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp.router(routerConfig: router.config()));
  await tester.pumpAndSettle();
  return router;
}

/// 「工作台下面那一页」。内容刻意极简：它只是根栈里的**第二页**，
/// 用来把「工作台不是根栈唯一一页」这个真实条件摆出来。
class _HomePage extends StatelessWidget {
  const _HomePage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text(_homeText)));
  }
}

/// 泳道宿主（真工作台的替身）。
///
/// 除了摆出那两块卡片，它还做**真工作台做的另一件事**：把自己那一页登记给
/// `WorkspaceNavigationBridge`。不登记的话，「返回」的接管判据（`workspaceIsOnTop`）
/// 永远为假 —— 而那是真 `BreezeWorkspacePage.didChangeDependencies` 里的动作，
/// 替身漏掉它，判据就会**假绿**（看起来"没接管"，其实是没人登记）。
class _LaneHostPage extends StatefulWidget {
  const _LaneHostPage({required this.boxAVisible});

  final bool boxAVisible;

  @override
  State<_LaneHostPage> createState() => _LaneHostPageState();
}

class _LaneHostPageState extends State<_LaneHostPage> {
  ModalRoute<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      _route = route;
      WorkspaceNavigationBridge.instance.attachWorkspaceRoute(route);
    }
  }

  @override
  void dispose() {
    final route = _route;
    if (route != null) {
      WorkspaceNavigationBridge.instance.detachWorkspaceRoute(route);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 「卡片外面」的东西
          const Text(_hostChromeText),
          Row(
            children: [
              _box(
                key: _boxAKey,
                label: _openLabelA,
                host: const WorkspaceLaneHost('left', 'shelf'),
                size: _boxA,
                isVisible: widget.boxAVisible,
              ),
              _box(
                key: _boxBKey,
                label: _openLabelB,
                host: const WorkspaceLaneHost('right', 'tools'),
                size: _boxB,
                isVisible: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _box({
    required Key key,
    required String label,
    required WorkspaceLaneHost host,
    required Size size,
    required bool isVisible,
  }) {
    return SizedBox(
      width: size.width,
      height: size.height,
      child: EmbeddedUpstreamPage(
        key: key,
        host: host,
        instanceKey: host.debugKey,
        isVisible: isVisible,
        builder: (_) => _FakeUpstreamPage(label: label),
      ),
    );
  }
}

/// 假装是上游那一整页（书架的 `BookshelfPage` / 工具的 `MorePage`）。
///
/// 刻意**不带 Scaffold**：面板里那块内容本来就没有自己的脚手架
/// （卡片面板更是如此），顺带把这条也验了。
class _FakeUpstreamPage extends StatelessWidget {
  const _FakeUpstreamPage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('UPSTREAM-PAGE'),
          TextButton(
            // 上游的写法：`context.pushRoute(XxxRoute())`，这里用等价的
            // `context.router.push(PageRouteInfo(...))`，不必生成路由类。
            onPressed: () =>
                context.router.push(const PageRouteInfo<void>(_targetName)),
            child: Text(label),
          ),
          TextButton(
            // 面板**首页**上的一下 `context.maybePop()`（`login_page.dart` 那种）。
            // 这时局部栈里只有摊在屏幕上的这一页 —— 没得更退，
            // 这一下必须**还回根栈**（= 退出工作台），否则键盘侧没有出口。
            onPressed: () => context.maybePop(),
            child: const Text(_laneRootBackLabel),
          ),
        ],
      ),
    );
  }
}

class _LaneTargetPage extends StatelessWidget {
  const _LaneTargetPage();

  @override
  Widget build(BuildContext context) {
    // 带 AppBar：自动返回箭头只在「这条局部栈能 pop」时才出现 ——
    // 它出现在卡片里，就是「退得回卡片原来的内容」的证据。
    // （`AppBar` 不是 const 构造，所以这层不能写 const。）
    return Scaffold(
      appBar: AppBar(title: const Text(_targetText)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('TARGET-BODY'),
            // 上游**自己画**的返回键，写法照抄 `page/search/widget/search_bar.dart`
            // 与 `page/search_result/view/search_bar.dart`：
            // `context.maybePop()` 走 auto_route 的 `AutoRouter.of(context)`，
            // **不是** `Navigator.maybePop(context)`，两条路的落点可以完全不同。
            TextButton(
              onPressed: () => context.maybePop(),
              child: const Text(_upstreamBackLabel),
            ),
            TextButton(
              // 对话框走**根** Navigator（`showDialog` 默认 `useRootNavigator: true`），
              // 于是它压在「工作台」上面 —— 那一刻根栈顶不是工作台，
              // 里面的 `context.pop()` 想关的是它自己。接管必须让开。
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('DIALOG'),
                  actions: [
                    TextButton(
                      // 上游对话框里的写法（`widgets/dialog.dart` 就是它）。
                      onPressed: () => dialogContext.pop(),
                      child: const Text(_closeDialogLabel),
                    ),
                  ],
                ),
              ),
              child: const Text(_openDialogLabel),
            ),
          ],
        ),
      ),
    );
  }
}
