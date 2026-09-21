import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/operation_binding/binding_input_recorder.dart';

void main() {
  LocaleSettings.setLocale(AppLocale.zhCn);

  testWidgets('滚轮录制测试 - 鼠标在 Container 内部', (tester) async {
    Map<String, dynamic>? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                captured = await BindingInputRecorder.show(context, {
                  'device': 'wheel',
                  'direction': 'down',
                });
              },
              child: const Text('record'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('record'));
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.text(t.bindingEditor.recordWaiting));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, 40)),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.bindingEditor.recordWaiting), findsNothing);
    await tester.tap(find.text(t.common.confirm));
    await tester.pumpAndSettle();

    expect(captured?['device'], 'wheel');
    expect(captured?['direction'], 'down');
  });

  testWidgets('滚轮录制测试 - 鼠标在对话框提示文字上也能捕获', (tester) async {
    Map<String, dynamic>? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                captured = await BindingInputRecorder.show(context, {
                  'device': 'wheel',
                  'direction': 'down',
                });
              },
              child: const Text('record'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('record'));
    await tester.pumpAndSettle();

    final titlePos = tester.getCenter(find.text(t.bindingEditor.recordHint));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: titlePos, scrollDelta: const Offset(0, -40)),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.bindingEditor.recordWaiting), findsNothing);
    await tester.tap(find.text(t.common.confirm));
    await tester.pumpAndSettle();

    expect(captured?['device'], 'wheel');
    expect(captured?['direction'], 'up');
  });

  testWidgets('滚轮录制测试 - 从键盘绑定进入录制，滚动滚轮自动切换为 wheel', (tester) async {
    Map<String, dynamic>? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                captured = await BindingInputRecorder.show(context, {
                  'device': 'keyboard',
                  'code': 'KeyA',
                });
              },
              child: const Text('record'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('record'));
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.text(t.bindingEditor.recordWaiting));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, 40)),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.bindingEditor.recordWaiting), findsNothing);
    await tester.tap(find.text(t.common.confirm));
    await tester.pumpAndSettle();

    expect(captured?['device'], 'wheel');
    expect(captured?['direction'], 'down');
  });

  testWidgets('触控板手势录制测试 - Mac 触控板双指滑动录制为 wheel', (tester) async {
    Map<String, dynamic>? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                captured = await BindingInputRecorder.show(context, {
                  'device': 'wheel',
                  'direction': 'down',
                });
              },
              child: const Text('record'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('record'));
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.text(t.bindingEditor.recordWaiting));

    // 模拟 Mac 触控板向上推（panDelta.dy < 0）
    await tester.sendEventToBinding(PointerPanZoomStartEvent(position: center));
    await tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(
        position: center,
        panDelta: const Offset(0, -20),
      ),
    );
    await tester.sendEventToBinding(PointerPanZoomEndEvent(position: center));
    await tester.pumpAndSettle();

    expect(find.text(t.bindingEditor.recordWaiting), findsNothing);
    await tester.tap(find.text(t.common.confirm));
    await tester.pumpAndSettle();

    expect(captured?['device'], 'wheel');
    expect(captured?['direction'], 'up');
  });
}
