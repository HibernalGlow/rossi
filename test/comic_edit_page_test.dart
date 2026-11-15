import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/comic_edit/method/comic_edit_debug.dart';
import 'package:zephyr/page/comic_edit/view/comic_edit_page.dart';
import 'package:zephyr/util/get_path.dart';
import 'package:zephyr/util/rust_loader.dart';

import 'test_helper.dart';

Map<String, dynamic> _detail() => <String, dynamic>{
  'comicInfo': <String, dynamic>{
    'id': 'c1',
    'title': 'Original',
    'description': '',
    'cover': <String, dynamic>{
      'id': 'cover',
      'url': '',
      'name': '',
      'path': '',
      'extern': <String, dynamic>{},
    },
  },
  'eps': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'ch1',
      'name': '第1话',
      'order': 1,
      'requestId': 'r1',
      'storageChapterId': 's1',
      'logicalKey': 'ch1',
      'groupTitle': '',
      'extern': <String, dynamic>{},
    },
  ],
  'extern': <String, dynamic>{},
};

List<Map<String, dynamic>> _chapters() => <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 's1',
    'name': '第1话',
    'order': 1,
    'logicalKey': 'ch1',
    'taskChapterId': 'r1',
    'storageChapterId': 's1',
    'groupTitle': '',
    'images': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'i1',
        'name': '1.png',
        'path': 'p1',
        'url': '',
        'extern': <String, dynamic>{},
      },
    ],
  },
];

void main() {
  late Directory downloadRoot;

  Future<void> settleImages(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pumpAndSettle();
  }

  setUpAll(() async {
    await initRustLib(silent: true);
    await TestObjectBoxHelper.setUpTestObjectBox();
    debugComicEditImagePathResolver = ({
      required String from,
      required String comicId,
      required String storageChapterId,
      required String path,
    }) async => '';
    downloadRoot = await Directory.systemTemp.createTemp('breeze_edit_page_');
    debugDownloadRootPath = downloadRoot.path;
  });

  tearDownAll(() async {
    debugComicEditImagePathResolver = null;
    debugDownloadRootPath = null;
    if (await downloadRoot.exists()) {
      await downloadRoot.delete(recursive: true);
    }
    await TestObjectBoxHelper.tearDownTestObjectBox();
  });

  setUp(() {
    objectbox.unifiedDownloadBox.removeAll();
    objectbox.downloadTaskBox.removeAll();
    final record = createTestDownload('test:c1')
      ..comicId = 'c1'
      ..title = 'Original'
      ..chapters = jsonEncode(_chapters())
      ..detailJson = jsonEncode(_detail());
    objectbox.unifiedDownloadBox.put(record);
  });

  testWidgets('编辑页渲染三个 Tab 与标题', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ComicEditPage(from: 'test', comicId: 'c1'),
      ),
    );
    await settleImages(tester);

    expect(find.text('编辑漫画'), findsOneWidget);
    expect(find.text('基本信息'), findsOneWidget);
    expect(find.text('章节'), findsOneWidget);
    expect(find.text('图片'), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);

    await tester.tap(find.text('章节'));
    await tester.pumpAndSettle();
    expect(find.text('第1话'), findsWidgets);

    await tester.tap(find.text('图片'));
    await settleImages(tester);
    await tester.tap(find.byKey(const ValueKey('p1')));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 张'), findsOneWidget);
    expect(find.byIcon(Icons.drive_file_move_outline), findsOneWidget);
  });

  testWidgets('宽屏使用左右分栏且不显示 Tab', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: ComicEditPage(from: 'test', comicId: 'c1'),
      ),
    );
    await settleImages(tester);

    expect(find.byType(TabBar), findsNothing);
    expect(find.text('章节'), findsOneWidget);
    expect(find.text('基本信息'), findsNothing);
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('第1话'), findsWidgets);
  });
}
