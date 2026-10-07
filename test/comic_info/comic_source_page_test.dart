import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_info/json/normal/normal_comic_all_info.dart';
import 'package:zephyr/page/comic_info/models/comic_source_page_url.dart';
import 'package:zephyr/service/comic_source_page/comic_source_page_store.dart';

/// 「在原站打开」这颗按钮的全部判据：链接**只能**来自插件已经交出来的页面地址，
/// 且从列表项记下来的那条要能跨进程取回（收藏 / 历史 / 下载入口靠它）。
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('comic_source_page_');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  ComicSourcePageStore storeInRoot() =>
      ComicSourcePageStore(directory: () async => root.path);

  File dataFile() => File(
    '${root.path}${Platform.pathSeparator}${ComicSourcePageStore.fileName}',
  );

  group('约定键', () {
    test('插件给的 href 会被认（这把尺子必须看得见合规的那一侧）', () {
      expect(
        ComicSourcePageStore.urlFromExtern({
          'href': 'https://e-hentai.org/g/1234/abc/',
        }),
        'https://e-hentai.org/g/1234/abc/',
      );
    });

    test('裸 url 是图片资源地址，不能当成页面', () {
      expect(
        ComicSourcePageStore.urlFromExtern({
          'url': 'https://cdn.example/cover-1.jpg',
        }),
        isEmpty,
      );
    });

    test('相对路径与非 http 值不算页面链接', () {
      expect(
        ComicSourcePageStore.urlFromExtern({'href': '/g/1234/abc/'}),
        isEmpty,
      );
      expect(ComicSourcePageStore.urlFromExtern({}), isEmpty);
      expect(ComicSourcePageStore.urlFromExtern(null), isEmpty);
    });

    test('href 优先于其余约定键', () {
      expect(
        ComicSourcePageStore.urlFromExtern({
          'webUrl': 'https://example.com/second',
          'href': 'https://example.com/first',
        }),
        'https://example.com/first',
      );
    });
  });

  group('存取', () {
    test('记下的链接换一份 store 实例仍取得回（真的落盘）', () async {
      final writer = storeInRoot();
      writer.remember(
        source: 'plugin-a',
        comicId: '1234',
        extern: {'href': 'https://example.com/g/1234/'},
      );
      await writer.flush();
      expect(await dataFile().exists(), isTrue);

      final reader = storeInRoot();
      await reader.load();
      expect(reader.urlOf('plugin-a', '1234'), 'https://example.com/g/1234/');
    });

    test('盘上的旧记录不会被新的一次写覆盖掉', () async {
      // 回归：flush 若不等 load 读完就写，「启动后第一批列表」会把整份历史
      // 覆盖成只剩刚记的那几条。
      await dataFile().writeAsString(
        jsonEncode({'old:1': 'https://example.com/old/'}),
      );

      final store = storeInRoot();
      store.rememberUrl(
        source: 'new',
        comicId: '2',
        url: 'https://example.com/new/',
      );
      await store.flush();

      final reloaded = storeInRoot();
      await reloaded.load();
      expect(reloaded.urlOf('old', '1'), 'https://example.com/old/');
      expect(reloaded.urlOf('new', '2'), 'https://example.com/new/');
    });

    test('插件没给链接时一次写入都不产生', () async {
      final store = storeInRoot();
      store.remember(
        source: 'plugin-a',
        comicId: '1',
        extern: {'uploader': 'someone'},
      );
      await store.flush();
      expect(await dataFile().exists(), isFalse);
    });
  });

  group('详情页解析顺序', () {
    test('详情自己给了就直接用，并顺手记进 store', () async {
      final store = storeInRoot();
      final url = await resolveComicSourcePageUrl(
        info: _info(comicExtern: {'href': 'https://example.com/g/1234/'}),
        from: 'plugin-a',
        comicId: '1234',
        store: store,
      );

      expect(url, 'https://example.com/g/1234/');
      expect(store.urlOf('plugin-a', '1234'), 'https://example.com/g/1234/');
    });

    test('详情没给、但列表项早前记过 —— 用记下来的那条', () async {
      final store = storeInRoot();
      store.rememberUrl(
        source: 'plugin-a',
        comicId: '1234',
        url: 'https://example.com/from-list/',
      );

      final url = await resolveComicSourcePageUrl(
        info: _info(),
        from: 'plugin-a',
        comicId: '1234',
        store: store,
      );

      expect(url, 'https://example.com/from-list/');
    });

    test('哪儿都没有就是空串（那颗卡不渲染的依据）', () async {
      final url = await resolveComicSourcePageUrl(
        info: _info(),
        from: 'plugin-a',
        comicId: 'never-seen',
        store: storeInRoot(),
      );
      expect(url, isEmpty);
    });
  });
}

NormalComicAllInfo _info({
  Map<String, dynamic> comicExtern = const <String, dynamic>{},
  Map<String, dynamic> topExtern = const <String, dynamic>{},
}) {
  const image = ComicImage(id: 'cover', url: '', name: 'cover');
  return NormalComicAllInfo(
    comicInfo: ComicInfo(
      id: '1234',
      title: '示例',
      titleMeta: const <ComicInfoActionItem>[],
      creator: Creator(id: '', name: '', avatar: image),
      description: '',
      cover: image,
      metadata: const <ComicInfoMetadata>[],
      extern: comicExtern,
    ),
    eps: const <Ep>[],
    recommend: const <Recommend>[],
    extern: topExtern,
  );
}
