import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';

Doc _doc(String name) =>
    Doc(originalName: name, path: '', fileServer: '', id: '');

int _slotFor(
  int docIndex, {
  required bool doublePage,
  bool leadingBlank = false,
}) => getSlotIndexFromStoredHistoryPage(
  storedHistoryPage: docIndex + 2,
  enableDoublePage: doublePage,
  insertLeadingBlank: leadingBlank,
);

void main() {
  group('松散图片被提升为目录书后的起始页', () {
    test('平铺页表按文件名命中，递归页表按相对路径尾部命中', () {
      final flat = [_doc('page_1.jpg'), _doc('page_2.jpg')];
      expect(findLocalEntryHintIndex(flat, 'page_2.jpg'), 1);

      final deep = [_doc('cover.jpg'), _doc('ch1/page_2.jpg')];
      expect(findLocalEntryHintIndex(deep, 'page_2.jpg'), 1);
    });

    test('那一张不在书里就交回按历史续读', () {
      final docs = [_doc('page_1.jpg')];
      expect(findLocalEntryHintIndex(docs, 'gone.jpg'), isNull);
      expect(findLocalEntryHintIndex(docs, ''), isNull);
    });

    test('页下标 +2 与历史页码同刻度，三种排版都落在正确的槽', () {
      expect(_slotFor(0, doublePage: false), 0);
      expect(_slotFor(3, doublePage: false), 3);

      // 双页：第 3、4 页（下标 2、3）同一槽
      expect(_slotFor(2, doublePage: true), 1);
      expect(_slotFor(3, doublePage: true), 1);

      // 双页 + 前导空白：第 1 页独占一槽，之后 (页码 ~/ 2)
      expect(_slotFor(0, doublePage: true, leadingBlank: true), 0);
      expect(_slotFor(3, doublePage: true, leadingBlank: true), 2);
    });
  });
}
