import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/widgets/navigation/navigation_dock.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_fill.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_shape.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_widgets.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_size_settings.dart';

const _coverAction = LibraryCoverTapAction.expandDetails;

Widget _host({
  required LibraryPresentation value,
  required List<LibraryPresentation?> captured,
  List<LibraryWeightSignal> signals = const [],
  LibraryCoverTapAction? cover,
  Key? boundaryKey,
  double textScale = 1,
}) => MaterialApp(
  builder: (context, child) => RepaintBoundary(
    key: boundaryKey,
    child: MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
  ),
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          key: const ValueKey('open-wall-settings'),
          onPressed: () async {
            captured[0] = await showLibrarySizeSettings(
              context,
              value,
              signals,
              gapWidgets: defaultLibraryGapWidgets(),
              defaultCoverTapAction: cover,
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

Future<void> _open(
  WidgetTester tester, {
  LibraryPresentation value = const LibraryPresentation(),
  List<LibraryPresentation?>? captured,
  List<LibraryWeightSignal> signals = const [],
  LibraryCoverTapAction? cover,
  Key? boundaryKey,
  double textScale = 1,
}) async {
  captured ??= [null];
  await tester.pumpWidget(
    _host(
      value: value,
      captured: captured,
      signals: signals,
      cover: cover,
      boundaryKey: boundaryKey,
      textScale: textScale,
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-wall-settings')));
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

/// 底部导航条的一格：按文案在 dock 子树里点，避开同名分组标题。
Future<void> _tapTab(WidgetTester tester, String label) async {
  final dock = find.byKey(const ValueKey('wall-settings-tabs'));
  await tester.ensureVisible(dock);
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: dock, matching: find.text(label)));
  await tester.pumpAndSettle();
}

Future<void> _apply(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('wall-settings-apply')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => LocaleSettings.setLocale(AppLocale.zhCn));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('连续滚动：尺寸、布局、组件在同一条流里，滚到哪段导航就亮哪段', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _open(tester);
    expect(find.text(t.workspace.displayWallCustom), findsOneWidget);
    final dock = find.byKey(const ValueKey('wall-settings-tabs'));
    expect(dock, findsOneWidget);
    NavigationDock dockWidget() => tester.widget<NavigationDock>(dock);
    // 三段基础内容都在同一棵树里（连续滚动，不按页卸载）。
    expect(dockWidget().destinations.length, 3);
    for (final label in [
      t.workspace.wallTabSize,
      t.workspace.wallTabLayout,
      t.workspace.wallTabComponents,
    ]) {
      expect(
        find.descendant(of: dock, matching: find.text(label)),
        findsOneWidget,
      );
    }
    expect(dockWidget().selectedIndex, 0);

    // 往下滚：不需要点任何东西，导航条自己换到下一段。
    final scroll = find.byType(SingleChildScrollView);
    await tester.drag(scroll, const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(dockWidget().selectedIndex, 1);
    expect(find.text(t.workspace.displayWall), findsOneWidget);
    await tester.drag(scroll, const Offset(0, -640));
    await tester.pumpAndSettle();
    expect(dockWidget().selectedIndex, 2);
    expect(find.text(t.workspace.gapFill), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('换页签时面板与底部导航条不移动', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _open(tester);
    final panel = find.byType(PopupPanel);
    final dock = find.byKey(const ValueKey('wall-settings-tabs'));
    final beforePanel = tester.getRect(panel);
    final beforeDock = tester.getRect(dock);
    for (final label in [
      t.workspace.wallTabLayout,
      t.workspace.wallTabComponents,
      t.workspace.wallTabSize,
      t.workspace.wallTabLayout,
    ]) {
      await _tapTab(tester, label);
      expect(tester.getRect(panel), beforePanel, reason: label);
      expect(tester.getRect(dock), beforeDock, reason: label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('组件页内嵌统一预览：25 款组件与 8 款图形都能看到实物', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _open(tester);
    await _tapTab(tester, t.workspace.wallTabComponents);

    final kit = defaultLibraryGapWidgets();
    expect(kit.length, 25);
    for (final spec in kit) {
      expect(
        find.byKey(ValueKey('gap-widget-preview-${spec.id}')),
        findsOneWidget,
        reason: spec.id,
      );
    }
    await _tapKey(tester, 'gap-tab-shapes');
    for (final style in kLibraryGapShapeStyles) {
      expect(
        find.byKey(ValueKey('gap-shape-preview-${style.name}')),
        findsOneWidget,
        reason: style.name,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('组件页改一项并应用，只回传这一项', (tester) async {
    final captured = <LibraryPresentation?>[null];
    await _open(tester, captured: captured);
    await _tapTab(tester, t.workspace.wallTabComponents);
    await _tapKey(tester, 'gap-widget-card-gap_cover_collage');
    await _apply(tester);

    expect(captured[0], isNotNull);
    expect(captured[0]!.gapWidgets['gap_cover_collage'], isFalse);
    expect(captured[0]!.gapFill, const LibraryPresentation().gapFill);
  });

  testWidgets('布局页与权重页、封面向导页按数据出现', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final captured = <LibraryPresentation?>[null];
    await _open(
      tester,
      captured: captured,
      signals: const [LibraryWeightSignal('tag', '标签权重', 2)],
      cover: _coverAction,
    );
    await _tapTab(tester, t.workspace.wallTabLayout);
    expect(find.text(t.workspace.displayWall), findsOneWidget);
    expect(find.text(t.workspace.heroVisual), findsOneWidget);
    expect(
      find.byKey(const ValueKey('library-weight-selector')),
      findsOneWidget,
    );

    await _tapTab(tester, t.workspace.wallTabWeights);
    expect(find.byKey(const ValueKey('library-slider-标签权重')), findsOneWidget);

    await _tapTab(tester, t.workspace.wallTabCover);
    expect(
      find.byKey(const ValueKey('library-cover-tap-openDetails')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏 + 2 倍字号：页签与各页都不溢出', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _open(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    await _tapTab(tester, t.workspace.wallTabLayout);
    expect(tester.takeException(), isNull);
    await _tapTab(tester, t.workspace.wallTabComponents);
    expect(tester.takeException(), isNull);
  });

  testWidgets('导出设置面板截图供人工检查', (tester) async {
    final output = Platform.environment['ROSSI_WALL_SETTINGS_OUTPUT'];
    if (output == null) return;
    for (final (name, size, scale) in [
      ('wide', const Size(1200, 900), 1.0),
      ('phone-dark', const Size(390, 844), 1.0),
      ('narrow-large-text', const Size(220, 800), 1.6),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final boundary = GlobalKey();
      final captured = <LibraryPresentation?>[null];
      await _open(
        tester,
        captured: captured,
        boundaryKey: boundary,
        textScale: scale,
      );
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      Future<void> shot(String file) async {
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File(
            '$output/$file.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await shot(name);
      await _tapTab(tester, t.workspace.wallTabLayout);
      await shot('$name-layout');
      await _tapTab(tester, t.workspace.wallTabComponents);
      await shot('$name-components');
      await _tapKey(tester, 'gap-tab-shapes');
      await shot('$name-shapes');
      // 关掉这一轮，下一轮重新打开（否则上一轮的页签会留在路由里）。
      await tester.tap(find.byKey(const ValueKey('wall-settings-cancel')));
      await tester.pumpAndSettle();
    }
    tester.view.reset();
  });
}
