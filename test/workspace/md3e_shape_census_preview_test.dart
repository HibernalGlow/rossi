// MD3 Expressive 形状与控件的**普查出图**，给别的工程当视觉参照用。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     ROSSI_UI_PREVIEW_DIR=<目录> \
//     flutter test --no-pub -j1 test/workspace/md3e_shape_census_preview_test.dart
//
// 出图机制沿用 `panel_expressive_preview_test.dart`：`RenderRepaintBoundary.toImage`
// 写 PNG，中文字体显式 loadFontFromList（`flutter test` 不加载 FontManifest）。
// 这里只碰**纯 widget**：形状目录、按钮轮廓的三态形变、图标键、工具条槽 ——
// 不接 ObjectBox / 工作台 / 原生库。
//
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/action_group.dart';
import 'package:zephyr/widgets/expressive/expressive_icon_button.dart';
import 'package:zephyr/widgets/expressive/expressive_shape.dart';

const _seed = Color(0xff8b4148);
const _cjkFamily = 'PreviewCJK';

Future<void> _loadCjk() async {
  final bytes = File(
    'asset/fonts/LXGWWenKaiLite-Regular.ttf',
  ).readAsBytesSync();
  await ui.loadFontFromList(bytes, fontFamily: _cjkFamily);
}

Future<void> _write(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  final output = Platform.environment['ROSSI_UI_PREVIEW_DIR'];
  if (output == null) return;
  final context = boundary.currentContext;
  if (context == null) return;
  await tester.runAsync(() async {
    final image = await (context.findRenderObject()! as RenderRepaintBoundary)
        .toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

/// 一颗静止态的形状样片：填充 + 名字。
Widget _swatch(
  ExpressiveButtonShape shape,
  double phase,
  ColorScheme scheme, {
  double size = 64,
  bool labelled = true,
}) {
  return SizedBox(
    width: labelled ? size + 26 : size,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: size,
          height: size,
          decoration: ShapeDecoration(
            color: scheme.primaryContainer,
            shape: expressiveButtonBorder(shape, phase, size),
          ),
        ),
        if (labelled)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              shape.name,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    ),
  );
}

Widget _section(String title, ColorScheme scheme) => Align(
  alignment: Alignment.centerLeft,
  child: Text(
    title,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: scheme.primary,
    ),
  ),
);

