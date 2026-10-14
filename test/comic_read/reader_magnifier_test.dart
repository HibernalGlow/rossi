/// 放大镜的取样几何与来源状态。
///
/// (a)(b) 两组的数字逐条抄自上游 mImageViewer 的单元测试
/// `loupe_mapping_keeps_source_scale_and_exposes_outside_background`
/// （`vendor/mimageviewer/src/ui_fullscreen.rs:66142-66175`）：那边是 egui `Rect`、
/// 这边是 `dart:ui` 的 `Rect`，但两边算的是同一把尺，所以期望值可以直接对齐。
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_read/model/reader_magnifier.dart';
import 'package:zephyr/page/comic_read/widgets/magnifier/reader_magnifier_layer.dart';
import 'package:zephyr/page/comic_read/widgets/magnifier/reader_magnifier_source.dart';

/// 上游 `assert_rect_close`（`ui_fullscreen.rs:55894-55900`）的对应物。
///
/// 那边给的容差是 `1e-3`（f32）；这边按分量比并按 `1e-6` 收 —— 不是抄来的松，
/// 而是 UV 的分母是 `(0.5+0.1)-(0.5-0.1)` 这种二进制里除不尽的数，
/// 逐分量比**精确相等**会在表示误差上翻红，而这条测试要断言的是几何关系不是舍入。
void expectRectClose(Rect actual, Rect expected, {double epsilon = 1e-6}) {
  expect(actual.left, closeTo(expected.left, epsilon));
  expect(actual.top, closeTo(expected.top, epsilon));
  expect(actual.right, closeTo(expected.right, epsilon));
  expect(actual.bottom, closeTo(expected.bottom, epsilon));
}

/// 上游 `assert_loupe_scale` 的对应物：透镜每一屏幕像素吃到多少**源像素**。
///
/// 三种落点必须给同一个数 —— 这正是那套 fraction 存在的全部理由：
/// UV 被裁进页面内之后，绘制矩形按同样比例收缩，于是贴边时是「窗口里画面贴边」，
/// 而不是「画面被偷偷多放大」。
double _sourcePixelsPerLoupePixel(
  ReaderLoupeMapping mapping,
  Size textureSize,
) {
  final horizontal =
      mapping.uvRect.width * textureSize.width / mapping.drawRect.width;
  final vertical =
      mapping.uvRect.height * textureSize.height / mapping.drawRect.height;
  return (horizontal + vertical) / 2;
}

