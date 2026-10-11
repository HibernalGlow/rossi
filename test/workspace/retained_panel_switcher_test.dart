import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/widgets/panels/retained_panel_switcher.dart';

class _Panel extends StatefulWidget {
  const _Panel(this.id);
  final String id;
  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  int count = 0;
  int builds = 0;
  @override
  Widget build(BuildContext context) {
    builds++;
    return TextButton(
      onPressed: () => setState(() => count++),
      child: Text('${widget.id}:$count'),
    );
  }
}

class _RenderProbe extends SingleChildRenderObjectWidget {
  const _RenderProbe({required this.counts, required super.child});
  final List<int> counts;

  @override
  RenderObject createRenderObject(BuildContext context) => _ProbeBox(counts);
}

class _ProbeBox extends RenderProxyBox {
  _ProbeBox(this.counts);
  final List<int> counts;

  @override
  void performLayout() {
    counts[0]++;
    super.performLayout();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    counts[1]++;
    super.paint(context, offset);
  }
}

void main() {
  testWidgets('切换有中间帧，保留内容状态并阻止退出面板接收点击和读屏', (tester) async {
    const panels = {'a': _Panel('a'), 'b': _Panel('b'), 'c': _Panel('c')};
    Widget host(String selected, {bool reduceMotion = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(
          body: RetainedPanelSwitcher(selectedId: selected, children: panels),
        ),
      ),
    );
    Finder panel(String id, {bool hidden = false}) => find.byWidgetPredicate(
      (w) => w is _Panel && w.id == id,
      skipOffstage: !hidden,
    );
    FadeTransition opacity(String id) => tester.widget<FadeTransition>(
      find.ancestor(of: panel(id), matching: find.byType(FadeTransition)).first,
    );
    await tester.pumpWidget(host('a'));
    await tester.tap(find.text('a:0'));
    await tester.pump();
    final original = tester.state<_PanelState>(panel('a'));
    final builds = original.builds;

    await tester.pumpWidget(host('b'));
    await tester.pump(const Duration(milliseconds: 80));
    expect(opacity('a').opacity.value, inExclusiveRange(0, 1));
    expect(opacity('b').opacity.value, inExclusiveRange(0, 1));
    final blocker = tester.widget<IgnorePointer>(
      find.ancestor(of: panel('a'), matching: find.byType(IgnorePointer)).first,
    );
    expect(blocker.ignoring, isTrue);
    final semantics = tester.widget<ExcludeSemantics>(
      find
          .ancestor(of: panel('a'), matching: find.byType(ExcludeSemantics))
          .first,
    );
    expect(semantics.excluding, isTrue);
    final outgoingAlpha = opacity('a').opacity.value;
    final incomingAlpha = opacity('b').opacity.value;
    await tester.pumpWidget(host('c'));
    expect(opacity('a').opacity.value, closeTo(outgoingAlpha, .0001));
    expect(opacity('b').opacity.value, closeTo(incomingAlpha, .0001));
    await tester.pump(const Duration(milliseconds: 50));
    final interruptedAlpha = opacity('b').opacity.value;
    await tester.pumpWidget(host('b'));
    expect(opacity('b').opacity.value, closeTo(interruptedAlpha, .0001));
    await tester.pumpAndSettle();
    expect(panel('a'), findsNothing);
    expect(tester.state(panel('a', hidden: true)), same(original));
    expect(original.builds, builds);

    await tester.pumpWidget(host('c'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(host('a'));
    await tester.pumpAndSettle();
    expect(find.text('a:1'), findsOneWidget);
    expect(tester.state(panel('a')), same(original));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(host('b', reduceMotion: true));
    await tester.pump();
    expect(opacity('b').opacity.value, 1);
    expect(panel('a'), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  for (final destination in ['b', 'd']) {
    testWidgets('a→$destination 动画复用面板图层，不逐帧布局和重画正文', (tester) async {
      final counts = {
        for (final id in ['a', 'b', 'c', 'd']) id: [0, 0],
      };
      final panels = {
        for (final entry in counts.entries)
          entry.key: _RenderProbe(
            counts: entry.value,
            child: const ColoredBox(color: Colors.blue),
          ),
      };
      Widget host(String selected) => MaterialApp(
        home: Scaffold(
          body: RetainedPanelSwitcher(selectedId: selected, children: panels),
        ),
      );
      await tester.pumpWidget(host('a'));
      expect(counts['a']![1], greaterThan(0));
      await tester.pumpWidget(host(destination));
      // 先绘制新进入面板，再记录动画期间的稳定图层。
      await tester.pump(const Duration(milliseconds: 16));
      final baseline = {
        for (final entry in counts.entries) entry.key: [...entry.value],
      };
      final transitions = find.descendant(
        of: find.byType(RetainedPanelSwitcher),
        matching: find.byType(FadeTransition),
      );
      final transition = tester
          .widgetList<FadeTransition>(transitions)
          .toList();
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final current = tester.widgetList<FadeTransition>(transitions).toList();
        expect(current.length, transition.length);
        for (var i = 0; i < current.length; i++) {
          expect(current[i], same(transition[i]));
        }
      }
      expect(counts, baseline, reason: '位移和透明度只更新图层，不使正文重新布局或绘制');
      expect(
        transition.every((w) => w.opacity.value > 0 && w.opacity.value < 1),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(find.byType(_RenderProbe), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
