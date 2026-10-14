import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/download/models/download_selection.dart';

DownloadChapterSelection _sel({
  List<String> ids = const ['ch-1', 'ch-2', 'ch-3'],
  List<String> downloaded = const [],
  List<String> selected = const [],
  bool skip = false,
}) {
  return DownloadChapterSelection(
    orderedIds: ids,
    downloadedIds: downloaded.toSet(),
    selectedIds: selected.toSet(),
    skipDownloaded: skip,
  );
}

void main() {
  group('章节勾选', () {
    test('全选把所有行勾上，再点取消全选清空', () {
      final base = _sel();
      expect(base.isAllSelected, isFalse);

      final all = base.withAllSelected(true);
      expect(all.selectedIds, {'ch-1', 'ch-2', 'ch-3'});
      expect(all.isAllSelected, isTrue);

      expect(all.withAllSelected(false).selectedIds, isEmpty);
    });

    test('空目录不算「已全选」（否则标题栏一进页就显示成取消全选）', () {
      expect(_sel(ids: const []).isAllSelected, isFalse);
      expect(_sel(ids: const []).selectableIds, isEmpty);
    });

    test('反选把选中的翻成没选中的，连点两次回到原样', () {
      final inverted = _sel(selected: const ['ch-1']).inverted();
      expect(inverted.selectedIds, {'ch-2', 'ch-3'});
      expect(inverted.inverted().selectedIds, {'ch-1'});
    });

    test('跳过已下载开着时，全选只挑没下过的', () {
      final skipped = _sel(
        downloaded: const ['ch-2'],
      ).withSkipDownloaded(true).withAllSelected(true);

      expect(skipped.selectedIds, {'ch-1', 'ch-3'});
      expect(skipped.selectableIds, ['ch-1', 'ch-3']);
      expect(skipped.isSkipped('ch-2'), isTrue);
      expect(skipped.isSkipped('ch-1'), isFalse);
      // 三行里只勾了两行，所以不能报「已全选」以外的口径
      expect(skipped.isAllSelected, isTrue);
    });

    test('开启跳过会顺手清掉已下载行的勾选，计数与真正入队的集合一致', () {
      final on = _sel(
        downloaded: const ['ch-2'],
        selected: const ['ch-1', 'ch-2'],
      ).withSkipDownloaded(true);

      expect(on.selectedIds, {'ch-1'});
      expect(on.selectedCount, 1);
      expect(on.orderedSelectedIds, ['ch-1']);
    });

    test('跳过开着时点已下载那一行什么都不改（返回同一份表）', () {
      final on = _sel(
        downloaded: const ['ch-2'],
        selected: const ['ch-1'],
        skip: true,
      );

      expect(on.toggled('ch-2').selectedIds, {'ch-1'});
      expect(identical(on.toggled('ch-2'), on), isTrue);
      // 对照：没跳过的那一行点下去就变
      expect(on.toggled('ch-3').selectedIds, {'ch-1', 'ch-3'});
    });

    test('反选不会把被跳过的行捞回来', () {
      final inverted = _sel(
        downloaded: const ['ch-2'],
        selected: const ['ch-1'],
        skip: true,
      ).inverted();

      expect(inverted.selectedIds, {'ch-3'});
    });

    test('关掉跳过不复活被清掉的勾选（勾选是动作的结果，不是缓存）', () {
      final on = _sel(
        downloaded: const ['ch-2'],
        selected: const ['ch-1', 'ch-2'],
      ).withSkipDownloaded(true);
      final off = on.withSkipDownloaded(false);

      expect(off.skipDownloaded, isFalse);
      expect(off.selectedIds, {'ch-1'});
      expect(off.downloadedIds, {'ch-2'});
    });

    test('入队顺序跟页面顺序，不按点选顺序', () {
      expect(_sel(selected: const ['ch-3', 'ch-1']).orderedSelectedIds, [
        'ch-1',
        'ch-3',
      ]);
    });
  });
}
