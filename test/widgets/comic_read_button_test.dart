import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_read_button.dart';

/// 封面「直接阅读」按钮自己的规矩：什么时候显形、什么时候根本不画、
/// 起读那一次等待期间画什么。这些规则一旦散到各张卡片上就会各写一份，
/// 所以钉在组件这一层。
void main() {
  Future<void> pumpCover(
    WidgetTester tester, {
    required Future<void> Function() onTap,
    Size coverSize = const Size(120, 160),
    double? buttonSize,
  }) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: coverSize.width,
              height: coverSize.height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0xFF123456)),
                  Positioned.fill(
                    child: ComicReadButton(onTap: onTap, size: buttonSize),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 按钮此刻是否可点：隐藏态外层是 [IgnorePointer]，点它等于落到卡片上。
  ///
  /// 两个 finder 都要限在按钮子树里 —— `MaterialApp` 自己那层也有同名组件，
  /// 全树去找会撞上「Too many elements」。
  bool tapReachesButton(WidgetTester tester) =>
      !tester
          .widget<IgnorePointer>(
            find.descendant(
              of: find.byType(ComicReadButton),
              matching: find.byType(IgnorePointer),
            ),
          )
          .ignoring;

  double revealOpacity(WidgetTester tester) =>
      tester
          .widget<AnimatedOpacity>(
            find.descendant(
              of: find.byType(ComicReadButton),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity;

  Future<void> enterMouse(WidgetTester tester, Offset to) async {
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer();
    addTearDown(pointer.removePointer);
    await pointer.moveTo(to);
    await tester.pumpAndSettle();
  }

  group('显形判据（真值表）', () {
    test('触屏：没有 hover 这回事，一律显形', () {
      for (final hovered in const [true, false]) {
        for (final busy in const [true, false]) {
          expect(
            shouldRevealComicReadButton(
              hasPointer: false,
              hovered: hovered,
              busy: busy,
            ),
            isTrue,
            reason: 'hovered=$hovered busy=$busy',
          );
        }
      }
    });

    test('有指针：悬停才显形，否则整屏封面都扣一个圆圈', () {
      expect(
        shouldRevealComicReadButton(hasPointer: true, hovered: true, busy: false),
        isTrue,
      );
      expect(
        shouldRevealComicReadButton(hasPointer: true, hovered: false, busy: false),
        isFalse,
      );
    });

    test('进度期间一律显形：正在转圈的按钮不能是隐形的', () {
      expect(
        shouldRevealComicReadButton(hasPointer: true, hovered: false, busy: true),
        isTrue,
      );
    });
  });

  testWidgets('触屏：常显、可点，点一次触发一次起读', (tester) async {
    var calls = 0;
    await pumpCover(tester, onTap: () async => calls++);

    expect(revealOpacity(tester), 1);
    expect(tapReachesButton(tester), isTrue);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets('桌面：默认收着且点不到，鼠标移进封面才浮出', (tester) async {
    // flutter_test 在本体结束时核对 foundation 的 debug 变量，那次核对跑在
    // tearDown 之前，所以覆盖值必须在本体内收回去。
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    var calls = 0;
    await pumpCover(tester, onTap: () async => calls++);

    expect(revealOpacity(tester), 0);
    // 「看不见却能点」比看不见更糟，所以隐藏态要真的挡住点击。
    expect(tapReachesButton(tester), isFalse);
    await tester.tapAt(tester.getCenter(find.byType(ComicReadButton)));
    await tester.pump();
    expect(calls, 0);

    await enterMouse(tester, tester.getCenter(find.byType(ComicReadButton)));
    expect(revealOpacity(tester), 1);
    expect(tapReachesButton(tester), isTrue);
    await tester.tapAt(tester.getCenter(find.byType(ComicReadButton)));
    await tester.pump();
    expect(calls, 1);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('起读的 Future 结束前转圈，结束后放回播放图标', (tester) async {
    final gate = _Gate();
    await pumpCover(tester, onTap: gate.wait);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

    gate.finish();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('等待期间连点只触发一次', (tester) async {
    final gate = _Gate();
    await pumpCover(tester, onTap: gate.wait);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byType(ComicReadButton)));
    await tester.tapAt(tester.getCenter(find.byType(ComicReadButton)));
    await tester.pump();
    expect(gate.calls, 1);

    gate.finish();
    await tester.pumpAndSettle();
  });

  testWidgets('格子太小就不画（44 的封面槽摆一颗圆圈等于糊住封面）', (tester) async {
    await pumpCover(tester, onTap: () async {}, coverSize: const Size(44, 44));

    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
  });

  testWidgets('调用方指定直径时照画不误，且就用这个直径', (tester) async {
    await pumpCover(
      tester,
      onTap: () async {},
      coverSize: const Size(44, 44),
      buttonSize: 20,
    );

    expect(tester.getSize(find.byType(InkWell)), const Size(20, 20));
  });

  test('尺寸口径：约占短边三分之一，夹在 26~44', () {
    expect(comicReadButtonSize(60), 26); // 密网格：兜到最小可点尺寸
    expect(comicReadButtonSize(120), closeTo(38.4, 0.01));
    expect(comicReadButtonSize(400), 44); // 横滑卡：兜到最大，别占屏
  });
}

/// 手动放行的异步动作：把「正在起读」这一状态钉在测试里。
class _Gate {
  int calls = 0;
  final Completer<void> _completer = Completer<void>();

  Future<void> wait() async {
    calls++;
    await _completer.future;
  }

  void finish() {
    if (!_completer.isCompleted) _completer.complete();
  }
}
