import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;
import 'package:zephyr/reader/ambient_palette.dart';
import 'package:zephyr/reader/reader_ambient_background.dart';

/// 在线图片没有 GPU 呈现器可读的 Rust 页缓存，因此从已经落盘的图片取样。
class ReaderAmbientImageSampler {
  ReaderAmbientImageSampler._();

  /// 取样结果缓存的条数上限。
  ///
  /// 一次阅读会话会走过几百页，不设上限就是一份只增不减的常驻内存，
  /// 在手机上是额外的 GC 压力 —— 而 GC 停顿正是「翻页卡一下」的一部分。
  /// 命中只在「回到已看过的页」时省一次解码，几十条足够覆盖回看窗口。
  static const int _maxCacheEntries = 48;

  static final Map<String, ReaderAmbientPalette> _cache =
      <String, ReaderAmbientPalette>{};
  static final Set<String> _inFlight = <String>{};

  /// 排队中的请求（不含正在跑的那一个）。
  ///
  /// 章节边界那几帧会有大量页同时落盘/解析，全都直接 `compute`
  /// 等于一次性开出十几个 isolate 去解全尺寸图，跟用户正在看的那一页抢 CPU。
  /// 串行化后同一时刻只有一个解码 isolate 在跑。
  static final List<String> _queued = <String>[];
  static bool _busy = false;

  static Future<void> sampleFile(String path) async {
    final cached = _cache[path];
    if (cached != null) {
      ReaderAmbientStore.instance.publish(cached);
      return;
    }
    if (_inFlight.contains(path)) return;
    _inFlight.add(path);
    _queued.add(path);
    if (_busy) return;
    await _pump();
  }

  static Future<void> _pump() async {
    _busy = true;
    try {
      while (_queued.isNotEmpty) {
        final path = _queued.removeAt(0);
        try {
          // 排队的这段时间里可能已被缓存命中路径取过色。
          if (_cache.containsKey(path)) continue;
          // 只把**路径**交给后台 isolate，读文件与解码都不在 UI isolate 上做。
          // 旧写法在这里 `File(path).readAsBytes()`：一页几 MB 的字节先进 UI isolate
          // 的堆，再由 `compute` 原样复制一份进新 isolate —— 边界那几页连着来，
          // 就是两次大块分配加一次 GC，正好落在用户翻到最后一页的那一刻。
          final values = await compute(_samplePaletteFromPath, path);
          if (values == null) continue;
          final palette = _paletteFromValues(values);
          _remember(path, palette);
          ReaderAmbientStore.instance.publish(palette);
        } catch (_) {
          // 取色失败时继续使用静态底色，不影响阅读。
        } finally {
          // 必须在这里摘掉：留在 `_inFlight` 里，等这条被缓存淘汰后就再也取不了色。
          _inFlight.remove(path);
        }
      }
    } finally {
      _busy = false;
    }
  }

  static void _remember(String path, ReaderAmbientPalette palette) {
    _cache[path] = palette;
    if (_cache.length <= _maxCacheEntries) return;
    // Map 保持插入序，淘汰最早那一条即可。
    _cache.remove(_cache.keys.first);
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

/// 在后台 isolate 里读文件并取样：UI isolate 只经手一个路径字符串。
///
/// 这里刻意用同步读：调用方已经不在 UI isolate 上了，同步读省掉一次
/// 「大缓冲区跨 isolate 搬运」，也不会让出线程去排 IO 池。
List<int>? _samplePaletteFromPath(String path) {
  return _samplePalette(File(path).readAsBytesSync());
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
