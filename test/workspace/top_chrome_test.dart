// 工作台顶栏**两种形态**的判据：桌面悬停揭示 / 触摸屏常驻。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/workspace/top_chrome_test.dart
//
// （本机必须解掉 `HTTP_PROXY`：沙箱代理会劫持 `flutter_tester` 的 WebSocket
//   握手，症状是 `Unable to connect to flutter_tester process:
//   Invalid WebSocket upgrade request`。这与被测代码无关。）
//
// 要回答的问题：**触摸屏上那个出口到底在不在、够不够得着。**
// 背景：工作台是 `Navigator.push` 上来的整页，**没有系统返回按钮** ——
// 桌面端靠「顶栏悬停揭示 + `Esc`」出去，而这两条在触摸屏上一条都成立不了
// （`MouseRegion` 永远不触发）。所以非桌面平台必须保留**常驻**顶栏。
//
// 形态由 `defaultTargetPlatform` 决定，判据用 `testWidgets` 的
// `variant: TargetPlatformVariant.only(...)` 把它设好（框架自己的机制，
// 会在测试体跑完后还原）—— `dart:io` 的 `Platform` 在测试里改不动，
// 这也是被测代码选前者而不是后者的原因之一。
//
// 三条判别纪律：
//
// 1. **判「占不占地方」用矩形，不用 `findsOneWidget`**。两种形态里顶栏
//    **都**「在树上」，区别只在矩形：揭示形态恒为 0..46 且内容也从 0 开始
//    （两层重叠），常驻形态内容从 46 开始（有状态栏时是 46+状态栏）。
//    `findsOneWidget` 在两种形态下都对，等于没验。
// 2. **「没生效」必须配一条「真的生效了」**。只说「点退出没反应」在按钮
//    压根找不到时也通过；所以那条判据是「召唤前点不着、召唤后点得着」成对的。
//    同理，「触摸屏按一下就能退出」不能只断言按钮在，要让**路由真的被弹掉**。
// 3. **平台显式核对**。形态靠 `variant` 设定，而 `variant` 忘了写不会报错 ——
//    判据会静默退回**宿主平台**（本机是 macOS）而看起来照样绿。
//    所以 `_openWorkspace` 头一件事就是把 `defaultTargetPlatform` 与
//    调用方声明的那个对上。
//
// 分工：**三档桌面 / 三档触摸的映射**由本文第 0 节穷举（纯逻辑）；
// **两种形态的布局后果**各用一个代表平台在 widget 层实测
// （桌面 macOS、触摸 android）—— 布局与平台无关，没必要跑六遍。
//
// ignore_for_file: avoid_print
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/breeze_workspace_page.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/service/workspace_layout_store.dart';
import 'package:zephyr/workspace/widgets/chrome/workspace_top_chrome.dart';
import 'package:zephyr/workspace/widgets/swimlane/swimlane_workspace.dart';

// ── 夹具 ────────────────────────────────────────────────────────────────────

const Size _windowSize = Size(1200, 900);

/// 「没有指针」那一档的代表。[TargetPlatformVariant.mobile] 是它的全集，
/// 但布局后果与哪一档无关，实测一个就够（映射由第 0 节穷举）。
const TargetPlatform _touch = TargetPlatform.android;

/// 「有指针」那一档的代表。[TargetPlatformVariant.desktop] 是它的全集。
const TargetPlatform _desktop = TargetPlatform.macOS;

/// 状态栏内边距（**物理**像素 —— 这里的 `devicePixelRatio` 是 1，与逻辑像素等价）。
const double _statusBar = 44;

/// 泳道内容的轻量替身：真内容是上游 `BookshelfPage` / `ComicReadPage`，
/// 要 ObjectBox、图源注册表、应用数据目录，判据里起不来。
/// 顶栏的形态与内容无关，所以替身只换「内容由谁构造」。
Widget _probeContent(String laneId) => Center(child: Text('content-$laneId'));

/// 把工作台**真的推成一条路由**再验。
///
/// 不用 `MaterialApp(home: BreezeWorkspacePage(...))`：那样工作台是**根路由**，
/// `maybePop` 什么都不做，「退出按钮到底生没生效」根本看不出来。
/// 推成一条路由之后，「点了退出 ⇒ 这一页从树上消失」才是可断言的行为。
Future<void> _openWorkspace(
  WidgetTester tester, {
  required TargetPlatform declaredPlatform,
  required WorkspaceLayoutStore store,
  FakeViewPadding padding = const FakeViewPadding(),
}) async {
  // 见文件头第 3 条：忘了写 `variant` 时这一条先红 —— 否则判据会静默
  // 退回宿主平台，看着照样绿。
  expect(
    defaultTargetPlatform,
    declaredPlatform,
    reason:
        '调用方声明的是 $declaredPlatform，实际跑的是 $defaultTargetPlatform —— '
        '`variant: TargetPlatformVariant.only(...)` 写漏了',
  );

  tester.view.physicalSize = _windowSize;
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = padding;
  addTearDown(tester.view.reset);

  // 先把整棵树换成空 widget，**逼上一棵树整体卸载**：`pumpWidget` 之间
  // Element 会按类型复用，第二个用例里 `initState` 就不再执行了。
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(home: _Launcher(store: store)));
  await tester.tap(find.text('打开工作台'));
  await tester.pumpAndSettle();
}

