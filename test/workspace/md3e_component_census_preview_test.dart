import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ray_menu/flutter_ray_menu.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/theme_shape.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/type/breadcrumb_style.dart';
import 'package:zephyr/util/toast/toast_style.dart';
import 'package:zephyr/widgets/action_group.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/control_shape.dart';
import 'package:zephyr/widgets/error_view.dart';
import 'package:zephyr/widgets/expressive/expressive_blob.dart';
import 'package:zephyr/widgets/expressive/expressive_icon_button.dart';
import 'package:zephyr/widgets/expressive/expressive_shape.dart';
import 'package:zephyr/widgets/expressive/shelf_list_editor.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/gesture_lock.dart';
import 'package:zephyr/widgets/glass/liquid_glass.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:zephyr/widgets/multi_choice_list_dialog.dart';
import 'package:zephyr/widgets/navigation/navigation_dock.dart';
import 'package:zephyr/widgets/navigation/navigation_shape.dart';
import 'package:zephyr/widgets/navigation/panel_switcher_tabs.dart';
import 'package:zephyr/widgets/navigation/path_breadcrumb.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/popup_select_field.dart';
import 'package:zephyr/widgets/radial/expressive_ray_menu.dart';
import 'package:zephyr/widgets/section_header.dart';
import 'package:zephyr/widgets/spring_lens/jelly_hover.dart';
import 'package:zephyr/widgets/spring_lens/spring_choice_bar.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_bar.dart';
import 'package:zephyr/widgets/toast/toast_card.dart';
import 'package:zephyr/workspace/model/shelf_library_query.dart';
import 'package:zephyr/workspace/widgets/cards/expressive_widgets.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view_mode.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_list_chip.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_list_rail.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_list_toolbar.dart';

// `globalSetting` 会读 `objectbox`（`main.dart` 的全局），而它 transitively 被
// `convertChineseForDisplay` 用到 —— 出图台里凡是走 `t`/中文转换的组件都要先立起
// 一份临时 ObjectBox，口径与 `panel_expressive_preview_test.dart` 一致。
import '../test_helper.dart';

/// **MD3 Expressive 组件普查出图台**（只出图，不碰 `lib/`）。
///
/// 用途：给另一个前端项目当**视觉参照集**。机制逐字沿用
/// `panel_expressive_preview_test.dart`：
/// `ROSSI_UI_PREVIEW_DIR=<目录> flutter test --no-pub -j1 <本文件>`，一图一 case。
///
/// 三条纪律与那条 harness 相同：
/// - `flutter test` 不加载 FontManifest，中文全豆腐块 → 显式 `loadFontFromList`
///   并把主题字族指过去；
/// - **不用 `pumpAndSettle`**：这一屏里到处是不定进度与弹簧，永远等不到；
/// - 出图前先 `expect(tester.takeException(), isNull)`，坏掉的图不许静默出一张空白。
///
/// 视口 = 出图尺寸：`toImage` 只拍得到视口内那一块，所以每张图的尺寸都按
/// 「内容真的落得下」算过，宁可留白也不要裁掉一角。
const _seed = Color(0xff8b4148);
const _cjkFamily = 'PreviewCJK';

Future<void> _loadCjk() async {
  final bytes = File(
    'asset/fonts/LXGWWenKaiLite-Regular.ttf',
  ).readAsBytesSync();
  await ui.loadFontFromList(bytes, fontFamily: _cjkFamily);
  // 同理，`Icon(Icons.xxx)` 用的是 MaterialIcons 那一支，test 里不加载就全是方框。
  // 从 SDK 缓存里显式注册一次（拿不到就跳过：图标成方框不影响其余判据）。
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final iconFont = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (iconFont.existsSync()) {
      await ui.loadFontFromList(
        iconFont.readAsBytesSync(),
        fontFamily: 'MaterialIcons',
      );
    }
  }
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

/// 一张出图台：固定视口 + 一份主题 + 桥接层 + 面板圆角 scope。
///
/// **视口会自动长高**：`toImage` 只拍得到视口内那一块，而 `_Blocks` 用的是
/// `SingleChildScrollView` —— 内容比视口高时它**不报错、只是滚不出去**，
/// 于是图会静默缺一角。所以这里量一次 `maxScrollExtent`，有富余就把视口抬高
/// 再拍，直到「一屏装得下全部」为止（最多 4 轮）。
Future<void> _pumpSheet(
  WidgetTester tester, {
  required GlobalKey boundary,
  required Widget child,
  required Size size,
  Brightness brightness = Brightness.dark,
}) async {
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var current = size;
  for (var attempt = 0; attempt < 4; attempt++) {
    final overflow = await _pumpAt(
      tester,
      boundary: boundary,
      child: child,
      size: current,
      brightness: brightness,
    );
    if (overflow <= 1) return;
    current = Size(current.width, current.height + overflow.ceil() + 2);
  }
  throw StateError(
    '出图台装了 4 轮仍装不下：视口 $current 之外还有内容，'
    '这张图会缺一角 —— 把内容拆成两张图，而不是放行。',
  );
}

Future<double> _pumpAt(
  WidgetTester tester, {
  required GlobalKey boundary,
  required Widget child,
  required Size size,
  required Brightness brightness,
}) async {
  tester.view.physicalSize = size;
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        // 少了 delegate，PopupMenuButton / Tooltip 会先抛 No MaterialLocalizations。
        supportedLocales: AppLocaleUtils.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          fontFamily: _cjkFamily,
        ),
        home: Scaffold(
          backgroundColor: scheme.surface,
          // 桥接层必须在 MaterialApp **里面**（它要读 Localizations 祖先）。
          // ignore: deprecated_member_use
          body: MaterialUiCompatibilityBridge(
            child: ThemeShapeScope(
              radius: kDefaultPanelRadius,
              child: SizedBox.fromSize(size: size, child: child),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  if (find.byType(_Blocks).evaluate().isEmpty) return 0;
  return tester.state<_BlocksState>(find.byType(_Blocks)).maxScrollExtent;
}

void _noopBool(bool value) {}
void _noopVoid() {}

/// 一条 ShapeBorder 的实拍（填充 + 默认描边），出图台的基本单元。
class _Swatch extends StatelessWidget {
  const _Swatch({required this.shape, required this.box, required this.fill});
  final ShapeBorder shape;
  final double box;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: box,
      height: box,
      child: Material(type: MaterialType.card, color: fill, shape: shape),
    );
  }
}

/// 一颗带小标签的格子（`Wrap` 里的一档）。
class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.child, this.width = 120});
  final String label;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            child,
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9.5, height: 1.15),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一组上面那条**看得见的题注**：读者要把「图 → 组件名」对上。
class _Block extends StatelessWidget {
  const _Block({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        child,
        const SizedBox(height: 20),
      ],
    );
  }
}

/// 竖着摞几组 `_Block`，左上对齐。带一只 `ScrollController`，
/// 好让 `_pumpSheet` 量出「还有多少内容滚不出去」并把视口抬高。
class _Blocks extends StatefulWidget {
  const _Blocks({required this.blocks, this.padding = 20, this.width});
  final List<Widget> blocks;
  final double padding;
  final double? width;

  @override
  State<_Blocks> createState() => _BlocksState();
}

class _BlocksState extends State<_Blocks> {
  final _scroll = ScrollController();

  /// 还有多少内容落在视口之外（0 = 这张图是完整的）。
  double get maxScrollExtent =>
      _scroll.hasClients ? _scroll.position.maxScrollExtent : 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scroll,
      padding: EdgeInsets.all(widget.padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.width != null)
            SizedBox(
              width: widget.width,
              child: Column(children: widget.blocks),
            )
          else
            ...widget.blocks,
        ],
      ),
    );
  }
}

const _allShapes = ExpressiveButtonShape.values;

