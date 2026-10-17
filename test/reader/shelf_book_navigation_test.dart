import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/service/reader/shelf_book_navigation.dart';
import 'package:zephyr/type/enum.dart';

void main() {
  test('按登记顺序切换相邻书籍并在边界提示', () async {
    final entries = [
      const ShelfBookNavigationEntry(
        key: 'source:a',
        comicId: 'a',
        from: 'source',
        type: ComicEntryType.normal,
      ),
      const ShelfBookNavigationEntry(
        key: 'source:b',
        comicId: 'b',
        from: 'source',
        type: ComicEntryType.normal,
      ),
      const ShelfBookNavigationEntry(
        key: 'source:c',
        comicId: 'c',
        from: 'source',
        type: ComicEntryType.normal,
      ),
    ];
    final opened = <String>[];
    final messages = <String>[];
    final controller = ShelfBookNavigationController(
      entries: entries,
      currentKey: 'source:b',
      open: (entry) async => opened.add(entry.comicId),
      notify: messages.add,
    );

    expect(controller.canGoPrevious, isTrue);
    expect(controller.canGoNext, isTrue);
    await controller.switchBook(false);
    await controller.switchBook(true);
    expect(opened, ['a', 'c']);

    final first = ShelfBookNavigationController(
      entries: entries,
      currentKey: 'source:a',
      open: (entry) async {},
      notify: messages.add,
    );
    await first.switchBook(false);
    expect(messages, ['已经是第一本书']);
  });
}
