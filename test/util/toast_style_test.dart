import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/util/toast/toast_style.dart';

/// 提示条样式解析的判据。
///
/// 这一层是**纯逻辑**（位置映射 + 区间钳制），所以判据不需要跑界面。
/// 重点在两条容易悄悄坏掉的地方：
/// 1. 设置可能来自云端同步覆盖，越界值必须夹回去，不能让滑块之外的数直接进渲染；
/// 2. 「常驻」（时长为 0）必须自动补上关闭按钮，否则那条提示根本关不掉。
void main() {
  group('九宫格位置映射', () {
    test('九个位置各自落到对应的 Alignment', () {
      const expected = <ToastPosition, Alignment>{
        ToastPosition.topLeft: Alignment.topLeft,
        ToastPosition.topCenter: Alignment.topCenter,
        ToastPosition.topRight: Alignment.topRight,
        ToastPosition.middleLeft: Alignment.centerLeft,
        ToastPosition.center: Alignment.center,
        ToastPosition.middleRight: Alignment.centerRight,
        ToastPosition.bottomLeft: Alignment.bottomLeft,
        ToastPosition.bottomCenter: Alignment.bottomCenter,
        ToastPosition.bottomRight: Alignment.bottomRight,
      };

      // 枚举漏一个就会在这里炸（`values.length` 与表长必须一致）。
      expect(expected.length, ToastPosition.values.length);
      for (final entry in expected.entries) {
        expect(
          toastAlignmentOf(entry.key),
          entry.value,
          reason: '${entry.key}',
        );
      }
    });

    test('默认设置停在右上：与改造前的行为一致', () {
      final spec = resolveToastOverlaySpec(const ToastSettingState());

      expect(spec.alignment, Alignment.topRight);
      expect(spec.duration, const Duration(milliseconds: 3000));
      expect(spec.maxWidth, 400);
      expect(spec.opacity, 1.0);
      expect(spec.maxVisible, 3);
      expect(spec.animationDuration, const Duration(milliseconds: 220));
      expect(spec.permanent, isFalse);
      expect(spec.showsCountdown, isTrue);
      expect(spec.showClose, isTrue);
    });
  });

  group('越界设置一律夹回区间', () {
    test('低于下限', () {
      final spec = resolveToastOverlaySpec(
        const ToastSettingState(
          edgePadding: -20,
          maxWidth: 10,
          opacityPercent: 5,
          maxVisible: 0,
          animationDurationMs: -100,
        ),
      );

      expect(spec.edgePadding, ToastStyleLimits.minEdgePadding.toDouble());
      expect(spec.maxWidth, ToastStyleLimits.minWidth.toDouble());
      expect(spec.opacity, ToastStyleLimits.minOpacityPercent / 100);
      expect(spec.maxVisible, ToastStyleLimits.minVisible);
      expect(
        spec.animationDuration,
        Duration(milliseconds: ToastStyleLimits.minAnimationMs),
      );
    });

    test('高于上限', () {
      final spec = resolveToastOverlaySpec(
        const ToastSettingState(
          edgePadding: 9999,
          durationMs: 99999999,
          maxWidth: 9999,
          opacityPercent: 400,
          maxVisible: 99,
          animationDurationMs: 9999,
        ),
      );

      expect(spec.edgePadding, ToastStyleLimits.maxEdgePadding.toDouble());
      expect(
        spec.duration,
        Duration(milliseconds: ToastStyleLimits.maxDurationMs),
      );
      expect(spec.maxWidth, ToastStyleLimits.maxWidth.toDouble());
      expect(spec.opacity, 1.0);
      expect(spec.maxVisible, ToastStyleLimits.maxVisible);
      expect(
        spec.animationDuration,
        Duration(milliseconds: ToastStyleLimits.maxAnimationMs),
      );
    });

    test('未越界的值原样保留', () {
      final spec = resolveToastOverlaySpec(
        const ToastSettingState(
          position: ToastPosition.bottomLeft,
          edgePadding: 24,
          durationMs: 4500,
          maxWidth: 520,
          opacityPercent: 80,
          maxVisible: 5,
          animationDurationMs: 300,
        ),
      );

      expect(spec.alignment, Alignment.bottomLeft);
      expect(spec.edgePadding, 24);
      expect(spec.duration, const Duration(milliseconds: 4500));
      expect(spec.maxWidth, 520);
      expect(spec.opacity, closeTo(0.8, 0.0001));
      expect(spec.maxVisible, 5);
      expect(spec.animationDuration, const Duration(milliseconds: 300));
      expect(spec.showsCountdown, isTrue);
    });
  });

  group('常驻语义（时长为 0）', () {
    test('常驻没有倒计时，且强制保留关闭按钮', () {
      final spec = resolveToastOverlaySpec(
        const ToastSettingState(durationMs: 0, showCloseButton: false),
      );

      expect(spec.permanent, isTrue);
      expect(spec.showsCountdown, isFalse);
      expect(spec.showClose, isTrue, reason: '常驻提示若同时没有关闭按钮，用户就再也关不掉了');
    });

    test('非永久且用户关掉关闭按钮时，确实不显示关闭按钮', () {
      final spec = resolveToastOverlaySpec(
        const ToastSettingState(durationMs: 3000, showCloseButton: false),
      );

      expect(spec.permanent, isFalse);
      expect(spec.showClose, isFalse);
    });

    test('进度条关掉时无论时长都不会画倒计时', () {
      final spec = resolveToastOverlaySpec(
        const ToastSettingState(durationMs: 3000, showProgressBar: false),
      );

      expect(spec.showsCountdown, isFalse);
    });
  });

  group('调用点显式时长覆盖', () {
    test('覆盖只动时长，其它字段保持不变', () {
      final base = resolveToastOverlaySpec(
        const ToastSettingState(
          position: ToastPosition.bottomRight,
          edgePadding: 30,
          maxWidth: 480,
          opacityPercent: 70,
          maxVisible: 2,
          animationDurationMs: 400,
          liquidGlass: true,
          showIcon: false,
        ),
      );

      final overridden = base.withDuration(const Duration(seconds: 1));

      expect(overridden.duration, const Duration(seconds: 1));
      expect(overridden.alignment, base.alignment);
      expect(overridden.edgePadding, base.edgePadding);
      expect(overridden.maxWidth, base.maxWidth);
      expect(overridden.opacity, base.opacity);
      expect(overridden.maxVisible, base.maxVisible);
      expect(overridden.animationDuration, base.animationDuration);
      expect(overridden.liquidGlass, isTrue);
      expect(overridden.showIcon, isFalse);
      expect(overridden.showClose, base.showClose);
    });

    test('覆盖成 0 秒即常驻，并补上关闭按钮', () {
      final base = resolveToastOverlaySpec(
        const ToastSettingState(showCloseButton: false),
      );
      expect(base.showClose, isFalse);

      final overridden = base.withDuration(Duration.zero);

      expect(overridden.permanent, isTrue);
      expect(overridden.showClose, isTrue);
      expect(overridden.showsCountdown, isFalse);
    });
  });
}
