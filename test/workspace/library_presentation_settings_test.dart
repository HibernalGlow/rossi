import 'dart:convert';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation_button.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/i18n/strings.g.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('默认偏好顺序严格成立，多项命中不累计；新增信号不改算法', () {
    const rules = {
      'favoriteTag': 3.0,
      'favoriteArtist': 2.0,
      'translated': 1.0,
    };
    final entries = [
      const LibraryEntry(
        key: 'language',
        title: '汉化',
        weightSignals: {'translated': 1},
      ),
      const LibraryEntry(
        key: 'artist',
        title: '画师',
        weightSignals: {'favoriteArtist': 1, 'translated': 1},
      ),
      const LibraryEntry(
        key: 'tag',
        title: 'tag',
        weightSignals: {'favoriteTag': 1},
      ),
    ];
    final weights = libraryWeights(
      entries,
      LibraryWeight.signals,
      signalWeights: rules,
    );
    expect(weights[0], lessThan(weights[1]));
    expect(weights[1], lessThan(weights[2]));
    final custom = libraryWeights(
      entries,
      LibraryWeight.signals,
      signalWeights: {...rules, 'translated': 8},
    );
    expect(custom[0], greaterThan(custom[2]));
    expect(
      librarySignalScore(
        const LibraryEntry(
          key: 'future',
          title: '新增',
          weightSignals: {'newCategory': 1},
        ),
        {'newCategory': 5},
      ),
      1,
    );
    expect(librarySignalScore(entries.last, {'favoriteTag': 0}), 0);
    for (final columns in [1, 2, 3, 6]) {
      final rows = libraryCanvasRows(
        entries: entries,
        columns: columns,
        presentation: const LibraryPresentation(
          weight: LibraryWeight.signals,
          signalWeights: rules,
        ),
      );
      expect(rows.expand((row) => row.indices), orderedEquals([0, 1, 2]));
      expect(
        rows.every((row) => row.spans.fold(0, (a, b) => a + b) <= columns),
        isTrue,
      );
    }
  });

  test('旧偏好、损坏数字、未知信号与新尺寸往返兼容', () {
    final old = LibraryPresentation.fromJson({'weight': 'balanced'});
    expect(old.cardWidth, 140);
    expect(old.cardHeight, 270);
    final damaged = LibraryPresentation.fromJson({
      'cardWidth': 10000,
      'cardHeight': -10,
      'gap': double.nan,
      'imageScale': double.infinity,
      'emphasis': double.nan,
      'signalWeights': {'newCategory': 4.0, 'bad': double.infinity},
    });
    expect(damaged.cardWidth, 420);
    expect(damaged.cardHeight, 180);
    expect(damaged.gap, 10);
    expect(damaged.imageScale, 1);
    expect(damaged.emphasis, .65);
    expect(damaged.signalWeights, {'newCategory': 4});
    final restored = LibraryPresentation.fromJson(
      jsonDecode(jsonEncode(damaged.toJson())),
    );
    expect(restored.toJson(), damaged.toJson());
    expect(libraryCanvasColumns(60, damaged), 1);
    expect(
      libraryCanvasColumns(800, const LibraryPresentation(cardWidth: 140)),
      greaterThan(
        libraryCanvasColumns(800, const LibraryPresentation(cardWidth: 300)),
      ),
    );
  });

  test('按三格反算卡片宽度：宽卡占两格，旁边保留一张普通卡', () {
    const gap = 10.0;
    final entries = List.generate(
      6,
      (i) => LibraryEntry(key: '$i', title: '$i'),
    );
    for (final width in [280.0, 600.0, 1020.0]) {
      final cardWidth = libraryCardWidthForColumns(width, 3, gap);
      final presentation = LibraryPresentation(
        weight: LibraryWeight.order,
        cardWidth: cardWidth,
        gap: gap,
      );
      expect(libraryCanvasColumns(width, presentation), 3);
      final rows = libraryCanvasRows(
        entries: entries,
        columns: 3,
        presentation: presentation,
      );
      expect(rows.first.indices, [0, 1]);
      expect(rows.first.spans, [2, 1]);
      expect(cardWidth * 3 + gap * 2, closeTo(width, .0001));
      expect(libraryCanvasColumns(width / 2, presentation), lessThan(3));
    }
  });

  for (final width in [220.0, 480.0, 1200.0]) {
    testWidgets('顶栏弹出设置在 $width 宽度可用并保存尺寸，正文没有设置行', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey<LibraryEditorialCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [LibraryPresentationButton(canvasKey: key)],
            ),
            body: LibraryEditorialCanvas(
              key: key,
              scope: 'settings',
              standalone: true,
              initialPresentation: const LibraryPresentation(
                hero: false,
                asymmetric: false,
              ),
              entries: const [LibraryEntry(key: 'item', title: '作品')],
              onTap: (_) {},
              legacyBuilder: (_) => const Text('普通视图'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> openTab(String label) async {
        final dock = find.byKey(const ValueKey('wall-settings-tabs'));
        await tester.ensureVisible(dock);
        await tester.pumpAndSettle();
        await tester.tap(find.descendant(of: dock, matching: find.text(label)));
        await tester.pumpAndSettle();
      }

      expect(find.text('不对称'), findsNothing);
      await tester.tap(find.byTooltip(LibraryPresentationButton.tooltip));
      await tester.pumpAndSettle();
      await openTab(t.workspace.wallTabLayout);
      expect(find.text('不对称'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<LibraryWeight>), findsNothing);
      await openTab(t.workspace.wallTabSize);
      final slider = tester.widget<M3ESlider>(
        find.byKey(const ValueKey('library-slider-卡片宽度')),
      );
      slider.onChanged!(240);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('wall-settings-apply')));
      await tester.pumpAndSettle();
      expect(find.text('不对称'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(
        prefs.getString('rossi.library.presentation.settings')!,
      );
      expect(saved['cardWidth'], 240);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('面积依据复用弹簧托盘；三格设置保存宽度，取消不改偏好', (tester) async {
    tester.view.physicalSize = const Size(620, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey<LibraryEditorialCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: [LibraryPresentationButton(canvasKey: key)]),
          body: LibraryEditorialCanvas(
            key: key,
            scope: 'density',
            standalone: true,
            initialPresentation: const LibraryPresentation(hero: false),
            entries: const [LibraryEntry(key: 'item', title: '作品')],
            onTap: (_) {},
            legacyBuilder: (_) => const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(LibraryPresentationButton.tooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 格'));
    await tester.pumpAndSettle();
    expect(find.text('当前每行 3 格'), findsOneWidget);
    // 面积依据在「布局」页签。
    final dock = find.byKey(const ValueKey('wall-settings-tabs'));
    await tester.ensureVisible(dock);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: dock, matching: find.text(t.workspace.wallTabLayout)),
    );
    await tester.pumpAndSettle();
    final selector = find.byKey(const ValueKey('library-weight-selector'));
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.byType(CommonPopupMenu), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.tap(find.text('原图比例'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wall-settings-apply')));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('rossi.library.presentation.density')!;
    expect(jsonDecode(saved)['weight'], 'imageShape');
    expect(jsonDecode(saved)['cardWidth'], closeTo((600 - 20) / 3, .001));
    await tester.tap(find.byTooltip(LibraryPresentationButton.tooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4 格'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wall-settings-cancel')));
    await tester.pumpAndSettle();
    expect(prefs.getString('rossi.library.presentation.density'), saved);
    expect(tester.takeException(), isNull);
  });

  testWidgets('单列仍体现标签面积层级，图片和卡片高度可独立调整', (tester) async {
    tester.view.physicalSize = const Size(280, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final heights = <String, double>{};
    LibraryEntry entry(String id) => LibraryEntry(
      key: id,
      title: id,
      weightSignals: {id: 1},
      media:
          (
            _, {
            required width,
            required height,
            required radius,
            required fit,
          }) {
            heights[id] = height;
            return SizedBox(width: width, height: height);
          },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryEditorialCanvas(
            scope: 'narrow-weights',
            standalone: true,
            initialPresentation: const LibraryPresentation(
              hero: false,
              weight: LibraryWeight.signals,
              cardWidth: 300,
              cardHeight: 360,
            ),
            weightSignals: const [
              LibraryWeightSignal('tag', 'tag', 3),
              LibraryWeightSignal('artist', 'artist', 2),
              LibraryWeightSignal('translated', '汉化', 1),
            ],
            entries: [entry('tag'), entry('artist'), entry('translated')],
            onTap: (_) {},
            legacyBuilder: (_) => const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(heights['tag'], greaterThan(heights['artist']!));
    expect(heights['artist'], greaterThan(heights['translated']!));
    expect(heights['translated'], greaterThan(360 - 76));
    expect(tester.takeException(), isNull);
  });

  testWidgets('图片尺寸独立于卡片尺寸，横竖图比例仍响应', (tester) async {
    var mediaHeight = 0.0;
    final key = GlobalKey<LibraryEditorialCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryEditorialCanvas(
            key: key,
            scope: 'images',
            standalone: true,
            initialPresentation: const LibraryPresentation(
              hero: false,
              asymmetric: false,
              cardWidth: 200,
              cardHeight: 320,
              imageScale: .5,
            ),
            entries: [
              LibraryEntry(
                key: 'image',
                title: '图片',
                media:
                    (
                      _, {
                      required width,
                      required height,
                      required radius,
                      required fit,
                    }) {
                      mediaHeight = height;
                      return SizedBox(width: width, height: height);
                    },
              ),
            ],
            onTap: (_) {},
            legacyBuilder: (_) => const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 悬浮操作不再扣除 76dp 底栏；图片直接按整张卡片的高度缩放。
    expect(mediaHeight, 160);
    expect(tester.takeException(), isNull);
  });
}
