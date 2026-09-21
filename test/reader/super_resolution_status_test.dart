import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/reader/super_resolution_status.dart';

/// 顶栏那枚「当前页超分」芯片的**全部判定逻辑**。
///
/// 它只回答三件事：这一页到哪一步了、超分后是多少分辨率、开关开着没有。
/// 三件事都是**推断**（把开关、旁路、流水线打点合成一个可显示的结论），
/// 而推断最容易出的毛病是**在失败时撒谎** —— 明明画面上是原图，芯片上写着
/// 「已超分」。所以这里的判据几乎每一条都是在钉「什么时候**不许**说已超分」。
void main() {
  const applied = SuperResolutionPagePhase.applied;
  const queued = SuperResolutionPagePhase.queued;
  const disabled = SuperResolutionPagePhase.disabled;
  const originalPreview = SuperResolutionPagePhase.originalPreview;

  SuperResolutionPageStatus resolve({
    int index = 0,
    bool platformSupported = true,
    bool upscaleEnabled = true,
    bool originalPreviewEnabled = false,
    SuperResolutionPagePhase? recorded,
    Size? sourceSize,
    Size? enhancedSize,
  }) => resolveSuperResolutionStatus(
    index: index,
    platformSupported: platformSupported,
    upscaleEnabled: upscaleEnabled,
    originalPreview: originalPreviewEnabled,
    recorded: recorded,
    sourceSize: sourceSize,
    enhancedSize: enhancedSize,
  );

  group('阶段归一（优先级就是它的意义）', () {
    test('平台没有这条路时，别的都无从谈起', () {
      expect(
        resolve(
          platformSupported: false,
          upscaleEnabled: false,
          recorded: applied,
        ).phase,
        SuperResolutionPagePhase.unsupported,
      );
    });

    test('开关关着就不许说「已超分」—— 哪怕盘上真有产物', () {
      // 这一条是整个文件的重点：recorded 是流水线留下的历史（上一轮真的换上了），
      // 但开关一关，画面就被旁路成原图了。照着 recorded 显示就是在撒谎。
      expect(resolve(upscaleEnabled: false, recorded: applied).phase, disabled);
    });

    test('原图对比优先于打点：画面上是原图就别说已超分', () {
      final status = resolve(
        originalPreviewEnabled: true,
        recorded: applied,
        sourceSize: const Size(1200, 1800),
        enhancedSize: const Size(2400, 3600),
      );
      expect(status.phase, originalPreview);
      // 但超分图多大这件事仍然是有意义的：切回去就知道。
      expect(status.enhancedSize, const Size(2400, 3600));
    });

    test('开着、也没旁路时，照抄流水线打的点', () {
      expect(resolve(recorded: queued).phase, queued);
      expect(resolve(recorded: applied).phase, applied);
    });

    test('没有任何记录就是「待超分」，不是「已超分」', () {
      expect(resolve().phase, SuperResolutionPagePhase.idle);
      expect(resolve().phase, isNot(applied));
    });

    test('下标与页码：还没推过任何一页时页码为 null', () {
      expect(resolve(index: 0).pageNumber, 1);
      expect(resolve(index: 9).pageNumber, 10);
      expect(resolve(index: -1).pageNumber, isNull);
    });
  });

  group('阶段文案', () {
    test('每个阶段都有话说（枚举穷尽，新阶段加进来会编译不过）', () {
      for (final phase in SuperResolutionPagePhase.values) {
        expect(superResolutionPhaseLabel(phase), isNotEmpty);
      }
    });

    test('关键几个字眼不能被改糊', () {
      expect(superResolutionPhaseLabel(applied), '已超分');
      expect(superResolutionPhaseLabel(disabled), '超分关');
      expect(superResolutionPhaseLabel(queued), '排队中');
      expect(
        superResolutionPhaseLabel(SuperResolutionPagePhase.skipped),
        '无需超分',
      );
      expect(
        superResolutionPhaseLabel(SuperResolutionPagePhase.failed),
        '超分失败',
      );
    });

    test('「正在跑」与「有产物」是两回事', () {
      expect(superResolutionPhaseIsBusy(queued), isTrue);
      expect(
        superResolutionPhaseIsBusy(SuperResolutionPagePhase.running),
        isTrue,
      );
      expect(superResolutionPhaseIsBusy(applied), isFalse);

      expect(superResolutionPhaseHasEnhancedResult(applied), isTrue);
      expect(
        superResolutionPhaseHasEnhancedResult(SuperResolutionPagePhase.ready),
        isTrue,
      );
      // 原图对比时产物还在（只是被旁路挡住），配色仍该走强调色。
      expect(superResolutionPhaseHasEnhancedResult(originalPreview), isTrue);
      expect(superResolutionPhaseHasEnhancedResult(disabled), isFalse);
      expect(superResolutionPhaseHasEnhancedResult(queued), isFalse);
    });
  });

  group('分辨率文字', () {
    test('量不出来就是 null —— 不编一个 0×0', () {
      expect(formatImageSize(null), isNull);
      expect(formatImageSize(const Size(2400, 3600)), '2400×3600');
      expect(formatImageSize(const Size(1200.4, 1800.6)), '1200×1801');
    });

    test('窄屏不写分辨率（硬塞会把顶栏撑爆）', () {
      final status = resolve(
        recorded: applied,
        sourceSize: const Size(1200, 1800),
        enhancedSize: const Size(2400, 3600),
      );
      expect(superResolutionSizeText(status, 420), isNull);
      expect(
        superResolutionSizeText(status, superResolutionSizeMinWidth - 1),
        isNull,
      );
    });

    test('中等宽度只报超分后的尺寸 —— 问的就是它', () {
      final status = resolve(
        recorded: applied,
        sourceSize: const Size(1200, 1800),
        enhancedSize: const Size(2400, 3600),
      );
      expect(superResolutionSizeText(status, 800), '2400×3600');
    });

    test('够宽才写「原图 → 超分后」', () {
      final status = resolve(
        recorded: applied,
        sourceSize: const Size(1200, 1800),
        enhancedSize: const Size(2400, 3600),
      );
      expect(
        superResolutionSizeText(status, superResolutionDeltaMinWidth),
        '1200×1800 → 2400×3600',
      );
      expect(
        superResolutionSizeText(status, superResolutionDeltaMinWidth - 1),
        '2400×3600',
      );
    });

    test('还没有超分产物时报原图尺寸（「无需超分 1200×1800」要说得圆）', () {
      final status = resolve(
        recorded: SuperResolutionPagePhase.skipped,
        sourceSize: const Size(1200, 1800),
      );
      expect(superResolutionSizeText(status, 800), '1200×1800');
    });

    test('两边都不知道就没有文字，也不报空串', () {
      expect(superResolutionSizeText(resolve(recorded: queued), 1000), isNull);
    });
  });

  group('tooltip 是窄屏唯一的出口', () {
    test('带页码与两个尺寸', () {
      final text = superResolutionTooltip(
        resolve(
          index: 4,
          recorded: applied,
          sourceSize: const Size(1200, 1800),
          enhancedSize: const Size(2400, 3600),
        ),
      );
      expect(text, contains('第 5 页'));
      expect(text, contains('1200×1800'));
      expect(text, contains('2400×3600'));
      // 这一句得说清楚「点它会发生什么」，不然点主体是干什么的没人知道。
      expect(text, contains('对比原图'));
    });

    test('尺寸未知时不出现空括号', () {
      final text = superResolutionTooltip(resolve(recorded: queued));
      expect(text, contains('排队'));
      expect(text, isNot(contains('（）')));
      expect(text, isNot(contains('null')));
    });

    test('关着的时候说清开关在哪（这是从前最缺的一句话）', () {
      final text = superResolutionTooltip(resolve(upscaleEnabled: false));
      expect(text, contains('开关'));
    });

    test('每个阶段都能生成一句完整的话', () {
      for (final phase in SuperResolutionPagePhase.values) {
        final text = superResolutionTooltip(
          resolve(recorded: phase, upscaleEnabled: true),
        );
        expect(text, isNotEmpty);
        expect(text, isNot(contains('null')));
      }
    });
  });
}
