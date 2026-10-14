import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

/// 与当前 ImageSizeCubit 同寿命；裁边几何不写入原始尺寸缓存或磁盘。
class PageTrimLayout extends ChangeNotifier {
  final Map<int, (String, Rect?)> _rects = {};

  Rect? rectFor(int index, String optionsKey) {
    final entry = _rects[index];
    return entry?.$1 == optionsKey ? entry?.$2 : null;
  }

  void report(int index, String optionsKey, Rect? rect) {
    if (_rects[index] == (optionsKey, rect)) return;
    _rects[index] = (optionsKey, rect);
    notifyListeners();
  }
}
