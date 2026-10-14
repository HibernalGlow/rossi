import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/comic_info/models/chapter_read_state.dart';
import 'package:zephyr/page/comic_info/widgets/episode_download_controller.dart';
import 'package:zephyr/page/comic_info/widgets/episode_read_mark_controller.dart';
import 'package:zephyr/page/comic_info/widgets/episode_selection_action_bar.dart';
import 'package:zephyr/page/download/models/download_chapter.dart';
import 'package:zephyr/service/reader/chapter_read_mark_service.dart';

import '../test_helper.dart';

/// 多选底栏「批量改阅读状态」这条入口的端到端验证：
/// 勾选若干章 → 点底栏按钮 → 落进真库；没勾选时按钮必须是死的。
///
/// 底栏从前 part 里抽成了 `EpisodeSelectionActionBar`，就是为了这里能真的
/// 构造它并点它 —— part 内的私有类在测试里拿不到。
const _source = 'test';
const _comicId = '1';

DownloadChapter _chapter(int order) => DownloadChapter(
  id: 'c$order',
  displayName: '第 $order 话',
  order: order,
  extern: const {},
  images: const [],
);

IconButton _button(WidgetTester tester, String tooltip) {
  final found = tester.widget<IconButton>(
    find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == tooltip,
    ),
  );
  return found;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EpisodeDownloadController dlController;
  late EpisodeReadMarkController readController;
  late List<DownloadChapter> chapters;

  setUpAll(TestObjectBoxHelper.setUpTestObjectBox);
  tearDownAll(TestObjectBoxHelper.tearDownTestObjectBox);

  setUp(() {
    objectbox.comicChapterReadMarkBox.removeAll();
    objectbox.unifiedHistoryBox.removeAll();
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
        chapterId: 'c2',
        chapterTitle: '第 2 话',
        chapterOrder: 2,
        pageIndex: 1,
        createdAt: now,
        lastReadAt: now,
        updatedAt: now,
        deleted: false,
        schemaVersion: 2,
      ),
    );
    chapters = List<DownloadChapter>.generate(5, (i) => _chapter(i + 1));
    dlController = EpisodeDownloadController();
    readController = EpisodeReadMarkController();
    readController.attach(from: _source, comicId: _comicId);
    dlController.lastChapters = chapters;
  });

  tearDown(() {
    dlController.dispose();
    readController.dispose();
  });

  Future<void> pumpBar(WidgetTester tester) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EpisodeSelectionActionBar(
            controller: dlController,
            readController: readController,
            isDownloadType: false,
            inline: true,
          ),
        ),
      ),
    );
  }

  testWidgets('选中两章后点「标记已读」，两章一起落库', (tester) async {
    dlController.enterSelection('c2');
    dlController.toggleSelect('c4');
    await pumpBar(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(t.comicInfo.markRead));
    await tester.pumpAndSettle();

    final marks = ChapterReadMarkService.instance.marksOf(_source, _comicId);
    expect(marks.keys.toList()..sort(), ['c2', 'c4']);
    expect(marks.values.every((mark) => mark.markedRead), isTrue);
    expect(readController.stateOf(chapters[3]), ChapterReadState.manualRead);
    // 书签仍停在第 2 话：批量标记不推进「实际读到哪里」。
    expect(objectbox.unifiedHistoryBox.getAll().single.chapterOrder, 2);
  });

  testWidgets('点「标记未读」能把读到过的章显式拉回未读', (tester) async {
    // c2 在书签之内，本来是推断已读。
    expect(readController.stateOf(chapters[1]), ChapterReadState.inferredRead);

    dlController.enterSelection('c2');
    await pumpBar(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(t.comicInfo.markUnread));
    await tester.pumpAndSettle();

    expect(readController.stateOf(chapters[1]), ChapterReadState.manualUnread);
    expect(
      ChapterReadMarkService.instance.marksOf(_source, _comicId)['c2']
          ?.markedRead,
      isFalse,
    );
  });

  testWidgets('没选中任何章时，两个标记按钮都是死的', (tester) async {
    // inline 变体在非多选态整个不进树，所以这条要挂非 inline 那份（底部浮条），
    // 它靠 IgnorePointer + 移出屏幕来「在场但不可用」。
    dlController.enterSelection('c2');
    dlController.exitSelection();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              EpisodeSelectionActionBar(
                controller: dlController,
                readController: readController,
                isDownloadType: false,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_button(tester, t.comicInfo.markRead).onPressed, isNull);
    expect(_button(tester, t.comicInfo.markUnread).onPressed, isNull);
  });

  testWidgets('插件不允许下载时，标记仍可用而下载/删除是死的', (tester) async {
    // attach 才会落 allowDownload；这里直接给一条不允许下载的详情数据。
    dlController.attach(
      from: _source,
      comicId: _comicId,
      comicTitle: 't',
      allowDownload: false,
    );
    dlController.lastChapters = chapters;
    dlController.enterSelection('c3');
    await pumpBar(tester);
    await tester.pumpAndSettle();

    expect(_button(tester, t.comicInfo.download).onPressed, isNull);
    expect(_button(tester, t.common.delete).onPressed, isNull);
    expect(_button(tester, t.comicInfo.markRead).onPressed, isNotNull);

    await tester.tap(find.byTooltip(t.comicInfo.markRead));
    await tester.pumpAndSettle();
    expect(
      ChapterReadMarkService.instance.marksOf(_source, _comicId).containsKey('c3'),
      isTrue,
    );
  });
}
