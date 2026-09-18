import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';

/// 超分覆盖原路径后，同时失效解码缓存和已挂载页面的图片流。
class UpscaledImageCache {
  UpscaledImageCache._();

  static final _replacements = StreamController<String>.broadcast();

  static Stream<String> get replacements => _replacements.stream;

  /// 仅在最终文件写入完成后调用，避免阅读器解码尚未写完的图片。
  static void notifyReplaced(String path) {
    PaintingBinding.instance.imageCache.evict(FileImage(File(path)));
    _replacements.add(path);
  }
}
