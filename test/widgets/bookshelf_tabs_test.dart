import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/navigation/panel_switcher_tabs.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_bar.dart';

void main() {
  testWidgets('书架页签悬停与点击仅使用自己的高亮，不触发第二层粉色气泡', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => ActionBubbleRegion(
                child: PanelSwitcherTabs(
                  items: const [
                    PanelSwitcherItem(label: '收藏'),
                    PanelSwitcherItem(label: '历史'),
                    PanelSwitcherItem(label: '下载'),
                  ],
                  selectedIndex: selected,
                  onSelected: (value) => setState(() => selected = value),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('历史')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    final bubble = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.foregroundPainter)
        .whereType<ActionBubblePainter>()
        .single;
    expect(bubble.alpha(), 0);
    final lens = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<SpringLensPainter>()
        .single;
    expect(lens.position, closeTo(1, .001));
    expect(lens.corner, 14);
    expect(lens.shadow?.blurRadius, 4);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('下载'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
