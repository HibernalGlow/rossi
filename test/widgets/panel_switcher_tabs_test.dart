import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/navigation/panel_switcher_tabs.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_bar.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/registry/workspace_panel_registry.dart';
import 'package:zephyr/workspace/widgets/panels/workspace_panel_tabs.dart';

void main() {
  for (final side in WorkspacePanelSide.values) {
    testWidgets('$side 泳道通过公共页签切换，保留右键收起和拖动', (tester) async {
      final panels = [
        for (var i = 0; i < 4; i++)
          WorkspacePanelDefinition(
            id: 'panel-$i',
            title: '面板 $i',
            icon: AppGlyphs.book,
            side: side,
            defaultOrder: i,
          ),
      ];
      var selected = panels.first;
      String? hidden;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) => WorkspacePanelTabs(
                  panels: panels,
                  activeId: selected.id,
                  onSelected: (panel) => setState(() => selected = panel),
                  onHide: (panel) => hidden = panel.id,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(PanelSwitcherTabs), findsOneWidget);
      Finder tab(int index) => find.bySemanticsLabel('面板 $index');
      final semantics = tester.ensureSemantics();
      await tester.tap(tab(3));
      await tester.pump();
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<SpringLensPainter>()
          .single;
      expect(selected.id, 'panel-3');
      await tester.pump(const Duration(milliseconds: 48));
      expect(painter.position, greaterThan(0));
      expect(painter.position, lessThan(3));
      await tester.pumpAndSettle();
      expect(painter.position, closeTo(3, .001));
      await tester.tap(
        tab(1),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(hidden, 'panel-1');
      expect(selected.id, 'panel-3');
      await tester.dragFrom(
        tester.getCenter(tab(3)),
        tester.getCenter(tab(0)) - tester.getCenter(tab(3)),
      );
      await tester.pumpAndSettle();
      expect(selected.id, 'panel-0');
      semantics.dispose();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('窄书架在放大字体后可以滚动访问最后一项', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 150,
                child: StatefulBuilder(
                  builder: (context, setState) => PanelSwitcherTabs(
                    items: const [
                      PanelSwitcherItem(label: '收藏'),
                      PanelSwitcherItem(label: '历史'),
                      PanelSwitcherItem(label: '下载'),
                    ],
                    selectedIndex: selected,
                    onSelected: (index) => setState(() => selected = index),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('下载'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();
    expect(selected, 2);
    expect(tester.takeException(), isNull);
  });
}
