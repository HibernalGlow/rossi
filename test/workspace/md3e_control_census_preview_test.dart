// MD3 Expressive **控件普查**出图（形状目录那份在
// `md3e_shape_census_preview_test.dart`）。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     ROSSI_UI_PREVIEW_DIR=<目录> \
//     flutter test --no-pub -j1 test/workspace/md3e_control_census_preview_test.dart
//
// 出图机制与主题配方沿用仓里既有的预览用例。构造参数一律照抄仓内真实调用点，
// 拿不准的控件不出图 —— 一张画错的图比缺一张图更坏。
//
// ignore_for_file: avoid_print, deprecated_member_use
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/expressive/expressive_blob.dart';
import 'package:zephyr/widgets/expressive/expressive_shape.dart';
import 'package:zephyr/widgets/glass/liquid_glass.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/section_header.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_bar.dart';
import 'package:zephyr/workspace/widgets/cards/expressive_widgets.dart';

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

ColorScheme _schemeOf(Brightness b) =>
    ColorScheme.fromSeed(seedColor: _seed, brightness: b);

Future<void> _pumpSheet(
  WidgetTester tester, {
  required GlobalKey boundary,
  required Size size,
  required Brightness brightness,
  required Widget child,
}) async {
  final scheme = _schemeOf(brightness);
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

Widget _h(String title, ColorScheme scheme) => Padding(
  padding: const EdgeInsets.only(top: 18, bottom: 10),
  child: Align(
    alignment: Alignment.centerLeft,
    child: Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: scheme.primary,
      ),
    ),
  ),
);