/// 三档示意色（不跟随主题，纯为了让形状/轮廓在图上最好读）。
const _fillA = Color(0xFFEACFD2);
const _fillB = Color(0xFFD8E2D9);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadCjk();
    await TestObjectBoxHelper.setUpTestObjectBox();
  });
  tearDownAll(TestObjectBoxHelper.tearDownTestObjectBox);

  // ==========================================================
  // A. 本仓自己的 Expressive 词汇
  // ==========================================================

  testWidgets('A1 形状普查：ExpressiveButtonShape 全部 35 档（暗）', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 720),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'lib/widgets/expressive/expressive_shape.dart — enum ExpressiveButtonShape '
              '(35 values) → MaterialShapes → expressiveButtonBorder(shape, 0, 62)。'
              'seed 0xff8b4148；填充色交替，只为把轮廓读清楚',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Wrap(
                spacing: 2,
                runSpacing: 2,
                children: [
                  for (final (index, shape) in _allShapes.indexed)
                    _Cell(
                      label: shape.name,
                      width: 128,
                      child: _Swatch(
                        box: 62,
                        fill: index.isEven ? _fillA : _fillB,
                        shape: expressiveButtonBorder(shape, 0, 62),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'a1-shape-census-dark');
  });

  testWidgets('A1b 形状普查（亮底：填充 + 描边两档）', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 860),
      brightness: Brightness.light,
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '同一份 ExpressiveButtonShape：左=填充 primaryContainer（expressiveButtonBorder '
                  'phase 0），右=描边档（ExpressiveMorphBorder(from: X, to: X, side: 2px secondary)）',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Wrap(
                    spacing: 2,
                    runSpacing: 2,
                    children: [
                      for (final shape in _allShapes)
                        _Cell(
                          label: shape.name,
                          width: 186,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _Swatch(
                                box: 54,
                                fill: scheme.primaryContainer,
                                shape: expressiveButtonBorder(shape, 0, 54),
                              ),
                              const SizedBox(width: 8),
                              _Swatch(
                                box: 54,
                                fill: Colors.transparent,
                                shape: ExpressiveMorphBorder(
                                  from: shape,
                                  to: shape,
                                  side: BorderSide(
                                    color: scheme.secondary,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'a1b-shape-census-light');
  });

  testWidgets('A2 形变三相位：expressiveButtonBorder(shape, phase, size)', (
    tester,
  ) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 920),
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'expressiveButtonBorder(shape, phase, size)：phase 0=静止 '
                  '1=按压(shape.pressedShape) 2=展开(shape.expandedShape)。'
                  'phase 是同一条状态轨迹，支持中途反向',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Wrap(
                    spacing: 2,
                    runSpacing: 2,
                    children: [
                      for (final shape in _allShapes)
                        _Cell(
                          width: 224,
                          label:
                              '${shape.name} → ${shape.pressedShape.name} → '
                              '${shape.expandedShape.name}',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _Swatch(
                                box: 46,
                                fill: scheme.primaryContainer,
                                shape: expressiveButtonBorder(shape, 0, 46),
                              ),
                              const SizedBox(width: 6),
                              _Swatch(
                                box: 46,
                                fill: scheme.primary,
                                shape: expressiveButtonBorder(shape, 1, 46),
                              ),
                              const SizedBox(width: 6),
                              _Swatch(
                                box: 46,
                                fill: scheme.tertiaryContainer,
                                shape: expressiveButtonBorder(shape, 2, 46),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'a2-shape-morph-phases-dark');
  });

  testWidgets('A3 A→B 形变序列：ExpressiveMorphBorder', (tester) async {
    final boundary = GlobalKey();
    const pairs = <(ExpressiveButtonShape, ExpressiveButtonShape)>[
      (ExpressiveButtonShape.heart, ExpressiveButtonShape.circle),
      (ExpressiveButtonShape.burst, ExpressiveButtonShape.cookie12Sided),
      (ExpressiveButtonShape.sunny, ExpressiveButtonShape.flower),
      (ExpressiveButtonShape.arrow, ExpressiveButtonShape.diamond),
      (ExpressiveButtonShape.gem, ExpressiveButtonShape.pentagon),
      (ExpressiveButtonShape.puffy, ExpressiveButtonShape.puffyDiamond),
      (ExpressiveButtonShape.clover4Leaf, ExpressiveButtonShape.cookie4Sided),
      (ExpressiveButtonShape.ghostish, ExpressiveButtonShape.arch),
      (ExpressiveButtonShape.pixelCircle, ExpressiveButtonShape.circle),
      (ExpressiveButtonShape.fan, ExpressiveButtonShape.triangle),
      (ExpressiveButtonShape.bun, ExpressiveButtonShape.pill),
      (ExpressiveButtonShape.slanted, ExpressiveButtonShape.gem),
    ];
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 620),
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ExpressiveMorphBorder(from:, to:, progress:, rotation:, side:)：'
                  '两条闭合轮廓按曲线特征匹配后逐点插值；每行 progress = 0 / .25 / .5 / .75 / 1',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      for (final (from, to) in pairs)
                        _Cell(
                          width: 320,
                          label: '${from.name} → ${to.name}',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final progress in const [
                                0.0,
                                .25,
                                .5,
                                .75,
                                1.0,
                              ]) ...[
                                _Swatch(
                                  box: 44,
                                  fill: scheme.secondaryContainer,
                                  shape: ExpressiveMorphBorder(
                                    from: from,
                                    to: to,
                                    progress: progress,
                                    side: BorderSide(
                                      color: scheme.primary,
                                      width: 1.6,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 5),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'a3-shape-morph-sequences-dark');
  });

  testWidgets('A4 ExpressiveIconButton：状态 × 形状（暗）', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 560),
      child: _Blocks(
        blocks: [
          _Block(
            title:
                'ExpressiveIconButton(glyph:, tooltip:, onPressed:, active:, size:, activeTurns:, activeGlyph:, shape:) — rest / active 两档',
            child: Wrap(
              spacing: 2,
              children: [
                for (final shape in const [
                  ExpressiveButtonShape.roundedSquare,
                  ExpressiveButtonShape.circle,
                  ExpressiveButtonShape.pill,
                  ExpressiveButtonShape.heart,
                  ExpressiveButtonShape.gem,
                  ExpressiveButtonShape.arrow,
                ]) ...[
                  _Cell(
                    width: 130,
                    label: '${shape.name} rest',
                    child: ExpressiveIconButton(
                      glyph: AppGlyphs.heart,
                      tooltip: shape.name,
                      shape: shape,
                      onPressed: () {},
                    ),
                  ),
                  _Cell(
                    width: 130,
                    label: '${shape.name} active',
                    child: ExpressiveIconButton(
                      glyph: AppGlyphs.heart,
                      activeGlyph: AppGlyphs.check,
                      tooltip: shape.name,
                      active: true,
                      shape: shape,
                      onPressed: () {},
                    ),
                  ),
                ],
              ],
            ),
          ),
          _Block(
            title:
                'ExpressiveIconButton：形状取样 + disabled 档（onPressed=null）+ size 40 / 56',
            child: Wrap(
              spacing: 2,
              children: [
                for (final (index, shape) in const [
                  ExpressiveButtonShape.burst,
                  ExpressiveButtonShape.cookie6Sided,
                  ExpressiveButtonShape.sunny,
                  ExpressiveButtonShape.puffy,
                  ExpressiveButtonShape.clover4Leaf,
                  ExpressiveButtonShape.fan,
                  ExpressiveButtonShape.pixelCircle,
                  ExpressiveButtonShape.arch,
                  ExpressiveButtonShape.verySunny,
                  ExpressiveButtonShape.diamond,
                ].indexed)
                  _Cell(
                    width: 130,
                    label: index == 3 ? '${shape.name} disabled' : shape.name,
                    child: ExpressiveIconButton(
                      glyph: AppGlyphs.sparkle,
                      tooltip: shape.name,
                      size: index == 0 ? 56 : 40,
                      shape: shape,
                      onPressed: index == 3 ? null : () {},
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'a4-expressive-icon-button-dark');
  });

  testWidgets('A4b ExpressiveIconButton（亮底）', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(820, 300),
      brightness: Brightness.light,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'ExpressiveIconButton — light scheme, seed 0xff8b4148（active 档换 '
              'primary 底 + onPrimary 图标，并带 activeTurns 旋转）',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
            SizedBox(height: 14),
            Wrap(
              spacing: 6,
              children: [
                _IconBtnSample(
                  shape: ExpressiveButtonShape.roundedSquare,
                  label: 'roundedSquare',
                ),
                _IconBtnSample(
                  shape: ExpressiveButtonShape.pill,
                  label: 'pill',
                ),
                _IconBtnSample(
                  shape: ExpressiveButtonShape.heart,
                  label: 'heart active',
                  active: true,
                ),
                _IconBtnSample(
                  shape: ExpressiveButtonShape.cookie6Sided,
                  label: 'cookie6Sided active',
                  active: true,
                ),
                _IconBtnSample(shape: ExpressiveButtonShape.gem, label: 'gem'),
                _IconBtnSample(
                  shape: ExpressiveButtonShape.pixelTriangle,
                  label: 'pixelTriangle',
                ),
              ],
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'a4b-expressive-icon-button-light');
  });

  testWidgets('A5 ActionGroup / ActionIconButton / ActionToggleButton', (
    tester,
  ) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 520),
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return _Blocks(
            blocks: [
              _Block(
                title:
                    'ActionGroup(children:, fill:, axis: Axis.horizontal, bubbleTargets:) + '
                    'ActionIconButton(glyph:, tooltip:, onPressed:, enabled:, muted:, onLongPress:) + '
                    'ActionToggleButton(glyph:, tooltip:, on:, onPressed:, enabled:) — 横排锁高 40',
                child: Row(
                  children: [
                    ActionGroup(
                      children: [
                        ActionIconButton(
                          glyph: AppGlyphs.chevronBack,
                          tooltip: '后退',
                          onPressed: () {},
                        ),
                        ActionIconButton(
                          glyph: AppGlyphs.chevronForward,
                          tooltip: '前进',
                          onPressed: () {},
                        ),
                        ActionIconButton(
                          glyph: AppGlyphs.arrowUp,
                          tooltip: '上一级',
                          onPressed: () {},
                        ),
                        const SizedBox(
                          width: ActionGroupMetrics.gapBetweenGroups,
                        ),
                        ActionIconButton(
                          glyph: AppGlyphs.refresh,
                          tooltip: '刷新（enabled=false）',
                          enabled: false,
                          onPressed: () {},
                        ),
                        ActionIconButton(
                          glyph: AppGlyphs.home,
                          tooltip: '主页（muted）',
                          muted: true,
                          onPressed: () {},
                        ),
                        const SizedBox(
                          width: ActionGroupMetrics.gapBetweenGroups,
                        ),
                        ActionToggleButton(
                          glyph: AppGlyphs.eye,
                          tooltip: '穿透模式（on）',
                          on: true,
                          onPressed: () {},
                        ),
                        ActionToggleButton(
                          glyph: AppGlyphs.pin,
                          tooltip: '固定（off）',
                          on: false,
                          onPressed: () {},
                        ),
                      ],
                    ),
                    const SizedBox(width: 24),
                    ActionGroup(
                      fill: scheme.tertiaryContainer,
                      children: [
                        ActionIconButton(
                          glyph: AppGlyphs.search,
                          tooltip: '搜索',
                          onPressed: () {},
                        ),
                        ActionIconButton(
                          glyph: AppGlyphs.sort,
                          tooltip: '排序',
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _Block(
                title:
                    'ActionGroup(axis: Axis.vertical) — 同一份槽，换方向不换口径（竖排锁宽 40）；右：fill 另传一档',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ActionGroup(
                      axis: Axis.vertical,
                      children: [
                        ActionIconButton(
                          glyph: AppGlyphs.layers,
                          tooltip: '图层',
                          onPressed: () {},
                        ),
                        ActionIconButton(
                          glyph: AppGlyphs.gridPlus,
                          tooltip: '网格',
                          onPressed: () {},
                        ),
                        ActionToggleButton(
                          glyph: AppGlyphs.bookmark,
                          tooltip: '书签（on）',
                          on: true,
                          onPressed: () {},
                        ),
                        ActionIconButton(
                          glyph: AppGlyphs.settings,
                          tooltip: '设置（disabled）',
                          enabled: false,
                          onPressed: () {},
                        ),
                      ],
                    ),
                    const SizedBox(width: 24),
                    ActionGroup(
                      axis: Axis.vertical,
                      fill: scheme.secondaryContainer,
                      children: [
                        ActionIconButton(
                          glyph: AppGlyphs.wand,
                          tooltip: '魔法',
                          onPressed: () {},
                        ),
                        ActionIconButton(
                          glyph: AppGlyphs.more,
                          tooltip: '更多',
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const _Block(
                title: 'ActionGroupMetrics（全应用一份的度量）',
                child: Text(
                  'buttonSize 40 · iconSize 20 · gapWithinGroup 4 · gapBetweenGroups 12 · '
                  'wellPadding 2 · radius = ControlShape.trackCorner 16\n'
                  '工具条按钮的按压反馈是 ElasticPress 形变（不是水波纹），所以 '
                  'ActionIconButton.style 把 pressed 档 overlay 抹平。',
                  style: TextStyle(fontSize: 11.5, height: 1.5),
                ),
              ),
            ],
          );
        },
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'a5-action-group-dark');
  });

  testWidgets('A6 ExpressiveShapeBadge + ExpressivePatchBackdrop', (
    tester,
  ) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 900),
      child: _Blocks(
        blocks: [
          _Block(
            title:
                'ExpressiveShapeBadge(icon:, shape:, seed:, size:, glyphSize:, tone: ExpressiveTone, active:, color:, foreground:) — 七档 tone × rest/active',
            child: Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                for (final tone in ExpressiveTone.values) ...[
                  _Cell(
                    width: 116,
                    label: '${tone.name} rest',
                    child: ExpressiveShapeBadge(
                      icon: AppGlyphs.bolt,
                      tone: tone,
                      size: 40,
                    ),
                  ),
                  _Cell(
                    width: 116,
                    label: '${tone.name} active',
                    child: ExpressiveShapeBadge(
                      icon: AppGlyphs.bolt,
                      tone: tone,
                      size: 40,
                      active: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
          _Block(
            title:
                'ExpressiveShapeBadge：shape 显式档（kExpressiveBadgeShapes 池 + expressiveShapeForSeed(seed)）',
            child: Wrap(
              spacing: 4,
              children: [
                for (final shape in kExpressiveBadgeShapes)
                  _Cell(
                    width: 116,
                    label: shape.name,
                    child: ExpressiveShapeBadge(
                      icon: AppGlyphs.donut,
                      shape: shape,
                      size: 42,
                      tone: ExpressiveTone.tertiary,
                    ),
                  ),
              ],
            ),
          ),
          _Block(
            title:
                'ExpressivePatchBackdrop(seed:, child:, tone:, active:, intensity:, borderRadius:, borderSide:, onTap:) — M3E 撞色几何贴片（两枚有机多边形 + 一枚种子 Blob 描边）',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final tone in ExpressiveTone.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ExpressivePatchBackdrop(
                      seed: tone.index * 977 + 13,
                      tone: tone,
                      active: tone.index.isEven,
                      intensity: tone.index.isEven ? 1.0 : 0.72,
                      borderRadius: tone.index.isEven
                          ? expressiveCornerMd
                          : expressiveCornerSm,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      onTap: () {},
                      child: SizedBox(
                        width: 1000,
                        child: Text(
                          'tone=${tone.name} · active=${tone.index.isEven} · '
                          'seed=${tone.index * 977 + 13} · '
                          'radius=${tone.index.isEven ? 'expressiveCornerMd' : 'expressiveCornerSm'}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'a6-expressive-badge-and-patch-dark');
  });

  testWidgets('A6b ExpressiveHeroBanner + ExpressiveToggleTile', (
    tester,
  ) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 820),
      child: _Blocks(
        blocks: [
          _Block(
            title:
                'ExpressiveHeroBanner(seed:, icon:, title:, subtitle:, shape:, tone:, active:, pills:, trailing:)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (index, tone) in const [
                  ExpressiveTone.secondary,
                  ExpressiveTone.primary,
                  ExpressiveTone.tertiary,
                ].indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SizedBox(
                      width: 1000,
                      child: ExpressiveHeroBanner(
                        seed: 4100 + index * 37,
                        icon: AppGlyphs.compass,
                        title: '今日阅读节奏 · 第 ${index + 1} 档',
                        subtitle: '撞色贴片 + 多态图标座 + 状态胶囊，替掉孤零零的一行小字',
                        tone: tone,
                        active: index == 1,
                        pills: const [
                          ExpressiveStatusPill(
                            text: '已读 24 页',
                            tone: ExpressiveTone.primary,
                          ),
                          ExpressiveStatusPill(
                            text: '同步中',
                            tone: ExpressiveTone.neutral,
                            compact: true,
                          ),
                          ExpressiveStatusPill(
                            text: '失败',
                            tone: ExpressiveTone.warning,
                          ),
                        ],
                        trailing: ExpressiveIconButton(
                          glyph: AppGlyphs.more,
                          tooltip: '更多',
                          shape: ExpressiveButtonShape.circle,
                          onPressed: _noopVoid,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _Block(
            title:
                'ExpressiveToggleTile(title:, value:, onChanged:, icon:, subtitle:, shape:, activeTone:, seed:, disabled:)',
            child: SizedBox(
              width: 1000,
              child: ExpressiveTileGrid(
                minTileWidth: 300,
                children: const [
                  ExpressiveToggleTile(
                    title: 'GPU 呈现',
                    subtitle: '轮廓由 ExpressiveBlob 生成',
                    icon: AppGlyphs.torch,
                    value: true,
                    onChanged: _noopBool,
                  ),
                  ExpressiveToggleTile(
                    title: '省电档',
                    subtitle: '关一切形变',
                    icon: AppGlyphs.moon,
                    value: false,
                    onChanged: _noopBool,
                  ),
                  ExpressiveToggleTile(
                    title: '墨水屏',
                    subtitle: 'disabled 档：整格 55% 透明',
                    icon: AppGlyphs.article,
                    value: true,
                    disabled: true,
                    onChanged: _noopBool,
                  ),
                  ExpressiveToggleTile(
                    title: 'shape = clover8Leaf',
                    icon: AppGlyphs.donut,
                    value: false,
                    shape: ExpressiveButtonShape.clover8Leaf,
                    activeTone: ExpressiveTone.tertiary,
                    onChanged: _noopBool,
                  ),
                  ExpressiveToggleTile(
                    title: 'activeTone = warning',
                    icon: AppGlyphs.warning,
                    value: true,
                    activeTone: ExpressiveTone.warning,
                    onChanged: _noopBool,
                  ),
                  ExpressiveToggleTile(
                    title: 'seed 固定 = 形状稳定',
                    icon: AppGlyphs.puzzle,
                    value: true,
                    seed: 7,
                    onChanged: _noopBool,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'a6b-expressive-hero-and-toggle-dark');
  });

  testWidgets('A7 ExpressiveTile / IconBadge / Tile / Section（暗 + 亮）', (
    tester,
  ) async {
    for (final (name, brightness) in const [
      ('a7-expressive-tile-kit-dark', Brightness.dark),
      ('a7b-expressive-tile-kit-light', Brightness.light),
    ]) {
      final boundary = GlobalKey();
      await _pumpSheet(
        tester,
        boundary: boundary,
        size: const Size(1160, 1000),
        brightness: brightness,
        child: _Blocks(
          blocks: [
            _Block(
              title:
                  'ExpressiveTile(child:, tone:, color:, radius:, padding:, onTap:, selected:, semanticLabel:) — 三档非对称圆角 expressiveCornerSm/Md/Lg（三圆一尖）',
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final (index, radius) in const [
                    expressiveCornerSm,
                    expressiveCornerMd,
                    expressiveCornerLg,
                  ].indexed)
                    SizedBox(
                      width: 320,
                      child: ExpressiveTile(
                        radius: radius,
                        onTap: () {},
                        child: Text(
                          'ExpressiveTile · radius 档 ${index + 1}（可点：ElasticPress 形变，无水波）',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  const SizedBox(
                    width: 320,
                    child: ExpressiveTile(
                      tone: ExpressiveTone.primary,
                      child: Text('tone = primary（不可点）'),
                    ),
                  ),
                  SizedBox(
                    width: 320,
                    child: ExpressiveTile(
                      selected: true,
                      tone: ExpressiveTone.sunken,
                      onTap: () {},
                      child: const Text('selected = true（主色底 + 1.5px 主色描边）'),
                    ),
                  ),
                ],
              ),
            ),
            _Block(
              title:
                  'ExpressiveIconBadge(icon:, size:, glyphSize:, tone:, color:, foreground:, sided: M3EShapeKind) — cookie 形图标座',
              child: Wrap(
                spacing: 4,
                children: [
                  for (final (index, kind) in const [
                    M3EShapeKind.cookie4Sided,
                    M3EShapeKind.cookie6Sided,
                    M3EShapeKind.cookie7Sided,
                    M3EShapeKind.cookie9Sided,
                    M3EShapeKind.cookie12Sided,
                    M3EShapeKind.flower,
                    M3EShapeKind.gem,
                    M3EShapeKind.puffy,
                    M3EShapeKind.sunny,
                    M3EShapeKind.burst,
                  ].indexed)
                    _Cell(
                      width: 110,
                      label: kind.name,
                      child: ExpressiveIconBadge(
                        icon: AppGlyphs.star,
                        size: 38,
                        sided: kind,
                        tone: ExpressiveTone
                            .values[index % ExpressiveTone.values.length],
                      ),
                    ),
                ],
              ),
            ),
            _Block(
              title:
                  'ExpressiveSection(title:, icon:, trailing:, children:) + ExpressiveTileGrid(children:, spacing:, minTileWidth:)',
              child: SizedBox(
                width: 1000,
                child: ExpressiveSection(
                  title: '分组：一个小标题 + 若干内容（tone 由标题 seed 轮转）',
                  icon: AppGlyphs.category,
                  trailing: const ExpressiveStatusPill(
                    text: '3 项',
                    compact: true,
                  ),
                  children: const [
                    ExpressiveFactTile(label: '图源', value: 'bika'),
                    SizedBox(height: 6),
                    ExpressiveFactTile(label: '话数', value: '第 12 话'),
                    SizedBox(height: 6),
                    ExpressiveFactTile(
                      label: '页',
                      value: '7 / 24',
                      emphasis: true,
                    ),
                  ],
                ),
              ),
            ),
            _Block(
              title: 'ExpressiveEmptyState(icon:, text:, hint:)',
              child: SizedBox(
                width: 640,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    ExpressiveEmptyState(
                      icon: AppGlyphs.openBook,
                      text: '还没有打开任何一本',
                      hint: '打开后这里会出现页码、槽位、呈现器与耗时四组事实',
                    ),
                    ExpressiveEmptyState(
                      icon: AppGlyphs.cloud,
                      text: '离线且没有缓存',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      await _write(tester, boundary, name);
    }
  });

  testWidgets('A7c ExpressiveFactTile / StatTile / Gauge / StatusPill', (
    tester,
  ) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 1040),
      child: _Blocks(
        width: 1000,
        blocks: [
          _Block(
            title:
                'ExpressiveFactTile(label:, value:, valueWidget:, icon:, tone:, emphasis:, onTap:, selected:, trailing:) — 量不到的数一律画 —，不 fallback 成 0',
            child: Column(
              children: const [
                ExpressiveFactTile(
                  label: '呈现器',
                  value: 'gpu_present',
                  icon: AppGlyphs.torch,
                ),
                SizedBox(height: 6),
                ExpressiveFactTile(
                  label: '当前档位',
                  value: '2× 超分',
                  icon: AppGlyphs.trend,
                  emphasis: true,
                ),
                SizedBox(height: 6),
                ExpressiveFactTile(
                  label: '编码',
                  value: null,
                  icon: AppGlyphs.box,
                  trailing: ExpressiveStatusPill(
                    text: '未知',
                    tone: ExpressiveTone.warning,
                    compact: true,
                  ),
                ),
                SizedBox(height: 6),
                ExpressiveFactTile(
                  label: '路径（不可点档套 SelectionArea，可复制）',
                  value: '/library/月光旅行者/012.zip',
                ),
                SizedBox(height: 6),
                ExpressiveFactTile(
                  label: '可点的一格（点了真的落地）',
                  value: '在文件管理器里显示',
                  onTap: _noopVoid,
                ),
                SizedBox(height: 6),
                ExpressiveFactTile(
                  label: '窄档（<200 会上下排）',
                  value: '短',
                  tone: ExpressiveTone.tertiary,
                ),
              ],
            ),
          ),
          _Block(
            title:
                'ExpressiveStatTile(value:, label:, icon:, highlight:, caption:, gauge:, onTap:, selected:, maxValueLines:)',
            child: ExpressiveTileGrid(
              minTileWidth: 210,
              children: const [
                ExpressiveStatTile(
                  value: '1 284',
                  label: '本页累计停留',
                  caption: '秒',
                  icon: AppGlyphs.hourglass,
                ),
                ExpressiveStatTile(
                  value: '76%',
                  label: '已读进度',
                  icon: AppGlyphs.book,
                  highlight: true,
                  gauge: .76,
                ),
                ExpressiveStatTile(
                  value: '—',
                  label: '超分耗时',
                  icon: AppGlyphs.speed,
                ),
                ExpressiveStatTile(
                  value: '2.4 GB',
                  label: '缓存占用',
                  icon: AppGlyphs.storage,
                  gauge: .34,
                ),
              ],
            ),
          ),
          _Block(
            title:
                'ExpressiveGauge(value:, color:, trackColor:, semanticsLabel:) — 弹簧驱动的 M3EProgressIndicator.linear',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                ExpressiveGauge(value: .18),
                SizedBox(height: 8),
                ExpressiveGauge(value: .62),
                SizedBox(height: 8),
                ExpressiveGauge(value: 1.0),
              ],
            ),
          ),
          _Block(
            title:
                'ExpressiveStatusPill(text:, tone:, icon:, dot:, compact:) — 一颗状态点 + 一个词',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                ExpressiveStatusPill(text: '就绪', tone: ExpressiveTone.primary),
                ExpressiveStatusPill(
                  text: '进行中',
                  tone: ExpressiveTone.secondary,
                ),
                ExpressiveStatusPill(
                  text: '已同步',
                  tone: ExpressiveTone.tertiary,
                ),
                ExpressiveStatusPill(text: '失败', tone: ExpressiveTone.warning),
                ExpressiveStatusPill(text: '原始数据', tone: ExpressiveTone.sunken),
                ExpressiveStatusPill(text: '中性', tone: ExpressiveTone.neutral),
                ExpressiveStatusPill(
                  text: '带图标（让位给图标）',
                  tone: ExpressiveTone.neutral,
                  icon: AppGlyphs.cloudDone,
                ),
                ExpressiveStatusPill(
                  text: 'compact',
                  tone: ExpressiveTone.secondary,
                  compact: true,
                ),
                ExpressiveStatusPill(
                  text: '无点',
                  tone: ExpressiveTone.primary,
                  dot: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'a7c-expressive-fact-stat-dark');
  });

  testWidgets('A8 ExpressiveBlob / ExpressiveBlobBorder', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 940),
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          const seeds = [11, 227, 913, 4044, 77777, 1 << 20];
          return _Blocks(
            blocks: [
              _Block(
                title:
                    'ExpressiveBlob.ofSeed(seed).path(rect:, progress:, safeInset:) — 同一个入口产一片各不相同的不规则轮廓；progress 0=不规则 1=收成 stadium；角半径只取 0/4/8/12dp 令牌 + 连续曲率',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (row, progress) in const [0.0, 0.5, 1.0].indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 92,
                              child: Text(
                                'progress\n$row',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  height: 1.3,
                                ),
                              ),
                            ),
                            for (final seed in seeds)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Column(
                                  children: [
                                    CustomPaint(
                                      size: const Size(142, 86),
                                      painter: _BlobPainter(
                                        seed: seed,
                                        progress: progress,
                                        fill: row.isEven
                                            ? scheme.primaryContainer
                                            : scheme.tertiaryContainer,
                                        stroke: scheme.secondary,
                                      ),
                                    ),
                                    Text(
                                      'seed $seed',
                                      style: const TextStyle(fontSize: 9.5),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              _Block(
                title:
                    'ExpressiveBlobBorder(seed:, progress:, safeInset:, side:) 装在装饰盒上（seed 走 expressiveBlobSeed(identity)，FNV-1a，跨编译稳定）',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final label in const [
                      '全部',
                      '未分类',
                      '阅读计划',
                      '深夜',
                      '月光旅行者',
                      '星河之间',
                      '名字很长的一档筛选标签',
                    ]) ...[
                      _BlobChip(label: label, progress: 0),
                      _BlobChip(label: label, progress: .55),
                      _BlobChip(label: label, progress: 1, selected: true),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'a8-expressive-blob-dark');
  });

  testWidgets('A9 PopupPanel（弹层本体：卡片档 280..420）', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 760),
      child: _Blocks(
        blocks: [
          _Block(
            title:
                'PopupPanel(title:, content:, actions:, actionsAlignment:, scrollable:) — 表面即 CommonPopupSurface（surfaceContainer + 托盘同源圆角 + 阴影）',
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                PopupPanel(
                  title: const Text('删除这个书签列表？'),
                  content: const Text('列表里的 12 条目会被移出书架，已下载的文件保留在磁盘上。'),
                  actions: [
                    TextButton(onPressed: () {}, child: const Text('取消')),
                    FilledButton(onPressed: () {}, child: const Text('删除')),
                  ],
                ),
                PopupPanel(
                  title: const Text('actionsAlignment = start'),
                  content: const Text('内容超高时可滚（scrollable: true）。'),
                  actionsAlignment: MainAxisAlignment.start,
                  scrollable: true,
                  actions: [
                    TextButton(onPressed: () {}, child: const Text('重置')),
                    OutlinedButton(onPressed: () {}, child: const Text('导出')),
                    FilledButton(onPressed: () {}, child: const Text('应用')),
                  ],
                ),
                const PopupPanel(
                  title: Text('只有标题与内容（没有动作条）'),
                  content: SizedBox(
                    height: 60,
                    child: ExpressiveFactTile(label: '字段', value: '值读回来的一档'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'a9-popup-panel-dark');
  });

  testWidgets('A9b ShelfListEditor + CommonPopupMenu', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 900),
      child: _Blocks(
        blocks: [
          _Block(
            title:
                'ShelfListEditor(title:, label:, description:, initialName:, onSave:, onDelete:) — PopupPanel + Form + TextFormField（AppShape.all 圆角 + 三枚按钮）',
            child: ShelfListEditor(
              title: '新建书签列表',
              label: '列表名称',
              description: '名称里不能出现斜杠；留空会被留在弹层里解释原因。',
              initialName: '月光旅行者',
              onSave: (_) {},
              onDelete: () {},
            ),
          ),
          _Block(
            title:
                'CommonPopupMenu(items:, minWidth:, maxWidth:) + CommonPopupMenuItem(label:, glyph:, onPressed:, danger:, checked:, subItems:, content:) / CommonPopupMenuItem.divider()，铺在 CommonPopupSurface(child:, depth:, padding:) 上',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CommonPopupSurface(
                  padding: const EdgeInsets.all(8),
                  child: CommonPopupMenu(
                    items: [
                      CommonPopupMenuItem(
                        label: '打开',
                        glyph: AppGlyphs.openInFull,
                        onPressed: () {},
                      ),
                      CommonPopupMenuItem(
                        label: '重命名',
                        glyph: AppGlyphs.edit,
                        checked: true,
                        onPressed: () {},
                      ),
                      const CommonPopupMenuItem.divider(),
                      CommonPopupMenuItem(
                        label: '更多动作',
                        glyph: AppGlyphs.more,
                        subItems: [
                          CommonPopupMenuItem(
                            label: '复制路径',
                            glyph: AppGlyphs.copy,
                            onPressed: () {},
                          ),
                          CommonPopupMenuItem(
                            label: '在文件管理器里显示',
                            glyph: AppGlyphs.folder,
                            onPressed: () {},
                          ),
                        ],
                      ),
                      CommonPopupMenuItem(
                        label: '删除列表',
                        glyph: AppGlyphs.delete,
                        danger: true,
                        onPressed: () {},
                      ),
                      const CommonPopupMenuItem(
                        label: '这一档不可用',
                        glyph: AppGlyphs.block,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                const CommonPopupSurface(
                  depth: .6,
                  padding: EdgeInsets.all(8),
                  child: CommonPopupMenu(
                    minWidth: 220,
                    items: [
                      CommonPopupMenuItem(
                        label: '带次要说明的一行',
                        glyph: AppGlyphs.article,
                        content: CommonPopupMenuTitle(
                          label: '常规宽度',
                          hint: '这一行用 content 替换了标签文本',
                        ),
                      ),
                      CommonPopupMenuItem(
                        label: '未选中档（checked=false）',
                        glyph: AppGlyphs.eye,
                        checked: false,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'a9b-editor-and-popup-menu-dark');
  });

  // ==========================================================
  // B. 上游 material_3_expressive 的标准 Expressive 控件族
  // ==========================================================

  testWidgets('B1 M3EButton：style × shape × size（暗 + 亮）', (tester) async {
    for (final (name, brightness) in const [
      ('b1-m3e-buttons-dark', Brightness.dark),
      ('b1b-m3e-buttons-light', Brightness.light),
    ]) {
      final boundary = GlobalKey();
      await _pumpSheet(
        tester,
        boundary: boundary,
        size: const Size(1160, 1080),
        brightness: brightness,
        child: _Blocks(
          blocks: [
            _Block(
              title:
                  'M3EButton(onPressed:, child: / icon+label:, style: M3EButtonStyle, size: M3EButtonSize, shape: M3EButtonShape, enabled:) — 每行一种 style，每格 shape/size',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final style in M3EButtonStyle.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 78,
                            child: Text(
                              style.name,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final shape in M3EButtonShape.values)
                                  for (final size in const [
                                    M3EButtonSize.xs,
                                    M3EButtonSize.sm,
                                    M3EButtonSize.md,
                                    M3EButtonSize.lg,
                                    M3EButtonSize.xl,
                                  ])
                                    M3EButton(
                                      onPressed: () {},
                                      style: style,
                                      shape: shape,
                                      size: size,
                                      label: Text('${shape.name}/${size.name}'),
                                    ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            _Block(
              title:
                  'M3EButton.icon / 选中态（isSelected + selectedIcon + selectedLabel）/ disabled',
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final style in M3EButtonStyle.values) ...[
                    M3EButton.icon(
                      onPressed: () {},
                      style: style,
                      size: M3EButtonSize.md,
                      icon: const Icon(Icons.add),
                      label: Text('${style.name} + icon'),
                    ),
                    M3EButton(
                      onPressed: () {},
                      style: style,
                      size: M3EButtonSize.md,
                      isSelected: true,
                      label: const Text('未选中'),
                      selectedLabel: const Text('已选中'),
                      icon: const Icon(Icons.favorite_border),
                      selectedIcon: const Icon(Icons.favorite),
                    ),
                    M3EButton(
                      onPressed: null,
                      enabled: false,
                      style: style,
                      size: M3EButtonSize.md,
                      label: const Text('disabled'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      await _write(tester, boundary, name);
    }
  });

  testWidgets('B2 M3EButtonGroup：standard / connected × density × 方向', (
    tester,
  ) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 1000),
      child: _Blocks(
        blocks: [
          for (final type in M3EButtonGroupType.values)
            _Block(
              title:
                  'M3EButtonGroup(actions: M3EButtonGroupAction…, type: ${type.name}, shape:, size:, style:, density:, direction:, spacing:, multiSelect:, selectedIndices:) — ${type == M3EButtonGroupType.connected ? 'connected：joined 轨道 + neighborSquish' : 'standard：带间距的一排'}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final density in M3EButtonGroupDensity.values)
                        M3EButtonGroup(
                          type: type,
                          density: density,
                          style: M3EButtonStyle.tonal,
                          actions: [
                            M3EButtonGroupAction(
                              label: const Text('左'),
                              icon: const Icon(Icons.navigate_before),
                            ),
                            M3EButtonGroupAction(
                              label: const Text('中'),
                              icon: const Icon(Icons.circle),
                            ),
                            M3EButtonGroupAction(
                              label: const Text('右'),
                              icon: const Icon(Icons.navigate_next),
                            ),
                            M3EButtonGroupAction(
                              label: const Text('禁用'),
                              enabled: false,
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  M3EButtonGroup(
                    type: type,
                    direction: Axis.vertical,
                    multiSelect: true,
                    selectedIndices: const {0, 2},
                    onSelectedIndicesChanged: (_) {},
                    actions: [
                      M3EButtonGroupAction(label: const Text('竖排 0')),
                      M3EButtonGroupAction(label: const Text('竖排 1')),
                      M3EButtonGroupAction(label: const Text('竖排 2')),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'b2-m3e-button-group-dark');
  });

  testWidgets('B3 M3EIconButton：variant × shape × size', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 720),
      child: _Blocks(
        blocks: [
          _Block(
            title:
                'M3EIconButton(icon:, onPressed:, tooltip:, variant: M3EIconButtonVariant, size: M3EIconButtonSize, shape: M3EIconButtonShapeVariant, isSelected:, selectedIcon:, badgeValue:, suppressInk:)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final variant in M3EIconButtonVariant.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 84,
                          child: Text(
                            variant.name,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final shape
                                in M3EIconButtonShapeVariant.values)
                              for (final size in M3EIconButtonSize.values)
                                M3EIconButton(
                                  icon: const Icon(Icons.favorite_border),
                                  selectedIcon: const Icon(Icons.favorite),
                                  isSelected:
                                      shape ==
                                          M3EIconButtonShapeVariant.square &&
                                      size == M3EIconButtonSize.md,
                                  variant: variant,
                                  size: size,
                                  shape: shape,
                                  onPressed: () {},
                                ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          _Block(
            title:
                'M3EIconButton：width（defaultWidth / narrow / wide）+ disabled（onPressed=null）+ badgeValue + tooltip + suppressInk',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final width in M3EIconButtonWidth.values)
                  M3EIconButton(
                    icon: const Icon(Icons.push_pin),
                    tooltip: 'width=${width.name}',
                    width: width,
                    size: M3EIconButtonSize.md,
                    variant: M3EIconButtonVariant.tonal,
                    onPressed: () {},
                  ),
                const M3EIconButton(
                  icon: Icon(Icons.lock),
                  tooltip: 'disabled',
                  variant: M3EIconButtonVariant.outlined,
                ),
                M3EIconButton(
                  icon: const Icon(Icons.notifications),
                  badgeValue: 3,
                  tooltip: 'badgeValue=3',
                  variant: M3EIconButtonVariant.filled,
                  size: M3EIconButtonSize.lg,
                  onPressed: () {},
                ),
                M3EIconButton(
                  icon: const Icon(Icons.mail),
                  badgeValue: '12+',
                  tooltip: 'badgeValue 是字符串',
                  variant: M3EIconButtonVariant.standard,
                  size: M3EIconButtonSize.xl,
                  onPressed: () {},
                ),
                M3EIconButton(
                  icon: const Icon(Icons.bolt),
                  tooltip: 'suppressInk = true',
                  suppressInk: true,
                  variant: M3EIconButtonVariant.standard,
                  size: M3EIconButtonSize.xl,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'b3-m3e-icon-buttons-dark');
  });

  testWidgets('B4 M3ESwitch / M3ECheckbox / M3ERadio', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 800),
      child: _Blocks(
        blocks: [
          _Block(
            title:
                'M3ESwitch(value:, onChanged:, selectedIcon:, unselectedIcon:, stateLayerSize:, semanticLabel:) — 开档滑块涨到带图标那一档',
            child: Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                _State(
                  label: 'value=false',
                  child: M3ESwitch(value: false, onChanged: (_) {}),
                ),
                _State(
                  label: 'true + selectedIcon',
                  child: M3ESwitch(
                    value: true,
                    onChanged: (_) {},
                    selectedIcon: const Icon(Icons.check, size: 16),
                  ),
                ),
                _State(
                  label: 'true + onChanged=null',
                  child: M3ESwitch(
                    value: true,
                    onChanged: null,
                    selectedIcon: const Icon(Icons.bolt, size: 16),
                  ),
                ),
                const _State(
                  label: '两档都带图标',
                  child: M3ESwitch(
                    value: false,
                    onChanged: _noopBool,
                    selectedIcon: Icon(Icons.check, size: 16),
                    unselectedIcon: Icon(Icons.close, size: 16),
                  ),
                ),
                _State(
                  label: 'stateLayerSize 52',
                  child: M3ESwitch(
                    value: true,
                    stateLayerSize: 52,
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
          _Block(
            title:
                'M3ECheckbox(value:, onChanged:, tristate:, error:, label:, boxSize:, hitSize:, targetSize:, checkedChild:, uncheckedChild:, focusable:)',
            child: Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _State(
                  label: 'false',
                  child: M3ECheckbox(value: false, onChanged: (_) {}),
                ),
                _State(
                  label: 'true',
                  child: M3ECheckbox(value: true, onChanged: (_) {}),
                ),
                _State(
                  label: 'null + tristate',
                  child: M3ECheckbox(
                    value: null,
                    tristate: true,
                    onChanged: (_) {},
                  ),
                ),
                _State(
                  label: 'error + true',
                  child: M3ECheckbox(
                    value: true,
                    error: true,
                    onChanged: (_) {},
                  ),
                ),
                _State(
                  label: 'disabled',
                  child: M3ECheckbox(value: true, onChanged: null),
                ),
                _State(
                  label: 'boxSize 26',
                  child: M3ECheckbox(
                    value: true,
                    boxSize: 26,
                    onChanged: (_) {},
                  ),
                ),
                _State(
                  label: 'error + false',
                  child: M3ECheckbox(
                    value: false,
                    error: true,
                    onChanged: (_) {},
                  ),
                ),
                M3ECheckbox(
                  value: true,
                  onChanged: (_) {},
                  label: const Text('带 label 的一档'),
                ),
                M3ECheckbox(
                  value: true,
                  onChanged: (_) {},
                  checkedChild: const Icon(Icons.star, size: 16),
                  label: const Text('自定义 checkedChild'),
                ),
              ],
            ),
          ),
          _Block(
            title:
                'M3ERadio<T>(value:, groupValue:, onChanged:, label:, error:, focusable:, semanticLabel:)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (index, option) in const ['紧凑', '舒适', '宽松'].indexed)
                  M3ERadio<String>(
                    value: option,
                    groupValue: index == 1 ? option : '紧凑',
                    onChanged: (_) {},
                    label: Text('M3ERadio value=$option'),
                  ),
                M3ERadio<String>(
                  value: '错误档',
                  groupValue: '错误档',
                  error: true,
                  onChanged: (_) {},
                  label: const Text('error = true'),
                ),
                const M3ERadio<String>(
                  value: '禁用档',
                  groupValue: null,
                  onChanged: null,
                  label: Text('onChanged = null'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'b4-m3e-selection-dark');
  });

  testWidgets('B5 M3ESlider：xs / s / m 三档轨道尺度', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 900),
      child: _Blocks(
        blocks: [
          _Block(
            title:
                'M3ESlider(value:, onChanged:, min:, max:, divisions:, label:, size: M3ESliderSize, trackThickness:, cornerRadius:, thumbLength:, dotSize:, dotSpacing:, icon:, iconPosition:, enabled:) — 厚轨 + 断轨就是这一族（xs / s / m）',
            child: SizedBox(
              width: 1020,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final size in const [
                    M3ESliderSize.xs,
                    M3ESliderSize.s,
                    M3ESliderSize.m,
                  ])
                    _SliderRow(size),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'b5-m3e-sliders-dark');
  });

  testWidgets('B5b M3ESlider：l / xl 厚档 + centered / wavy / vertical', (
    tester,
  ) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 1100),
      child: _Blocks(
        blocks: [
          _Block(
            title: 'M3ESlider：l / xl —— 轨道厚到能装下刻度点与文字的那两档',
            child: SizedBox(
              width: 1020,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _SliderRow(M3ESliderSize.l),
                  _SliderRow(M3ESliderSize.xl),
                ],
              ),
            ),
          ),
          _Block(
            title:
                'M3ESlider.centered(value:, onChanged:, divisions:, haptic:, size:) — 轨道从中线向两边生长',
            child: SizedBox(
              width: 1020,
              child: Column(
                children: [
                  M3ESlider.centered(value: .28, onChanged: (_) {}),
                  M3ESlider.centered(
                    value: .5,
                    min: 0,
                    max: 100,
                    divisions: 8,
                    size: M3ESliderSize.l,
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
          _Block(
            title:
                'M3ESlider.wavy / M3ESlider.wavyCentered(amplitude:, wavelength:, waveSpeed:) — 波浪轨道',
            child: SizedBox(
              width: 1020,
              child: Column(
                children: [
                  M3ESlider.wavy(value: .4, onChanged: (_) {}),
                  M3ESlider.wavy(
                    value: .7,
                    amplitude: 6,
                    wavelength: 24,
                    size: M3ESliderSize.m,
                    onChanged: (_) {},
                  ),
                  M3ESlider.wavyCentered(
                    value: .3,
                    amplitude: 8,
                    size: M3ESliderSize.l,
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
          _Block(
            title: 'M3ESlider.vertical / M3ESlider.verticalCentered — 竖轴档',
            child: SizedBox(
              height: 270,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 250,
                    child: M3ESlider.vertical(value: .55, onChanged: (_) {}),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    height: 250,
                    child: M3ESlider.vertical(
                      value: .2,
                      divisions: 5,
                      onChanged: (_) {},
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    height: 250,
                    child: M3ESlider.verticalCentered(
                      value: .3,
                      size: M3ESliderSize.m,
                      onChanged: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'b5b-m3e-sliders-large-dark');
  });

  testWidgets('B6 M3EChip 四型', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 720),
      child: _Block(
        title:
            'M3EChip(label:, type: M3EChipType(assist/filter/input/suggestion), leading:, avatar:, trailing:, selected:, elevated:, onPressed:, onDeleted:)',
        child: Wrap(
          spacing: 8,
          runSpacing: 10,
          children: [
            for (final type in M3EChipType.values) ...[
              M3EChip(label: '${type.name} 常态', type: type, onPressed: () {}),
              M3EChip(
                label: '${type.name} 选中',
                type: type,
                selected: true,
                onPressed: () {},
              ),
              M3EChip(label: '${type.name} 禁用', type: type, onPressed: null),
              M3EChip(
                label: '${type.name} leading+trailing',
                type: type,
                leading: const Icon(Icons.bolt, size: 16),
                trailing: const Icon(Icons.close, size: 16),
                onDeleted: () {},
                onPressed: () {},
              ),
              M3EChip(
                label: '${type.name} elevated',
                type: type,
                elevated: true,
                avatar: const Icon(Icons.circle, size: 14),
                onPressed: () {},
              ),
              M3EChip(label: '${type.name} 无回调（纯展示）', type: type),
            ],
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'b6-m3e-chips-dark');
  });

  testWidgets('B7 M3ESegmentedButton：单选 / 多选 / 四档 density', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 640),
      child: _Block(
        title:
            'M3ESegmentedButton<T>(segments: M3ESegment…, selected:, onSelectionChanged:, multiSelect:, showSelectedIcon:, density: M3ESegmentedButtonDensity, enabled:)',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final density in M3ESegmentedButtonDensity.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'density = ${density.name}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    M3ESegmentedButton<String>(
                      density: density,
                      segments: const [
                        M3ESegment(value: 'a', label: '列表'),
                        M3ESegment(value: 'b', label: '网格'),
                        M3ESegment(
                          value: 'c',
                          label: '瀑布',
                          icon: Icon(Icons.grid_view),
                        ),
                        M3ESegment(value: 'd', label: '禁用', enabled: false),
                      ],
                      selected: const {'b'},
                      onSelectionChanged: (_) {},
                    ),
                  ],
                ),
              ),
            M3ESegmentedButton<String>(
              multiSelect: true,
              segments: const [
                M3ESegment(value: 'x', label: '只看已读'),
                M3ESegment(value: 'y', label: '只看离线'),
                M3ESegment(value: 'z', label: '只看失败'),
              ],
              selected: const {'x', 'z'},
              onSelectionChanged: (_) {},
            ),
            const SizedBox(height: 12),
            M3ESegmentedButton<String>(
              showSelectedIcon: false,
              enabled: false,
              segments: const [
                M3ESegment(value: 'p', label: '整条 disabled（enabled=false）'),
                M3ESegment(value: 'q', label: '第二档'),
              ],
              selected: const {'p'},
              onSelectionChanged: _noopSegments,
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'b7-m3e-segmented-dark');
  });

  testWidgets('B8 M3EFab / M3EExtendedFab', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 1000),
      child: _Blocks(
        blocks: [
          _Block(
            title:
                'M3EFab(icon:, onPressed:, size: M3EFabSize(small/regular/medium/large), color: M3EFabColor, cornerRadius:, elevation:, tooltip:, appear:)',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final size in M3EFabSize.values)
                  for (final color in const [
                    M3EFabColor.primary,
                    M3EFabColor.secondary,
                    M3EFabColor.tertiary,
                    M3EFabColor.surface,
                  ])
                    _Cell(
                      width: 132,
                      label: '${size.name}/${color.name}',
                      child: M3EFab(
                        icon: const Icon(Icons.add),
                        size: size,
                        color: color,
                        onPressed: () {},
                      ),
                    ),
              ],
            ),
          ),
          _Block(
            title:
                'M3EFab：primaryFilled / secondaryFilled / tertiaryFilled + disabled（onPressed 缺省）+ 自定义 cornerRadius',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final color in const [
                  M3EFabColor.primaryFilled,
                  M3EFabColor.secondaryFilled,
                  M3EFabColor.tertiaryFilled,
                ])
                  _Cell(
                    width: 132,
                    label: color.name,
                    child: M3EFab(
                      icon: const Icon(Icons.edit),
                      color: color,
                      size: M3EFabSize.large,
                      onPressed: () {},
                    ),
                  ),
                const _Cell(
                  width: 132,
                  label: 'disabled',
                  child: M3EFab(icon: Icon(Icons.lock)),
                ),
                _Cell(
                  width: 132,
                  label: 'cornerRadius 8',
                  child: M3EFab(
                    icon: const Icon(Icons.push_pin),
                    cornerRadius: 8,
                    onPressed: () {},
                  ),
                ),
              ],
            ),
          ),
          _Block(
            title:
                'M3EExtendedFab(label:, icon:, onPressed:, size: M3EExtendedFabSize, color:, extended:, elevation:, appear:) — extended=false 收成圆',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final size in M3EExtendedFabSize.values) ...[
                  M3EExtendedFab(
                    label: 'extended ${size.name}',
                    icon: const Icon(Icons.download),
                    size: size,
                    onPressed: () {},
                  ),
                  M3EExtendedFab(
                    label: 'collapsed ${size.name}',
                    icon: const Icon(Icons.download),
                    size: size,
                    extended: false,
                    color: M3EFabColor.tertiary,
                    onPressed: () {},
                  ),
                ],
                const M3EExtendedFab(
                  label: 'disabled',
                  icon: Icon(Icons.lock),
                  size: M3EExtendedFabSize.medium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'b8-m3e-fabs-dark');
  });

  testWidgets('B9 M3EProgressIndicator：circular / linear × 定/不定 × wavy', (
    tester,
  ) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 940),
      child: _Blocks(
        blocks: [
          _Block(
            title:
                'M3EProgressIndicator.circular(value:, size:, strokeWidth:, trackStrokeWidth:, color:, trackColor:, showTrack:) — value=null 即不定进度',
            child: Wrap(
              spacing: 14,
              runSpacing: 10,
              children: [
                for (final value in const [.35, .8, null])
                  for (final box in const [32.0, 48.0])
                    _Cell(
                      width: 136,
                      label: 'circular ${box.toInt()} value=$value',
                      child: M3EProgressIndicator.circular(
                        value: value,
                        size: box,
                      ),
                    ),
                _Cell(
                  width: 136,
                  label: 'circular .6 showTrack=false',
                  child: M3EProgressIndicator.circular(
                    value: .6,
                    showTrack: false,
                    size: 48,
                  ),
                ),
                _Cell(
                  width: 136,
                  label: 'circular .6 粗描边',
                  child: M3EProgressIndicator.circular(
                    value: .6,
                    strokeWidth: 10,
                    trackStrokeWidth: 10,
                    size: 48,
                  ),
                ),
                _Cell(
                  width: 136,
                  label: 'circular 自定义色',
                  child: M3EProgressIndicator.circular(
                    value: .45,
                    color: const Color(0xFFB98A2E),
                    trackColor: Color(0x33B98A2E),
                    size: 48,
                  ),
                ),
              ],
            ),
          ),
          _Block(
            title:
                'M3EProgressIndicator.circularWavy(amplitude:, wavelength:, waveSpeed:, gapSize:) — 波浪圈',
            child: Wrap(
              spacing: 14,
              children: [
                for (final value in const [.25, .6, null])
                  _Cell(
                    width: 144,
                    label: 'circularWavy value=$value',
                    child: M3EProgressIndicator.circularWavy(
                      value: value,
                      size: 54,
                      amplitude: 4,
                    ),
                  ),
              ],
            ),
          ),
          _Block(
            title:
                'M3EProgressIndicator.linear(value:, linearSize:, strokeWidth:, trackStrokeWidth:, color:, trackColor:) / .linearWavy(stopSize:, wavelength:, amplitude:)',
            child: SizedBox(
              width: 1000,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final size in M3EProgressIndicatorSize.values) ...[
                    Text(
                      'linearSize = ${size.name}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    M3EProgressIndicator.linear(value: .42, linearSize: size),
                    const SizedBox(height: 8),
                    M3EProgressIndicator.linear(linearSize: size),
                    const SizedBox(height: 8),
                    M3EProgressIndicator.linearWavy(
                      value: .66,
                      linearSize: size,
                      amplitude: 5,
                    ),
                    const SizedBox(height: 8),
                    M3EProgressIndicator.linearWavy(
                      value: null,
                      linearSize: size,
                      stopSize: 3,
                      wavelength: 30,
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'b9-m3e-progress-dark');
  });

  testWidgets('B10 M3EBadge：数字 / 超上限 / 点 / 文案 / 自定义色 / offset', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 760),
      child: _Block(
        title:
            'M3EBadge(child:, count:, label:, showDot:, maxCount:, alignment: M3EBadgeAlignment(topLeft/topCenter/topRight), offset:, backgroundColor:, foregroundColor:)',
        child: Wrap(
          spacing: 26,
          runSpacing: 26,
          children: [
            for (final alignment in M3EBadgeAlignment.values)
              for (final (badge, badgeWidget) in <(String, Widget)>[
                (
                  'count',
                  M3EBadge(
                    count: 5,
                    alignment: alignment,
                    child: const Icon(Icons.mail, size: 40),
                  ),
                ),
                (
                  'count>maxCount',
                  M3EBadge(
                    count: 1287,
                    maxCount: 99,
                    alignment: alignment,
                    child: const Icon(Icons.notifications, size: 40),
                  ),
                ),
                (
                  'showDot',
                  M3EBadge(
                    showDot: true,
                    alignment: alignment,
                    child: const Icon(Icons.widgets, size: 40),
                  ),
                ),
                (
                  'label',
                  M3EBadge(
                    label: '新',
                    alignment: alignment,
                    child: const Icon(Icons.person, size: 40),
                  ),
                ),
              ])
                _Cell(
                  width: 128,
                  label: '${alignment.name} / $badge',
                  child: badgeWidget,
                ),
            _Cell(
              width: 128,
              label: '自定义配色',
              child: M3EBadge(
                count: 12,
                backgroundColor: const Color(0xFFB98A2E),
                foregroundColor: Colors.black,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.tune),
                ),
              ),
            ),
            _Cell(
              width: 128,
              label: 'offset + 宿主是 Fab',
              child: M3EBadge(
                count: 3,
                offset: const Offset(6, 6),
                child: M3EFab(icon: const Icon(Icons.add), onPressed: () {}),
              ),
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'b10-m3e-badges-dark');
  });

  // ==========================================================
  // C. 本仓的导航 / 表面 / 弹层 / 弹簧
  // ==========================================================

  testWidgets('C1 NavigationDock（lens 弹跳导航条）', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 420),
      child: _Blocks(
        blocks: [
          _Block(
            title:
                'NavigationDock(destinations: List<NavigationDockDestination>, selectedIndex:, onSelected:, trailing:) — 选中态是一颗会在目的地之间弹跳的 lens；条高 52、格子 62、图标 22',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 620,
                  height: 82,
                  child: NavigationDock(
                    destinations: const [
                      NavigationDockDestination(
                        glyph: AppGlyphs.dashboard,
                        label: '书架',
                      ),
                      NavigationDockDestination(
                        glyph: AppGlyphs.compass,
                        label: '发现',
                      ),
                      NavigationDockDestination(
                        glyph: AppGlyphs.history,
                        label: '历史',
                      ),
                      NavigationDockDestination(
                        glyph: AppGlyphs.download,
                        label: '下载',
                      ),
                      NavigationDockDestination(
                        glyph: AppGlyphs.settings,
                        label: '设置',
                      ),
                    ],
                    selectedIndex: 1,
                    onSelected: (_) {},
                    trailing: ActionIconButton(
                      glyph: AppGlyphs.add,
                      tooltip: '新建',
                      onPressed: () {},
                    ),
                  ),
                ),
                SizedBox(
                  width: 380,
                  height: 82,
                  child: NavigationDock(
                    destinations: const [
                      NavigationDockDestination(
                        glyph: AppGlyphs.chevronBack,
                        label: '返回',
                      ),
                      NavigationDockDestination(
                        glyph: AppGlyphs.home,
                        label: '主页',
                      ),
                      NavigationDockDestination(
                        glyph: AppGlyphs.search,
                        label: '搜索',
                      ),
                    ],
                    selectedIndex: 0,
                    onSelected: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'c1-navigation-dock-dark');
  });

  testWidgets('C2 SpringLensBar / SpringChoiceBar / PanelSwitcherTabs', (
    tester,
  ) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 700),
      child: _Blocks(
        blocks: [
          _Block(
            title:
                'SpringLensBar(tabs: List<SpringLensTab>, selectedIndex:, onSelected:, axis:, tabSizes:, draggable:, lensColor:, lensCorner:, tintColor:, padding:) + SpringChoiceBar<T>(options:, value:, onChanged:)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 520,
                  height: 52,
                  child: SpringLensBar(
                    tabs: const [
                      SpringLensTab(
                        child: Icon(Icons.format_list_bulleted),
                        semanticLabel: '列表',
                      ),
                      SpringLensTab(
                        child: Icon(Icons.grid_view),
                        semanticLabel: '网格',
                      ),
                      SpringLensTab(
                        child: Icon(Icons.view_agenda),
                        semanticLabel: '瀑布',
                      ),
                      SpringLensTab(
                        child: Icon(Icons.expand),
                        semanticLabel: '展开',
                      ),
                    ],
                    selectedIndex: 1,
                    onSelected: (_) {},
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: 480,
                  child: SpringChoiceBar<String>(
                    options: const [
                      (value: 'title', label: '标题'),
                      (value: 'author', label: '作者'),
                      (value: 'time', label: '更新时间'),
                      (value: 'source', label: '图源'),
                    ],
                    value: 'time',
                    onChanged: (_) {},
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 220,
                  child: SpringLensBar(
                    axis: Axis.vertical,
                    tabs: const [
                      SpringLensTab(
                        child: Icon(Icons.dashboard),
                        semanticLabel: '概览',
                      ),
                      SpringLensTab(
                        child: Icon(Icons.menu),
                        semanticLabel: '目录',
                      ),
                      SpringLensTab(
                        child: Icon(Icons.tune),
                        semanticLabel: '调节',
                      ),
                    ],
                    selectedIndex: 2,
                    onSelected: (_) {},
                  ),
                ),
              ],
            ),
          ),
          _Block(
            title:
                'PanelSwitcherTabs(items: List<PanelSwitcherItem>, selectedIndex:, onSelected:, appearance: labels|icons, axis:, iconExtent:)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 420,
                  child: PanelSwitcherTabs(
                    appearance: PanelSwitcherAppearance.labels,
                    items: const [
                      PanelSwitcherItem(label: '信息'),
                      PanelSwitcherItem(label: '控制'),
                      PanelSwitcherItem(label: '发现'),
                      PanelSwitcherItem(label: '洞察'),
                    ],
                    selectedIndex: 0,
                    onSelected: (_) {},
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: 300,
                  child: PanelSwitcherTabs(
                    appearance: PanelSwitcherAppearance.icons,
                    items: const [
                      PanelSwitcherItem(
                        label: '信息',
                        tooltip: '信息',
                        child: GlyphIcon(AppGlyphs.article, size: 20),
                      ),
                      PanelSwitcherItem(
                        label: '控制',
                        tooltip: '控制',
                        child: GlyphIcon(AppGlyphs.sliders, size: 20),
                      ),
                      PanelSwitcherItem(
                        label: '发现',
                        tooltip: '发现',
                        child: GlyphIcon(AppGlyphs.compass, size: 20),
                      ),
                    ],
                    selectedIndex: 1,
                    onSelected: (_) {},
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 150,
                  child: PanelSwitcherTabs(
                    axis: Axis.vertical,
                    items: const [
                      PanelSwitcherItem(label: '左泳道'),
                      PanelSwitcherItem(label: '中泳道'),
                      PanelSwitcherItem(label: '右泳道'),
                    ],
                    selectedIndex: 2,
                    onSelected: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'c2-lens-bars-and-tabs-dark');
  });

  testWidgets('C3 PathBreadcrumb + ControlShape / AppShape 档位', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 700),
      child: _Blocks(
        blocks: [
          _Block(
            title:
                'PathBreadcrumb(entries: List<PathCrumb>, onSelected:, overflowLabel:, style: BreadcrumbStyle, enabled:, animate:, trailing:)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'style = restrained',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
                SizedBox(
                  width: 900,
                  height: 52,
                  child: PathBreadcrumb(
                    entries: const [
                      PathCrumb(id: 'root', label: '主页', isRoot: true),
                      PathCrumb(id: 'a', label: '图书馆'),
                      PathCrumb(id: 'b', label: '月光旅行者'),
                      PathCrumb(id: 'c', label: '第 12 话', isCurrent: true),
                    ],
                    onSelected: (_) {},
                    overflowLabel: '…',
                    style: BreadcrumbStyle.restrained,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'style = expressive（+ trailing）',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
                SizedBox(
                  width: 900,
                  height: 52,
                  child: PathBreadcrumb(
                    entries: const [
                      PathCrumb(id: 'root', label: '根目录', isRoot: true),
                      PathCrumb(id: 'a', label: '下载'),
                      PathCrumb(id: 'b', label: '归档'),
                      PathCrumb(id: 'c', label: '2026-10'),
                      PathCrumb(id: 'd', label: '当前这一格', isCurrent: true),
                    ],
                    onSelected: (_) {},
                    overflowLabel: '折叠',
                    style: BreadcrumbStyle.expressive,
                    trailing: ActionIconButton(
                      glyph: AppGlyphs.refresh,
                      tooltip: '刷新',
                      onPressed: () {},
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'enabled = false（只读档）',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
                SizedBox(
                  width: 900,
                  height: 52,
                  child: PathBreadcrumb(
                    entries: const [
                      PathCrumb(id: 'r', label: '只读路径', isRoot: true),
                      PathCrumb(id: 's', label: '/library'),
                      PathCrumb(id: 't', label: '当前', isCurrent: true),
                    ],
                    enabled: false,
                    animate: false,
                    onSelected: _noopCrumb,
                    overflowLabel: '…',
                  ),
                ),
              ],
            ),
          ),
          _Block(
            title:
                'ControlShape(corner 12 / compactCorner 8 / labelCorner 14 / trackCorner 16) 与 AppShape.all(AppCorner) — RoundedSuperellipseBorder 连续曲率',
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final (label, shape) in <(String, OutlinedBorder)>[
                  ('ControlShape.rounded 12', ControlShape.rounded),
                  ('ControlShape.track 16', ControlShape.track),
                  ('ControlShape.withCorner(8)', ControlShape.withCorner(8)),
                  ('ControlShape.withCorner(14)', ControlShape.withCorner(14)),
                  ('AppShape.full（RoundedSuperellipse）', AppShape.full),
                ])
                  _Cell(
                    width: 210,
                    label: label,
                    child: SizedBox(
                      width: 190,
                      height: 40,
                      child: Material(color: _fillA, shape: shape),
                    ),
                  ),
                for (final corner in const [
                  AppCorner.xs,
                  AppCorner.sm,
                  AppCorner.md,
                  AppCorner.lg,
                  AppCorner.xl,
                  AppCorner.xxl,
                  AppCorner.full,
                ])
                  _Cell(
                    width: 128,
                    label: 'AppShape.all(${corner.toInt()})',
                    child: SizedBox(
                      width: 100,
                      height: 44,
                      child: Material(
                        color: _fillB,
                        shape: AppShape.all(corner),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'c3-breadcrumb-and-shape-tokens-dark');
  });

  testWidgets('C4 LiquidGlassSurface 厚度档 + 退化档', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 560),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LiquidGlassSurface(child:, thickness: LiquidGlassThickness, borderRadius / radius, '
              'lightAngle:, opacity:, enabled:, spec: LiquidGlassSpec, shadowScale:) — 身后必须有东西才读得出 blur',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _BackdropPainter()),
                  ),
                  Positioned(
                    left: 24,
                    top: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final thickness in LiquidGlassThickness.values)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: LiquidGlassSurface(
                              thickness: thickness,
                              radius: kDefaultPanelRadius,
                              child: SizedBox(
                                width: 430,
                                height: 46,
                                child: Center(
                                  child: Text(
                                    'thickness = ${thickness.name}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 24,
                    top: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        LiquidGlassSurface(
                          thickness: LiquidGlassThickness.thick,
                          borderRadius: BorderRadius.circular(28),
                          opacity: .82,
                          lightAngle: 210,
                          shadowScale: 1.6,
                          child: const SizedBox(
                            width: 250,
                            height: 92,
                            child: Center(
                              child: Text(
                                'borderRadius 28 / opacity .82\nlightAngle 210 / shadowScale 1.6',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, height: 1.4),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        LiquidGlassSurface(
                          enabled: false,
                          borderRadius: BorderRadius.circular(16),
                          child: const SizedBox(
                            width: 250,
                            height: 62,
                            child: Center(
                              child: Text(
                                'enabled = false（不 blur 的退化档）',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'c4-liquid-glass-dark');
  });

  testWidgets('C5 ExpressiveRayMenu（轮盘）', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 760),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ExpressiveRayMenu(rings: List<RayMenuRing>, geometry: RayMenuGeometry, style: RayMenuStyle, '
            'onSelected:, onDismiss:, centerLabel:, cancelLabel:) — 内圈/外圈各 8 格，variant = slice；'
            'RayMenuStyle 的字段全是「角色」，宿主按 ColorScheme 填',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: SizedBox(
                width: 640,
                height: 640,
                child: ExpressiveRayMenu(
                  geometry: const RayMenuGeometry(
                    radius: 290,
                    innerRadius: 68,
                    ringWidth: 100,
                    variant: RayMenuVariant.slice,
                  ),
                  style: const RayMenuStyle(
                    surface: Color(0xF222252D),
                    segment: Color(0xE630343F),
                    border: Color(0x665E6575),
                    foreground: Color(0xFFF2F3F7),
                    muted: Color(0xFFADB4C3),
                    selected: Color(0xFF8B4148),
                  ),
                  centerLabel: '轮盘',
                  cancelLabel: '取消',
                  rings: [
                    RayMenuRing(
                      slotCount: 8,
                      items: const [
                        RayMenuItem(
                          id: 'next',
                          label: '下一话',
                          slot: 0,
                          icon: Icon(Icons.skip_next, size: 18),
                        ),
                        RayMenuItem(
                          id: 'fit',
                          label: '适应屏幕',
                          slot: 2,
                          icon: Icon(Icons.fit_screen, size: 18),
                        ),
                        RayMenuItem(
                          id: 'prev',
                          label: '上一话',
                          slot: 4,
                          icon: Icon(Icons.skip_previous, size: 18),
                        ),
                        RayMenuItem(
                          id: 'off',
                          label: '禁用格',
                          slot: 6,
                          enabled: false,
                        ),
                      ],
                    ),
                    RayMenuRing(
                      slotCount: 8,
                      items: const [
                        RayMenuItem(
                          id: 'up',
                          label: '上滚',
                          slot: 0,
                          icon: Icon(Icons.arrow_upward, size: 16),
                        ),
                        RayMenuItem(
                          id: 'down',
                          label: '下滚',
                          slot: 1,
                          icon: Icon(Icons.arrow_downward, size: 16),
                        ),
                        RayMenuItem(
                          id: 'zoom',
                          label: '放大',
                          slot: 3,
                          icon: Icon(Icons.zoom_in, size: 16),
                        ),
                        RayMenuItem(
                          id: 'crop',
                          label: '裁切',
                          slot: 5,
                          icon: Icon(Icons.crop_free, size: 16),
                        ),
                        RayMenuItem(
                          id: 'lock',
                          label: '锁',
                          slot: 7,
                          icon: Icon(Icons.lock, size: 16),
                        ),
                      ],
                    ),
                  ],
                  onSelected: (_) {},
                  onDismiss: () {},
                ),
              ),
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'c5-ray-menu-dark');
  });

  testWidgets('C6 CollapsibleCard（expressive 档）', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 1020),
      child: _Blocks(
        blocks: [
          _Block(
            title:
                'CollapsibleCard(cardId:, title:, icon:, isExpanded:, onToggle:, trailing:, child:, expressive:, headerless:, collapsedChild:, scrollContent:, margin:, contentPadding:, onMoveUp:, onMoveDown:, onHide:, disabledHint:)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final expanded in const [true, false])
                  SizedBox(
                    width: 920,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: CollapsibleCard(
                        cardId: 'census-${expanded ? 'open' : 'closed'}',
                        title: expanded
                            ? 'expressive = true · 展开'
                            : 'expressive = true · 折叠（读回 collapsedChild）',
                        icon: AppGlyphs.equalizer,
                        isExpanded: expanded,
                        expressive: true,
                        onToggle: () {},
                        collapsedChild: expanded
                            ? null
                            : const Text(
                                '折叠时读回来的一行摘要',
                                style: TextStyle(fontSize: 12),
                              ),
                        onMoveUp: () {},
                        onMoveDown: () {},
                        onHide: () {},
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ExpressiveStatTile(
                              value: '48 / 120',
                              label: '今日页数',
                              icon: AppGlyphs.book,
                              gauge: .4,
                            ),
                            SizedBox(height: 8),
                            ExpressiveToggleTile(
                              title: '自动追更',
                              icon: AppGlyphs.sync,
                              value: true,
                              onChanged: _noopBool,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                SizedBox(
                  width: 920,
                  child: CollapsibleCard(
                    cardId: 'census-headerless',
                    title: 'headerless = true（没有卡头，整块是内容）',
                    icon: AppGlyphs.photos,
                    isExpanded: true,
                    expressive: true,
                    headerless: true,
                    onToggle: () {},
                    child: const SizedBox(
                      height: 64,
                      child: Center(
                        child: Text('headerless 档由外层卡片统一提供材质，卡头不再重复长一条栏'),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 920,
                  child: CollapsibleCard(
                    cardId: 'census-disabled',
                    title: 'disabledHint：这一格当前不可用',
                    icon: AppGlyphs.block,
                    isExpanded: true,
                    expressive: true,
                    disabledHint: '要先打开一本书',
                    onToggle: () {},
                    child: const SizedBox(
                      height: 40,
                      child: Center(child: Text('带 disabledHint 的一档')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'c6-collapsible-card-dark');
  });

  testWidgets('C7 ShelfListRail / ShelfListChip / ShelfListToolbar', (
    tester,
  ) async {
    final boundary = GlobalKey();
    final controller = TextEditingController(text: '月光');
    addTearDown(controller.dispose);
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 620),
      child: _Blocks(
        blocks: [
          _Block(
            title:
                'ShelfListRail(children:, onCreate:, onEdit:) + ShelfListChip(label:, selected:, onTap:, identity:) — 轮廓由 ExpressiveBlob 按 identity 生成，选中档收成 stadium',
            child: ShelfListRail(
              onCreate: () {},
              onEdit: () {},
              children: [
                for (final (index, name) in const [
                  '全部',
                  '未分类',
                  '阅读计划',
                  '深夜',
                  '月光旅行者',
                  '星河之间',
                ].indexed)
                  ShelfListChip(
                    label: name,
                    identity: '/$name',
                    selected: index == 4,
                    onTap: () {},
                  ),
              ],
            ),
          ),
          _Block(
            title:
                'ShelfListToolbar(viewMode:, onViewMode:, sort:, onSort:, searchController:, onKeywordChanged:, count:, onExport:, onImport:, portLabel:, timelineOn:, busy:) — 一长条工具槽',
            child: SizedBox(
              width: 1080,
              child: ShelfListToolbar(
                viewMode: LibraryViewMode.coverList,
                onViewMode: (_) {},
                sort: const ShelfSort(field: ShelfSortField.time),
                onSort: (_) {},
                searchController: controller,
                onKeywordChanged: (_) {},
                count: 52,
                onExport: () {},
                onImport: () {},
                portLabel: '历史数据',
                timelineOn: true,
                onTimeline: () {},
              ),
            ),
          ),
          _Block(
            title: 'ShelfListChip 单颗三档（rest / selected / 长名自己收平）',
            child: const Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                ShelfListChip(
                  label: '静止的一档',
                  identity: '/rest',
                  selected: false,
                  onTap: _noopVoid,
                ),
                ShelfListChip(
                  label: '选中的这一档',
                  identity: '/selected',
                  selected: true,
                  onTap: _noopVoid,
                ),
                ShelfListChip(
                  label: '名字很长的一档筛选标签会自己收平',
                  identity: '/long',
                  selected: false,
                  onTap: _noopVoid,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'c7-shelf-list-family-dark');
  });

  testWidgets(
    'C8 SectionHeader / PopupSelectField / FluentPopupMenuButton / ErrorView / ToastCard',
    (tester) async {
      final boundary = GlobalKey();
      await _pumpSheet(
        tester,
        boundary: boundary,
        size: const Size(1160, 1120),
        child: _Blocks(
          blocks: [
            _Block(
              title: 'SectionHeader(title:, subtitle:, onTap:, margin:)',
              child: SizedBox(
                width: 640,
                child: Column(
                  children: [
                    const SectionHeader(title: '没有右箭头的分节', subtitle: '副标题在右'),
                    SectionHeader(
                      title: '可以点进去的分节',
                      subtitle: '3 项',
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),
            _Block(
              title:
                  'PopupSelectField<T>(label:, value:, options:, onChanged:, glyphOf:) + popupFieldDecoration(context, label) — 填充字段外壳；FluentPopupMenuButton<T>(itemBuilder:, onSelected:, icon:, tooltip:)',
              child: SizedBox(
                width: 640,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PopupSelectField<String>(
                      label: '新页签启动于',
                      value: 'current',
                      options: const {
                        'current': '当前目录',
                        'home': '主页',
                        'parent': '上一层',
                      },
                      onChanged: (_) {},
                      glyphOf: (value) => switch (value) {
                        'current' => AppGlyphs.folder,
                        'home' => AppGlyphs.home,
                        _ => AppGlyphs.chevronBack,
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        FluentPopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          tooltip: '更多',
                          itemBuilder: (_) => const [
                            FluentPopupMenuItem(
                              value: 'a',
                              title: Text('动作 A'),
                            ),
                            FluentPopupMenuItem(
                              value: 'b',
                              title: Text('动作 B（selected）'),
                              selected: true,
                            ),
                            FluentPopupMenuItem.divider(),
                            FluentPopupMenuItem(
                              value: 'c',
                              title: Text('带 leading / trailing'),
                              leading: Icon(Icons.copy, size: 16),
                              trailing: Text('⌘C'),
                            ),
                            FluentPopupMenuItem(
                              value: 'd',
                              title: Text('这一档禁用'),
                              enabled: false,
                            ),
                          ],
                          onSelected: (_) {},
                        ),
                        const SizedBox(width: 16),
                        FluentPopupMenuButton<String>(
                          itemBuilder: (_) => const [
                            FluentPopupMenuItem(
                              value: 'x',
                              title: Text('只有 child 的一档'),
                            ),
                          ],
                          onSelected: (_) {},
                          child: const Text('FluentPopupMenuButton(child:)'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            _Block(
              title: 'ErrorView(errorMessage:, onRetry:)',
              child: SizedBox(
                width: 640,
                height: 160,
                child: ErrorView(errorMessage: '图源没有响应（示例文案）', onRetry: () {}),
              ),
            ),
            _Block(
              title:
                  'ToastCard(type: ToastType, message:, spec: ToastOverlaySpec, onDismiss:, title:) — 四种类型 + 带标题档',
              child: SizedBox(
                width: 540,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final type in ToastType.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ToastCard(
                          type: type,
                          title: type == ToastType.error ? '出了点问题' : null,
                          message: 'ToastType.${type.name} — 这是一条会被拍进图里的提示文案',
                          spec: _toastSpec,
                          onDismiss: () {},
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      await _write(tester, boundary, 'c8-misc-chrome-dark');
    },
  );

  testWidgets('C9 托盘真的飞出来：showPopupPanel(relative) 的飞行中一帧 + 落位一帧', (
    tester,
  ) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 720),
      child: Builder(
        builder: (context) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'showPopupPanel(context:, builder:, presentation: PopupPresentation.relative) — '
                '托盘沿弧线长成卡片、内容由糊变清（CommonPopupRoute）',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => showPopupPanel<void>(
                  context: context,
                  presentation: PopupPresentation.relative,
                  builder: (popupContext) => PopupPanel(
                    title: const Text('筛选'),
                    content: const SizedBox(
                      width: 320,
                      child: PopupSelectField<String>(
                        label: '排序',
                        value: 'time',
                        options: {'time': '更新时间', 'title': '标题'},
                        onChanged: _noopString,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(popupContext).pop(),
                        child: const Text('重置'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(popupContext).pop(),
                        child: const Text('应用'),
                      ),
                    ],
                  ),
                ),
                child: const Text('点我：相对弹出一张筛选面板'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('点我：相对弹出一张筛选面板'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    await _write(tester, boundary, 'c9-popup-tray-mid-flight-dark');
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'c9b-popup-tray-settled-dark');
  });

  testWidgets('C9c showPopupPanel(modal)：全屏遮罩 + 居中卡片', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 720),
      child: Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () => showPopupPanel<void>(
              context: context,
              presentation: PopupPresentation.modal,
              builder: (_) => PopupPanel(
                title: const Text('modal 档：要先看清再决定'),
                content: const Text('全屏遮罩 + 居中卡片。分量重的动作走这一条，不长得像一次随手点击。'),
                actions: [
                  TextButton(onPressed: () {}, child: const Text('取消')),
                  FilledButton(onPressed: () {}, child: const Text('确定')),
                ],
              ),
            ),
            child: const Text('点我：modal 档'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('点我：modal 档'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'c9c-popup-modal-dark');
  });

  testWidgets('C10 表达族合影（亮底）：一颗形状在四族控件上', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 1220),
      brightness: Brightness.light,
      child: _Blocks(
        blocks: [
          _Block(
            title:
                '同一档 ExpressiveButtonShape 同时落在：ExpressiveIconButton（按钮）/ ExpressiveShapeBadge（图标座）/ ExpressivePatchBackdrop（贴片底）/ _BlobChip（胶囊）',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final shape in const [
                  ExpressiveButtonShape.roundedSquare,
                  ExpressiveButtonShape.pill,
                  ExpressiveButtonShape.gem,
                  ExpressiveButtonShape.cookie4Sided,
                  ExpressiveButtonShape.sunny,
                  ExpressiveButtonShape.heart,
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 130,
                          child: Text(
                            shape.name,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        ExpressiveIconButton(
                          glyph: AppGlyphs.star,
                          tooltip: shape.name,
                          shape: shape,
                          onPressed: () {},
                        ),
                        const SizedBox(width: 10),
                        ExpressiveShapeBadge(
                          icon: AppGlyphs.star,
                          shape: shape,
                          size: 40,
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 170,
                          height: 46,
                          child: ExpressivePatchBackdrop(
                            seed: shape.index * 131,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: const Center(
                              child: Text(
                                'PatchBackdrop',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          _Block(
            title:
                'JellyHover(builder: (context, swellX, swellY) => …) 静止档 + 一屏标准 Expressive 控件（M3EButton / M3EChip / M3ESwitch / M3ESlider / M3EFab）',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                JellyHover(
                  builder: (context, swellX, swellY) => Container(
                    width: 170,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(ControlShape.corner),
                    ),
                    child: const Center(child: Text('JellyHover 内容')),
                  ),
                ),
                M3EButton(
                  onPressed: () {},
                  size: M3EButtonSize.lg,
                  shape: M3EButtonShape.square,
                  style: M3EButtonStyle.tonal,
                  label: const Text('M3EButton tonal/square/lg'),
                ),
                M3EChip(
                  label: 'M3EChip filter 选中',
                  type: M3EChipType.filter,
                  selected: true,
                  onPressed: () {},
                ),
                M3ESwitch(value: true, onChanged: (_) {}),
                SizedBox(
                  width: 240,
                  child: M3ESlider(
                    value: .55,
                    size: M3ESliderSize.l,
                    onChanged: (_) {},
                  ),
                ),
                M3EFab(icon: const Icon(Icons.add), onPressed: () {}),
              ],
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'c10-family-lineup-light');
  });

  testWidgets('B11 M3ENavigationBar / M3ENavigationRail', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 1180),
      child: _Blocks(
        blocks: [
          _Block(
            title:
                'M3ENavigationBar(destinations: M3ENavigationBarDestination…, selectedIndex:, onDestinationSelected:, labelBehavior:, iconBehavior:, layout:, size:, shapeFamily:, density:, indicatorStyle:, backgroundColor:) — 指示块会在目的地之间弹跳',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final behavior in M3ENavBarLabelBehavior.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'labelBehavior = ${behavior.name}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(
                          width: 620,
                          child: M3ENavigationBar(
                            labelBehavior: behavior,
                            selectedIndex: 1,
                            onDestinationSelected: (_) {},
                            destinations: const [
                              M3ENavigationBarDestination(
                                icon: Icon(Icons.dashboard),
                                label: '概览',
                              ),
                              M3ENavigationBarDestination(
                                icon: Icon(Icons.explore),
                                selectedIcon: Icon(Icons.explore),
                                label: '发现',
                                badgeCount: 3,
                              ),
                              M3ENavigationBarDestination(
                                icon: Icon(Icons.history),
                                label: '历史',
                              ),
                              M3ENavigationBarDestination(
                                icon: Icon(Icons.settings),
                                label: '设置',
                                badgeDot: true,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                for (final style in M3ENavBarIndicatorStyle.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SizedBox(
                      width: 620,
                      child: M3ENavigationBar(
                        indicatorStyle: style,
                        size: M3ENavBarSize.small,
                        shapeFamily: M3ENavBarShapeFamily.round,
                        selectedIndex: 2,
                        onDestinationSelected: (_) {},
                        destinations: const [
                          M3ENavigationBarDestination(
                            icon: Icon(Icons.book),
                            label: '书架',
                          ),
                          M3ENavigationBarDestination(
                            icon: Icon(Icons.download),
                            label: '下载',
                          ),
                          M3ENavigationBarDestination(
                            icon: Icon(Icons.tune),
                            label: '调节',
                          ),
                        ],
                      ),
                    ),
                  ),
                for (final layout in M3ENavBarLayout.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SizedBox(
                      width: 900,
                      child: M3ENavigationBar(
                        layout: layout,
                        alignment: M3ENavBarAlignment.start,
                        selectedIndex: 0,
                        onDestinationSelected: (_) {},
                        destinations: [
                          M3ENavigationBarDestination(
                            icon: const Icon(Icons.apps),
                            label: 'layout=${layout.name}',
                          ),
                          const M3ENavigationBarDestination(
                            icon: Icon(Icons.category),
                            label: '分类',
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _Block(
            title:
                'M3ENavigationRail(sections: M3ENavigationRailSection…, selectedIndex:, onDestinationSelected:, type:, modality:, labelBehavior:, fab:, leading:, trailing:, showDivider:)',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final type in M3ENavigationRailType.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'type = ${type.name}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(
                          width:
                              type == M3ENavigationRailType.expanded ||
                                  type == M3ENavigationRailType.alwaysExpand
                              ? 260
                              : 96,
                          height: 340,
                          child: M3ENavigationRail(
                            type: type,
                            selectedIndex: 1,
                            onDestinationSelected: (_) {},
                            fab: const M3ENavigationRailFabSlot(
                              icon: Icon(Icons.add),
                              label: '新建',
                              size: M3EFabSize.regular,
                            ),
                            sections: [
                              M3ENavigationRailSection(
                                header: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: Text('分组一'),
                                ),
                                destinations: const [
                                  M3ENavigationRailDestination(
                                    icon: Icon(Icons.dashboard),
                                    label: '概览',
                                  ),
                                  M3ENavigationRailDestination(
                                    icon: Icon(Icons.explore),
                                    label: '发现',
                                    badgeCount: 7,
                                  ),
                                  M3ENavigationRailDestination(
                                    icon: Icon(Icons.bookmark),
                                    label: '书签',
                                  ),
                                ],
                              ),
                              M3ENavigationRailSection(
                                header: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: Text('分组二'),
                                ),
                                destinations: const [
                                  M3ENavigationRailDestination(
                                    icon: Icon(Icons.settings),
                                    label: '设置',
                                    short: true,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'b11-m3e-navigation-dark');
  });

  testWidgets('B12 M3ETabs / M3EAppBar / M3EToolbar', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 860),
      child: _Blocks(
        blocks: [
          _Block(
            title:
                'M3ETabs(tabs: M3ETab…, selectedIndex:, onTabSelected:, variant: M3ETabsVariant, alignment:, scrollable:) — primary 图标在上，secondary 图标在前',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final variant in M3ETabsVariant.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'variant = ${variant.name}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(
                          width: 700,
                          child: M3ETabs(
                            variant: variant,
                            selectedIndex: 1,
                            onTabSelected: (_) {},
                            tabs: const [
                              M3ETab(label: '信息', icon: Icon(Icons.article)),
                              M3ETab(
                                label: '控制',
                                icon: Icon(Icons.tune),
                                badgeCount: 2,
                              ),
                              M3ETab(label: '发现', icon: Icon(Icons.explore)),
                              M3ETab(label: '洞察', badgeDot: true),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                for (final alignment in M3ETabsAlignment.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: SizedBox(
                      width: 700,
                      child: M3ETabs(
                        variant: M3ETabsVariant.secondary,
                        alignment: alignment,
                        selectedIndex: 0,
                        onTabSelected: (_) {},
                        tabs: [
                          M3ETab(label: '对齐 ${alignment.name}'),
                          const M3ETab(label: '第二页'),
                          const M3ETab(label: '第三页'),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _Block(
            title:
                'M3EAppBar.top(leading:, titleText:, subtitleText:, actions:, centerTitle:, shapeFamily:, density:, variant:) / M3EToolbar(leading:, titleText:, subtitleText:, size:, axis:, expanded:) — 两者都是 PreferredSizeWidget',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final shapeFamily in M3EAppBarShapeFamily.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SizedBox(
                      width: 900,
                      height: 104,
                      child: M3EAppBar.top(
                        shapeFamily: shapeFamily,
                        titleText:
                            'M3EAppBar.top · shapeFamily=${shapeFamily.name}',
                        subtitleText: '副标题：这一档是 docked 之外的顶部条',
                        leading: const Icon(Icons.menu),
                        actions: const [
                          Icon(Icons.search),
                          SizedBox(width: 8),
                          Icon(Icons.more_vert),
                        ],
                      ),
                    ),
                  ),
                SizedBox(
                  width: 900,
                  height: 104,
                  child: M3EToolbar(
                    titleText: 'M3EToolbar（横向、expanded）',
                    subtitleText: '底部停靠那一档见源码注释',
                    size: M3EToolbarSize.medium,
                    axis: Axis.horizontal,
                    expanded: true,
                    leading: const Icon(Icons.arrow_back),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'b12-m3e-tabs-and-bars-dark');
  });

  testWidgets('B13 M3ETextField / M3ESearchBar', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 1000),
      child: _Blocks(
        blocks: [
          _Block(
            title:
                'M3ETextField(controller:, label:, placeholder:, supportingText:, errorText:, leading:, trailing:, variant: M3ETextFieldVariant, obscureText:, enabled:, isRequired:, maxLines:, prefixText:, suffixText:, maxLength:, showCounter:)',
            child: SizedBox(
              width: 560,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final variant in M3ETextFieldVariant.values) ...[
                    Text(
                      'variant = ${variant.name}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    M3ETextField(
                      variant: variant,
                      label: '列表名称',
                      placeholder: '输入一个名字',
                      supportingText: '名称里不能出现斜杠',
                    ),
                    const SizedBox(height: 10),
                    M3ETextField(
                      variant: variant,
                      label: '带 leading / trailing',
                      leading: const Icon(Icons.search, size: 20),
                      trailing: const Icon(Icons.close, size: 20),
                    ),
                    const SizedBox(height: 10),
                    M3ETextField(
                      variant: variant,
                      label: 'errorText 档',
                      errorText: '这个名字已经被用了',
                    ),
                    const SizedBox(height: 10),
                    M3ETextField(
                      variant: variant,
                      label: 'enabled = false',
                      enabled: false,
                    ),
                    const SizedBox(height: 10),
                    M3ETextField(
                      variant: variant,
                      label: '多行 + 计数器',
                      maxLines: 3,
                      maxLength: 120,
                      showCounter: true,
                      isRequired: true,
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ),
          _Block(
            title:
                'M3ESearchBar(controller:, hintText:, leading:, trailing:, enabled:, backgroundColor:, side:, shape:, padding:, elevation:) — 56dp 胶囊，聚焦时会变宽',
            child: SizedBox(
              width: 620,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const M3ESearchBar(hintText: '搜索书架、历史与下载'),
                  const SizedBox(height: 12),
                  M3ESearchBar(
                    controller: TextEditingController(text: '月光'),
                    hintText: '带初值',
                    leading: const Icon(Icons.search),
                    trailing: const [Icon(Icons.close)],
                  ),
                  const SizedBox(height: 12),
                  const M3ESearchBar(
                    hintText: 'enabled = false',
                    enabled: false,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'b13-m3e-fields-and-search-dark');
  });

  testWidgets(
    'B14 M3ECard / M3EListItem / M3EDivider / M3ESnackbar / M3ELoadingIndicator',
    (tester) async {
      final boundary = GlobalKey();
      await _pumpSheet(
        tester,
        boundary: boundary,
        size: const Size(1160, 1200),
        child: _Blocks(
          blocks: [
            _Block(
              title:
                  'M3ECard(child:, variant: M3ECardVariant(elevated/filled/outlined), onPressed:, alternativeActions:, expanded:, padding:, borderRadius:, color:, border:, width:, onSwipe:, swipeAction:)',
              child: Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final variant in M3ECardVariant.values)
                    SizedBox(
                      width: 300,
                      child: M3ECard(
                        variant: variant,
                        onPressed: () {},
                        alternativeActions: (_) {},
                        child: SizedBox(
                          height: 110,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'M3ECard ${variant.name}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  '卡片体：变体之间只差底色与描边',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _Block(
              title:
                  'M3EListItem(headline:, supportingText:, overline:, trailingText:, leading:, trailing:, onTap:, selected:, enabled:, showDivider:, largeLeading:, appearance:, variant:)',
              child: SizedBox(
                width: 620,
                child: Column(
                  children: [
                    for (final (index, title) in const [
                      '常规一行',
                      '带 overline 与 supporting',
                      'largeLeading + trailing',
                      'selected',
                      'disabled',
                    ].indexed)
                      M3EListItem(
                        headline: title,
                        overline: index == 1 ? 'OVERLINE' : null,
                        supportingText: index == 1 ? '第二行说明文字' : null,
                        trailingText: index == 2 ? '12 页' : null,
                        largeLeading: index == 2,
                        leading: index == 2 ? null : const Icon(Icons.book),
                        trailing: index == 2
                            ? const Icon(Icons.chevron_right)
                            : null,
                        selected: index == 3,
                        enabled: index != 4,
                        showDivider: index > 0,
                        onTap: () {},
                      ),
                  ],
                ),
              ),
            ),
            _Block(
              title:
                  'M3EDivider(axis: M3EDividerAxis, inset: M3EDividerInset, thickness:, indent:, endIndent:, outerMargin:, color:)',
              child: SizedBox(
                width: 620,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final inset in M3EDividerInset.values) ...[
                      Text(
                        'inset = ${inset.name}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      M3EDivider(inset: inset),
                    ],
                    M3EDivider(axis: M3EDividerAxis.horizontal, thickness: 4),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 40,
                      child: Row(
                        children: const [
                          Text('竖轴'),
                          M3EDivider(axis: M3EDividerAxis.vertical),
                          Text('档'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _Block(
              title:
                  'M3ESnackbar(message:, actionLabel:, onAction:, showCloseButton:, onClose:) + M3ELoadingIndicator(variant: M3ELoadingIndicatorVariant, color:, size:, containerColor:, polygons:, morphRotationDegrees:)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: 620,
                    child: M3ESnackbar(
                      message: '已经把这 12 本移进书架',
                      actionLabel: '撤销',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: 620,
                    child: M3ESnackbar(
                      message: '带关闭按钮的一档',
                      actionLabel: '查看',
                      showCloseButton: true,
                      onAction: () {},
                      onClose: () {},
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    children: [
                      for (final variant in M3ELoadingIndicatorVariant.values)
                        _Cell(
                          width: 140,
                          label: 'M3ELoadingIndicator ${variant.name}',
                          child: M3ELoadingIndicator(
                            variant: variant,
                            size: 44,
                          ),
                        ),
                      _Cell(
                        width: 140,
                        label: '自定义多边形',
                        child: M3ELoadingIndicator(
                          size: 44,
                          color: const Color(0xFFB98A2E),
                          morphRotationDegrees: 40,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      await _write(tester, boundary, 'b14-m3e-cards-lists-misc-dark');
    },
  );

  testWidgets('B15 M3EMenu 打开态 + M3ETooltip 悬停态', (tester) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 760),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'M3EMenu.entries(anchorBuilder: (context, open) => …, entries: M3EMenuEntry…, '
              'position: M3EMenuAnchorPosition, colorStyle:, variant:, selectionMode:, selectedValue:) — '
              '菜单从锚点弹簧展开；M3ETooltip(child:, message: / richMessage:, persistent:, preferredPlacement:)',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                M3EMenu.entries(
                  anchorBuilder: (context, open) => M3EButton(
                    onPressed: open,
                    style: M3EButtonStyle.filled,
                    size: M3EButtonSize.md,
                    label: const Text('点开：动作菜单'),
                  ),
                  entries: [
                    M3EMenuEntry(
                      label: '打开',
                      leading: const Icon(Icons.open_in_new),
                      trailingText: '↵',
                      onPressed: () {},
                    ),
                    M3EMenuEntry(
                      label: '复制路径',
                      leading: const Icon(Icons.copy),
                      onPressed: () {},
                    ),
                    M3EMenuEntry(
                      label: '这一档不可用',
                      enabled: false,
                      onPressed: () {},
                    ),
                    M3EMenuEntry(
                      label: '删除',
                      leading: const Icon(Icons.delete),
                      isDestructive: true,
                      onPressed: () {},
                    ),
                  ],
                ),
                const SizedBox(width: 26),
                M3EMenu.entries(
                  position: M3EMenuAnchorPosition.bottomEnd,
                  selectionMode: M3EMenuSelectionMode.single,
                  selectedValue: 'b',
                  onSelected: (_) {},
                  anchorBuilder: (context, open) => M3EButton(
                    onPressed: open,
                    style: M3EButtonStyle.outlined,
                    size: M3EButtonSize.md,
                    label: const Text('点开：单选菜单'),
                  ),
                  entries: const [
                    M3EMenuEntry(label: 'a · 紧凑', value: 'a'),
                    M3EMenuEntry(label: 'b · 舒适', value: 'b'),
                    M3EMenuEntry(label: 'c · 宽松', value: 'c'),
                  ],
                ),
                const SizedBox(width: 26),
                M3ETooltip(
                  message: '这一档是悬停出来的提示',
                  child: M3EButton(
                    onPressed: () {},
                    style: M3EButtonStyle.tonal,
                    size: M3EButtonSize.md,
                    label: const Text('悬停我：普通 tooltip'),
                  ),
                ),
                const SizedBox(width: 18),
                M3ETooltip(
                  persistent: true,
                  richTitle: '富提示',
                  richMessage: '带标题、正文与动作的那一档（persistent 只在 rich 上支持）',
                  actions: [
                    TextButton(onPressed: () {}, child: const Text('知道了')),
                  ],
                  child: M3EButton(
                    onPressed: () {},
                    style: M3EButtonStyle.elevated,
                    size: M3EButtonSize.md,
                    label: const Text('persistent 富提示'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    // 两个菜单都点开；富提示靠 persistent 常显，普通 tooltip 靠鼠标悬停。
    // 锚点用 byType 定位：M3EButton 会把 label 重新排进自己的版式里，
    // `find.text` 在它的子树里找不到那颗 Text（实测 0 命中）。
    await tester.tap(find.byType(M3EMenu).first, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byType(M3EMenu).last, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(-400, -400));
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(M3ETooltip).first));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'b15-m3e-menu-and-tooltip-open-dark');
  });

  testWidgets('C11 AppGesturePatternBoard / ExpressiveReveal / 多选弹层', (
    tester,
  ) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 700),
      child: Builder(
        builder: (context) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AppGesturePatternBoard(onCompleted:) — 九宫手势盘（lib/widgets/gesture_lock.dart）',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              const SizedBox(
                width: 240,
                height: 240,
                child: AppGesturePatternBoard(onCompleted: _noopPattern),
              ),
              const SizedBox(height: 18),
              Text(
                'ExpressiveReveal(visible:, child:) — 左 visible=true，右 false（高度与透明度一起收）',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExpressiveReveal(
                    visible: true,
                    child: SizedBox(
                      width: 300,
                      height: 60,
                      child: M3ESearchBar(hintText: '展开出来的一行搜索'),
                    ),
                  ),
                  SizedBox(width: 20),
                  ExpressiveReveal(visible: false, child: Text('收回去了')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'c11-gesture-board-and-reveal-dark');
  });

  testWidgets('C12 showMultiChoiceListDialog（PopupPanel + CheckboxListTile）', (
    tester,
  ) async {
    final boundary = GlobalKey();
    await _pumpSheet(
      tester,
      boundary: boundary,
      size: const Size(1160, 620),
      child: Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () => showMultiChoiceListDialog(
              context,
              title: '选择要导出的图源',
              options: const [
                MultiChoiceDialogOption(label: 'Bika', value: 'bika'),
                MultiChoiceDialogOption(label: '禁漫', value: 'jm'),
                MultiChoiceDialogOption(label: '本地', value: 'local'),
              ],
              initialSelected: const {'bika'},
              useFilledConfirmButton: true,
              width: 360,
              height: 180,
            ),
            child: const Text('点我：多选弹层'),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('点我：多选弹层'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'c12-multi-choice-dialog-dark');
  });
}

// ==========================================================================
// 出图台自己的小零件（不属于被测组件）
// ==========================================================================

/// Toast 的静态 spec（外观由「设置 → 提示样式」决定，这里给一档固定的）。
const _toastSpec = ToastOverlaySpec(
  alignment: Alignment.topCenter,
  edgePadding: 16,
  duration: Duration(seconds: 3),
  maxWidth: 540,
  opacity: 1,
  maxVisible: 3,
  animationDuration: Duration(milliseconds: 300),
  liquidGlass: false,
  showProgressBar: true,
  showIcon: true,
  showClose: true,
);

void _noopSegments(Set<String> value) {}
void _noopString(String value) {}
void _noopCrumb(PathCrumb crumb) {}
void _noopPattern(List<int> cells) {}

/// 一档 `M3ESliderSize` 的五种写法（普通 / 带刻度与 label / 带图标 / 自定义厚轨 / 禁用）。
class _SliderRow extends StatelessWidget {
  const _SliderRow(this.size);
  final M3ESliderSize size;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'size=${size.name}（trackHeight ${size.trackHeight} / '
            'cornerRadius ${size.cornerRadius} / handleHeight ${size.handleHeight}）',
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
          M3ESlider(value: .34, size: size, onChanged: (_) {}),
          M3ESlider(
            value: 62,
            min: 0,
            max: 100,
            divisions: 10,
            label: '62',
            size: size,
            onChanged: (_) {},
          ),
          M3ESlider(
            value: .8,
            size: size,
            icon: const Icon(Icons.volume_up),
            iconPosition: M3ESliderIconPosition.start,
            onChanged: (_) {},
          ),
          M3ESlider(
            value: .5,
            size: size,
            trackThickness: size.trackHeight * 1.6,
            onChanged: (_) {},
          ),
          M3ESlider(value: .5, size: size, enabled: false, onChanged: null),
        ],
      ),
    );
  }
}

/// 一个控件 + 下面一行小字。
class _State extends StatelessWidget {
  const _State({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(fontSize: 9.5)),
      ],
    );
  }
}

/// 把 blob 轮廓画出来（`ExpressiveBlob.path` 的直接用法）。
class _BlobPainter extends CustomPainter {
  const _BlobPainter({
    required this.seed,
    required this.progress,
    required this.fill,
    required this.stroke,
  });
  final int seed;
  final double progress;
  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final path = ExpressiveBlob.ofSeed(
      seed,
    ).path(rect: Offset.zero & size, progress: progress, safeInset: 14);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _BlobPainter old) =>
      old.seed != seed || old.progress != progress;
}

/// 给 LiquidGlass 铺一块「身后有东西」的底（否则 blur 读不出来）。
class _BackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const colors = [
      Color(0xFF8B4148),
      Color(0xFF3C6E5A),
      Color(0xFFB98A2E),
      Color(0xFF445E8C),
    ];
    for (final (index, color) in colors.indexed) {
      final rect = Rect.fromLTWH(
        (size.width / 4) * index,
        index.isEven ? 20 : 150,
        size.width / 2.4,
        size.height / 2.6,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(40)),
        Paint()..color = color.withValues(alpha: .9),
      );
    }
    TextPainter(
        text: const TextSpan(
          text: '身后的文字与色块 —— 玻璃层 blur 的就是这些',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )
      ..layout()
      ..paint(canvas, const Offset(24, 300));
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter old) => false;
}

/// 亮档的 ExpressiveIconButton 小样（const 树里不能带闭包，所以抽一颗）。
class _IconBtnSample extends StatelessWidget {
  const _IconBtnSample({
    required this.shape,
    required this.label,
    this.active = false,
  });
  final ExpressiveButtonShape shape;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExpressiveIconButton(
            glyph: AppGlyphs.heart,
            activeGlyph: AppGlyphs.check,
            tooltip: label,
            active: active,
            shape: shape,
            onPressed: () {},
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 9.5)),
        ],
      ),
    );
  }
}

/// 装在装饰盒上的一档 blob（`ExpressiveBlobBorder` 的直接用法）。
class _BlobChip extends StatelessWidget {
  const _BlobChip({
    required this.label,
    required this.progress,
    this.selected = false,
  });
  final String label;
  final double progress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerHigh,
          shape: ExpressiveBlobBorder(
            seed: expressiveBlobSeed(label),
            progress: progress,
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Align(
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ),
      ),
    );
  }
}
