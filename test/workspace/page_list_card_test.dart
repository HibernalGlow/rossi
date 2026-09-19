import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/model/normal_comic_ep_info.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/workspace/widgets/cards/page_list_card.dart';

void main() {
  setUp(() {
    ReaderSessionCoordinator.instance.detachSession('test-comic');
  });

  tearDown(() {
    ReaderSessionCoordinator.instance.detachSession('test-comic');
  });

  testWidgets('PageListCard 在空会话下正常渲染且无断言失败', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
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
    expect(tester.takeException(), isNull);
    expect(find.text('打开书本后显示页面导航'), findsOneWidget);
  });

  testWidgets(
      'PageListCard 在活跃会话下正常渲染 active content (listWidget) 且无 shape/borderRadius 断言失败',
      (tester) async {
    final coordinator = ReaderSessionCoordinator.instance;
    coordinator.attachSession(
      comicId: 'test-comic',
      from: 'test',
      title: '测试漫画',
      epInfo: NormalComicEpInfo(
        epName: '第 1 话',
        docs: const [
          Doc(
            originalName: 'page1.jpg',
            path: 'p1',
            fileServer: 's1',
            id: '1',
          ),
          Doc(
            originalName: 'page2.jpg',
            path: 'p2',
            fileServer: 's1',
            id: '2',
          ),
        ],
      ),
      currentSlot: 0,
      totalSlots: 2,
      jumpToSlot: (_) async {},
    );

    await tester.pumpWidget(
      const MaterialApp(
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
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