void main() {
  const loupe = Rect.fromLTWH(20, 30, 300, 300);
  const halfUv = Offset(0.1, 0.2);
  const textureSize = Size(1000, 500);

  group('readerLoupeSampleMapping', () {
    test('(a) 居中没有裁切：uvRect 就是想要的窗口，drawRect 就是透镜本身', () {
      final mapping = readerLoupeSampleMapping(
        uvCenter: const Offset(0.5, 0.5),
        halfUv: halfUv,
        loupeRect: loupe,
      );
      expectRectClose(mapping.uvRect, const Rect.fromLTRB(0.4, 0.3, 0.6, 0.7));
      expectRectClose(mapping.drawRect, loupe);
      expect(
        _sourcePixelsPerLoupePixel(mapping, textureSize),
        closeTo(2 / 3, 1e-9),
      );
    });

    test('(b) 贴左边缘：uvRect 收进页面，drawRect 跟着收缩而不是拉伸', () {
      final mapping = readerLoupeSampleMapping(
        uvCenter: const Offset(0.0, 0.5),
        halfUv: halfUv,
        loupeRect: loupe,
      );
      // UV 被钳在 0：页面外那半格没有像素可取。
      expect(mapping.uvRect.left, 0.0);
      expectRectClose(mapping.uvRect, const Rect.fromLTRB(0.0, 0.3, 0.1, 0.7));
      // 绘制矩形因此只剩窗口右半 —— 多出来的左边留给黑底。
      expect(mapping.drawRect.left, greaterThan(loupe.left));
      expectRectClose(mapping.drawRect, const Rect.fromLTRB(170, 30, 320, 330));
      expect(
        _sourcePixelsPerLoupePixel(mapping, textureSize),
        closeTo(2 / 3, 1e-9),
      );
    });

    test('右上角同样收缩（上游 right_top 那一组数字）', () {
      final mapping = readerLoupeSampleMapping(
        uvCenter: const Offset(1.0, 0.0),
        halfUv: halfUv,
        loupeRect: loupe,
      );
      expectRectClose(mapping.drawRect, const Rect.fromLTRB(20, 180, 170, 330));
      expect(
        _sourcePixelsPerLoupePixel(mapping, textureSize),
        closeTo(2 / 3, 1e-9),
      );
    });

    test('整页比窗口还小：四周都留底（上游 small_image 那一组数字）', () {
      final mapping = readerLoupeSampleMapping(
        uvCenter: const Offset(0.5, 0.5),
        halfUv: const Offset(1.0, 1.0),
        loupeRect: loupe,
      );
      expectRectClose(mapping.uvRect, const Rect.fromLTRB(0, 0, 1, 1));
      expectRectClose(mapping.drawRect, const Rect.fromLTRB(95, 105, 245, 255));
      expect(
        _sourcePixelsPerLoupePixel(mapping, const Size(100, 100)),
        closeTo(2 / 3, 1e-9),
      );
    });
  });

  group('退化输入', () {
    test('(c) 页面尺寸退化时 halfUv 给零，不给 NaN/Infinity', () {
      for (final size in const [Size(0, 100), Size(100, 0), Size(0, 0)]) {
        expect(
          readerLoupeHalfUv(loupeSize: 220, zoomPercent: 300, displayedPageSize: size),
          Offset.zero,
        );
      }
      for (final size in const [
        Size(double.nan, 100),
        Size(100, double.nan),
        Size(double.infinity, 100),
      ]) {
        expect(
          readerLoupeHalfUv(loupeSize: 220, zoomPercent: 300, displayedPageSize: size),
          Offset.zero,
        );
      }
    });

    test('倍率为零/负也一样给零（halfUv 会被当作除数）', () {
      expect(
        readerLoupeHalfUv(loupeSize: 220, zoomPercent: 0, displayedPageSize: const Size(400, 600)),
        Offset.zero,
      );
    });
  });

  group('readerLoupeWindowRect', () {
    const viewport = Rect.fromLTWH(0, 0, 800, 600);

    test('(d) 默认右下摆', () {
      expect(
        readerLoupeWindowRect(focalGlobal: const Offset(100, 100), loupeSize: 200, viewport: viewport),
        const Rect.fromLTWH(140, 140, 200, 200),
      );
    });

    test('(d) 贴近右/下边缘时翻到对侧', () {
      final right = readerLoupeWindowRect(
        focalGlobal: const Offset(780, 300),
        loupeSize: 200,
        viewport: viewport,
      );
      expect(right.right, lessThanOrEqualTo(780));
      expect(right.left, 780 - kReaderLoupeOffset - 200);

      final bottom = readerLoupeWindowRect(
        focalGlobal: const Offset(300, 590),
        loupeSize: 200,
        viewport: viewport,
      );
      expect(bottom.bottom, lessThanOrEqualTo(590));
      expect(bottom.top, 590 - kReaderLoupeOffset - 200);
    });

    test('(d) 整个视口扫一遍：不许逃出视口', () {
      for (var x = 0.0; x <= 800; x += 25) {
        for (var y = 0.0; y <= 600; y += 25) {
          final rect = readerLoupeWindowRect(
            focalGlobal: Offset(x, y),
            loupeSize: 200,
            viewport: viewport,
          );
          expect(rect.left, greaterThanOrEqualTo(viewport.left), reason: '焦点 ($x, $y)');
          expect(rect.top, greaterThanOrEqualTo(viewport.top), reason: '焦点 ($x, $y)');
          expect(rect.right, lessThanOrEqualTo(viewport.right), reason: '焦点 ($x, $y)');
          expect(rect.bottom, lessThanOrEqualTo(viewport.bottom), reason: '焦点 ($x, $y)');
        }
      }
    });

    test('越界的边长与 NaN 会被 normalizer 收回一档', () {
      final rect = readerLoupeWindowRect(
        focalGlobal: const Offset(400, 300),
        loupeSize: 9999,
        viewport: viewport,
      );
      expect(rect.width, kReaderLoupeSizeMax);
      expect(rect.height, kReaderLoupeSizeMax);
    });
  });

  group('页面 UV → 位图 UV', () {
    test('(e) 横长页拆左半时，页面 uv 0.5 落到位图 uv 0.25', () {
      final mapped = readerLoupeBitmapUvRect(
        const Rect.fromLTRB(0.5, 0.5, 0.5, 0.5),
        const Rect.fromLTRB(0, 0, 0.5, 1),
      );
      expect(mapped.left, closeTo(0.25, 1e-12));
      expect(mapped.top, closeTo(0.5, 1e-12));
    });

    test('整页（子矩形 = 全 UV）时是恒等映射', () {
      const pageUv = Rect.fromLTRB(0.2, 0.3, 0.4, 0.6);
      expect(
        readerLoupeBitmapUvRect(pageUv, const Rect.fromLTRB(0, 0, 1, 1)),
        pageUv,
      );
    });

    test('拆右半时 0.5 落到 0.75', () {
      final mapped = readerLoupeBitmapUvRect(
        const Rect.fromLTRB(0.5, 0.5, 0.5, 0.5),
        const Rect.fromLTRB(0.5, 0, 1, 1),
      );
      expect(mapped.left, closeTo(0.75, 1e-12));
    });
  });

  group('旋转与取值范围', () {
    test('(f) 90/270 度不支持取样，0/360/-360 支持', () {
      expect(readerLoupeSupportedForRotation(90), isFalse);
      expect(readerLoupeSupportedForRotation(270), isFalse);
      expect(readerLoupeSupportedForRotation(45), isFalse);
      expect(readerLoupeSupportedForRotation(0), isTrue);
      expect(readerLoupeSupportedForRotation(360), isTrue);
      expect(readerLoupeSupportedForRotation(-360), isTrue);
    });

    test('(g) 倍率钳进区间，NaN/±Infinity 回到缺省档', () {
      expect(normalizeReaderLoupeZoomPercent(300), 300);
      expect(normalizeReaderLoupeZoomPercent(50), kReaderLoupeZoomPercentMin.toDouble());
      expect(normalizeReaderLoupeZoomPercent(1000), kReaderLoupeZoomPercentMax.toDouble());
      expect(normalizeReaderLoupeZoomPercent(double.nan), kReaderLoupeZoomPercentDefault.toDouble());
      expect(normalizeReaderLoupeZoomPercent(double.infinity), kReaderLoupeZoomPercentDefault.toDouble());
      expect(normalizeReaderLoupeZoomPercent(double.negativeInfinity), kReaderLoupeZoomPercentDefault.toDouble());
      // 先四舍五入再钳，所以小数不会留下一个非整数档。
      expect(normalizeReaderLoupeZoomPercent(314.6), 315);
    });

    test('步进一档 25%，400% 起一档翻倍，且始终落在区间内', () {
      expect(stepReaderLoupeZoomPercent(300, 1), 325);
      expect(stepReaderLoupeZoomPercent(300, -1), 275);
      expect(stepReaderLoupeZoomPercent(400, 1), 450);
      expect(stepReaderLoupeZoomPercent(800, 1), 800);
      expect(stepReaderLoupeZoomPercent(150, -1), 150);
    });

    test('边长同样钳区间并吃掉 NaN', () {
      expect(normalizeReaderLoupeSize(10), kReaderLoupeSizeMin);
      expect(normalizeReaderLoupeSize(9999), kReaderLoupeSizeMax);
      expect(normalizeReaderLoupeSize(double.nan), kReaderLoupeSizeDefault);
    });
  });

  group('取样窗口那道门', () {
    test('焦点稍微移出页面仍算「窗口里有画面」', () {
      const page = Rect.fromLTWH(100, 100, 400, 600);
      // 300% 下一边 220 的窗口，取样窗口是 220/3 ≈ 73px：往外挪 20px 还在窗口内。
      expect(
        readerLoupeFocalHasPage(pageRect: page, focal: const Offset(80, 400), loupeSize: 220, zoomPercent: 300),
        isTrue,
      );
      expect(
        readerLoupeFocalHasPage(pageRect: page, focal: const Offset(0, 400), loupeSize: 220, zoomPercent: 300),
        isFalse,
      );
    });

    test('退化的页面矩形永远判 false（不给 NaN 机会）', () {
      expect(
        readerLoupeFocalHasPage(pageRect: Rect.zero, focal: const Offset(10, 10), loupeSize: 220, zoomPercent: 300),
        isFalse,
      );
    });
  });

  group('ReaderMagnifierSource', () {
    test('(h) 同页重复报告不重解；位图没解出来之前不许声称能取样', () async {
      final source = ReaderMagnifierSource();
      addTearDown(source.dispose);
      final gate = Completer<ui.Image?>();
      var calls = 0;

      Future<ui.Image?> request() {
        calls++;
        return gate.future;
      }

      source.reportPage(
        pageIdentity: '1-0',
        globalPageRect: const Rect.fromLTWH(0, 0, 400, 600),
        bitmapUvSubRect: const Rect.fromLTRB(0, 0, 1, 1),
        requestImage: request,
        rotationDegrees: 0,
      );
      // 控件必须有回读路径：这一页还没有像素，层不许说「我能从它取样」。
      expect(source.canSample, isFalse);
      expect(source.hasImage, isFalse);

      // 在飞的并发复用同一条 future（两个入口同时 ensureImage 也只解一次）。
      final first = source.ensureImage();
      final second = source.ensureImage();
      expect(identical(first, second), isTrue);

      gate.complete(await createTestImage(width: 8, height: 8, cache: false));
      await first;
      expect(calls, 1);
      expect(source.canSample, isTrue);

      // 翻页动画/滚动每帧都会重报矩形：身份没变就不该再解一次。
      source.reportPage(
        pageIdentity: '1-0',
        globalPageRect: const Rect.fromLTWH(0, -40, 400, 600),
        bitmapUvSubRect: const Rect.fromLTRB(0, 0, 1, 1),
        requestImage: request,
        rotationDegrees: 0,
      );
      await source.ensureImage();
      expect(calls, 1);
      expect(source.canSample, isTrue);
      expect(source.globalPageRect, const Rect.fromLTWH(0, -40, 400, 600));
    });

    test('换页身份会交还旧位图；旋转页即便有像素也不能取样', () async {
      final source = ReaderMagnifierSource();
      addTearDown(source.dispose);
      var calls = 0;
      Future<ui.Image?> request() async {
        calls++;
        return createTestImage(width: 4, height: 4, cache: false);
      }

      void report(Object identity, {int rotation = 0}) {
        source.reportPage(
          pageIdentity: identity,
          globalPageRect: const Rect.fromLTWH(0, 0, 400, 600),
          bitmapUvSubRect: const Rect.fromLTRB(0, 0, 1, 1),
          requestImage: request,
          rotationDegrees: rotation,
        );
      }

      report('1-0');
      await source.ensureImage();
      expect(calls, 1);
      expect(source.canSample, isTrue);

      // 同一页转了 90°：位图还留着（同页不重解），但旋转那道门必须把它拦下 ——
      // 这条断言之所以成立，只是因为上面那行 hasImage 是真的。
      report('1-0', rotation: 90);
      expect(source.hasImage, isTrue);
      expect(source.canSample, isFalse);

      // 翻到下一页：旧的交还、新的重解。
      report('1-1');
      expect(source.hasImage, isFalse);
      await source.ensureImage();
      expect(calls, 2);
    });

    test('解不动的页不重试；clear 之后回到「没有页」', () async {
      final source = ReaderMagnifierSource();
      addTearDown(source.dispose);
      var calls = 0;
      Future<ui.Image?> failing() async {
        calls++;
        return null;
      }

      void report(Object identity) {
        source.reportPage(
          pageIdentity: identity,
          globalPageRect: const Rect.fromLTWH(0, 0, 100, 100),
          bitmapUvSubRect: const Rect.fromLTRB(0, 0, 1, 1),
          requestImage: failing,
          rotationDegrees: 0,
        );
      }

      report('2-3');
      await source.ensureImage();
      await source.ensureImage();
      expect(calls, 1, reason: '同一页解失败后，别每根悬停指针都撞一次解码');
      expect(source.canSample, isFalse);

      source.clear();
      expect(source.pageIdentity, isNull);
      expect(source.globalPageRect, isNull);
      expect(source.bitmapUvSubRect, const Rect.fromLTRB(0, 0, 1, 1));
      expect(source.canSample, isFalse);

      // 换了页身份，重新给一次机会。
      report('2-4');
      await source.ensureImage();
      expect(calls, 2);
    });
  });

  group('层的命中穿透', () {
    testWidgets('铺满阅读区的放大镜层不吃页面点击', (tester) async {
      final source = ReaderMagnifierSource();
      addTearDown(source.dispose);
      var taps = 0;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const ColoredBox(color: Color(0x01000000)),
                ),
              ),
              Positioned.fill(
                child: ReaderMagnifierLayer(
                  source: source,
                  enabled: true,
                  mode: ReaderMagnifierMode.auto,
                  zoomPercent: kReaderLoupeZoomPercentDefault,
                  sizeLogical: kReaderLoupeSizeDefault.toInt(),
                  locked: false,
                ),
              ),
            ],
          ),
        ),
      );

      await tester.tapAt(const Offset(120, 240));
      await tester.pump();
      expect(taps, 1, reason: 'Listener/MouseRegion 只是观察者，下层手势必须原样收到');
    });

    testWidgets('关掉时不留监听也不留观察层', (tester) async {
      final source = ReaderMagnifierSource();
      addTearDown(source.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              Positioned.fill(
                child: ReaderMagnifierLayer(
                  source: source,
                  enabled: false,
                  mode: ReaderMagnifierMode.auto,
                  zoomPercent: kReaderLoupeZoomPercentDefault,
                  sizeLogical: kReaderLoupeSizeDefault.toInt(),
                  locked: false,
                ),
              ),
            ],
          ),
        ),
      );

      // 关掉之后这层不该留任何观察者：按自己子树判，不判全树（测试脚手架自己
      // 也可能挂 CustomPaint/Listener，按全树判会得到无关的结论）。
      final layer = find.byType(ReaderMagnifierLayer);
      expect(find.descendant(of: layer, matching: find.byType(Listener)), findsNothing);
      expect(
        find.descendant(of: layer, matching: find.byType(MouseRegion)),
        findsNothing,
      );
      expect(
        find.descendant(of: layer, matching: find.byType(CustomPaint)),
        findsNothing,
      );
    });
  });
}
