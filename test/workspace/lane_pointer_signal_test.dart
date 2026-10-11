import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/util/input/binding_input_capture.dart';
import 'package:zephyr/util/input/binding_pointer_signal_guard.dart';
import 'package:zephyr/workspace/input/workspace_lane_input_region.dart';

void main() {
  testWidgets('滚轮绑定只消费一次，跨泳道拒收时恢复 InteractiveViewer 直接变换', (tester) async {
    final native = ScrollController();
    final matrix = TransformationController();
    addTearDown(native.dispose);
    addTearDown(matrix.dispose);
    String? owner;
    var actions = 0;
    bool accept(String id) {
      owner ??= id;
      return owner == id;
    }

    WorkspaceLaneInputRegion region(String id, Widget child) =>
        WorkspaceLaneInputRegion(
          acceptWheel: () => accept(id),
          onPanZoomStart: (_) {},
          onPanZoomEnd: (_) {},
          child: child,
        );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: region(
                  'panel',
                  const SizedBox.expand(key: ValueKey('panel')),
                ),
              ),
              Expanded(
                child: region(
                  'reader',
                  BindingPointerSignalRegion(
                    onPointerSignal: (event) {
                      final before = matrix.value.clone();
                      if (BindingPointerSignalGuard.isRejected(event)) {
                        BindingPointerSignalGuard.afterRejected(
                          event,
                          () => matrix.value = before,
                        );
                        return;
                      }
                      GestureBinding.instance.pointerSignalResolver.register(
                        event,
                        (_) {
                          matrix.value = before;
                          actions++;
                        },
                      );
                    },
                    child: InteractiveViewer(
                      key: const ValueKey('reader'),
                      transformationController: matrix,
                      child: ListView(
                        controller: native,
                        children: const [SizedBox(height: 3000)],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    Future<void> wheel(String id) async {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byKey(ValueKey(id))),
          scrollDelta: const Offset(0, -80),
        ),
      );
      await tester.pump();
    }

    await wheel('panel');
    final before = matrix.value.clone();
    await wheel('reader');
    expect(actions, 0);
    expect(matrix.value.storage, before.storage);
    expect(native.offset, 0);
    owner = null;
    await wheel('reader');
    expect(actions, 1);
    expect(native.offset, 0, reason: '绑定消费之后 Scrollable 不再滚第二遍');
    expect(matrix.value.storage, before.storage);
    await tester.pumpWidget(const SizedBox());
  });
}
