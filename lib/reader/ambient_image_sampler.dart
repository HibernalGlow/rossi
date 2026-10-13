import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;
import 'package:zephyr/reader/ambient_palette.dart';
import 'package:zephyr/reader/reader_ambient_background.dart';

/// 在线图片没有 GPU 呈现器可读的 Rust 页缓存，因此从已经落盘的图片取样。
class ReaderAmbientImageSampler {
  ReaderAmbientImageSampler._();

  static final Map<String, ReaderAmbientPalette> _cache =
      <String, ReaderAmbientPalette>{};
  static final Set<String> _inFlight = <String>{};

  static Future<void> sampleFile(String path) async {
    final cached = _cache[path];
    if (cached != null) {
      ReaderAmbientStore.instance.publish(cached);
      return;
    }
    if (!_inFlight.add(path)) return;
    try {
      final bytes = await File(path).readAsBytes();
      final values = await compute(_samplePalette, bytes);
      if (values == null) return;
      final palette = _paletteFromValues(values);
      _cache[path] = palette;
      ReaderAmbientStore.instance.publish(palette);
    } catch (_) {
      // 取色失败时继续使用静态底色，不影响阅读。
    } finally {
      _inFlight.remove(path);
    }
  }

  static ReaderAmbientPalette _paletteFromValues(List<int> values) {
    Color color(int offset) => Color.from(
      alpha: 1,
      red: values[offset] / 255,
      green: values[offset + 1] / 255,
      blue: values[offset + 2] / 255,
    );

    List<Color> edge(int offset) => <Color>[
      for (var i = 0; i < ReaderAmbientPalette.stops; i++)
        color(offset + i * 3),
    ];

    final edgeLength = ReaderAmbientPalette.stops * 3;
    return ReaderAmbientPalette(
      average: color(0),
      top: edge(3),
      right: edge(3 + edgeLength),
      bottom: edge(3 + edgeLength * 2),
      left: edge(3 + edgeLength * 3),
    );
  }
}

/// 返回 average + 四条边的 RGB 值；null 表示无法解码。
List<int>? _samplePalette(Uint8List bytes) {
  final decoded = image.decodeImage(bytes);
  if (decoded == null || decoded.width < 1 || decoded.height < 1) {
    return null;
  }
  final sampled = decoded.width > 160
      ? image.copyResize(decoded, width: 160)
      : decoded;
  final lastX = sampled.width - 1;
  final lastY = sampled.height - 1;
  int coordinate(int length, int index) =>
      length * index ~/ (ReaderAmbientPalette.stops - 1);
  final edges = <List<image.Pixel>>[
    [
      for (var i = 0; i < ReaderAmbientPalette.stops; i++)
        sampled.getPixel(coordinate(lastX, i), 0),
    ],
    [
      for (var i = 0; i < ReaderAmbientPalette.stops; i++)
        sampled.getPixel(lastX, coordinate(lastY, i)),
    ],
    [
      for (var i = 0; i < ReaderAmbientPalette.stops; i++)
        sampled.getPixel(coordinate(lastX, i), lastY),
    ],
    [
      for (var i = 0; i < ReaderAmbientPalette.stops; i++)
        sampled.getPixel(0, coordinate(lastY, i)),
    ],
  ];
  final all = edges.expand((edge) => edge).toList();
  int average(int Function(image.Pixel pixel) channel) =>
      all.map(channel).reduce((a, b) => a + b) ~/ all.length;
  final values = <int>[
    average((pixel) => pixel.r.toInt()),
    average((pixel) => pixel.g.toInt()),
    average((pixel) => pixel.b.toInt()),
  ];
  for (final edge in edges) {
    for (final pixel in edge) {
      values
        ..add(pixel.r.toInt())
        ..add(pixel.g.toInt())
        ..add(pixel.b.toInt());
    }
  }
  return values;
}
