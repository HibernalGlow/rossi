import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_read/cubit/reader_page_order_cubit.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/model/reader_page_order.dart';

Doc _doc(String name, {String? id}) => Doc(
  originalName: name,
  path: '/fake/$name',
  fileServer: '',
  id: id ?? name,
);

List<Doc> _docs(List<String> names) => List<Doc>.generate(
  names.length,
  (index) => _doc(names[index]),
  growable: false,
);

void main() {
  group('自然序排序键', () {
    test('数字段按数值比，page2 排在 page10 前', () {
      // 阳性对照：码位序会把 10 排在 2 前面，这条断言就是在抓那个反例。
      final order = readerNaturalOrder(const ['page10.jpg', 'page2.jpg', 'page1.jpg']);
      expect(order, <int>[2, 1, 0]);
    });

    test('全角数字也算数字段', () {
      final order = readerNaturalOrder(const ['１０.jpg', '２.jpg']);
      expect(order, <int>[1, 0]);
    });

    test('符号剥离后 #1 与 1 同键，平局按源下标定序', () {
      final withHash = readerNaturalSortKey('#1.jpg');
      final plain = readerNaturalSortKey('1.jpg');
      expect(withHash.length, plain.length);
      expect(compareReaderNaturalKeys(withHash, plain), 0);
      // 同键的两个名字必须靠源下标定序，否则每次重排都可能互换 = 翻页抖。
      expect(readerNaturalOrder(const ['#1.jpg', '1.jpg']), <int>[0, 1]);
      expect(readerNaturalOrder(const ['1.jpg', '#1.jpg']), <int>[0, 1]);
    });

    test('数字块排在文本块前（与 local_core 的枚举顺序一致）', () {
      expect(
        compareReaderNaturalKeys(
          readerNaturalSortKey('1BACKUP'),
          readerNaturalSortKey('BaiduNetdiskDownload'),
        ),
        lessThan(0),
      );
    });

    test('超长数字段饱和而不抛异常', () {
      final key = readerNaturalSortKey('99999999999999999999999999.jpg');
      expect(key.first, isA<ReaderNaturalNum>());
    });
  });

  group('排列的校验与变换', () {
    test('长度不符、越界、重复下标一律退回 null', () {
      expect(normalizeReaderPageOrder(null, 3), isNull);
      expect(normalizeReaderPageOrder(<int>[0, 1], 3), isNull);
      expect(normalizeReaderPageOrder(<int>[0, 1, 3], 3), isNull);
      expect(normalizeReaderPageOrder(<int>[0, 1, 1], 3), isNull);
      expect(normalizeReaderPageOrder(<int>[2, 0, 1], 3), <int>[2, 0, 1]);
    });

    test('倒序是一份合法排列，且两次倒序回到原样', () {
      final reversed = List<int>.unmodifiable(readerSourceOrder(5).reversed);
      expect(reversed, <int>[4, 3, 2, 1, 0]);
      expect(normalizeReaderPageOrder(reversed, 5), reversed);
      expect(
        readerCustomOrderFrom(reversed, seedMode: ReaderPageOrderMode.reverse),
        <int>[0, 1, 2, 3, 4],
      );
    });

    test('readerMoveInOrder 与 ReorderableListView 的下标语义一致', () {
      // Flutter 给的 newIndex 是「移除之前」的位置：往下拖时要先减一才落得准
      // （官方示例里那句 `if (newIndex > oldIndex) newIndex -= 1`）。
      expect(readerMoveInOrder(const <int>[0, 1, 2], 0, 2), <int>[1, 0, 2]);
      expect(readerMoveInOrder(const <int>[0, 1, 2], 2, 0), <int>[2, 0, 1]);
      // 把第 2 格拖到末尾：三项的列表里「末尾」是 newIndex = 3，减一之后落位 2。
      expect(readerMoveInOrder(const <int>[0, 1, 2], 1, 3), <int>[0, 2, 1]);
      // 相邻互换的正确写法是 `1 → 0`：`newIndex` 带着被拖走那一格计数，
      // 所以 `0 → 1` 量的就是「放回自己后面」= 原地不动（实测恒等，不是 bug）。
      expect(readerMoveInOrder(const <int>[0, 1, 2], 1, 0), <int>[1, 0, 2]);
      expect(readerMoveInOrder(const <int>[0, 1, 2], 0, 1), <int>[0, 1, 2]);
    });

    test('位置与源下标互查', () {
      const order = <int>[2, 0, 1];
      expect(readerPositionOfSource(order, 2), 0);
      expect(readerPositionOfSource(order, 1), 2);
      expect(readerPositionOfSource(order, 5), isNull);
    });
  });

  group('ReaderPageOrderCubit', () {
    test('档位为 custom 但没有排列时按原样铺，而不是空列表', () {
      final cubit = ReaderPageOrderCubit();
      final docs = _docs(<String>['a', 'b', 'c']);
      expect(
        cubit.resolveOrder(
          chapterId: 'ch1',
          mode: ReaderPageOrderMode.custom,
          docs: docs,
        ),
        <int>[0, 1, 2],
      );
      addTearDown(cubit.close);
    });

    test('应用手动排列后按它铺，并按章隔离', () {
      final cubit = ReaderPageOrderCubit();
      final docs = _docs(<String>['a', 'b', 'c']);
      cubit.applyCustomOrder('ch1', <int>[1, 2, 0]);
      expect(
        cubit.resolveOrder(
          chapterId: 'ch1',
          mode: ReaderPageOrderMode.custom,
          docs: docs,
        ),
        <int>[1, 2, 0],
      );
      expect(
        cubit.resolveOrder(
          chapterId: 'ch2',
          mode: ReaderPageOrderMode.custom,
          docs: docs,
        ),
        <int>[0, 1, 2],
      );
      expect(cubit.hasCustomOrder('ch1'), isTrue);
      expect(cubit.hasCustomOrder('ch2'), isFalse);
      addTearDown(cubit.close);
    });

    test('页表变短时旧排列对不上号，直接退回原样而不是越界取页', () {
      final cubit = ReaderPageOrderCubit();
      cubit.applyCustomOrder('ch1', <int>[2, 0, 1]);
      final shorter = _docs(<String>['a', 'b']);
      expect(
        cubit.resolveOrder(
          chapterId: 'ch1',
          mode: ReaderPageOrderMode.custom,
          docs: shorter,
        ),
        <int>[0, 1],
      );
      addTearDown(cubit.close);
    });

    test('orderedDocs 给的页与 resolveOrder 一致（下游按下标取的就是这一份）', () {
      final cubit = ReaderPageOrderCubit();
      final docs = _docs(<String>['page10.jpg', 'page2.jpg', 'page1.jpg']);
      final ordered = cubit.orderedDocs(
        chapterId: 'ch1',
        mode: ReaderPageOrderMode.natural,
        docs: docs,
      );
      expect(
        ordered.map((doc) => doc.originalName),
        <String>['page1.jpg', 'page2.jpg', 'page10.jpg'],
      );
      // 每一页还是它自己：排序只换位置，不改内容，尺寸缓存与历史都按源下标查。
      expect(ordered.every((doc) => docs.contains(doc)), isTrue);
      addTearDown(cubit.close);
    });

    test('清除本章排列后 emit 新状态；清除别章不动状态', () {
      final cubit = ReaderPageOrderCubit();
      cubit.applyCustomOrder('ch1', <int>[1, 0]);
      final before = cubit.state;
      cubit.clearCustomOrder('ch2');
      expect(identical(cubit.state, before), isTrue);
      cubit.clearCustomOrder('ch1');
      expect(cubit.hasCustomOrder('ch1'), isFalse);
      addTearDown(cubit.close);
    });

    test('换档位后缓存跟着换，不会把上一档的排列端出来', () {
      final cubit = ReaderPageOrderCubit();
      final docs = _docs(<String>['page10.jpg', 'page2.jpg']);
      expect(
        cubit.resolveOrder(
          chapterId: 'ch1',
          mode: ReaderPageOrderMode.source,
          docs: docs,
        ),
        <int>[0, 1],
      );
      expect(
        cubit.resolveOrder(
          chapterId: 'ch1',
          mode: ReaderPageOrderMode.reverse,
          docs: docs,
        ),
        <int>[1, 0],
      );
      expect(
        cubit.resolveOrder(
          chapterId: 'ch1',
          mode: ReaderPageOrderMode.natural,
          docs: docs,
        ),
        <int>[1, 0],
      );
      addTearDown(cubit.close);
    });
  });
}
