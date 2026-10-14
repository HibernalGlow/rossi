import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/operation_binding/binding_input_editor.dart';
import 'package:zephyr/page/setting/operation_binding/binding_input_recorder.dart';
import 'package:zephyr/widgets/popup_select_field.dart';

void main() {
  testWidgets('触屏可组合区域和单击，切换鼠标保留区域，通用区域可清除', (tester) async {
    var input = <String, dynamic>{
      'device': 'mouse',
      'action': 'click',
      'button': 0,
      'area': 'middle-center',
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, setState) => SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: BindingInputEditor(
                  input: input,
                  onChanged: (next) => setState(() => input = next),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Future<void> select(String label, String value) async {
      final field = find.byWidgetPredicate(
        (w) => w is PopupSelectField<String> && w.label == label,
      );
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text(value).last);
      await tester.pumpAndSettle();
    }

    await select(t.bindingEditor.device, t.bindingEditor.touch);
    expect(input['device'], 'touch');
    expect(input['gesture'], 'tap');
    expect(input['area'], 'middle-center');
    await select(t.bindingEditor.area, t.bindingEditor.anyArea);
    expect(input.containsKey('area'), isFalse);
    expect(input['gesture'], 'tap');
    expect(tester.takeException(), isNull);
  });

  for (final doubleTap in [false, true]) {
    testWidgets('录制触屏：${doubleTap ? '真实两次点击' : '一次点击不会冒充双击'}', (tester) async {
      Map<String, dynamic>? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  captured = await BindingInputRecorder.show(context, {
                    'device': 'touch',
                    'gesture': 'double-tap',
                    'fingers': 1,
                    'area': 'middle-center',
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
      final point = tester.getCenter(find.text(t.bindingEditor.recordWaiting));
      await tester.sendEventToBinding(
        PointerDownEvent(
          pointer: 20,
          position: point,
          timeStamp: const Duration(milliseconds: 100),
        ),
      );
      await tester.sendEventToBinding(
        PointerUpEvent(
          pointer: 20,
          position: point,
          timeStamp: const Duration(milliseconds: 140),
        ),
      );
      await tester.pump();
      if (doubleTap) {
        await tester.sendEventToBinding(
          PointerDownEvent(
            pointer: 21,
            position: point,
            timeStamp: const Duration(milliseconds: 220),
          ),
        );
        await tester.sendEventToBinding(
          PointerUpEvent(
            pointer: 21,
            position: point,
            timeStamp: const Duration(milliseconds: 260),
          ),
        );
        await tester.pump();
      }
      await tester.tap(find.text(t.common.confirm));
      await tester.pumpAndSettle();
      expect(captured?['device'], 'touch');
      expect(captured?['gesture'], doubleTap ? 'double-tap' : 'tap');
      expect(captured?['area'], 'middle-center');
    });
  }

  testWidgets('录制触屏滑动仍为 touch，不误记为鼠标轨迹', (tester) async {
    Map<String, dynamic>? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                captured = await BindingInputRecorder.show(context, {
                  'device': 'touch',
                  'gesture': 'tap',
                  'fingers': 1,
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
    final point = tester.getCenter(find.text(t.bindingEditor.recordWaiting));
    await tester.dragFrom(point, const Offset(-90, 0));
    await tester.pump();
    await tester.tap(find.text(t.common.confirm));
    await tester.pumpAndSettle();
    expect(captured?['device'], 'touch');
    expect(captured?['gesture'], 'swipe-left');
  });
}