String _suffix(Brightness b) => b == Brightness.dark ? 'dark' : 'light';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadCjk);

  final boundary = GlobalKey();

  testWidgets('出图：M3E 按钮族 / 开关 / 勾选 / chip / FAB', (tester) async {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      final scheme = _schemeOf(brightness);
      await _pumpSheet(
        tester,
        boundary: boundary,
        size: const Size(880, 980),
        brightness: brightness,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _h(
              'M3EButton · 五种样式（filled / tonal / outlined / elevated / text）+ 禁用',
              scheme,
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                M3EButton(child: const Text('Filled'), onPressed: () {}),
                M3EButton(
                  child: const Text('Tonal'),
                  onPressed: () {},
                  style: M3EButtonStyle.tonal,
                ),
                M3EButton(
                  child: const Text('Outlined'),
                  onPressed: () {},
                  style: M3EButtonStyle.outlined,
                ),
                M3EButton(
                  child: const Text('Elevated'),
                  onPressed: () {},
                  style: M3EButtonStyle.elevated,
                ),
                M3EButton(
                  child: const Text('Text'),
                  onPressed: () {},
                  style: M3EButtonStyle.text,
                ),
                M3EButton(
                  icon: GlyphIcon(AppGlyphs.check, size: 18),
                  child: const Text('带图标'),
                  onPressed: () {},
                ),
                M3EButton(child: const Text('禁用'), onPressed: null),
              ],
            ),
            _h('同一颗键的五档尺寸（xs / sm / md / lg / xl，高度 32→136）', scheme),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                M3EButton(
                  child: const Text('xs'),
                  onPressed: () {},
                  size: M3EButtonSize.xs,
                ),
                M3EButton(
                  child: const Text('sm'),
                  onPressed: () {},
                  size: M3EButtonSize.sm,
                ),
                M3EButton(
                  child: const Text('md'),
                  onPressed: () {},
                  size: M3EButtonSize.md,
                ),
                M3EButton(
                  child: const Text('lg'),
                  onPressed: () {},
                  size: M3EButtonSize.lg,
                ),
                M3EButton(
                  child: const Text('xl'),
                  onPressed: () {},
                  size: M3EButtonSize.xl,
                ),
              ],
            ),
            _h('方形档 shape: square（同一批样式换轮廓）', scheme),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                M3EButton(
                  child: const Text('filled'),
                  onPressed: () {},
                  shape: M3EButtonShape.square,
                ),
                M3EButton(
                  child: const Text('tonal'),
                  onPressed: () {},
                  style: M3EButtonStyle.tonal,
                  shape: M3EButtonShape.square,
                ),
                M3EButton(
                  child: const Text('outlined'),
                  onPressed: () {},
                  style: M3EButtonStyle.outlined,
                  shape: M3EButtonShape.square,
                ),
              ],
            ),
            _h('M3ESwitch（关 / 开 / 带勾 / 禁用）与 M3ECheckbox（未勾 / 已勾 / 禁用）', scheme),
            Row(
              children: [
                M3ESwitch(value: false, onChanged: (_) {}),
                const SizedBox(width: 12),
                M3ESwitch(value: true, onChanged: (_) {}),
                const SizedBox(width: 12),
                M3ESwitch(
                  value: true,
                  selectedIcon: GlyphIcon(AppGlyphs.check, size: 16),
                  onChanged: (_) {},
                ),
                const SizedBox(width: 12),
                M3ESwitch(value: false, onChanged: null),
                const SizedBox(width: 28),
                M3ECheckbox(value: false, onChanged: (_) {}),
                M3ECheckbox(value: true, onChanged: (_) {}),
                M3ECheckbox(value: true, onChanged: null),
              ],
            ),
            _h('M3EChip · 默认 / 选中 / 带前导 / 可删 / 禁用', scheme),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                M3EChip(label: 'assist', onPressed: () {}),
                M3EChip(label: 'selected', selected: true, onPressed: () {}),
                M3EChip(
                  label: 'leading',
                  leading: GlyphIcon(AppGlyphs.check, size: 16),
                  onPressed: () {},
                ),
                M3EChip(
                  label: 'deletable',
                  trailing: GlyphIcon(AppGlyphs.close, size: 16),
                  onDeleted: () {},
                ),
                const M3EChip(label: 'disabled'),
              ],
            ),
            _h('M3EFab 四档（40 / 56 / 80 / 96）+ 第三色调 + M3EExtendedFab', scheme),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                M3EFab(
                  icon: GlyphIcon(AppGlyphs.add),
                  onPressed: () {},
                  size: M3EFabSize.small,
                ),
                const SizedBox(width: 12),
                M3EFab(
                  icon: GlyphIcon(AppGlyphs.add),
                  onPressed: () {},
                  size: M3EFabSize.regular,
                ),
                const SizedBox(width: 12),
                M3EFab(
                  icon: GlyphIcon(AppGlyphs.add),
                  onPressed: () {},
                  size: M3EFabSize.medium,
                ),
                const SizedBox(width: 12),
                M3EFab(
                  icon: GlyphIcon(AppGlyphs.add),
                  onPressed: () {},
                  size: M3EFabSize.large,
                  color: M3EFabColor.tertiary,
                ),
                const SizedBox(width: 20),
                M3EExtendedFab(
                  label: '下载全部',
                  icon: GlyphIcon(AppGlyphs.download),
                  onPressed: () {},
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '（本张全部来自 material_3_expressive 1.1.6；配色由 material_ui 的 ColorScheme.fromSeed 派生，种子 0xff8b4148）',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      await _write(
        tester,
        boundary,
        'm3e-buttons-switches-${_suffix(brightness)}',
      );
    }
  });

  testWidgets('出图：M3E 滑杆 / 进度 / 加载 / 卡片 / 列表', (tester) async {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      final scheme = _schemeOf(brightness);
      await _pumpSheet(
        tester,
        boundary: boundary,
        size: const Size(880, 1000),
        brightness: brightness,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _h('M3ESlider · 四档粗细（xs / s / m / l）—— 厚轨 + 空心胶囊拇指', scheme),
            M3ESlider(
              value: .42,
              min: 0,
              max: 1,
              size: M3ESliderSize.xs,
              onChanged: (_) {},
            ),
            M3ESlider(
              value: .42,
              min: 0,
              max: 1,
              size: M3ESliderSize.s,
              onChanged: (_) {},
            ),
            M3ESlider(
              value: .42,
              min: 0,
              max: 1,
              size: M3ESliderSize.m,
              onChanged: (_) {},
            ),
            M3ESlider(
              value: .42,
              min: 0,
              max: 1,
              size: M3ESliderSize.l,
              onChanged: (_) {},
            ),
            _h('离散档（divisions）与禁用', scheme),
            M3ESlider(
              value: .6,
              min: 0,
              max: 1,
              divisions: 10,
              size: M3ESliderSize.xs,
              onChanged: (_) {},
            ),
            M3ESlider(
              value: .6,
              min: 0,
              max: 1,
              size: M3ESliderSize.xs,
              onChanged: null,
            ),
            _h('波浪档 M3ESlider.wavy（Rhythm 那条进度线的同款语言）', scheme),
            M3ESlider.wavy(value: .45, min: 0, max: 1, onChanged: (_) {}),
            _h('进度：线性定量 / 线性不定 / 环形 / 环形波浪 / 加载指示', scheme),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const M3EProgressIndicator.linear(value: 40),
                const SizedBox(height: 12),
                const M3EProgressIndicator.linear(),
                const SizedBox(height: 16),
                Row(
                  children: const [
                    M3EProgressIndicator.circular(),
                    SizedBox(width: 24),
                    M3EProgressIndicator.circularWavy(),
                    SizedBox(width: 24),
                    M3ELoadingIndicator(),
                  ],
                ),
              ],
            ),
            _h('M3ECard · 各档 variant', scheme),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final variant in M3ECardVariant.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: M3ECard(
                      variant: variant,
                      child: SizedBox(
                        width: 190,
                        height: 92,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            variant.name,
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            _h('M3EList + M3EListItem（副标题 / 选中 / 前导图标 / 尾部开关）', scheme),
            M3EList(
              itemCount: 3,
              outerRadius: 20,
              innerRadius: 4,
              gap: 2,
              itemBuilder: (context, index) => M3EListItem(
                headline: '第 ${index + 1} 条',
                supportingText: index == 1 ? '带副标题的一条' : null,
                selected: index == 1,
                leading: GlyphIcon(AppGlyphs.dashboard, size: 20),
                trailing: index == 2
                    ? M3ESwitch(value: true, onChanged: (_) {})
                    : null,
                onTap: () {},
              ),
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      await _write(
        tester,
        boundary,
        'm3e-sliders-progress-list-${_suffix(brightness)}',
      );
    }
  });

  testWidgets('出图：M3EShapeContainer 形状目录（上游那份）', (tester) async {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      final scheme = _schemeOf(brightness);
      await _pumpSheet(
        tester,
        boundary: boundary,
        size: const Size(880, 760),
        brightness: brightness,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _h(
              'M3EShapeKind · ${M3EShapeKind.values.length} 档（material_3_expressive 自带目录）',
              scheme,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 12,
              children: [
                for (final kind in M3EShapeKind.values)
                  SizedBox(
                    width: 84,
                    child: Column(
                      children: [
                        M3EShapeContainer(
                          kind: kind,
                          width: 56,
                          height: 56,
                          color: scheme.primaryContainer,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            kind.name,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
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
      await _write(tester, boundary, 'm3e-shape-kind-${_suffix(brightness)}');
    }
  });

  testWidgets('出图：仓内 Expressive 套件（分组 / 事实条 / 统计 / 仪表 / 胶囊 / 开关行 / 空态）', (
    tester,
  ) async {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      final scheme = _schemeOf(brightness);
      await _pumpSheet(
        tester,
        boundary: boundary,
        size: const Size(880, 1080),
        brightness: brightness,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _h(
              'ExpressiveSection + ExpressiveShapeBadge + ExpressiveStatusPill',
              scheme,
            ),
            ExpressiveSection(
              title: '阅读洞察',
              icon: AppGlyphs.dashboard,
              trailing: const ExpressiveStatusPill(text: '已同步'),
              children: const [
                ExpressiveFactTile(
                  label: '本章页数',
                  value: '24',
                  icon: AppGlyphs.picker,
                ),
                ExpressiveFactTile(
                  label: '超分耗时',
                  value: '1.8 s',
                  icon: AppGlyphs.clock,
                ),
                ExpressiveFactTile(
                  label: '失败',
                  value: '0',
                  icon: AppGlyphs.logs,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _h('ExpressiveStatTile + ExpressiveGauge（读数与仪表）', scheme),
            const Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ExpressiveStatTile(
                  value: '1 284',
                  label: '在读书架',
                  icon: AppGlyphs.resources,
                ),
                ExpressiveStatTile(
                  value: '76%',
                  label: '缓存命中',
                  icon: AppGlyphs.bolt,
                  gauge: .76,
                ),
                ExpressiveStatTile(
                  value: '—',
                  label: '编码大小',
                  icon: AppGlyphs.target,
                ),
                ExpressiveGauge(value: .34),
              ],
            ),
            const SizedBox(height: 16),
            _h('ExpressiveTile + ExpressiveIconBadge（异形底）', scheme),
            ExpressiveTile(
              onTap: () {},
              child: Row(
                children: [
                  const ExpressiveIconBadge(
                    icon: AppGlyphs.connections,
                    sided: M3EShapeKind.cookie6Sided,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('缩略图缓存', style: TextStyle(fontSize: 14)),
                  ),
                  M3ESwitch(value: true, onChanged: (_) {}),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ExpressiveToggleTile(
              title: '边看边下载',
              subtitle: '读完一章再停，不额外占带宽',
              icon: AppGlyphs.download,
              value: true,
              onChanged: (_) {},
              shape: ExpressiveButtonShape.cookie4Sided,
            ),
            const SizedBox(height: 16),
            _h('ExpressiveHeroBanner（种子决定轮廓）与 ExpressiveEmptyState', scheme),
            ExpressiveHeroBanner(
              seed: 7,
              icon: AppGlyphs.star,
              title: '本周读了 12 话',
              subtitle: '比上周多 3 话',
            ),
            const SizedBox(height: 12),
            const ExpressiveEmptyState(
              icon: AppGlyphs.proxies,
              text: '还没有下载任务',
              hint: '在书详情里选章节，长按可以一次选一片',
            ),
            const SizedBox(height: 16),
            _h('SectionHeader（仓里那份分组标题，和上面 ExpressiveSection 是一对）', scheme),
            const SectionHeader(title: '下载', subtitle: '队列与并发'),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      await _write(
        tester,
        boundary,
        'rossi-expressive-kit-${_suffix(brightness)}',
      );
    }
  });

  testWidgets('出图：弹簧透镜条 / 液态玻璃 / 异形团块描边 / 弹层面板', (tester) async {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      final scheme = _schemeOf(brightness);
      await _pumpSheet(
        tester,
        boundary: boundary,
        size: const Size(1000, 1080),
        brightness: brightness,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _h('SpringLensBar（选中项被"透镜"鼓起）', scheme),
            SpringLensBar(
              selectedIndex: 1,
              onSelected: (_) {},
              tabs: const [
                SpringLensTab(child: Text('书架')),
                SpringLensTab(child: Text('发现')),
                SpringLensTab(child: Text('下载')),
                SpringLensTab(child: Text('设置')),
              ],
            ),
            const SizedBox(height: 20),
            _h(
              'LiquidGlassSurface · thin / regular / thick（压在渐变底上才看得出折射）',
              scheme,
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final thickness in LiquidGlassThickness.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Container(
                      width: 220,
                      height: 150,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            scheme.primary,
                            scheme.tertiary,
                            scheme.secondary,
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: LiquidGlassSurface(
                          thickness: thickness,
                          child: Center(
                            child: Text(
                              thickness.name,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _h('ExpressiveBlobBorder · 同种子三档进度（0 / .5 / 1）× 四个种子', scheme),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final seed in [1, 23, 404, 9999])
                  for (final progress in [0.0, .5, 1.0])
                    Container(
                      width: 62,
                      height: 62,
                      decoration: ShapeDecoration(
                        color: scheme.secondaryContainer,
                        shape: ExpressiveBlobBorder(
                          seed: seed,
                          progress: progress,
                          side: BorderSide(color: scheme.outline, width: 1.5),
                        ),
                      ),
                    ),
              ],
            ),
            const SizedBox(height: 20),
            _h('PopupPanel（标题 / 正文 / 动作行）', scheme),
            PopupPanel(
              title: const Text('批量下载'),
              content: const Text('共 12 话，按队列并发数依次拉取。'),
              actions: [
                TextButton(onPressed: () {}, child: const Text('取消')),
                M3EButton(
                  child: const Text('开始'),
                  onPressed: () {},
                  size: M3EButtonSize.xs,
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
        'rossi-lens-glass-blob-popup-${_suffix(brightness)}',
      );
    }
  });
}
