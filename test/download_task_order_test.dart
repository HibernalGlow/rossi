import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/service/download/download_task_order.dart';

DownloadTaskOrderRow _row(int id, String key) => (id: id, key: key);

List<int> _ids(List<DownloadTaskOrderRow> rows) =>
    rows.map((r) => r.id).toList();

void main() {
  group('下载任务启动顺序', () {
    test('没置顶时按入队顺序（id 升序）', () {
      final ordered = sortDownloadTasksForStart(
        rows: [_row(3, 'c'), _row(1, 'a'), _row(2, 'b')],
      );

      expect(_ids(ordered), [1, 2, 3]);
    });

    test('置顶的插到队首，其余保持原顺序', () {
      final ordered = sortDownloadTasksForStart(
        rows: [_row(1, 'a'), _row(2, 'b'), _row(3, 'c')],
        pinnedKeys: const ['c'],
      );

      expect(_ids(ordered), [3, 1, 2]);
    });

    test('多个置顶按「最后点的先走」排，非置顶仍按入队顺序', () {
      // 用户先点 b 再点 c：他现在最想要的是 c。
      final ordered = sortDownloadTasksForStart(
        rows: [_row(1, 'a'), _row(2, 'b'), _row(3, 'c'), _row(4, 'd')],
        pinnedKeys: const ['c', 'b'],
      );

      expect(_ids(ordered), [3, 2, 1, 4]);
    });

    test('集合里的 key 不在队列里时不影响任何一行（陈旧置顶是空转不是错位）', () {
      final ordered = sortDownloadTasksForStart(
        rows: [_row(1, 'a'), _row(2, 'b')],
        pinnedKeys: const ['ghost', 'b'],
      );

      expect(_ids(ordered), [2, 1]);
    });

    test('同 id 不会出现两次；排序是全排列不漏行', () {
      final rows = [for (var i = 1; i <= 6; i++) _row(i, 'k$i')];
      final ordered = sortDownloadTasksForStart(
        rows: rows,
        pinnedKeys: const ['k4', 'k2'],
      );

      expect(
        ordered.map((row) => row.id).toSet(),
        rows.map((r) => r.id).toSet(),
      );
      expect(ordered, hasLength(rows.length));
    });

    test('点优先把 key 挪到最前，重复点同一章不改顺序', () {
      expect(pinTaskKey(pinnedKeys: const ['b', 'c'], key: 'a'), [
        'a',
        'b',
        'c',
      ]);
      expect(pinTaskKey(pinnedKeys: const ['a', 'b'], key: 'a'), ['a', 'b']);
      expect(pinTaskKey(pinnedKeys: const [], key: 'a'), ['a']);
      // 点在中间的那颗上：把它提到最前，别把它挤到自己后面。
      expect(pinTaskKey(pinnedKeys: const ['a', 'b', 'c'], key: 'c'), [
        'c',
        'a',
        'b',
      ]);
    });

    test('置顶表只留还在队列里的 key，并去重', () {
      expect(
        prunePinnedKeys(
          pinnedKeys: const ['a', 'gone', 'a', 'b'],
          queuedKeys: const {'a', 'b', 'c'},
        ),
        ['a', 'b'],
      );
      expect(
        prunePinnedKeys(pinnedKeys: const ['x'], queuedKeys: const <String>{}),
        isEmpty,
      );
    });
  });
}
