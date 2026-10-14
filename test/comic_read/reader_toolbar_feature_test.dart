import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/reader_bottom_toolbar.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_feature_button.dart';

void main() {
  testWidgets('钉住底栏常驻、可取消，更多不重复列出', (tester) async {
    var pinned = false;
    final rebuild = GlobalKey<State<StatefulBuilder>>();
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: StatefulBuilder(
              key: rebuild,
              builder: (context, setState) => Center(
                child: ReaderBottomToolbar(
                  previousChapter: () {},
                  nextChapter: () {},
                  selectChapter: () {},
                  openSettings: () {},
                  goHome: () {},
                  toggleThumbnails: () {},
                  togglePinned: () => setState(() => pinned = !pinned),
                  thumbnailsVisible: false,
                  pinned: pinned,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pin = find.byTooltip(t.reader.pinBottomBar);
    expect(pin, findsOneWidget);
    expect(tester.getSize(pin).shortestSide, greaterThanOrEqualTo(48));
    await tester.tap(pin);
    await tester.pumpAndSettle();
    expect(pinned, isTrue);
    expect(find.byTooltip(t.reader.unpinBottomBar), findsOneWidget);
    await tester.tap(find.byTooltip(t.common.more));
    await tester.pumpAndSettle();
    expect(find.text(t.reader.unpinBottomBar), findsNothing);
    expect(find.text(t.reader.thumbnailStripExpand), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('增强按钮快速切换、收缩标签和减少动效保持可操作', (tester) async {
    var selected = false;
    var showLabel = true;
    var reduced = false;
    late StateSetter update;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: Scaffold(
                body: Center(
                  child: ReaderToolbarFeatureButton(
                    icon: AppGlyphs.sparkle,
                    label: '超分',
                    tooltip: '本书超分',
                    selected: selected,
                    showLabel: showLabel,
                    onPressed: () => setState(() => selected = !selected),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    final button = find.byType(FilledButton);
    expect(tester.getSize(button).height, 48);
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(selected, isTrue);
    expect(
      tester.getSemantics(button),
      matchesSemantics(
        label: '超分',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    update(() {
      showLabel = false;
      reduced = true;
    });
    await tester.pumpAndSettle();
    expect(tester.getSize(button), const Size(48, 48));
    await tester.tap(button);
    await tester.pump();
    expect(selected, isFalse);
    final shape =
        tester.widget<FilledButton>(button).style!.shape!.resolve({})
            as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(24));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('长按预览在松手时恢复且不会触发点击', (tester) async {
    var taps = 0;
    var starts = 0;
    var ends = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ReaderToolbarFeatureButton(
              icon: AppGlyphs.sparkle,
              label: '超分',
              tooltip: '对比原图',
              onPressed: () => taps++,
              onLongPressStart: () => starts++,
              onLongPressEnd: () => ends++,
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(FilledButton)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(starts, 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(ends, 1);
    expect(taps, 0);
  });
}
