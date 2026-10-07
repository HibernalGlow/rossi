/// 「这一页到底显示什么」那张表的验证。
///
/// 这条链以前**没有**集中的裁决：三个功能各自记账，互相只打了一个洞
/// （译文占轨 → 超分让路），所以谁都能说「我这一步成功了」，而画面上的赢家没人算过。
/// 这里的重点因此不是「能算出一个来源」，而是**几处会谎报的格子**：
/// 旁路开着还说已显示、缺擦字底却选了叠层（等于把中文画在日文上）、超分关着还报超分图。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:zephyr/reader/page_display_source.dart';
import 'package:zephyr/reader/translated_page_overlay.dart';
import 'package:zephyr/service/ocr/translated_page_display_mode.dart';

PageDisplayFacts _facts({
  bool baked = false,
  bool layer = false,
  bool base = false,
  bool sr = false,
  TranslatedPageDisplayChoice choice = TranslatedPageDisplayChoice.baked,
  bool bypass = false,
  bool upscaleEnabled = true,
}) => (
  hasBakedPage: baked,
  hasTranslationLayer: layer,
  hasOverlayBase: base,
  hasSuperResolution: sr,
  translationChoice: choice,
  bypassesEnhancedTrack: bypass,
  upscaleEnabled: upscaleEnabled,
);

const _overlay = TranslatedPageDisplayChoice.overlay;

void main() {
  group('resolvePageDisplaySource', () {
    test('什么都没有：原图', () {
      expect(resolvePageDisplaySource(_facts()), PageDisplaySource.original);
    });

    test('只有超分产物：超分图赢', () {
      expect(
        resolvePageDisplaySource(_facts(sr: true)),
        PageDisplaySource.superResolved,
      );
    });

    test('超分功能关着：有产物也不许当显示来源', () {
      expect(
        resolvePageDisplaySource(_facts(sr: true, upscaleEnabled: false)),
        PageDisplaySource.original,
        reason: '用户关掉超分之后还端出超分图，画面就不follow设置',
      );
    });

    test('旁路压倒一切：烘焙页、图层、超分全都在，画面上仍是原图', () {
      // 阳性对照。少了这一格，「只要旁路开着就返回被挡住」这种把归属忘掉的写法
      // 也能全绿；反过来这一格也把「烘焙赢过旁路」那种谎报钉住。
      expect(
        resolvePageDisplaySource(
          _facts(
            baked: true,
            layer: true,
            base: true,
            sr: true,
            choice: _overlay,
            bypass: true,
          ),
        ),
        PageDisplaySource.blockedByOriginalPreview,
      );
    });

    test('烘焙成品页占着轨：它赢，超分只能等', () {
      expect(
        resolvePageDisplaySource(
          _facts(baked: true, sr: true, choice: _overlay),
        ),
        PageDisplaySource.bakedPage,
        reason: '烘焙档占的是那一页唯一的像素，与超分互斥是现状',
      );
    });

    test('想要叠层但没有擦字底：绝不许选叠层', () {
      // 渲染台实测：译文叠在没擦字的原图上，字压字率 0.085。
      // 所以缺底图时必须回落，而不是硬叠。
      expect(
        resolvePageDisplaySource(_facts(layer: true, sr: true, choice: _overlay)),
        PageDisplaySource.superResolved,
      );
      expect(
        resolvePageDisplaySource(_facts(layer: true, choice: _overlay)),
        PageDisplaySource.original,
      );
    });

    test('想要叠层但没有图层数据：也不许选叠层', () {
      expect(
        resolvePageDisplaySource(_facts(base: true, sr: true, choice: _overlay)),
        PageDisplaySource.superResolved,
      );
    });

    test('叠层前提齐了：叠层赢，而且这一格**不否定超分**', () {
      // 「翻译迁移到超分后的图上」的落点：底图就是超分产物，译文只是盖在上面的一层。
      expect(
        resolvePageDisplaySource(
          _facts(layer: true, base: true, sr: true, choice: _overlay),
        ),
        PageDisplaySource.overlayOnBase,
      );
    });

    test('默认（烘焙）选择下，图层与底图都在也不走叠层', () {
      expect(
        resolvePageDisplaySource(_facts(layer: true, base: true, sr: true)),
        PageDisplaySource.superResolved,
        reason: '模式没切到叠层，就不该擅自改变画面',
      );
    });

    test('默认档位确实是烘焙', () {
      // 这条看着像废话，但它是上面那格的**前提**：哪天有人把 defaultChoice 改成
      // overlay 而不改底图落盘，全链路会安静地画出中日文叠在一起的页。
      expect(TranslatedPageDisplayMode.defaultChoice, TranslatedPageDisplayChoice.baked);
    });
  });

  group('叠层的落位几何', () {
    test('盒子与底图同比例：铺满、不偏移', () {
      final fit = overlayPaintFit(
        boxWidth: 800,
        boxHeight: 1200,
        baseWidth: 800,
        baseHeight: 1200,
      )!;
      expect(fit.scale, closeTo(1.0, 1e-9));
      expect(fit.offset, const Offset(0, 0));
    });

    test('底图是超分 2×：倍率就是 2，字要跟着底图放大', () {
      final fit = overlayPaintFit(
        boxWidth: 800,
        boxHeight: 1200,
        baseWidth: 400,
        baseHeight: 600,
      )!;
      expect(fit.scale, closeTo(2.0, 1e-9));
    });

    test('横长页进竖盒：按 contain 居中，上下留边而不是拉满', () {
      final fit = overlayPaintFit(
        boxWidth: 600,
        boxHeight: 1000,
        baseWidth: 1200,
        baseHeight: 800,
      )!;
      expect(fit.scale, closeTo(0.5, 1e-9));
      expect(fit.offset.dx, closeTo(0, 1e-9));
      expect(fit.offset.dy, closeTo(300, 1e-9));
      // 阳性对照：如果实现按盒子铺满，这里会是 1000/800=1.25 且 dy=0。
      expect(fit.scale, isNot(closeTo(1.25, 1e-6)));
    });

    test('尺寸不合法：返回 null（什么都不画），不猜倍率', () {
      for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
          overlayPaintFit(
            boxWidth: bad,
            boxHeight: 1000,
            baseWidth: 800,
            baseHeight: 1200,
          ),
          isNull,
          reason: 'boxWidth=$bad 时必须拒绝作画',
        );
      }
      expect(
        overlayPaintFit(
          boxWidth: 800,
          boxHeight: 1000,
          baseWidth: 0,
          baseHeight: 1200,
        ),
        isNull,
      );
    });
  });
}
