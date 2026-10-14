import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zephyr/reader/ambient_image_sampler.dart';
import 'package:zephyr/reader/reader_ambient_background.dart';

/// 「自适应背景取色」这条旁路的门禁。
///
/// 它原先在 UI isolate 上 `File(path).readAsBytes()` 把整页几 MB 读进堆，
/// 再让 `compute` 原样复制进一个新 isolate。章节边界那几页连着解析完，
/// 就是连着几次大块分配 + GC —— 正好落在用户翻到最后一页那一刻。
/// 现在只把**路径**交给后台 isolate，读与解都在那边发生。
///
/// 下面钉的是三件能从外部机器可观测的事：
/// 换成「路径进 isolate」之后仍然出得了正确的颜色；命中缓存不再回读盘；
/// 多个请求串行排空、不死锁。淘汰上限（48 条）不在这里测，见报告。
Uint8List _solidPng({required int r, required int g, required int b}) {
  final canvas = img.Image(width: 200, height: 120);
  for (var y = 0; y < 120; y++) {
    for (var x = 0; x < 200; x++) {
      canvas.setPixel(x, y, img.ColorRgba8(r, g, b, 255));
    }
  }
  return Uint8List.fromList(img.encodePng(canvas));
}

void main() {
  late Directory temp;
  final store = ReaderAmbientStore.instance;

  setUp(() {
    store.clear();
  });
  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('rossi_ambient_sampler_');
  });
  tearDownAll(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  String writeFile(
    String name, {
    required int r,
    required int g,
    required int b,
  }) {
    final file = File('${temp.path}/$name')
      ..writeAsBytesSync(_solidPng(r: r, g: g, b: b));
    return file.path;
  }

  test('把路径交给后台 isolate 之后，取色仍然出得来并且颜色对得上', () async {
    final path = writeFile('red.png', r: 220, g: 40, b: 40);

    await ReaderAmbientImageSampler.sampleFile(path);

    final palette = store.palette.value;
    expect(palette, isNotNull, reason: 'sampleFile 的首个调用方会驱动队列排空');
    // 纯色图：resize 不改变分量，留 1 档容差防量化。
    expect(palette!.average.red, closeTo(220, 1));
    expect(palette.average.green, closeTo(40, 1));
    expect(palette.average.blue, closeTo(40, 1));
  });

  test('同一路径第二次取样不再读盘：文件删掉也照样发布', () async {
    final path = writeFile('green.png', r: 30, g: 200, b: 90);
    await ReaderAmbientImageSampler.sampleFile(path);
    final first = store.palette.value;
    expect(first, isNotNull);

    File(path).deleteSync();
    store.clear();
    expect(store.palette.value, isNull);

    await ReaderAmbientImageSampler.sampleFile(path);
    expect(
      store.palette.value,
      isNotNull,
      reason: '文件已经不在了还能发布，说明走的是缓存而不是重新读盘解码。',
    );
    expect(store.palette.value, first);
  });

  test('边界那一下的并发取样会串行排空，不死锁也不漏页', () async {
    final paths = <String>[
      writeFile('p1.png', r: 10, g: 10, b: 10),
      writeFile('p2.png', r: 200, g: 10, b: 10),
      writeFile('p3.png', r: 10, g: 200, b: 10),
    ];

    // 先同步把三条都塞进队列：第一条启动 pump，后两条只排队。
    final inflight = paths.map(ReaderAmbientImageSampler.sampleFile).toList();
    await Future.wait(inflight).timeout(const Duration(seconds: 30));

    // 三条都进了缓存：把文件全删了再逐条取样，仍应立刻发布。
    for (final path in paths) {
      File(path).deleteSync();
    }
    for (final path in paths) {
      store.clear();
      await ReaderAmbientImageSampler.sampleFile(path);
      expect(store.palette.value, isNotNull, reason: '排队的 $path 没有被静默丢掉。');
    }
    // 最后一条是绿的（p3）—— 顺序按请求序，不是乱序覆盖。
    expect(store.palette.value!.average.green, closeTo(200, 1));
  });
}
