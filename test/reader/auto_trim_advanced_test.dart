import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/reader/auto_trim_settings.dart';
import 'package:zephyr/reader/page_trim_layout.dart';
import 'package:zephyr/page/comic_read/model/page_trim.dart';

void main() {
  test('default options preserve upstream result and safety bounds', () {
    const options = AutoTrimOptions();
    const content = Rect.fromLTRB(.08, .12, .92, .88);
    expect(options.tolerance, 24);
    expect(options.protect(content), content);
    expect(options.protect(null), isNull);
    expect(options.copyWith(maxCropPercent: 0).protect(content), isNull);
    expect(options.copyWith(tolerance: 999).tolerance, 64);
    expect(options.copyWith(safetyMarginPermille: 0).safetyMarginPermille, 6);
  });

  test(
    'advanced limits only expand content, never cut into detected region',
    () {
      const content = Rect.fromLTRB(.19, .1, .82, .92);
      final protected = const AutoTrimOptions(
        maxCropPercent: 5,
        safetyMarginPermille: 16,
      ).protect(content)!;
      expect(protected, const Rect.fromLTRB(.05, .05, .95, .95));
      expect(protected.contains(content.topLeft), isTrue);
      expect(protected.contains(content.bottomRight), isTrue);
      expect(
        const AutoTrimOptions().protect(const Rect.fromLTRB(-.1, 0, 1, 1)),
        isNull,
      );
    },
  );

  test(
    'strip grows to content aspect ratio and keeps both vertical endpoints',
    () {
      const original = Size(800, 1200);
      const content = Rect.fromLTRB(.1, 0, .9, 1);
      const box = Size(400, 750);
      final trim = computePageTrim(
        boxSize: box,
        imageSize: original,
        contentRect: content,
      )!;
      expect(trim.scale, closeTo(1.25, 1e-9));
      // contain before crop: original is 400 x 600, centered at y=75.
      expect(75 * trim.scale + trim.dy, closeTo(0, 1e-9));
      expect(675 * trim.scale + trim.dy, closeTo(750, 1e-9));
      expect(40 * trim.scale + trim.dx, closeTo(0, 1e-9));
      expect(360 * trim.scale + trim.dx, closeTo(400, 1e-9));
    },
  );

  test('layout ignores results belonging to old parameter revision', () {
    final layout = PageTrimLayout();
    addTearDown(layout.dispose);
    var notifications = 0;
    layout.addListener(() => notifications++);
    const content = Rect.fromLTRB(.1, 0, .9, 1);
    layout.report(0, '24:20:6', content);
    layout.report(0, '24:20:6', content);
    expect(notifications, 1);
    expect(layout.rectFor(0, '24:20:6'), content);
    expect(layout.rectFor(0, '32:20:6'), isNull);
    expect(layout.rectFor(1, '24:20:6'), isNull);
  });

  test('advanced options persist their complete parameter identity', () async {
    SharedPreferences.setMockInitialValues({});
    await AutoTrimSettings.save(
      const AutoTrimOptions(
        tolerance: 30,
        maxCropPercent: 12,
        safetyMarginPermille: 16,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('auto_trim_tolerance'), 30);
    expect(prefs.getInt('auto_trim_max_crop_percent'), 12);
    expect(prefs.getInt('auto_trim_safety_permille'), 16);
    expect(AutoTrimSettings.options.value.cacheKey, '30:12:16');
    await AutoTrimSettings.save(const AutoTrimOptions());
  });
}
