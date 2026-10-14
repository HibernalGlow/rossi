import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/donwload_task/models/download_task_comic_scope.dart';

({String comicId, String comicName}) _row(String comicId, {String? name}) {
  return (comicId: comicId, comicName: name ?? '漫画$comicId');
}

void main() {
  group('队列按漫画分组', () {
    test('同一本的多章合成一组，章数按行数累加', () {
      final groups = downloadTasksGroupedByComic([
        _row('a'),
        _row('a'),
        _row('a'),
        _row('b'),
      ]);

      expect(groups, hasLength(2));
      expect(groups.map((g) => g.comicId), ['a', 'b']);
      expect(groups.map((g) => g.taskCount), [3, 1]);
    });

    test('顺序跟着「第一次出现」，不跟章数也不跟字母', () {
      // 队列每刷一次就重排的话，同一本会在屏幕上跳来跳去；分段已经是状态维度的了。
      final groups = downloadTasksGroupedByComic([
        _row('z'),
        _row('m'),
        _row('m'),
        _row('a'),
        _row('z'),
      ]);

      expect(groups.map((g) => g.comicId), ['z', 'm', 'a']);
      expect(groups.map((g) => g.taskCount), [2, 2, 1]);
    });

    test('同一 id 换了名字仍是一组，名字取第一次见到那份', () {
      final groups = downloadTasksGroupedByComic([
        _row('a', name: '旧书名'),
        _row('a', name: '证书改名后的书名'),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.comicName, '旧书名');
      expect(groups.single.taskCount, 2);
    });

    test('空队列不产生任何组', () {
      expect(downloadTasksGroupedByComic(const []), isEmpty);
    });

    test('未选中某本时不筛掉任何行；选中后只留那一本', () {
      expect(
        downloadTaskMatchesComicScope(selectedComicId: null, comicId: 'a'),
        isTrue,
      );
      expect(
        downloadTaskMatchesComicScope(selectedComicId: 'a', comicId: 'a'),
        isTrue,
      );
      expect(
        downloadTaskMatchesComicScope(selectedComicId: 'b', comicId: 'a'),
        isFalse,
      );
    });
  });
}
