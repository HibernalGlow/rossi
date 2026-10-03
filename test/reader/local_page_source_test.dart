import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/reader/local_page_source.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/src/rust/api/local.dart';
import 'package:zephyr/src/rust/frb_generated.dart';

class _LocalSourceApi implements RustLibApi {
  late LocalSourceInfo info;
  late LocalPageInfo page;
  final closed = <BigInt>[];

  /// 页表长度。`LocalPageSource` 的页数取自 `localSourcePages` 返回的**条数**，
  /// 不是 `LocalSourceInfo.pageCount` 那个打开时的申报值 —— 所以想造「同一章补了页」
  /// 必须动这里。默认 1，保持原有那条用例一模一样。
  int pageReplicas = 1;

  @override
  Future<LocalSourceOpenResult> crateApiLocalOpenLocalSource({
    required String path,
  }) async {
    expect(path, info.path);
    return LocalSourceOpenResult(source: info);
  }

  @override
  Future<List<LocalPageInfo>> crateApiLocalLocalSourcePages({
    required BigInt id,
  }) async => List.generate(
    pageReplicas,
    (i) => LocalPageInfo(index: i, name: page.name, size: page.size),
  );

  @override
  bool crateApiLocalLocalClose({required BigInt id}) {
    closed.add(id);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory directory;
  late _LocalSourceApi api;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rossi-local-source-');
    api = _LocalSourceApi();
    RustLib.initMock(api: api);
  });

  tearDown(() async {
    RustLib.dispose();
    // ignore: invalid_use_of_internal_member
    RustLib.instance.resetState();
    await directory.delete(recursive: true);
  });

  for (final kind in LocalSourceKind.values) {
    test('$kind 为播放器提供正确的直接文件路径并释放会话', () async {
      const name = '视频 2.MP4';
      final media = File(p.join(directory.path, name));
      await media.writeAsBytes([1, 2, 3]);
      final sourcePath = switch (kind) {
        LocalSourceKind.mediaFile => media.path,
        LocalSourceKind.folder => directory.path,
        LocalSourceKind.zip => p.join(directory.path, 'book.cbz'),
        LocalSourceKind.rar => p.join(directory.path, 'book.cbr'),
      };
      api.info = LocalSourceInfo(
        id: BigInt.one,
        path: sourcePath,
        kind: kind,
        pageCount: 1,
        totalBytes: BigInt.from(3),
      );
      api.page = LocalPageInfo(index: 0, name: name, size: BigInt.from(3));
      final opened = await LocalPageSource.open(sourcePath);
      expect(opened, isA<PageSourceOpened>());
      final source = (opened as PageSourceOpened).source;
      expect(source.path, sourcePath);
      expect(source.pageCount, 1);
      expect(source.pages.single.name, name);
      expect(
        await source.getPageFilePath(0),
        kind == LocalSourceKind.mediaFile || kind == LocalSourceKind.folder
            ? media.path
            : isNull,
      );
      expect(await source.getPageFilePath(-1), isNull);
      expect(await source.getPageFilePath(1), isNull);
      await source.close();
      await source.close();
      expect(api.closed, [BigInt.one]);
      expect(await source.getPageFilePath(0), isNull);
    });
  }

  group('本地档的成品页源身份', () {
    Future<LocalPageSource> openChapter(
      String name, {
      int pageCount = 3,
    }) async {
      final path = p.join(directory.path, name);
      api.info = LocalSourceInfo(
        id: BigInt.one,
        path: path,
        kind: LocalSourceKind.zip,
        pageCount: pageCount,
        totalBytes: BigInt.from(3),
      );
      api.page = LocalPageInfo(index: 0, name: '001.jpg', size: BigInt.from(3));
      api.pageReplicas = pageCount;
      final opened = await LocalPageSource.open(path);
      return ((opened as PageSourceOpened).source) as LocalPageSource;
    }

    test('一本一章报得出源身份（在线那档用的是 from|漫画|章）', () async {
      final source = await openChapter('book.cbz');
      expect(source, isA<TranslationScopeBearing>());
      expect(
        source.translationCacheScope,
        'local|${p.join(directory.path, 'book.cbz')}|3',
      );
    });

    test('同一路径两种拼法算同一章（补页之前的相对路径不该把缓存劈成两半）', () async {
      final a = await openChapter('book.cbz');
      final b = await openChapter(p.join('sub', '..', 'book.cbz'));
      expect(a.translationCacheScope, b.translationCacheScope);
    });

    test('换一章就是另一个源身份 —— 这正是 A 本第 5 页不再端给 B 本第 5 页的那道闸', () async {
      final one = await openChapter('vol1.cbz');
      final two = await openChapter('vol2.cbz');
      expect(one.translationCacheScope, isNot(two.translationCacheScope));
    });

    test('同一章补了页，源身份跟着变（页号与内容的对应关系已经变了）', () async {
      final before = await openChapter('book.cbz', pageCount: 3);
      final after = await openChapter('book.cbz', pageCount: 5);
      expect(before.translationCacheScope, isNot(after.translationCacheScope));
    });
  });
}
