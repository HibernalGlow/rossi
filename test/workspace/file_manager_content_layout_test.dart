import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:multi_split_view/multi_split_view.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_content_layout.dart';

void main() {
  testWidgets('现成分栏容器拖动后保留宽度，追加目录列时保持现有列宽', (tester) async {
    Future<void> show(List<String> ids) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 700,
              height: 400,
              child: FileManagerSplitContent(
                ids: ids,
                children: [for (final id in ids) Center(child: Text(id))],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(['root', 'content']);
    final split = tester.widget<MultiSplitView>(find.byType(MultiSplitView));
    final controller = split.controller!;
    final drag = find.descendant(
      of: find.byType(MultiSplitView),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is GestureDetector && widget.onHorizontalDragUpdate != null,
      ),
    );
    expect(drag, findsOneWidget);
    final before = tester.getCenter(find.text('root')).dx;
    await tester.drag(drag, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('root')).dx, greaterThan(before));
    final width = controller.areas.first.size;
    await show(['root', 'child', 'content']);
    final resized = tester
        .widget<MultiSplitView>(find.byType(MultiSplitView))
        .controller!;
    expect(resized.areas.first.size, width);
    expect(resized.areas.length, 3);
    expect(tester.takeException(), isNull);
    await show(['content']);
    expect(tester.takeException(), isNull);
  });
}
