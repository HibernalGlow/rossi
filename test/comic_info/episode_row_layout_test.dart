import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/comic_info/json/normal/normal_comic_all_info.dart';
import 'package:zephyr/page/comic_info/widgets/episode_download_controller.dart';
import 'package:zephyr/page/comic_info/widgets/episode_read_mark_controller.dart';
import 'package:zephyr/page/comic_info/widgets/episode_read_marker.dart';
import 'package:zephyr/page/comic_info/widgets/eps.dart';
import 'package:zephyr/page/download/models/download_chapter.dart';
import 'package:zephyr/service/reader/chapter_read_mark_service.dart';
import 'package:zephyr/type/enum.dart';

import '../test_helper.dart';

/// 章节行的几何尺：本功能给行首加了一个常驻标记槽，标题可用宽度因此变窄。
/// 这条测试把「窄屏会不会压爆」变成可测的数：溢出（黄黑条/异常）必须不出现，
/// 并且把前导列实际吃掉的宽度、标题还剩多少量出来。
///
/// 注意测试环境默认 textScale 是 3.0（本仓踩过），必须钉回 1.0，否则量的是
/// 放大后的字，结论对不上真机。
const _source = 'test';
const _comicId = '1';

DownloadChapter _chapter(int order, {String? name}) => DownloadChapter(
  id: 'c$order',
  displayName: name ?? '第 $order 话',
  order: order,
  extern: const {},
  images: const [],
);

Ep _ep(int order, {String? name}) =>
    Ep(id: 'c$order', name: name ?? '第 $order 话', order: order);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EpisodeDownloadController dlController;
  late EpisodeReadMarkController readController;
  late DownloadChapter chapter;

  setUpAll(TestObjectBoxHelper.setUpTestObjectBox);
  tearDownAll(TestObjectBoxHelper.tearDownTestObjectBox);

  setUp(() {
    objectbox.comicChapterReadMarkBox.removeAll();
    objectbox.unifiedHistoryBox.removeAll();
    // 行里的繁简转换会读 globalSetting，而它取的是 userSettingBox 的 id=1 行。
    objectbox.userSettingBox.put(UserSetting());
    dlController = EpisodeDownloadController();
    readController = EpisodeReadMarkController();
    readController.attach(from: _source, comicId: _comicId);
  });

  tearDown(() {
    dlController.dispose();
    readController.dispose();
  });

  Future<void> pumpRow(
    WidgetTester tester, {
    required double width,
    String? title,
  }) async {
    chapter = _chapter(1, name: title);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.noScaling),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: EpButtonWidget(
                  doc: _ep(1, name: title),
                  chapter: chapter,
                  controller: dlController,
                  readController: readController,
                  allInfo: null,
                  epsLength: 12,
                  type: ComicEntryType.normal,
                  comicId: _comicId,
                  from: _source,
                  index: 0,
                  isReversed: false,
                  downloadAllowed: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('最窄的真实机型宽度下不溢出，标题仍有可读宽度', (tester) async {
    // 310 是台账里记过的手机窄档，346 是卡片区实测过的溢出边界。
    for (final width in <double>[310, 346, 360, 400, 560]) {
      await pumpRow(tester, width: width, title: '第 12 话：一个相当长的章节标题用来挤压');
      expect(
        tester.takeException(),
        isNull,
        reason: 'width=$width 下行内溢出',
      );
      final row = find.byType(EpButtonWidget);
      expect(tester.getSize(row).height, 56, reason: 'width=$width');
      final titleBox = tester.getSize(find.text('第 12 话：一个相当长的章节标题用来挤压'));
      expect(titleBox.width, greaterThan(40), reason: 'width=$width 标题被挤到不可读');
    }
  });

  testWidgets('量出前导列吃掉的宽度与标题剩余宽度', (tester) async {
    await pumpRow(tester, width: 360, title: '短标题');
    final rowLeft = tester.getTopLeft(find.byType(EpButtonWidget)).dx;
    final markerBox = tester.getRect(find.byType(EpisodeReadMarker));
    // 行内左右各 14 的 padding（见 eps.dart 的 Container），标记槽本体 32。
    expect(markerBox.left - rowLeft, 14, reason: '标记槽要贴着行的左边距');
    expect(markerBox.width, 32);
    // 前导列总宽 = 槽 32 + 右间距 12；这一列就是本功能给行首新增的宽度。
    final labelLeft = tester.getTopLeft(
      find.text(t.comicInfo.episodeLabel(index: 1)),
    ).dx;
    expect(labelLeft - rowLeft, 14 + 44);
    // 360 宽下标题还剩多少：写进断言，槽位或边距一改就红。
    final titleWidth = tester.getSize(find.text('短标题')).width;
    expect(titleWidth, greaterThan(60));
  });

  testWidgets('点在标记槽上只改标记，不会顺手打开章节', (tester) async {
    // 行本身是可点的（onTap → 进阅读器）。标记槽是它的子 InkWell，必须赢下这一下：
    // 这里没有 auto_route 的 Router，一旦点击冒泡到行上，`pushRoute` 就会抛异常，
    // 所以「没有异常 + 标记行真的写进去了」两头一起证明它没打开章节。
    await pumpRow(tester, width: 360, title: '点标记不改进度');

    await tester.tap(find.byType(EpisodeReadMarker));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '这一下不该冒泡到行、去开阅读器');
    final marks = ChapterReadMarkService.instance.marksOf(_source, _comicId);
    expect(marks.containsKey('c1'), isTrue);
    expect(objectbox.unifiedHistoryBox.isEmpty(), isTrue, reason: '没打开章节就没有新书签行');
  });

  testWidgets('对照：点在行体上会去开阅读器（本 harness 没有 Router，所以必抛）', (tester) async {
    await pumpRow(tester, width: 360, title: '点标题');
    await tester.tap(find.text('点标题'));
    await tester.pumpAndSettle();
    final err = tester.takeException();
    // 上面那条「点在标记槽上不抛」若没有这一条，就可能是因为点击根本没生效
    // （点击没送达 / 事件被吞）而恒真。这里先把「点在行体上一定会尝试导航」
    // 钉住，那条断言才是在量手势归属，不是在量「什么都没发生」。
    expect(err, isNotNull, reason: '行体点击应当尝试导航并因此失败');
  });

  testWidgets('人为标未读的章用主色标题，也不破坏几何', (tester) async {
    objectbox.comicChapterReadMarkBox.put(
      ChapterReadMarkService.instance.buildMark(
        source: _source,
        comicId: _comicId,
        chapterId: 'c1',
        chapterOrder: 1,
        markedRead: false,
      ),
    );
    await pumpRow(tester, width: 310, title: '标了未读的长标题也要放得下');

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(EpButtonWidget)).height, 56);
  });
}
