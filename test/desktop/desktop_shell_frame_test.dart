// 「窗口全屏时，自制标题栏整条让位」的判据。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/desktop/desktop_shell_frame_test.dart
//
// （本机必须解掉 `HTTP_PROXY`：沙箱代理会劫持 `flutter_tester` 的 WebSocket
//   握手，报 `Invalid WebSocket upgrade request`。这与被测代码无关。）
//
// 这条链路只有两件事：「全屏状态这个值对不对」与「为真时那一行还在不在」。
// 前者由服务的事件入口决定，后者就是一个 `if` + `Column` —— 都跟引擎无关，
// 所以 widget test 是充分判据。
//
// **判别「让位」必须看矩形，不能只看 `findsNothing`**：把标题栏换成
// `SizedBox(height: 40)`（还在占位但已经找不到 CustomTitleBar）能让
// `findsNothing` 通过，而 `内容的 top == 0` 会当场戳穿它。所以两条都断言。
//
// 最要紧的一条是「窗口自己报的全屏」：`onWindowEnterFullScreen` 正是
// macOS 那边 ⌃⌘F / 视图菜单进全屏时发来的事件 —— 用户报的
// 「全屏了还挂着标题栏」就是这条路径没被记账。
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/service/reader/reader_desktop_fullscreen_service.dart';
import 'package:zephyr/widgets/desktop/custom_title_bar.dart';
import 'package:zephyr/widgets/desktop/desktop_shell_frame.dart';

const _contentKey = ValueKey('shell-content');

/// 标题栏高度（`custom_title_bar.dart` 里写死的 40）。
const _titleBarHeight = 40.0;

