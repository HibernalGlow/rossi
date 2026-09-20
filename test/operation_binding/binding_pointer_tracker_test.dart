import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/util/input/binding_input_capture.dart';
import 'package:zephyr/util/input/binding_pointer_tracker.dart';

void main() {
  testWidgets('九宫格单击等待手势胜出，子视频点击不会触发两次', (tester) async {
    final events = <String>[];
    final tracker = BindingPointerTracker(
      deferAreaClicks: true,
      lookup: (_) => null,
      dispatch: (input) {
        if (input['device'] != 'area' || input['action'] != 'click') {
          return false;
        }
        events.add(input['area'] as String);
        return true;
      },
    );
    addTearDown(tracker.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Listener(
          onPointerDown: (event) => tracker.down(
            event,
            event.localPosition.dx < 200 ? 'top-left' : 'middle-right',
          ),
          onPointerUp: tracker.up,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final input = tracker.deferredAreaClick;
              if (!tracker.claimed && input != null) tracker.dispatch(input);
            },
            child: Align(
              alignment: Alignment.topLeft,
              child: GestureDetector(
                onTap: () => events.add('video'),
                child: Container(width: 100, height: 100, color: Colors.black),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(50, 50));
    expect(events, ['video']);
    await tester.tapAt(const Offset(300, 100));
    expect(events, ['video', 'middle-right']);
    await tester.tapAt(const Offset(150, 100));
    expect(events.last, 'top-left', reason: '保留真实格子，不压成旧版左中格');
  });

  testWidgets('绑定滚轮先于内部滚动接收事件，点击仍穿透', (tester) async {
    final events = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BindingPointerSignalRegion(
            onPointerSignal: (event) => GestureBinding
                .instance
                .pointerSignalResolver
                .register(event, (_) => events.add('binding')),
            child: Listener(
              onPointerSignal: (event) => GestureBinding
                  .instance
                  .pointerSignalResolver
                  .register(event, (_) => events.add('scroll')),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => events.add('tap'),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(100, 100),
        scrollDelta: Offset(0, 30),
      ),
    );
    expect(events, ['binding']);
    await tester.tapAt(const Offset(100, 100));
    expect(events, ['binding', 'tap']);
  });

  testWidgets('触控绑定按真实手指数采集，取消事件不执行动作', (tester) async {
    final inputs = <Map<String, dynamic>>[];
    final tracker = BindingPointerTracker(
      lookup: (_) => null,
      dispatch: (input) {
        if (input['device'] != 'touch') return false;
        inputs.add(input);
        return true;
      },
    );
    addTearDown(tracker.dispose);
    tracker.down(
      const PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.touch,
        position: Offset(200, 100),
      ),
      'middle-right',
    );
    tracker.down(
      const PointerDownEvent(
        pointer: 2,
        kind: PointerDeviceKind.touch,
        position: Offset(200, 200),
      ),
      'middle-right',
    );
    tracker.move(
      const PointerMoveEvent(
        pointer: 1,
        kind: PointerDeviceKind.touch,
        position: Offset(100, 100),
      ),
    );
    tracker.move(
      const PointerMoveEvent(
        pointer: 2,
        kind: PointerDeviceKind.touch,
        position: Offset(100, 200),
      ),
    );
    tracker.up(
      const PointerUpEvent(
        pointer: 1,
        kind: PointerDeviceKind.touch,
        position: Offset(100, 100),
      ),
    );
    expect(inputs, isEmpty);
    tracker.up(
      const PointerUpEvent(
        pointer: 2,
        kind: PointerDeviceKind.touch,
        position: Offset(100, 200),
      ),
    );
    expect(inputs, [
      {'device': 'touch', 'gesture': 'swipe-left', 'fingers': 2},
    ]);
    tracker.down(
      const PointerDownEvent(
        pointer: 3,
        kind: PointerDeviceKind.touch,
        position: Offset(200, 100),
      ),
      null,
    );
    tracker.cancel();
    tracker.up(
      const PointerUpEvent(
        pointer: 3,
        kind: PointerDeviceKind.touch,
        position: Offset(100, 100),
      ),
    );
    expect(inputs, hasLength(1));
  });

  testWidgets('长按按配置定时触发，松开不重复执行单击', (tester) async {
    final inputs = <Map<String, dynamic>>[];
    final tracker = BindingPointerTracker(
      lookup: (input) => input['device'] == 'mouse' && input['action'] == 'hold'
          ? {
              'input': {'durationMs': 700, 'moveTolerancePx': 8},
            }
          : null,
      dispatch: (input) {
        if (input['action'] != 'hold') return false;
        inputs.add(input);
        return true;
      },
    );
    addTearDown(tracker.dispose);
    tracker.down(
      const PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
        position: Offset(20, 20),
      ),
      null,
    );
    await tester.pump(const Duration(milliseconds: 699));
    expect(inputs, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(inputs.single, {'device': 'mouse', 'button': 2, 'action': 'hold'});
    tracker.up(
      const PointerUpEvent(
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        position: Offset(20, 20),
      ),
    );
    expect(inputs, hasLength(1));
    expect(tracker.claimed, isTrue);
  });

  testWidgets('鼠标轨迹压缩相邻方向，释放后只执行一次', (tester) async {
    final inputs = <Map<String, dynamic>>[];
    final tracker = BindingPointerTracker(
      lookup: (_) => null,
      dispatch: (input) {
        if (input['device'] != 'mouse-gesture') return false;
        inputs.add(input);
        return true;
      },
    );
    addTearDown(tracker.dispose);
    tracker.down(
      const PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
        position: Offset(100, 100),
      ),
      null,
    );
    tracker.move(const PointerMoveEvent(pointer: 1, position: Offset(70, 100)));
    tracker.move(const PointerMoveEvent(pointer: 1, position: Offset(40, 100)));
    tracker.move(const PointerMoveEvent(pointer: 1, position: Offset(40, 40)));
    tracker.up(const PointerUpEvent(pointer: 1, position: Offset(40, 40)));
    expect(inputs.single['directions'], ['left', 'up']);
    expect(inputs.single['trigger'], 'instant');
  });
}
