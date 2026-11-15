import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_info/json/normal/normal_comic_all_info.dart';
import 'package:zephyr/page/comic_info/widgets/episode_download_controller.dart';
import 'package:zephyr/page/comic_info/widgets/eps.dart';
import 'package:zephyr/page/download/models/download_chapter.dart';
import 'package:zephyr/type/enum.dart';

import 'test_helper.dart';

void main() {
  setUpAll(TestObjectBoxHelper.setUpTestObjectBox);
  tearDownAll(TestObjectBoxHelper.tearDownTestObjectBox);
  tearDown(TestObjectBoxHelper.cleanComicFolderBoxes);

  Future<void> pumpRow(WidgetTester tester, {required bool isRead}) async {
    final controller = EpisodeDownloadController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EpButtonWidget(
            doc: const Ep(id: 'ch1', name: '第1话', order: 1),
            chapter: const DownloadChapter(
              id: 'ch1',
              displayName: '第1话',
              order: 1,
              extern: {},
              images: [],
            ),
            controller: controller,
            allInfo: null,
            epsLength: 1,
            type: ComicEntryType.normal,
            comicId: 'c1',
            from: 'src',
            index: 0,
            isReversed: false,
            isRead: isRead,
            downloadAllowed: false,
          ),
        ),
      ),
    );
  }

  testWidgets('已读章节标题置灰，未读章节保持正常字色', (tester) async {
    await LocaleSettings.setLocale(AppLocale.zhCn);

    await pumpRow(tester, isRead: true);
    final readTitle = tester.widget<Text>(find.text('第1话'));
    expect(readTitle.style?.color?.a, lessThan(1.0));
    expect(readTitle.style?.fontWeight, FontWeight.w500);

    await pumpRow(tester, isRead: false);
    final unreadTitle = tester.widget<Text>(find.text('第1话'));
    expect(unreadTitle.style?.color?.a, 1.0);
    expect(unreadTitle.style?.fontWeight, FontWeight.w600);
  });
}
