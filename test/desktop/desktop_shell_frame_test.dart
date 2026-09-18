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

Future<void> _pumpShell(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: DesktopShellFrame(
        child: Container(key: _contentKey, color: const Color(0xFF123456)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double _contentTop(WidgetTester tester) =>
    tester.getRect(find.byKey(_contentKey)).top;

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

  testWidgets('应用自己请求的全屏同样让位（阅读器里的全屏按钮走的是 syncFullscreen）', (
    tester,
  ) async {
    await _pumpShell(tester);

    service.syncFullscreen(true);
    await tester.pumpAndSettle();

    expect(find.byType(CustomTitleBar), findsNothing);
    expect(_contentTop(tester), 0);
  });
}
