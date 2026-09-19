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
import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/workspace_reader_target.dart';
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
}

// ── 测试用最小的宿主 ────────────────────────────────────────────────────────

const _hostName = 'LaneHostRoute';
const _targetName = 'LaneTargetRoute';

const _hostChromeText = 'HOST-CHROME';
const _openLabelA = 'OPEN-A';
const _openLabelB = 'OPEN-B';
const _targetText = 'TARGET-PAGE';

const Size _boxA = Size(300, 400);
const Size _boxB = Size(220, 300);

/// 测试窗口：远比两块卡片大，「全屏」与「开在卡片里」才分得开。
const Size _windowSize = Size(1200, 900);

const _boxAKey = ValueKey<String>('box-a');
const _boxBKey = ValueKey<String>('box-b');

/// 真 `AppRouter` 的缩微版：**继承** `RootStackRouter` 并覆写 `routes` / `guards`
/// （与 `lib/config/router/router.dart` 同一写法 —— `routes` / `guards` 在
/// `RootStackRouter` 上是**要覆写的 getter**，不是构造参数）。
class _TestRouter extends RootStackRouter {
  _TestRouter({required this.boxAVisible});

  final bool boxAVisible;

  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      page: PageInfo(
        _hostName,
        builder: (_) => _LaneHostPage(boxAVisible: boxAVisible),
      ),
      initial: true,
    ),
    AutoRoute(
      page: PageInfo(_targetName, builder: (_) => const _LaneTargetPage()),
    ),
  ];

  /// 被测对象：全站唯一的那个守卫。
  @override
  List<AutoRouteGuard> get guards => const [WorkspaceRouteGuard()];
}

Future<void> _pumpHost(WidgetTester tester, {bool boxAVisible = true}) async {
  tester.view.physicalSize = _windowSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // 先把它换成一块空 widget，**逼上一棵树整体卸载**。
  //
  // 不是仪式：`AutoRoutePage` 的 key 由路由名推出，两次 `_pumpHost` 之间是稳定的，
  // 于是 Element 会被**复用**、`EmbeddedUpstreamPage.initState` 不再执行 ——
  // 而每个用例的 `tearDown` 清过登记，复用就会让新用例里的卡片**从未登记过**，
  // 判据于是变成「全屏」而测试还以为在验卡片。卸载一次再挂，登记必然重做。
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: _TestRouter(boxAVisible: boxAVisible).config(),
    ),
  );
  await tester.pumpAndSettle();
}

class _LaneHostPage extends StatelessWidget {
  const _LaneHostPage({required this.boxAVisible});

  final bool boxAVisible;

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
                isVisible: boxAVisible,
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
      body: const Center(child: Text('TARGET-BODY')),
    );
  }
}
