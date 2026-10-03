import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/model/normal_comic_ep_info.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/workspace/widgets/cards/page_list_card.dart';

void _noop() {}

List<Doc> _docs(int n) => List<Doc>.generate(
  n,
  (i) => Doc(
    originalName: 'page${i + 1}.jpg',
    path: 'p$i',
    fileServer: 's1',
    id: '$i',
  ),
);

void main() {
  testWidgets('MEASURE geometry', (tester) async {
    ScrollPosition posOf(Type list) => tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(list),
            matching: find.byType(Scrollable),
          )
          .first,
    ).position;

    Rect listRect(Type list) =>
        tester.getRect(find.byType(list).first);

    Rect? activeRect(String matcher) {
      final f = find.ancestor(
        of: find.text('当前'),
        matching: find.byType(matcher == 'ink' ? InkWell : ListTile),
      );
      return f.evaluate().isEmpty ? null : tester.getRect(f.first);
    }

    final coordinator = ReaderSessionCoordinator.instance;
    coordinator.attachSession(
      comicId: 'test-comic',
      from: 'test',
      title: '测试漫画',
      epInfo: NormalComicEpInfo(epName: '第 1 话', docs: _docs(300)),
      currentSlot: 0,
      totalSlots: 300,
      jumpToSlot: (_) async {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 600,
            child: PageListCard(
              isExpanded: true,
              onToggle: _noop,
              isStandalone: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    void dump(String tag, Type list) {
      final p = posOf(list);
      final r = listRect(list);
      final a = activeRect(tag == 'grid' ? 'ink' : 'tile');
      print(
        '$tag rect=$r h=${p.viewportDimension} max=${p.maxScrollExtent} '
        'offset=${p.pixels} active=$a '
        'activeTopInView=${a == null ? "OFFSCREEN" : a.top - r.top} '
        'centerInView=${a == null ? "-" : (a.center.dy - r.top)} '
        'want=${p.viewportDimension / 2}',
      );
    }

    dump('grid0', GridView);

    coordinator.updateProgress(currentSlot: 150, totalSlots: 300);
    await tester.pumpAndSettle();
    dump('grid150', GridView);

    coordinator.updateProgress(currentSlot: 20, totalSlots: 300);
    await tester.pumpAndSettle();
    dump('grid20', GridView);

    // details 模式
    await tester.tap(find.byTooltip('视图模式'));
    await tester.pumpAndSettle();
    dump('details20', ListView);
    coordinator.updateProgress(currentSlot: 150, totalSlots: 300);
    await tester.pumpAndSettle();
    dump('details150', ListView);

    // list 模式
    await tester.tap(find.byTooltip('视图模式'));
    await tester.pumpAndSettle();
    dump('list150', ListView);
    coordinator.updateProgress(currentSlot: 20, totalSlots: 300);
    await tester.pumpAndSettle();
    dump('list20', ListView);

    expect(tester.takeException(), isNull);
  });
}
