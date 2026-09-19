// 桌面窗口全屏的**记账契约**判据。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/desktop/reader_fullscreen_ownership_test.dart
//
// 用户报：「开始阅读以后，它会把当前软件的全屏给退出。」
//
// 根因不在「谁按了什么键」，而在**两本账混成了一本**：阅读器拿「窗口现在是不是
// 全屏」（`isFullScreen()`）当自己的账，并于 `dispose` 时「还」回去。于是
// **用户自己**按 ⌃⌘F 进的全屏，在阅读器换实例时（工作台泳道里换书、详情页点
// 「开始阅读」）被阅读器强行退掉了。
//
// 所以这里钉的不是「调了哪个 API」，而是三件事：
//   1. 窗口自己报的全屏事件 = 用户/系统的行为 ⇒ **不算应用借的**；
//   2. 阅读器 bootstrap 时的对齐读取（`syncFullscreen`）⇒ **不算应用借的**；
//   3. 只有应用主动请求过（`setFullscreen(true)`）的全屏，才轮到
//      `releaseRequestedFullscreen()` 去还。
//
// 后两条的「不做」正是修复本身：旧实现里 `dispose` 无条件 `syncFullscreen(false)`
// 并把窗口按回非全屏，这两条用例都会红。
//
// 测试环境里没有 window_manager 插件，`setFullScreen` 必然抛 MissingPluginException
// —— 这里把它当成「它**真的去动窗口了**」的正向证据（见 `_touchWindowApi`）。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/service/reader/reader_desktop_fullscreen_service.dart';

/// 调一次会碰窗口 API 的操作，返回「它是否真的尝试过」。
///
/// 测试环境没有插件 ⇒ 调用必然失败；**失败即证明它动手了**，
/// 成功反而是没调（例如提前 return 的空转）。
Future<bool> _touchWindowApi(Future<void> Function() action) async {
  try {
    await action();
    return false;
  } on MissingPluginException {
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = ReaderDesktopFullscreenService.instance;

  setUp(() {
    // 单例跨用例存活，每个用例都从「非全屏、没有借出的全屏」起步。
    service.syncFullscreen(false);
  });

  test('窗口自己进的全屏（⌃⌘F / 视图菜单）：不算应用借的', () {
    service.onWindowEnterFullScreen();

    expect(service.fullscreenNotifier.value, isTrue, reason: '窗口说进了全屏');
    expect(
      service.appRequestedFullscreen,
      isFalse,
      reason: '这次全屏是用户自己要的，应用没有借',
    );
  });

  test('窗口自己进的全屏：退出阅读器时不许替他退出（本次 bug 的回归判据）', () async {
    service.onWindowEnterFullScreen();
    expect(service.fullscreenNotifier.value, isTrue, reason: '前置：已全屏');

    // 阅读器 dispose 时调的就是它。
    final touched = await _touchWindowApi(service.releaseRequestedFullscreen);

    expect(touched, isFalse, reason: '不该去动窗口 —— 白得的东西不能替用户还回去');
    expect(
      service.fullscreenNotifier.value,
      isTrue,
      reason: '全屏还在（旧实现会在这里把它按成 false，于是自制标题栏挂回来）',
    );
  });

  test('阅读器 bootstrap 的对齐读取：只对齐通知，不算借', () async {
    // 阅读器打开时做的事：读窗口一眼 → 对齐通知状态。
    service.syncFullscreen(true);

    expect(service.fullscreenNotifier.value, isTrue, reason: '通知与窗口对齐');
    expect(service.appRequestedFullscreen, isFalse, reason: 'sync 只是读，不是借');

    final touched = await _touchWindowApi(service.releaseRequestedFullscreen);
    expect(touched, isFalse, reason: '没借过 ⇒ 退出阅读器时什么都不做');
    expect(service.fullscreenNotifier.value, isTrue, reason: '窗口还全屏着');
  });

  test('应用自己借的全屏（阅读器里的全屏按钮）：退出阅读器时才还', () async {
    expect(
      await _touchWindowApi(() => service.setFullscreen(true)),
      isTrue,
      reason: '应用主动请求 ⇒ 真的去调窗口 API 了',
    );
    expect(service.appRequestedFullscreen, isTrue, reason: '这次是应用借的');
    expect(service.fullscreenNotifier.value, isTrue, reason: '先乐观更新');

    expect(
      await _touchWindowApi(service.releaseRequestedFullscreen),
      isTrue,
      reason: '借了就要还 ⇒ 去调窗口 API',
    );
    expect(service.appRequestedFullscreen, isFalse, reason: '还完就不欠了');
    expect(service.fullscreenNotifier.value, isFalse, reason: '窗口该回到非全屏');
  });

  test('窗口自己报的事件会把「应用借的」清掉（用户按 ⌃⌘F 进来）', () async {
    // 先让应用借一次（`setFullscreen` 会抛，但记账已经写进去了）。
    await _touchWindowApi(() => service.setFullscreen(true));
    expect(service.appRequestedFullscreen, isTrue, reason: '前置：应用借过');

    // 用户按 ⌃⌘F（或视图菜单）：窗口自己报的全屏事件。
    service.onWindowEnterFullScreen();

    expect(
      service.appRequestedFullscreen,
      isFalse,
      reason: '窗口自己报的事件一律算用户的行为，应用不再持有这次全屏',
    );
  });
}
