import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_super_resolution.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/type/enum.dart';

/// 「超分条件」（分辨率阈值）的档位规则。
///
/// 这条规则被**两处 UI**（设置页、阅读器设置面板的下拉）和**两条执行路**共用：
/// 文件层 `RealSrSuperResolution.upscaleAndConvertToWebp` 与呈现器
/// `GpuPresentController`（`gpu_present_controller.dart` 里的 `shouldUpscale`）——
/// 二者最终都读 `RealSrSettings.loadResolutionThreshold()`。
/// 各写一遍迟早漂移，「下拉显示 1080、写回的却是 2160」那类看起来没生效的怪象
/// 就是这么来的，所以规则收在 [RealSrSettings] 里，这里把它钉住。
void main() {
  const p540 = RealSrResolutionThreshold.p540;
  const p720 = RealSrResolutionThreshold.p720;
  const p1080 = RealSrResolutionThreshold.p1080;
  const p1440 = RealSrResolutionThreshold.p1440;
  const p2160 = RealSrResolutionThreshold.p2160;

  group('可选档位', () {
    test('桌面端：全档位可选（含 1440 / 2160）', () {
      expect(
        RealSrSettings.availableThresholdsFor(isDesktop: true),
        RealSrResolutionThreshold.values,
      );
    });

    test('移动端：最高只到 1080', () {
      expect(
        RealSrSettings.availableThresholdsFor(isDesktop: false),
        const <RealSrResolutionThreshold>[p540, p720, p1080],
      );
    });
  });

  group('越界夹取（effectiveThreshold）', () {
    test('集合内的取值原样返回 —— 不许无脑改成 1080', () {
      expect(RealSrSettings.effectiveThreshold(p540, isDesktop: false), p540);
      expect(RealSrSettings.effectiveThreshold(p720, isDesktop: false), p720);
      expect(RealSrSettings.effectiveThreshold(p1080, isDesktop: false), p1080);
    });

    test('移动端越界回落 1080（与 loadResolutionThreshold 的夹取规则同源）', () {
      expect(RealSrSettings.effectiveThreshold(p1440, isDesktop: false), p1080);
      expect(RealSrSettings.effectiveThreshold(p2160, isDesktop: false), p1080);
    });

    test('桌面端 2160 不被夹掉', () {
      expect(RealSrSettings.effectiveThreshold(p2160, isDesktop: true), p2160);
      expect(RealSrSettings.effectiveThreshold(p1440, isDesktop: true), p1440);
    });
  });

  group('档位自身的性质（回落逻辑依赖它）', () {
    test('maxWidth 单调递增 —— 顺序错了「回落 available.last」就落到错的档位', () {
      final values = RealSrResolutionThreshold.values;
      for (var i = 1; i < values.length; i++) {
        expect(
          values[i].maxWidth,
          greaterThan(values[i - 1].maxWidth),
          reason: '${values[i]} 的 maxWidth 必须大于 ${values[i - 1]}',
        );
      }
    });

    test('shouldUpscale 是「宽度 < 阈值」，故阈值本身即宽度上限像素值', () {
      expect(p540.maxWidth, 540);
      expect(p720.maxWidth, 720);
      expect(p1080.maxWidth, 1080);
      expect(p1440.maxWidth, 1440);
      expect(p2160.maxWidth, 2160);
    });
  });

  group('knownSize：同一个文件别读两遍', () {
    // 呈现器的流水线要**先**拿到尺寸（顶栏要显示「超分后是多少」），再判阈值。
    // 没有这个入口，同一个文件就会被读两遍（`imageSizeOf` 会把整个文件读进来）。
    // 判据刻意给一个**不存在的路径**：真的去读它必然失败并返回 false，
    // 于是「给了尺寸就不读文件」这件事在结论里就显出来了。
    test('给了已知尺寸就不再碰文件，边界仍是「小于才超分」', () async {
      expect(
        await RealSrSuperResolution.shouldUpscale(
          '/不存在/这一页.png',
          threshold: p720,
          knownSize: const Size(600, 900),
        ),
        isTrue,
      );
      expect(
        await RealSrSuperResolution.shouldUpscale(
          '/不存在/这一页.png',
          threshold: p720,
          knownSize: const Size(720, 1080),
        ),
        isFalse,
        reason: '等于阈值不超分（宽度 < 阈值才是真）',
      );
    });

    test('量不出尺寸就不超分（不猜）', () async {
      expect(
        await RealSrSuperResolution.shouldUpscale(
          '/不存在/这一页.png',
          threshold: p720,
        ),
        isFalse,
      );
    });
  });
}
