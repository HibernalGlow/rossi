import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/donwload_task/view/download_task.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/service/download/models/download_task_json.dart';

import 'test_helper.dart';

DownloadTask _task({
  required String chapterId,
  required String stateCode,
  required bool isDownloading,
  required String status,
  int completed = 0,
  int total = 0,
  int bytesPerSecond = 0,
}) {
  final payload = DownloadTaskJson(
    from: 'plugin-a',
    comicId: 'comic/1',
    comicName: '测试漫画',
    chapterRef: DownloadChapterTaskRef(
      chapterId: chapterId,
      title: chapterId,
      order: 1,
    ),
    stateCode: stateCode,
    completedImages: completed,
    totalImages: total,
    bytesPerSecond: bytesPerSecond,
  );
  return DownloadTask()
    ..comicId = payload.comicId
    ..comicName = payload.comicName
    ..isCompleted = false
    ..isDownloading = isDownloading
    ..status = status
    ..taskInfo = payload;
}

/// 下载设置卡读的是全局设置 cubit，页面外必须给它一个 provider。
Widget _app() => BlocProvider(
  create: (_) => GlobalSettingCubit(),
  child: const MaterialApp(home: DownloadTaskPage()),
);

void main() {
  setUpAll(() async {
    await TestObjectBoxHelper.setUpTestObjectBox();
    LocaleSettings.setLocale(AppLocale.zhCn);
  });

  tearDownAll(() async {
    await TestObjectBoxHelper.tearDownTestObjectBox();
  });

  tearDown(() {
    objectbox.downloadTaskBox.removeAll();
    TestObjectBoxHelper.cleanComicFolderBoxes();
  });

  testWidgets('下载中显示页数/速度与暂停按钮，暂停任务显示继续按钮', (tester) async {
    objectbox.downloadTaskBox.put(
      _task(
        chapterId: 'ch-1',
        stateCode: 'running',
        isDownloading: true,
        status: '下载中',
        completed: 12,
        total: 45,
        bytesPerSecond: 1536,
      ),
    );
    objectbox.downloadTaskBox.put(
      _task(
        chapterId: 'ch-2',
        stateCode: 'paused',
        isDownloading: false,
        status: '已暂停',
        completed: 30,
        total: 45,
      ),
    );

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('已下载 12/45 页 · 2 KB/s'), findsOneWidget);
    // 暂停的任务保留页数，但不显示过期速度。
    expect(find.text('已下载 30/45 页'), findsOneWidget);
    // 各一个：下载中 tile 的暂停按钮、暂停 tile 的暂停头像、暂停 tile 的继续按钮。
    expect(find.byIcon(Icons.pause_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('页顶就是下载设置，页底列出已离线漫画', (tester) async {
    // 夹具的 chapters / detailJson 都是空串：解析不出来只当没章节信息，不该炸列表。
    objectbox.unifiedDownloadBox.put(createTestDownload('plugin-a:comic/9'));

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('下载设置'), findsOneWidget);
    expect(find.text('同时下载章节数'), findsOneWidget);
    expect(find.text('单图下载延时'), findsOneWidget);
    expect(find.textContaining('当前最多同时请求'), findsOneWidget);

    expect(find.text('已离线漫画'), findsOneWidget);
    expect(find.text('Test Comic plugin-a:comic/9'), findsOneWidget);
  });

  testWidgets('没有下载记录时，离线区显示空态而不是消失', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('已离线漫画'), findsOneWidget);
    expect(find.text('还没有已下载的漫画'), findsOneWidget);
  });

  testWidgets('输入越界的并发数会被钳制、落库，预算提示跟着变', (tester) async {
    // cubit 的写库路径固定读 id=1 那行；测试库里没有就按 main 的做法种一行。
    if (objectbox.userSettingBox.get(1) == null) {
      objectbox.userSettingBox.put(UserSetting());
    }
    final cubit = GlobalSettingCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: const MaterialApp(home: DownloadTaskPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 三个框的顺序 = 同时下载章节数 / 单章节图片并发 / 单图下载延时。
    await tester.enterText(find.byType(TextField).first, '99');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(cubit.state.downloadTaskConcurrency, kMaxParallelChapters);
    final committed = tester
        .widgetList<TextField>(find.byType(TextField))
        .first
        .controller!
        .text;
    expect(committed, '$kMaxParallelChapters');
    // 预算提示按钳制后的值算：10 章 × 3 图。
    expect(find.textContaining('当前最多同时请求 30 张图'), findsOneWidget);
  });
}
