import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DenoiseChanges extends ChangeNotifier {
  void changed() => notifyListeners();
}

enum ImageEnhancementMode {
  original('原图'),
  denoise('仅 JPEG 降噪'),
  upscale('仅超分'),
  denoiseThenUpscale('先降噪再超分');

  const ImageEnhancementMode(this.label);
  final String label;

  bool get usesDenoise => this == denoise || this == denoiseThenUpscale;
  bool get usesUpscale => this == upscale || this == denoiseThenUpscale;

  static ImageEnhancementMode fromStages({
    required bool denoise,
    required bool upscale,
  }) => switch ((denoise, upscale)) {
    (false, false) => original,
    (true, false) => ImageEnhancementMode.denoise,
    (false, true) => ImageEnhancementMode.upscale,
    (true, true) => denoiseThenUpscale,
  };
}

/// JPEG 降噪单独占一档；超分仍由 RealSrBookScope 决定。
class ImageDenoiseSettings {
  ImageDenoiseSettings._();

  static const _globalKey = 'image_denoise_enabled';
  static const _booksKey = 'image_denoise_books';
  static const _revisionKey = 'image_denoise_model_revision';
  static const _maxBookOverrides = 200;
  static final _DenoiseChanges _notifier = _DenoiseChanges();
  static ChangeNotifier get changes => _notifier;

  static Future<bool> globalEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_globalKey) ?? false;

  static Future<bool> enabledFor(String? bookKey) async {
    if (bookKey != null) {
      final prefs = await SharedPreferences.getInstance();
      final override = _decode(prefs.getString(_booksKey))[bookKey];
      if (override != null) return override;
    }
    return globalEnabled();
  }

  static Map<String, bool> _decode(String? raw) {
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is bool)
            entry.key as String: entry.value as bool,
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveGlobal(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_globalKey, enabled);
    _notifier.changed();
  }

  static Future<void> saveFor(String? bookKey, bool enabled) async {
    if (bookKey == null) return saveGlobal(enabled);
    final prefs = await SharedPreferences.getInstance();
    final books = _decode(prefs.getString(_booksKey));
    if (enabled == await globalEnabled()) {
      books.remove(bookKey);
    } else {
      books.remove(bookKey);
      books[bookKey] = enabled;
    }
    while (books.length > _maxBookOverrides) {
      books.remove(books.keys.first);
    }
    await prefs.setString(_booksKey, jsonEncode(books));
    _notifier.changed();
  }

  static Future<String> cacheKey({
    required bool denoise,
    required bool upscale,
    required String upscaleKey,
  }) async {
    if (!denoise) return upscaleKey;
    final prefs = await SharedPreferences.getInstance();
    final revision = prefs.getInt(_revisionKey) ?? 0;
    final denoiseKey = 'realplksr_1x_$revision';
    return upscale ? '${denoiseKey}_then_$upscaleKey' : denoiseKey;
  }

  static Future<void> modelChanged() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_revisionKey, DateTime.now().microsecondsSinceEpoch);
    _notifier.changed();
  }
}
