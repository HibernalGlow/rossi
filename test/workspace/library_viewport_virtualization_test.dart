import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/widgets/library_viewport_anchor.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';

void main() {
  testWidgets('长展墙持续滚动后只保留视口附近卡片，位置锚点可重新对齐', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = ScrollController();
    final registry = LibraryViewportRegistry();
    final key = GlobalKey<LibraryEditorialCanvasState>();
    var active = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryEditorialCanvas(
            key: key,
            scrollController: controller,
            scope: 'virtualization',
            standalone: true,
            initialPresentation: const LibraryPresentation(
              hero: false,
              asymmetric: false,
              gapFill: LibraryGapFill.off,
            ),
            entries: [
              for (var i = 0; i < 2000; i++)
                LibraryEntry(key: '$i', title: 'Book $i'),
            ],
            wrapCard: (_, row, child) => LibraryViewportAnchor(
              registry: registry,
              entryKey: row.key,
              child: child,
            ),
            cardBuilder: (_, entry, tap) =>
                _Probe(onMount: () => active++, onDispose: () => active--),
            legacyBuilder: (_) => const SizedBox(),
            onTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(active, inInclusiveRange(1, 40));
    for (var i = 1; i < 30; i++) {
      controller.jumpTo(i * 1200);
      await tester.pumpAndSettle();
      expect(active, inInclusiveRange(1, 40));
    }
    final saved = registry.firstVisible()!;
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(key.currentState!.jumpToEntry(saved.key), isTrue);
    await tester.pumpAndSettle();
    expect(registry.align(saved.key, saved.offset), isTrue);
    await tester.pumpAndSettle();
    expect(registry.firstVisible()!.key, saved.key);
    expect(registry.firstVisible()!.offset, closeTo(saved.offset, .5));
    await tester.pumpWidget(const SizedBox());
    expect(active, 0);
    expect(registry.firstVisible(), isNull);
    controller.dispose();
    expect(tester.takeException(), isNull);
  });
}

class _Probe extends StatefulWidget {
  const _Probe({required this.onMount, required this.onDispose});
  final VoidCallback onMount, onDispose;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.teal);
}
