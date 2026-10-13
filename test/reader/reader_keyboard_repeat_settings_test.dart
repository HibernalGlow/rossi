import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/controller/reader_keyboard_repeat_timing.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_keyboard_repeat_settings.dart';

void main() {
  test('导入越界参数时限制节奏与动画，非有限速度回落默认', () {
    for (final speed in [0.5, 2.0, 4.0, 10.0, 15.0]) {
      final timing = ReaderKeyboardRepeatTiming(
        pagesPerSecond: speed,
        holdDelayMs: 350,
      );
      expect(timing.interval.inMicroseconds, closeTo(1000000 / speed, 1));
      expect(timing.animationDuration, lessThan(timing.interval));
      expect(timing.firstAnimationDuration.inMilliseconds, 300);
    }
    final fastest = ReaderKeyboardRepeatTiming(
      pagesPerSecond: 1000,
      holdDelayMs: -1,
    );
    expect(fastest.pagesPerSecond, 15);
    expect(fastest.holdDelay.inMilliseconds, 100);
    expect(fastest.firstAnimationDuration.inMilliseconds, 100);
    final invalid = ReaderKeyboardRepeatTiming(
      pagesPerSecond: double.nan,
      holdDelayMs: 10000,
    );
    expect(invalid.pagesPerSecond, 4);
    expect(invalid.holdDelay.inMilliseconds, 2000);
  });

  testWidgets('速度支持直接输入，高级延迟默认折叠，滑杆与数值保持同步', (tester) async {
    var speed = 4.0;
    var delay = 350;
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ReaderKeyboardRepeatSettings(
                pagesPerSecond: speed,
                holdDelayMs: delay,
                onSpeedChanged: (value) => setState(() => speed = value),
                onDelayChanged: (value) => setState(() => delay = value),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '7.3');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(speed, 7.3);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 7.3);
    await tester.tap(find.text(t.reader.keyboardPageTurnAdvanced));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    final delayField = find.byType(TextField).last;
    await tester.enterText(delayField, '600');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(delay, 600);
    await tester.enterText(find.byType(TextField).first, '99');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(speed, 15);
    await tester.enterText(find.byType(TextField).first, '.');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(speed, 15);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '15.0',
    );
  });

  testWidgets('窄面板和大字体仍能调节速度与延迟', (tester) async {
    tester.view.physicalSize = const Size(280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: ReaderKeyboardRepeatSettings(
                  pagesPerSecond: 4,
                  holdDelayMs: 350,
                  onSpeedChanged: (_) {},
                  onDelayChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text(t.reader.keyboardPageTurnAdvanced));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