Future<void> _pumpSheet(
  WidgetTester tester, {
  required GlobalKey boundary,
  required Size size,
  required Brightness brightness,
  required Widget child,
}) async {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          fontFamily: _cjkFamily,
        ),
        home: Scaffold(
          backgroundColor: scheme.surface,
          body: MaterialUiCompatibilityBridge(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Align(alignment: Alignment.topLeft, child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

const _allShapes = ExpressiveButtonShape.values;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadCjk);

  final boundary = GlobalKey();

  testWidgets('出图：形状目录静止态（暗 / 亮）', (tester) async {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      final scheme = ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: brightness,
      );
      await _pumpSheet(
        tester,
        boundary: boundary,
        size: const Size(760, 620),
        brightness: brightness,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section(
              'ExpressiveButtonShape · ${_allShapes.length} 档（静止态）',
              scheme,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 10,
              children: [for (final s in _allShapes) _swatch(s, 0, scheme)],
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      await _write(
        tester,
        boundary,
        'shape-census-rest-${brightness == Brightness.dark ? 'dark' : 'light'}',
      );
    }
  });

  testWidgets('出图：形状三态形变（静止 → 按压 → 展开）', (tester) async {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    );
    for (final half in [_ShapeHalf.first, _ShapeHalf.second]) {
      final shapes = half == _ShapeHalf.first
          ? _allShapes.take(18).toList()
          : _allShapes.skip(18).toList();
      await _pumpSheet(
        tester,
        boundary: boundary,
        size: Size(520, 116 * shapes.length + 140),
        brightness: Brightness.dark,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section('同一形状的三态：静止 / 按压 / 展开', scheme),
            const SizedBox(height: 8),
            for (final s in shapes)
              SizedBox(
                height: 96,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        s.name,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    _swatch(s, 0, scheme, size: 54, labelled: false),
                    const SizedBox(width: 14),
                    _swatch(s, 1, scheme, size: 54, labelled: false),
                    const SizedBox(width: 14),
                    _swatch(s, 2, scheme, size: 54, labelled: false),
                  ],
                ),
              ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      await _write(
        tester,
        boundary,
        half == _ShapeHalf.first
            ? 'shape-morph-phases-a'
            : 'shape-morph-phases-b',
      );
    }
  });

  testWidgets('出图：ExpressiveIconButton 的形状与选中态', (tester) async {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      final scheme = ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: brightness,
      );
      const picked = [
        ExpressiveButtonShape.roundedSquare,
        ExpressiveButtonShape.pill,
        ExpressiveButtonShape.clover4Leaf,
        ExpressiveButtonShape.burst,
        ExpressiveButtonShape.gem,
        ExpressiveButtonShape.ghostish,
        ExpressiveButtonShape.bun,
        ExpressiveButtonShape.heart,
      ];
      await _pumpSheet(
        tester,
        boundary: boundary,
        size: const Size(760, 420),
        brightness: brightness,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section('ExpressiveIconButton · 未选中', scheme),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final s in picked)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: ExpressiveIconButton(
                      glyph: AppGlyphs.star,
                      tooltip: s.name,
                      onPressed: () {},
                      shape: s,
                      size: 44,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _section('同一批形状 · 选中（active，图标会转一档）', scheme),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final s in picked)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: ExpressiveIconButton(
                      glyph: AppGlyphs.star,
                      tooltip: '${s.name}-active',
                      onPressed: () {},
                      active: true,
                      shape: s,
                      size: 44,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _section('尺寸档（32 / 40 / 56 / 72）与禁用态', scheme),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (final size in [32.0, 40.0, 56.0, 72.0])
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ExpressiveIconButton(
                      glyph: AppGlyphs.search,
                      tooltip: 'size-$size',
                      onPressed: () {},
                      size: size,
                      shape: ExpressiveButtonShape.cookie7Sided,
                    ),
                  ),
                ExpressiveIconButton(
                  glyph: AppGlyphs.arrowBack,
                  tooltip: 'disabled',
                  onPressed: null,
                  size: 44,
                  shape: ExpressiveButtonShape.slanted,
                ),
              ],
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      await _write(
        tester,
        boundary,
        'expressive-icon-buttons-${brightness == Brightness.dark ? 'dark' : 'light'}',
      );
    }
  });

  testWidgets('出图：ActionGroup 工具条槽（横排 / 竖排 / 禁用 / muted）', (tester) async {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    );
    List<Widget> icons({bool lastDisabled = false, bool muted = false}) => [
      ActionIconButton(
        glyph: AppGlyphs.search,
        tooltip: '搜索',
        onPressed: () {},
      ),
      const SizedBox(width: ActionGroupMetrics.gapWithinGroup),
      ActionIconButton(
        glyph: AppGlyphs.dashboard,
        tooltip: '面板',
        onPressed: () {},
        muted: muted,
      ),
      const SizedBox(width: ActionGroupMetrics.gapWithinGroup),
      ActionIconButton(
        glyph: AppGlyphs.history,
        tooltip: lastDisabled ? '禁用' : '历史',
        onPressed: lastDisabled ? null : () {},
      ),
    ];
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(760, 470),
      brightness: Brightness.dark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section('ActionGroup · 横排（末颗禁用）', scheme),
          const SizedBox(height: 8),
          ActionGroup(children: icons(lastDisabled: true)),
          const SizedBox(height: 18),
          _section('ActionGroup · 横排 + 显式底色 fill', scheme),
          const SizedBox(height: 8),
          ActionGroup(
            fill: scheme.secondaryContainer,
            children: icons(muted: true),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section('ActionGroup · 竖排（侧栏那一档）', scheme),
                    const SizedBox(height: 8),
                    ActionGroup(axis: Axis.vertical, children: icons()),
                  ],
                ),
              ),
              const SizedBox(width: 28),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section('两颗键之间不自动加分隔：间距由调用方给', scheme),
                    const SizedBox(height: 8),
                    ActionGroup(
                      children: [
                        ...icons(),
                        const SizedBox(width: 18),
                        ActionIconButton(
                          glyph: AppGlyphs.tools,
                          tooltip: '设置',
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'action-groups-dark');
  });
}

enum _ShapeHalf { first, second }
