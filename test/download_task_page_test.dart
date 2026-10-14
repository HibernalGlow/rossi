import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/donwload_task/view/download_task.dart';
import 'package:zephyr/page/donwload_task/widgets/offline_comic_section.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/service/download/models/download_task_json.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry_surface.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view_mode.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_timeline_view.dart';

import 'test_helper.dart';

DownloadTask _task({
  required String chapterId,
  required String stateCode,
  required bool isDownloading,
  required String status,
  int completed = 0,
  int total = 0,
  int bytesPerSecond = 0,
  String comicId = 'comic/1',
  String comicName = '测试漫画',
}) {
  final payload = DownloadTaskJson(
    from: 'plugin-a',
    comicId: comicId,
    comicName: comicName,
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

/// 展开默认收起的下载设置卡。
Future<void> _expandSettings(WidgetTester tester) async {
  await tester.tap(find.text('下载设置'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await TestObjectBoxHelper.setUpTestObjectBox();
    LocaleSettings.setLocale(AppLocale.zhCn);
  });

  tearDownAll(() async {
    await TestObjectBoxHelper.tearDownTestObjectBox();
  });

  setUp(() {
    objectbox.downloadTaskBox.removeAll();
    TestObjectBoxHelper.cleanComicFolderBoxes();
    // 离线书架视图记在 SharedPreferences。
    SharedPreferences.setMockInitialValues({});
    // cubit 的写库路径固定读 id=1 那行；测试库里没有就按 main 的做法种一行。
    if (objectbox.userSettingBox.get(1) == null) {
      objectbox.userSettingBox.put(UserSetting());
    }
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
    // 行里的图标是自绘 Glyph（不是 Icon widget），所以按 tooltip 认动作。
    expect(find.byTooltip('暂停下载'), findsOneWidget);
    expect(find.byTooltip('继续下载'), findsOneWidget);
  });

  testWidgets('下载设置默认收成一行摘要，点开才是控件；页底列已离线漫画', (tester) async {
    // 夹具的 chapters / detailJson 都是空串：解析不出来只当没章节信息，不该炸列表。
    objectbox.unifiedDownloadBox.put(createTestDownload('plugin-a:comic/9'));

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 收起态只有一行摘要（默认 2 章 × 3 图，间隔 150 ms）。
    expect(find.text('下载设置'), findsOneWidget);
    expect(find.text('2 章 · 每章 3 图 · 间隔 150 ms'), findsOneWidget);
    expect(find.text('同时下载章节数'), findsNothing);

    await _expandSettings(tester);

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

  testWidgets('越界的存量并发数被钳到上限显示，预算提示跟着钳后的值算', (tester) async {
    final cubit = GlobalSettingCubit();
    addTearDown(cubit.close);
    cubit.updateState(
      (current) =>
          current.copyWith(downloadTaskConcurrency: 99, downloadConcurrency: 3),
    );

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: const MaterialApp(home: DownloadTaskPage()),
      ),
    );
    await tester.pumpAndSettle();
    await _expandSettings(tester);

    // 三个滑杆的顺序 = 同时下载章节数 / 单章节图片并发 / 单图下载延时。
    final chapterSlider = tester.widget<Slider>(find.byType(Slider).first);
    expect(chapterSlider.value, kMaxParallelChapters.toDouble());
    expect(chapterSlider.max, kMaxParallelChapters.toDouble());
    // 预算提示按钳制后的值算：10 章 × 3 图。
    expect(find.textContaining('当前最多同时请求 30 张图'), findsOneWidget);
  });

  testWidgets('拖动滑杆改并发数会写回全局设置', (tester) async {
    final cubit = GlobalSettingCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: const MaterialApp(home: DownloadTaskPage()),
      ),
    );
    await tester.pumpAndSettle();
    await _expandSettings(tester);

    final before = cubit.state.downloadTaskConcurrency;
    // 点在轨道中间：取值必然偏离默认值，且仍在合法区间内。
    await tester.tap(find.byType(Slider).first);
    await tester.pumpAndSettle();

    expect(cubit.state.downloadTaskConcurrency, isNot(before));
    expect(
      cubit.state.downloadTaskConcurrency,
      inInclusiveRange(1, kMaxParallelChapters),
    );
  });

  testWidgets('已离线漫画复用书架视图，切换列表和时间线都会改变内容', (tester) async {
    objectbox.unifiedDownloadBox.put(createTestDownload('plugin-a:comic/9'));
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
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final viewButton = find.byTooltip('视图模式：封面网格');
    await tester.ensureVisible(viewButton);
    expect(
      tester.widget<LibraryEntrySurface>(find.byType(LibraryEntrySurface)).mode,
      LibraryViewMode.coverGrid,
    );

    await tester.tap(viewButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('紧凑列表'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<LibraryEntrySurface>(find.byType(LibraryEntrySurface)).mode,
      LibraryViewMode.compact,
    );
    expect(find.byTooltip('视图模式：紧凑列表'), findsOneWidget);
    // 队列操作与离线库的视图各司其职。
    expect(find.byTooltip('暂停下载'), findsOneWidget);

    await tester.tap(find.byTooltip('按天看时间线'));
    await tester.pumpAndSettle();
    expect(find.byType(ShelfTimelineView), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);
    expect(
      tester.widget<LibraryEntrySurface>(find.byType(LibraryEntrySurface)).mode,
      LibraryViewMode.coverList,
    );

    await tester.tap(find.byTooltip('退出时间线'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<LibraryEntrySurface>(find.byType(LibraryEntrySurface)).mode,
      LibraryViewMode.compact,
    );
  });

  testWidgets('离线漫画长按仍可确认删除', (tester) async {
    final record = createTestDownload('plugin-a:comic/9');
    objectbox.unifiedDownloadBox.put(record);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(OfflineComicLibrary),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(LibraryEntrySurface));
    expect(find.byType(LibraryEntrySurface).hitTestable(), findsOneWidget);
    await tester.longPress(find.byType(LibraryEntrySurface));
    await tester.pumpAndSettle();

    expect(find.text(t.comicEntry.deleteDownload), findsOneWidget);
    await tester.tap(find.text(t.common.cancel));
    await tester.pumpAndSettle();
    expect(objectbox.unifiedDownloadBox.get(record.id), isNotNull);
  });

  testWidgets('失败行单独立区，区头带「重试失败项」', (tester) async {
    objectbox.downloadTaskBox.put(
      _task(
        chapterId: 'ch-bad',
        stateCode: 'failed',
        isDownloading: false,
        status: '失败',
      ),
    );
    objectbox.downloadTaskBox.put(
      _task(
        chapterId: 'ch-hold',
        stateCode: 'paused',
        isDownloading: false,
        status: '已暂停',
      ),
    );

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // 失败与等待分开计数，批量重试挂在失败那一区的区头上。
    expect(find.text('失败 (1)'), findsOneWidget);
    expect(find.text('重试失败项'), findsOneWidget);
    expect(find.text('等待中 (1)'), findsOneWidget);
  });

  testWidgets('没有失败行时不画失败区，也不给批量重试（阴性对照）', (tester) async {
    objectbox.downloadTaskBox.put(
      _task(
        chapterId: 'ch-hold',
        stateCode: 'paused',
        isDownloading: false,
        status: '已暂停',
      ),
    );

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('等待中 (1)'), findsOneWidget);
    expect(find.textContaining('失败 ('), findsNothing);
    expect(find.text('重试失败项'), findsNothing);
  });

  testWidgets('概览胶囊报整批的量，状态筛选只改看得见哪些行', (tester) async {
    // 夹具把 status 留空：行里会画 task.status，留了字就会和筛选胶囊撞名。
    objectbox.downloadTaskBox.put(
      _task(
        chapterId: 'ch-run',
        stateCode: 'running',
        isDownloading: true,
        status: '',
        completed: 8,
        total: 20,
      ),
    );
    objectbox.downloadTaskBox.put(
      _task(
        chapterId: 'ch-bad',
        stateCode: 'failed',
        isDownloading: false,
        status: '',
      ),
    );
    objectbox.downloadTaskBox.put(
      _task(
        chapterId: 'ch-hold',
        stateCode: 'paused',
        isDownloading: false,
        status: '',
      ),
    );
    objectbox.downloadTaskBox.put(
      _task(
        chapterId: 'ch-queue',
        stateCode: 'queued',
        isDownloading: false,
        status: '',
      ),
    );

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('还剩 4 章'), findsOneWidget);
    expect(find.text('失败 1 章'), findsOneWidget);
    // 页级总数只有报过章节页数的那一行贡献，另几行不掺数。
    expect(find.text('已下 8/20 页'), findsOneWidget);
    // 区只有三格（正在下载 / 失败 / 等待中）：暂停与排队的行同住「等待中」，
    // 但筛选胶囊是五档 —— 所以这里是 (2)，下面筛「等待中」只剩 (1)。
    expect(find.text('失败 (1)'), findsOneWidget);
    expect(find.text('等待中 (2)'), findsOneWidget);

    await tester.tap(find.text('失败'));
    await tester.pumpAndSettle();

    expect(find.text('失败 (1)'), findsOneWidget);
    expect(find.textContaining('等待中 ('), findsNothing);
    expect(find.byTooltip('暂停下载'), findsNothing);
    expect(find.byTooltip('继续下载'), findsNothing);
    // 概览不跟着筛选缩：它说的是「这批还有多少活」，筛完剩一行也还是 4 章没跑完。
    expect(find.text('还剩 4 章'), findsOneWidget);

    await tester.tap(find.text('等待中'));
    await tester.pumpAndSettle();

    // 「等待中」那一档不收已暂停的行（它有自己那颗胶囊），所以从 (2) 掉到 (1)。
    expect(find.text('等待中 (1)'), findsOneWidget);
    expect(find.byTooltip('继续下载'), findsNothing);
    expect(find.textContaining('失败 ('), findsNothing);
    // 批量重试挂在失败区的区头上，区不在了它也不该留在屏幕上。
    expect(find.text('重试失败项'), findsNothing);

    await tester.tap(find.text('已暂停'));
    await tester.pumpAndSettle();

    // 筛到已暂停时区头跟着换口径：那一行确实是暂停的，不叫「等待中」。
    expect(find.text('已暂停 (1)'), findsOneWidget);
    expect(find.textContaining('等待中 ('), findsNothing);
    expect(find.byTooltip('继续下载'), findsOneWidget);

    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();

    expect(find.text('失败 (1)'), findsOneWidget);
    expect(find.text('等待中 (2)'), findsOneWidget);
  });

  testWidgets('筛到空结果时提示「当前筛选没有任务」，而不是画一条空队列', (tester) async {
    objectbox.downloadTaskBox.put(
      _task(
        chapterId: 'ch-bad',
        stateCode: 'failed',
        isDownloading: false,
        status: '',
      ),
    );

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('暂无下载任务'), findsNothing);

    await tester.tap(find.text('已暂停'));
    await tester.pumpAndSettle();

    expect(find.text('当前筛选没有任务'), findsOneWidget);
    expect(find.textContaining('失败 ('), findsNothing);
    // 队列其实非空，所以不能走「暂无下载任务」那条空态文案。
    expect(find.text('暂无下载任务'), findsNothing);
    expect(find.text('还剩 1 章'), findsOneWidget);
  });

  testWidgets('队列跨多本时给一排漫画胶囊，点它就只看这一本', (tester) async {
    objectbox.downloadTaskBox.put(
      _task(
        chapterId: 'a-1',
        stateCode: 'queued',
        isDownloading: false,
        status: '',
        comicId: 'comic/a',
        comicName: '甲书',
      ),
    );
    objectbox.downloadTaskBox.put(
      _task(
        chapterId: 'a-2',
        stateCode: 'failed',
        isDownloading: false,
        status: '',
        comicId: 'comic/a',
        comicName: '甲书',
      ),
    );
    objectbox.downloadTaskBox.put(
      _task(
        chapterId: 'b-1',
        stateCode: 'queued',
        isDownloading: false,
        status: '',
        comicId: 'comic/b',
        comicName: '乙书',
      ),
    );

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('全部漫画'), findsOneWidget);
    expect(find.text('甲书（2 章）'), findsOneWidget);
    expect(find.text('乙书（1 章）'), findsOneWidget);
    expect(find.text('失败 (1)'), findsOneWidget);
    expect(find.text('等待中 (2)'), findsOneWidget);

    await tester.tap(find.text('乙书（1 章）'));
    await tester.pumpAndSettle();

    // 只看乙书：甲书那一章失败连带它的批量重试一起消失。
    expect(find.textContaining('失败 ('), findsNothing);
    expect(find.text('重试失败项'), findsNothing);
    expect(find.text('等待中 (1)'), findsOneWidget);
    expect(find.text('乙书 b-1'), findsOneWidget);
    expect(find.text('甲书 a-1'), findsNothing);
    // 胶囊本身不跟着缩：它们就是「换一本看」的入口，藏掉别的就回不去了。
    expect(find.text('甲书（2 章）'), findsOneWidget);
    // 概览说的是整批，不跟着这一排胶囊缩。
    expect(find.text('还剩 3 章'), findsOneWidget);

    await tester.tap(find.text('甲书（2 章）'));
    await tester.pumpAndSettle();

    expect(find.text('失败 (1)'), findsOneWidget);
    expect(find.text('等待中 (1)'), findsOneWidget);
    expect(find.text('甲书 a-1'), findsOneWidget);
    expect(find.text('乙书 b-1'), findsNothing);

    await tester.tap(find.text('全部漫画'));
    await tester.pumpAndSettle();

    expect(find.text('等待中 (2)'), findsOneWidget);
  });

  testWidgets('只有一本漫画时不画那排胶囊（阴性对照）', (tester) async {
    objectbox.downloadTaskBox.put(
      _task(
        chapterId: 'a-1',
        stateCode: 'queued',
        isDownloading: false,
        status: '',
        comicId: 'comic/a',
        comicName: '甲书',
      ),
    );
    objectbox.downloadTaskBox.put(
      _task(
        chapterId: 'a-2',
        stateCode: 'queued',
        isDownloading: false,
        status: '',
        comicId: 'comic/a',
        comicName: '甲书',
      ),
    );

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('全部漫画'), findsNothing);
    // 行照常画（标题里本来就带书名），少的那一排不该把别的也带走。
    expect(find.text('甲书 a-1'), findsOneWidget);
    expect(find.text('还剩 2 章'), findsOneWidget);
    expect(find.text('等待中 (2)'), findsOneWidget);
  });
}
