import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/util/input/reader_input_bridge.dart';
import 'package:zephyr/util/input/reader_input_context.dart';

/// 阅读器按键转交的门控：只有 `reader` context 活跃时才转交。
///
/// 这是「打开设置面板后左右键失效」那个 bug 的结构性判据 ——
/// 设置面板不给 `reader` 引入竞争者，于是左右键仍由 `reader` 解析。
void main() {
  final event = KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.arrowRight,
    logicalKey: LogicalKeyboardKey.arrowRight,
    timeStamp: Duration.zero,
  );

  test('reader context 活跃才转交；其它泳道（panel）不转交', () {
    final bridge = ReaderInputBridge.instance;
    var calls = 0;
    KeyEventResult handler(KeyEvent _) {
      calls++;
      return KeyEventResult.handled;
    }

    bridge.attach(handler);
    addTearDown(() => bridge.detach(handler));

    bridge.setActiveContexts(const <ReaderInputContext>{
      ReaderInputContext.reader,
    });
    expect(bridge.readerContextActive, isTrue);
    expect(bridge.dispatch(event), KeyEventResult.handled);
    expect(calls, 1, reason: 'reader 活跃时应转交一次');

    bridge.setActiveContexts(const <ReaderInputContext>{
      ReaderInputContext.panel,
    });
    expect(bridge.readerContextActive, isFalse);
    expect(bridge.dispatch(event), KeyEventResult.ignored);
    expect(calls, 1, reason: 'panel 活跃时不应再转交');
  });

  test('没有登记处理器时不转交（照常往下冒泡）', () {
    final bridge = ReaderInputBridge.instance;
    bridge.setActiveContexts(const <ReaderInputContext>{
      ReaderInputContext.reader,
    });
    expect(bridge.readerContextActive, isFalse);
    expect(bridge.dispatch(event), KeyEventResult.ignored);
  });

  test('context 优先级与 global 隔离与 neoview 一致', () {
    // 数值逐条对齐 neoview 的 READER_INPUT_CONTEXT_PRIORITY。
    expect(ReaderInputContext.global.priority, 0);
    expect(ReaderInputContext.reader.priority, 100);
    expect(ReaderInputContext.video.priority, 150);
    expect(ReaderInputContext.panel.priority, 200);
    expect(ReaderInputContext.shell.priority, 250);
    expect(ReaderInputContext.editor.priority, 300);
    expect(ReaderInputContext.modal.priority, 400);

    // global 在 shell / editor / modal 下被隔离。
    for (final context in ReaderInputContext.values) {
      final expected =
          context == ReaderInputContext.shell ||
          context == ReaderInputContext.editor ||
          context == ReaderInputContext.modal;
      expect(context.isolatesGlobal, expected, reason: '$context');
    }
  });
}
