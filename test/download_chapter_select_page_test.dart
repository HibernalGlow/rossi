import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/download/models/unified_comic_download.dart';
import 'package:zephyr/page/download/view/download.dart';

import 'test_helper.dart';

const _info = UnifiedComicDownloadInfo(
  source: 'plugin_a',
  comicId: 'comic_1',
  title: '测试漫画',
  chapters: [
    UnifiedComicDownloadChapter(id: 'ch-1', title: '第1话', order: 1),
    UnifiedComicDownloadChapter(id: 'ch-2', title: '第2话', order: 2),
    UnifiedComicDownloadChapter(id: 'ch-3', title: '第3话', order: 3),
  ],
);

Widget _app() => BlocProvider(
  create: (_) => GlobalSettingCubit(),
  child: MaterialApp(home: DownloadPage(downloadInfo: _info)),
);

/// 把第 2 话记成本地已下载（页里靠 uniqueKey 找到这条记录再按逻辑身份比对）。
void _markChapter2Downloaded() {
  objectbox.unifiedDownloadBox.put(
    createTestDownload('plugin_a:comic_1')
      ..chapters = jsonEncode([
        {'id': 'ch-2', 'logicalKey': 'ch-2', 'order': 2, 'title': '第2话'},
      ]),
  );
}

void main() {
  setUpAll(() async {
    await TestObjectBoxHelper.setUpTestObjectBox();
    LocaleSettings.setLocale(AppLocale.zhCn);
  });

  tearDownAll(TestObjectBoxHelper.tearDownTestObjectBox);

  setUp(() {
    objectbox.downloadTaskBox.removeAll();
    TestObjectBoxHelper.cleanComicFolderBoxes();
  });

  testWidgets('进页勾住第一个没下载过的，摘要报已选与本地已有', (tester) async {
    _markChapter2Downloaded();

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('已选 1 / 共 3 章'), findsOneWidget);
    expect(find.text('本地已有 1 章'), findsOneWidget);
    expect(find.text('第2话'), findsOneWidget);
  });

  testWidgets('反选把勾选翻面', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('已选 1 / 共 3 章'), findsOneWidget);
    await tester.tap(find.byTooltip('反选'));
    await tester.pumpAndSettle();

    expect(find.text('已选 2 / 共 3 章'), findsOneWidget);
  });

  testWidgets('全勾选到 3 章后按钮文案翻成取消全选', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 3 / 共 3 章'), findsOneWidget);
    expect(find.byTooltip('取消全选'), findsOneWidget);

    await tester.tap(find.byTooltip('取消全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 / 共 3 章'), findsOneWidget);
  });

  testWidgets('开跳过已下载：已下载那章从勾选里掉出去，行也点不动', (tester) async {
    _markChapter2Downloaded();

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 3 / 共 3 章'), findsOneWidget);

    await tester.tap(find.byTooltip('跳过已下载'));
    await tester.pumpAndSettle();

    expect(find.text('已选 2 / 共 3 章'), findsOneWidget);
    expect(find.textContaining('跳过已下载'), findsWidgets);

    // 被跳过的那一行点下去不该改变勾选。
    await tester.tap(find.text('第2话'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 / 共 3 章'), findsOneWidget);
  });

  testWidgets('没开跳过时，已下载那一章照样可选（跳过不是默认生效）', (tester) async {
    _markChapter2Downloaded();

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('第2话'));
    await tester.pumpAndSettle();

    expect(find.text('已选 2 / 共 3 章'), findsOneWidget);
  });
}
