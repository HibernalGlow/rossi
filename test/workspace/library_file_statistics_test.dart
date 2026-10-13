import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/workspace/service/library_file_statistics.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('rossi-stats-');
    await File('${root.path}/a').writeAsBytes([1, 2, 3]);
    await File('${root.path}/.hidden').writeAsBytes([4, 5]);
    final child = await Directory('${root.path}/child').create();
    await File('${child.path}/b').writeAsBytes([1, 2, 3, 4]);
    await Link('${root.path}/loop').create(root.path);
  });
  tearDown(() => root.delete(recursive: true));

  test('区分当前层和递归统计；不跟随链接、不把隐藏文件算入默认统计', () async {
    final direct = await scanLibraryDirectory(
      root.path,
      recursive: false,
      showHidden: false,
      cancelled: () => false,
    );
    expect(direct!.count, 2);
    expect(direct.bytes, 3);
    expect(direct.complete, isTrue);
    final recursive = await scanLibraryDirectory(
      root.path,
      recursive: true,
      showHidden: false,
      cancelled: () => false,
    );
    expect(recursive!.count, 3);
    expect(recursive.bytes, 7);
    final hidden = await scanLibraryDirectory(
      root.path,
      recursive: true,
      showHidden: true,
      cancelled: () => false,
    );
    expect(hidden!.count, 4);
    expect(hidden.bytes, 9);
  });
  test('取消不会返回部分数据冒充总数，无权限或丢失目录标为不完整', () async {
    expect(
      await scanLibraryDirectory(
        root.path,
        recursive: true,
        showHidden: false,
        cancelled: () => true,
      ),
      isNull,
    );
    final missing = await scanLibraryDirectory(
      '${root.path}/missing',
      recursive: true,
      showHidden: false,
      cancelled: () => false,
    );
    expect(missing!.complete, isFalse);
  });
  test('旧批次被新请求取消，旧数据不会写回新目录', () async {
    final cache = LibraryFileStatisticsCache();
    var oldReady = 0;
    var newReady = 0;
    final old = cache.prepare(
      [root.path],
      recursive: true,
      showHidden: false,
      revision: 'old',
      onReady: () => oldReady++,
    );
    final current = cache.prepare(
      ['${root.path}/child'],
      recursive: false,
      showHidden: false,
      revision: 'new',
      onReady: () => newReady++,
    );
    await Future.wait([old, current]);
    expect(oldReady, 0);
    expect(newReady, 1);
    expect(cache.values.keys, ['${root.path}/child']);
    cache.dispose();
  });
}