Future<void> _pumpShell(
  WidgetTester tester, {
  bool transparentTitleBar = false,
  bool titleBarFused = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: DesktopShellFrame(
        transparentTitleBar: transparentTitleBar,
        titleBarFused: titleBarFused,
        child: Container(key: _contentKey, color: const Color(0xFF123456)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double _contentTop(WidgetTester tester) =>
    tester.getRect(find.byKey(_contentKey)).top;

/// 标题栏那一层「材质」的底色。
///
/// 取 `CustomTitleBar` 里最外层那个 `Container`（`find.descendant` 是前序遍历，
/// 第一个就是它）—— 透明档要验的是**这一层不画底色**，
/// 而不是「按钮的 hover 底色变没变」。
Color? _titleBarColor(WidgetTester tester) {
  final container = tester.widget<Container>(
    find
        .descendant(
          of: find.byType(CustomTitleBar),
          matching: find.byType(Container),
        )
        .first,
  );
  return container.color;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = ReaderDesktopFullscreenService.instance;

  setUp(() {
    // 单例跨用例存活，每个用例都从「非全屏」这个确定状态起步。
    service.syncFullscreen(false);
  });

  test('窗口的全屏事件就是唯一真相：进入/离开都直接写进 notifier', () {
    expect(service.fullscreenNotifier.value, isFalse, reason: '前置：非全屏');

    service.onWindowEnterFullScreen();
    expect(service.fullscreenNotifier.value, isTrue, reason: '窗口说进了全屏');

    service.onWindowLeaveFullScreen();
    expect(service.fullscreenNotifier.value, isFalse, reason: '窗口说退了全屏');
  });

  testWidgets('非全屏：标题栏在位，内容从它下面开始', (tester) async {
    await _pumpShell(tester);

    expect(find.byType(CustomTitleBar), findsOneWidget);
    expect(
      tester.getRect(find.byType(CustomTitleBar)).height,
      _titleBarHeight,
      reason: '标题栏就是那一行 40px',
    );
    expect(_contentTop(tester), _titleBarHeight, reason: '内容顶在标题栏之下');
  });

  testWidgets('窗口自己进全屏（⌃⌘F / 视图菜单）：标题栏让位，内容顶到 y=0', (tester) async {
    await _pumpShell(tester);
    expect(find.byType(CustomTitleBar), findsOneWidget, reason: '前置：非全屏时它在');

    // 就是 macOS 在 windowDidEnterFullScreen 时发来的那一个事件。
    service.onWindowEnterFullScreen();
    await tester.pumpAndSettle();

    expect(find.byType(CustomTitleBar), findsNothing, reason: '整条不再建');
    expect(_contentTop(tester), 0, reason: '那 40px 必须还给内容，不能只藏不留');
  });

  testWidgets('窗口自己退全屏：标题栏回来，内容又让回 40px', (tester) async {
    await _pumpShell(tester);

    service.onWindowEnterFullScreen();
    await tester.pumpAndSettle();
    expect(_contentTop(tester), 0, reason: '前置：已全屏');

    service.onWindowLeaveFullScreen();
    await tester.pumpAndSettle();

    expect(find.byType(CustomTitleBar), findsOneWidget);
    expect(_contentTop(tester), _titleBarHeight, reason: '非全屏时标题栏要回来');
  });

  testWidgets('应用自己请求的全屏同样让位（阅读器里的全屏按钮走的是 syncFullscreen）', (tester) async {
    await _pumpShell(tester);

    service.syncFullscreen(true);
    await tester.pumpAndSettle();

    expect(find.byType(CustomTitleBar), findsNothing);
    expect(_contentTop(tester), 0);
  });

  group('透明标题栏开关', () {
    test('摆放判定的真值表：全屏优先，透明档再分独立行 / 融合浮层', () {
      expect(
        resolveDesktopTitleBarPlacement(
          isFullscreen: false,
          transparent: false,
        ),
        DesktopTitleBarPlacement.reserved,
        reason: '开关关着 = 改造前那一行（实色独立行）',
      );
      expect(
        resolveDesktopTitleBarPlacement(
          isFullscreen: false,
          transparent: false,
          fused: true,
        ),
        DesktopTitleBarPlacement.reserved,
        reason: 'fused 是透明档的子选项：开关关着时是死数据，不许改变摆放',
      );
      expect(
        resolveDesktopTitleBarPlacement(
          isFullscreen: false,
          transparent: true,
          fused: false,
        ),
        DesktopTitleBarPlacement.reserved,
        reason: '独立行（默认档）= 仍占一行，只是栏不画底色',
      );
      expect(
        resolveDesktopTitleBarPlacement(
          isFullscreen: false,
          transparent: true,
          fused: true,
        ),
        DesktopTitleBarPlacement.overlay,
        reason: '融合浮层 = 不占位、浮在内容上',
      );
      expect(
        resolveDesktopTitleBarPlacement(
          isFullscreen: true,
          transparent: true,
          fused: true,
        ),
        DesktopTitleBarPlacement.hidden,
        reason: '全屏优先于一切：任何档位下那一行都整条让位',
      );
    });

    testWidgets('透明 + 独立行（默认）：栏仍占 40px、内容从它下面开始，且不画底色', (tester) async {
      await _pumpShell(tester, transparentTitleBar: true);

      expect(
        _contentTop(tester),
        _titleBarHeight,
        reason: '独立行不改摆放：内容还是顶在标题栏之下',
      );
      expect(find.byType(CustomTitleBar), findsOneWidget);
      expect(
        _titleBarColor(tester),
        Colors.transparent,
        reason: '这一层不许画底色 —— 页面背景要从它底下连上来',
      );
    });

    testWidgets('透明 + 融合浮层：那 40px 让给内容，标题栏浮在上面、不画底色', (tester) async {
      await _pumpShell(tester, transparentTitleBar: true, titleBarFused: true);

      // 「不占位」必须看矩形：只看 `findsOneWidget` 不能区分占位与浮层。
      expect(_contentTop(tester), 0, reason: '内容顶到窗口顶部（独立行这里是 40）');
      expect(
        find.byType(CustomTitleBar),
        findsOneWidget,
        reason: '透明 ≠ 不建：应用名与窗口按钮还要挂在那儿',
      );
      expect(
        tester.getRect(find.byType(CustomTitleBar)).height,
        _titleBarHeight,
        reason: '浮层自己还是那 40px 高，只是不再占内容的位置',
      );
      expect(
        _titleBarColor(tester),
        Colors.transparent,
        reason: '这一层不许再画底色，否则「透明」名不副实',
      );
    });

    testWidgets('开关关着时底色照旧是主题 surface（与透明档成对断言）', (tester) async {
      await _pumpShell(tester);

      expect(_contentTop(tester), _titleBarHeight, reason: '前置：占着那一行');
      expect(
        _titleBarColor(tester),
        isNot(Colors.transparent),
        reason: '关着的时候必须还有底色 —— 否则「开了才透明」这个结论不成立',
      );
    });

    testWidgets('透明（融合浮层）+ 窗口全屏：整条不建，内容仍然顶到 y=0', (tester) async {
      await _pumpShell(tester, transparentTitleBar: true, titleBarFused: true);
      expect(find.byType(CustomTitleBar), findsOneWidget, reason: '前置：它在');

      service.onWindowEnterFullScreen();
      await tester.pumpAndSettle();

      expect(
        find.byType(CustomTitleBar),
        findsNothing,
        reason: '任何档位下全屏都是整条让位',
      );
      expect(_contentTop(tester), 0);
    });
  });
}
