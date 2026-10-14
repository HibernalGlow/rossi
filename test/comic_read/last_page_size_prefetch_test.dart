import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_read/cubit/image_size_cubit.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/method/prefetch_image_sizes.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';

/// 「翻到最后一页会卡一下」这条链路的回归门禁。
///
/// 章节边界上，`ComicReadSuccessWidget` 会把**所有**已加载章节重新交给
/// `prefetchChapterImageSizes`。旧判据只看「这一页量到过尺寸没有」，
/// 于是磁盘上没有的页（在线未下载、本地压缩包内）每次边界都被重探一遍，
/// 而单次探测要跑三组候选路径 + 十几次同步跨桥。
/// 下面几条分别钉住：探测次数、通知次数、以及负缓存不许挡住真实上报。

Uint8List _pngBytes({required int width, required int height}) {
  final b = Uint8List(24);
  b.setRange(0, 8, <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  b.setRange(12, 16, <int>[0x49, 0x48, 0x44, 0x52]); // "IHDR"
  final view = ByteData.sublistView(b);
  view.setUint32(16, width);
  view.setUint32(20, height);
  return b;
}

List<Doc> _docs(String tag, int count) => List<Doc>.generate(
  count,
  (i) => Doc(
    originalName: '$tag$i',
    path: '$tag/$i.jpg',
    fileServer: '',
    id: '$tag$i',
  ),
);

ImageSizeCubit _cubit(int count) => ImageSizeCubit.create(
  defaultWidth: 400,
  count: count,
  sourceTag: 'test',
  pageKeys: List<String>.generate(count, (i) => 'comic|ep|page_$i'),
  chapterOrder: 0,
  // 非 null 即跳过开机水合，这条测试不碰真实缓存盘。
  persistedCache: const <int, Size>{},
);

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('rossi_prefetch_storm_');
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('边界重跑所有章节时，每页一次会话只探测一次', () async {
    final cubit = _cubit(24);
    var probes = 0;
    Future<String> miss({
      required String from,
      required String path,
      required String cartoonId,
      required String chapterId,
      required String storageChapterId,
    }) async {
      probes++;
      return '';
    }

    final chapterA = _docs('a', 12);
    final chapterB = _docs('b', 12);
    Future<void> fanOut() async {
      await prefetchChapterImageSizes(
        imageSizeCubit: cubit,
        docs: chapterA,
        comicId: 'comic',
        from: 'test',
        chapterId: 'epA',
        chapterOrder: 5,
        contentWidth: 400,
        resolveCachedPath: miss,
      );
      await prefetchChapterImageSizes(
        imageSizeCubit: cubit,
        docs: chapterB,
        comicId: 'comic',
        from: 'test',
        chapterId: 'epB',
        chapterOrder: 6,
        contentWidth: 400,
        resolveCachedPath: miss,
      );
    }

    await fanOut();
    // 阳性对照：缝本身确实被走到，24 页各探一次。
    expect(probes, 24);

    // 再翻三次「最后一页」：调用方每次都会把两章全量重交一遍。
    await fanOut();
    await fanOut();
    await fanOut();

    expect(
      probes,
      24,
      reason:
          '负缓存失效 —— 每翻到章末都把已加载章节整批重探，'
          '探测量按「章数 × 页数 × 边界次数」增长，正好卡在最后一页那一下。',
    );
    await cubit.close();
  });

  test('命中的尺寸攒批上报，不再逐页通知监听者', () async {
    final cubit = _cubit(20);
    final file = File('${tmp.path}/page.png')
      ..writeAsBytesSync(_pngBytes(width: 800, height: 1200));

    var emits = 0;
    final sub = cubit.stream.listen((_) => emits++);

    await prefetchChapterImageSizes(
      imageSizeCubit: cubit,
      docs: _docs('c', 20),
      comicId: 'comic',
      from: 'test',
      chapterId: 'epC',
      chapterOrder: 1,
      contentWidth: 400,
      resolveCachedPath:
          ({
            required from,
            required path,
            required cartoonId,
            required chapterId,
            required storageChapterId,
          }) async => file.path,
    );
    await sub.cancel();

    // 20 页 / 每 8 页一批 = 3 次通知；旧写法是 20 次。
    expect(emits, lessThanOrEqualTo(3));
    expect(emits, greaterThanOrEqualTo(1));
    final first = cubit.getSize(
      resolveStableSizeCacheIndex(chapterOrder: 1, localPageIndex: 0),
    );
    expect(first.isCached, isTrue);
    // 800×1200 按 400 宽等比 → 高 600。
    expect(first.size.height, closeTo(600, 0.001));
    await cubit.close();
  });

  test('探测落空不挡住图片上屏后的真实尺寸上报', () async {
    final cubit = _cubit(4);
    final index = resolveStableSizeCacheIndex(
      chapterOrder: 7,
      localPageIndex: 2,
    );

    expect(cubit.isProbed(index), isFalse);
    await prefetchChapterImageSizes(
      imageSizeCubit: cubit,
      docs: _docs('d', 4),
      comicId: 'comic',
      from: 'test',
      chapterId: 'epD',
      chapterOrder: 7,
      contentWidth: 400,
      resolveCachedPath:
          ({
            required from,
            required path,
            required cartoonId,
            required chapterId,
            required storageChapterId,
          }) async => '',
    );
    expect(
      cubit.isProbed(index),
      isTrue,
      reason: '落空也要记账，否则每次边界都会重跑这条页的多候选路径解析。',
    );

    // `ImageDisplay` 上屏后的上报不看负缓存，照常生效。
    cubit.updateSize(index, const Size(500, 700));
    final reported = cubit.getSize(index);
    expect(reported.isCached, isTrue);
    expect(reported.size, const Size(500, 700));
    await cubit.close();
  });

  test('重复交给同一批尺寸不会再 emit 一次', () async {
    final cubit = _cubit(6);
    final index = resolveStableSizeCacheIndex(
      chapterOrder: 0,
      localPageIndex: 1,
    );
    cubit.updateSizes(<int, Size>{index: const Size(400, 500)});

    var emits = 0;
    final sub = cubit.stream.listen((_) => emits++);
    cubit.updateSizes(<int, Size>{index: const Size(400, 500)});
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(emits, 0);
    await cubit.close();
  });
}
