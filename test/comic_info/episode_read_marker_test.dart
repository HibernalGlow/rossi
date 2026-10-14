import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/comic_info/models/chapter_read_state.dart';
import 'package:zephyr/page/comic_info/widgets/episode_read_mark_controller.dart';
import 'package:zephyr/page/comic_info/widgets/episode_read_marker.dart';
import 'package:zephyr/page/download/models/download_chapter.dart';
import 'package:zephyr/service/reader/chapter_read_mark_service.dart';

import '../test_helper.dart';

/// 「不打开章节就能标记」这条入口的端到端验证：手势 → 控制器 → 真库。
///
/// 只挂 [EpisodeReadMarker]，不整页起详情页（详情页要 bloc + 路由 + 插件数据）。
/// 判据一律落在库里，屏幕上的东西只用来确认「用户点得到」。
const _source = 'test';
const _comicId = '1';

DownloadChapter _chapter(int order) => DownloadChapter(
  id: 'c$order',
  displayName: '第 $order 话',
  order: order,
  extern: const {},
  images: const [],
);

void _seedBookmark(int chapterOrder) {
  final now = DateTime.utc(2026, 10, 13, 12);
  objectbox.unifiedHistoryBox.put(
    UnifiedComicHistory(
      uniqueKey: '$_source:$_comicId',
      source: _source,
      comicId: _comicId,
      title: 't',
      description: '',
      cover: '',
      creator: '',
      titleMeta: '[]',
      metadata: '[]',
      chapterId: 'c$chapterOrder',
      chapterTitle: '第 $chapterOrder 话',
      chapterOrder: chapterOrder,
      pageIndex: 1,
      createdAt: now,
      lastReadAt: now,
      updatedAt: now,
      deleted: false,
      schemaVersion: 2,
    ),
  );
}

Widget _host(EpisodeReadMarkController controller, DownloadChapter chapter, {
  required VoidCallback onMarkThroughRead,
}) {
  return MaterialApp(
    home: Scaffold(
      body: EpisodeReadMarker(
        controller: controller,
        chapter: chapter,
        onMarkThroughRead: onMarkThroughRead,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EpisodeReadMarkController controller;
  late List<DownloadChapter> chapters;

  setUpAll(TestObjectBoxHelper.setUpTestObjectBox);
  tearDownAll(TestObjectBoxHelper.tearDownTestObjectBox);

  setUp(() {
    objectbox.comicChapterReadMarkBox.removeAll();
    objectbox.unifiedHistoryBox.removeAll();
    _seedBookmark(3);
    chapters = List<DownloadChapter>.generate(6, (i) => _chapter(i + 1));
    controller = EpisodeReadMarkController();
    controller.attach(from: _source, comicId: _comicId);
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> pumpMarker(
    WidgetTester tester, {
    DownloadChapter? chapter,
    VoidCallback? onMarkThroughRead,
  }) {
    return tester.pumpWidget(
      _host(
        controller,
        chapter ?? chapters[2],
        onMarkThroughRead:
            onMarkThroughRead ??
            () => controller.markThroughRead(
              target: chapters[2],
              displayChapters: chapters,
              displayReversed: false,
            ),
      ),
    );
  }

  testWidgets('轻点标记槽位直接落库，不经过阅读器', (tester) async {
    await pumpMarker(tester);

    // 第 3 话书签推出来是已读 ⇒ 轻点应当落成「人为标未读」。
    await tester.tap(find.byType(EpisodeReadMarker));
    await tester.pumpAndSettle();

    final marks = ChapterReadMarkService.instance.marksOf(_source, _comicId);
    expect(marks['c3']?.markedRead, isFalse);
    expect(controller.stateOf(chapters[2]), ChapterReadState.manualUnread);
    // 书签没被这次点击挪动。
    expect(objectbox.unifiedHistoryBox.getAll().single.chapterOrder, 3);
  });

  testWidgets('长按开面板，选「至此为已读」把前缀全落库', (tester) async {
    await pumpMarker(tester);

    await tester.longPress(find.byType(EpisodeReadMarker));
    await tester.pumpAndSettle();

    // 面板必须真的把四个动作摆出来了（用户不用打开阅读器就能挑）。
    expect(find.text(t.comicInfo.markRead), findsOneWidget);
    expect(find.text(t.comicInfo.markUnread), findsOneWidget);
    expect(find.text(t.comicInfo.markThroughRead), findsOneWidget);
    expect(find.text(t.comicInfo.clearReadMark), findsOneWidget);

    await tester.tap(find.text(t.comicInfo.markThroughRead));
    await tester.pumpAndSettle();

    final marks = ChapterReadMarkService.instance.marksOf(_source, _comicId);
    expect(marks.keys.toList()..sort(), ['c1', 'c2', 'c3']);
    expect(marks.values.every((mark) => mark.markedRead), isTrue);
    expect(controller.stateOf(chapters[5]), ChapterReadState.unread);
  });

  testWidgets('面板里选「标记已读」压过书签推断', (tester) async {
    // 第 6 话在书签之后，本来是未读。
    await pumpMarker(tester, chapter: chapters[5]);
    expect(controller.stateOf(chapters[5]), ChapterReadState.unread);

    await tester.longPress(find.byType(EpisodeReadMarker));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.comicInfo.markRead));
    await tester.pumpAndSettle();

    expect(controller.stateOf(chapters[5]), ChapterReadState.manualRead);
    expect(
      ChapterReadMarkService.instance.marksOf(_source, _comicId)['c6']
          ?.markedRead,
      isTrue,
    );
    // 而「实际读到哪里」仍是第 3 话：两者是分开的两件事。
    expect(objectbox.unifiedHistoryBox.getAll().single.chapterOrder, 3);
  });
}
