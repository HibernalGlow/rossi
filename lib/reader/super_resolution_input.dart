import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:zephyr/reader/page_source.dart';

/// 常见编码直接送入超分；JXL/AVIF 等使用阅读器已有的原生解码器。
String superResolutionInputExtension(PageSource source, int index) {
  final extension = index < source.pages.length
      ? p.extension(source.pages[index].name).toLowerCase()
      : '';
  return const {'.png', '.jpg', '.jpeg', '.webp'}.contains(extension)
      ? extension
      : '.png';
}

bool requiresSuperResolutionDecode(PageSource source, int index) {
  if (index >= source.pages.length) return false;
  return !const {
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
  }.contains(p.extension(source.pages[index].name).toLowerCase());
}

Future<void> writeSuperResolutionInput(
  PageSource source,
  int index,
  File destination,
) async {
  Uint8List? bytes;
  if (requiresSuperResolutionDecode(source, index)) {
    final result = await source.load(index, intent: PageLoadIntent.prefetch);
    if (result is! PageLoaded || result.content is! RasterPageContent) {
      throw StateError('无法解码第 ${index + 1} 页的超分输入');
    }
    bytes = await compute(_encodePng, result.content as RasterPageContent);
  } else {
    bytes = await source.getPageBytes(index);
  }
  if (bytes == null || bytes.isEmpty) throw StateError('超分输入为空');
  await destination.writeAsBytes(bytes, flush: true);
}

Uint8List _encodePng(RasterPageContent raster) => image.encodePng(
  image.Image.fromBytes(
    width: raster.width,
    height: raster.height,
    bytes: raster.rgba.buffer,
    bytesOffset: raster.rgba.offsetInBytes,
    numChannels: 4,
  ),
  level: 1,
);
