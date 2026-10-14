import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// mImageViewer 检测器的薄适配：容差交给上游，安全参数只扩大其内容区。
@immutable
class AutoTrimOptions {
  const AutoTrimOptions({
    this.tolerance = 24,
    this.maxCropPercent = 20,
    this.safetyMarginPermille = 6,
  });

  final int tolerance;
  final int maxCropPercent;
  final int safetyMarginPermille;
  String get cacheKey => '$tolerance:$maxCropPercent:$safetyMarginPermille';

  AutoTrimOptions copyWith({
    int? tolerance,
    int? maxCropPercent,
    int? safetyMarginPermille,
  }) => AutoTrimOptions(
    tolerance: (tolerance ?? this.tolerance).clamp(0, 64),
    maxCropPercent: (maxCropPercent ?? this.maxCropPercent).clamp(0, 20),
    safetyMarginPermille: (safetyMarginPermille ?? this.safetyMarginPermille)
        .clamp(6, 40),
  );

  /// 上游已经保留 0.6%；额外留边与裁切上限均不能放大上游裁切范围。
  Rect? protect(Rect? detected) {
    if (detected == null || maxCropPercent == 0) return null;
    if (!detected.left.isFinite ||
        !detected.top.isFinite ||
        !detected.right.isFinite ||
        !detected.bottom.isFinite ||
        detected.left < 0 ||
        detected.top < 0 ||
        detected.right > 1 ||
        detected.bottom > 1 ||
        detected.isEmpty) {
      return null;
    }
    final extra = (safetyMarginPermille.clamp(6, 40) - 6) / 1000;
    final limit = maxCropPercent.clamp(0, 20) / 100;
    // 只把检测矩形向外扩大；降低上限会保留更多余白，不能切进内容。
    final rect = Rect.fromLTRB(
      (detected.left - extra).clamp(0.0, limit),
      (detected.top - extra).clamp(0.0, limit),
      (detected.right + extra).clamp(1 - limit, 1.0),
      (detected.bottom + extra).clamp(1 - limit, 1.0),
    );
    return rect == const Rect.fromLTWH(0, 0, 1, 1) ? null : rect;
  }
}

class AutoTrimSettings {
  AutoTrimSettings._();
  static final options = ValueNotifier(const AutoTrimOptions());
  static Future<void>? _loading;

  static Future<void> load() => _loading ??= _load();

  @visibleForTesting
  static void resetForTesting() {
    _loading = null;
    options.value = const AutoTrimOptions();
  }

  static Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    options.value = const AutoTrimOptions().copyWith(
      tolerance: prefs.getInt('auto_trim_tolerance'),
      maxCropPercent: prefs.getInt('auto_trim_max_crop_percent'),
      safetyMarginPermille: prefs.getInt('auto_trim_safety_permille'),
    );
  }

  static Future<void> save(AutoTrimOptions value) async {
    await load();
    final safe = value.copyWith();
    options.value = safe;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('auto_trim_tolerance', safe.tolerance);
    await prefs.setInt('auto_trim_max_crop_percent', safe.maxCropPercent);
    await prefs.setInt('auto_trim_safety_permille', safe.safetyMarginPermille);
  }
}