Finder get _bar => find.byType(WorkspaceTopChrome);
Finder get _content => find.byType(SwimlaneWorkspace);
Finder get _exitButton => find.byIcon(Icons.arrow_back_rounded);

/// 顶栏与内容各自的矩形 —— 两种形态的全部差别都在这里。
({Rect bar, Rect content}) _rects(WidgetTester tester) =>
    (bar: tester.getRect(_bar), content: tester.getRect(_content));

/// 揭示形态当前的淡入程度。
///
/// 「可见」与「吃不吃鼠标」是**两个独立机制**（`AnimatedOpacity` 与
/// `IgnorePointer`），所以两者各要一条判据：只验其中一个的话，
/// 另一个坏掉判据照样绿（变异体 M41 / M42 就是分别打这两处）。
double _revealOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(WorkspaceTopChromeReveal),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

void main() {
  // ── 0：形态映射（纯逻辑，不挂 widget 树）────────────────────────────────

  test('形态映射：三桌面 ⇒ 揭示，三触摸 ⇒ 常驻', () {
    for (final platform in TargetPlatform.values) {
      final hasPointer =
          platform == TargetPlatform.windows ||
          platform == TargetPlatform.macOS ||
          platform == TargetPlatform.linux;
      expect(
        WorkspaceTopChromeMode.forTargetPlatform(platform),
        hasPointer
            ? WorkspaceTopChromeMode.reveal
            : WorkspaceTopChromeMode.persistent,
        reason:
            '$platform：判据是**这个平台有没有鼠标指针**。'
            '把触摸屏判成揭示的症状是「用户进得来出不去」',
      );
    }
  });

  // ── 1：触摸屏（没有指针）—— 顶栏必须常驻 ────────────────────────────────

  testWidgets('触摸屏：顶栏占一行真实高度，内容从它下面开始', (tester) async {
    await _openWorkspace(
      tester,
      declaredPlatform: _touch,
      store: WorkspaceLayoutMemoryStore(),
    );

    final r = _rects(tester);
    expect(r.bar.top, 0);
    expect(
      r.bar.height,
      WorkspaceTopChrome.barHeight,
      reason: '常驻顶栏的高度就是那一行（分隔线算在这之内，不该多出 1px）',
    );
    expect(
      r.content.top,
      r.bar.bottom,
      reason:
          '内容必须**正好**从顶栏下面开始：常驻却把内容压在下面的话，'
          '用户会永远看不见内容的第一行',
    );
    expect(
      r.content.height,
      _windowSize.height - WorkspaceTopChrome.barHeight,
      reason: '顶栏那 46px 是从内容里让出来的，不是凭空多出来的',
    );
    expect(_bar, findsOneWidget, reason: '顶栏只能有一条');
    expect(
      find.byType(WorkspaceTopChromeReveal),
      findsNothing,
      reason: '触摸屏上没有 hover，揭示形态在那儿等于没有出口',
    );
  }, variant: TargetPlatformVariant.only(_touch));

  testWidgets('触摸屏：退出按钮**第一下**就生效（不需要任何 hover）', (tester) async {
    await _openWorkspace(
      tester,
      declaredPlatform: _touch,
      store: WorkspaceLayoutMemoryStore(),
    );

    expect(_bar, findsOneWidget, reason: '前置：顶栏在');

    // 触摸屏上唯一能发生的事就是「按一下」。没有鼠标、没有 Esc，
    // 如果这一下不生效，用户就出不去工作台了。
    await tester.tap(_exitButton);
    await tester.pumpAndSettle();

    expect(
      find.byType(BreezeWorkspacePage),
      findsNothing,
      reason: '按一下就该回到进入前那一页',
    );
    expect(find.text('打开工作台'), findsOneWidget, reason: '确实回到了发起进入的那一页');
  }, variant: TargetPlatformVariant.only(_touch));

  testWidgets('触摸屏：顶栏把状态栏一起吃掉，那一截也铺成顶栏的底色', (tester) async {
    await _openWorkspace(
      tester,
      declaredPlatform: _touch,
      store: WorkspaceLayoutMemoryStore(),
      padding: const FakeViewPadding(top: _statusBar),
    );

    final r = _rects(tester);
    expect(
      r.bar.top,
      0,
      reason:
          '顶栏要**从窗口最顶端**开始铺（底色铺到状态栏下面）：'
          '把 SafeArea 套在整列外面的话，状态栏那一条会露出 Scaffold 的底色，'
          '与顶栏之间出现一道色差',
    );
    expect(
      r.bar.height,
      WorkspaceTopChrome.barHeight + _statusBar,
      reason: '总高 = 那一行 + 状态栏',
    );
    expect(
      r.content.top,
      WorkspaceTopChrome.barHeight + _statusBar,
      reason: '内容既不该被顶栏压住，也不该再躲一次状态栏（那样会白空出一条）',
    );
  }, variant: TargetPlatformVariant.only(_touch));

  // ── 2：桌面（有指针）—— 保持悬停揭示 ────────────────────────────────────

  testWidgets('桌面：顶栏不占高度，内容仍从窗口最顶端铺满', (tester) async {
    await _openWorkspace(
      tester,
      declaredPlatform: _desktop,
      store: WorkspaceLayoutMemoryStore(),
    );

    final r = _rects(tester);
    expect(
      r.content.top,
      0,
      reason:
          '桌面端「内容从顶上铺满」这条不能因为加了常驻形态而丢掉：'
          '泳道模式下每条泳道已经自带栏头，再压一条常驻顶栏就是第二层顶栏'
          '（上面还叠着系统标题栏）',
    );
    expect(r.bar.top, 0);
    expect(
      r.bar.height,
      WorkspaceTopChrome.barHeight,
      reason: '揭示形态恒为 46 高 —— 揭示时正好接管泳道栏头那一行',
    );
    expect(
      r.bar.bottom > r.content.top,
      isTrue,
      reason: '它是**叠在内容之上**的浮层（这是揭示形态唯一的代价）',
    );
    expect(_bar, findsOneWidget, reason: '顶栏只能有一条');
  }, variant: TargetPlatformVariant.only(_desktop));

  // ── 3：揭示形态本身：默认不吃鼠标 / 召唤之后才生效 ──────────────────────

  // 这一段直接挂 `WorkspaceTopChromeReveal`，用自己记的计数当探针 ——
  // 在工作台整页里「点退出」的结果是路由被弹掉，但在这一层只需要知道
  // 「这一下有没有真的落到按钮上」。平台无关，所以不给 variant。
  testWidgets('揭示形态：默认不吃鼠标，鼠标贴到窗口最顶端之后才可点', (tester) async {
    var exits = 0;
    final cubit = WorkspaceCubit();
    addTearDown(cubit.close);

    tester.view.physicalSize = _windowSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      BlocProvider<WorkspaceCubit>.value(
        value: cubit,
        child: MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const Positioned.fill(
                  child: ColoredBox(color: Color(0xFF123456)),
                ),
                WorkspaceTopChromeReveal(
                  onExit: () => exits++,
                  onResetLayout: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // ① 默认：不可见、也不吃鼠标 —— 点下去什么都不该发生。
    expect(
      _revealOpacity(tester),
      0,
      reason: '默认透明：它是叠在内容上层的浮层，一直亮着就是把内容顶部那一行盖掉',
    );
    await tester.tap(_exitButton, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      exits,
      0,
      reason:
          '顶栏默认 `IgnorePointer`：它挡在内容上面，'
          '要是还吃鼠标，用户就点不到内容顶部那一块了',
    );

    // ② 鼠标贴到窗口最顶端，把触发带唤出来。
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer(location: const Offset(600, 300));
    await tester.pump();
    await pointer.moveTo(
      const Offset(600, WorkspaceTopChrome.triggerHeight / 2),
    );
    // 两帧：第一帧让 `onEnter` 改状态，第二帧让 `MouseTracker` 把
    // 「现在谁在指针底下」重新算一遍（顶栏这时才结束 `IgnorePointer`）。
    await tester.pump();
    await tester.pump();
    await pointer.moveTo(const Offset(600, 25)); // 进到顶栏本体上
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // 淡入

    // ③ 这一下必须真的落到退出按钮上（与 ① 成对：不是「反正都点不到」）。
    expect(
      _revealOpacity(tester),
      1,
      reason: '召唤出来之后就得是看得见的',
    );
    await tester.tap(_exitButton);
    await tester.pumpAndSettle();
    expect(
      exits,
      1,
      reason: '召唤出来之后它就得是能点的 —— 否则桌面端也没有出口（只剩 Esc）',
    );
  });
}

/// 发起进入工作台的那一页。
class _Launcher extends StatelessWidget {
  const _Launcher({required this.store});

  final WorkspaceLayoutStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              // 名字要给：工作台靠它判断「我是不是栈顶」，`_handleOpenInLane`
              // 的 `popUntil` 也按它匹配。
              settings: const RouteSettings(name: BreezeWorkspacePage.routeName),
              builder: (_) => BreezeWorkspacePage(
                store: store,
                debugLaneContentBuilder: _probeContent,
              ),
            ),
          ),
          child: const Text('打开工作台'),
        ),
      ),
    );
  }
}
