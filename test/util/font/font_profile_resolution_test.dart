import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/util/font/font_profile.dart';

void main() {
  group('nearestConfiguredWeight', () {
    test('没有任何候选时返回 null', () {
      expect(nearestConfiguredWeight(400, const <int>[]), isNull);
    });

    test('精确命中', () {
      expect(nearestConfiguredWeight(500, const [300, 400, 500, 700]), 500);
    });

    test('向上就近（霞鹜文楷 Light/Regular/Medium 场景）', () {
      // 只有 300/400/500 时，请求 600 应取 500，而不是回落 400。
      expect(nearestConfiguredWeight(600, const [300, 400, 500]), 500);
      expect(nearestConfiguredWeight(700, const [300, 400, 500]), 500);
    });

    test('向下就近', () {
      expect(nearestConfiguredWeight(200, const [400, 700]), 400);
      expect(nearestConfiguredWeight(100, const [300]), 300);
    });

    test('同距取较小字重（倾向真字形而非模拟加粗）', () {
      // 请求 600：500 与 700 距离相等，取 500。
      expect(nearestConfiguredWeight(600, const [500, 700]), 500);
      expect(nearestConfiguredWeight(600, const [700, 500]), 500);
    });

    test('无序输入不影响结果', () {
      expect(nearestConfiguredWeight(800, const [900, 300, 700, 400]), 700);
    });
  });

  group('resolveFontFamily', () {
    const defaultFamily = 'user-font-default-1';
    const overrides = <int, String>{
      300: 'user-font-w300-1',
      400: 'user-font-w400-1',
      500: 'user-font-w500-1',
    };

    test('只配默认字体：任何字重都用默认家族', () {
      final family = resolveFontFamily(
        defaultFamily: defaultFamily,
        overrideFamilies: const {},
        weight: FontWeight.w700,
      );
      expect(family, defaultFamily);
    });

    test('weight 为 null 按 400 处理', () {
      final family = resolveFontFamily(
        defaultFamily: null,
        overrideFamilies: overrides,
        weight: null,
      );
      expect(family, overrides[400]);
    });

    test('精确命中覆盖项', () {
      final family = resolveFontFamily(
        defaultFamily: defaultFamily,
        overrideFamilies: overrides,
        weight: FontWeight.w500,
      );
      expect(family, overrides[500]);
    });

    test('未覆盖的字重取最近覆盖项，不落默认', () {
      // w700 请求：覆盖里有 500，比默认家族更贴近设计意图。
      final family = resolveFontFamily(
        defaultFamily: defaultFamily,
        overrideFamilies: overrides,
        weight: FontWeight.w700,
      );
      expect(family, overrides[500]);
    });

    test('什么都没有时返回空串（保持原 TextStyle）', () {
      final family = resolveFontFamily(
        defaultFamily: null,
        overrideFamilies: const {},
        weight: FontWeight.w400,
      );
      expect(family, isEmpty);
    });

    test('只有默认时返回默认（引擎模拟加粗）', () {
      final family = resolveFontFamily(
        defaultFamily: defaultFamily,
        overrideFamilies: const {},
        weight: FontWeight.w900,
      );
      expect(family, defaultFamily);
    });
  });
}
