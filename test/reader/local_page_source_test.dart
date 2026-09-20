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
  }) async => [page];

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
}
