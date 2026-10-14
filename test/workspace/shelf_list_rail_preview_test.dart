import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_list_chip.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_list_rail.dart';

/// 书签分类轨的渲染台：把静止 / 悬停 / 选中三档出图，用眼睛复核尺读不出来的
/// 东西（轮廓读不读得通「这是一档筛选」、收平时文字有没有被啃）。
///
/// 出图口径与 `library_settings_preview_test.dart` 同一套路：
/// `ROSSI_UI_PREVIEW_DIR=<目录> flutter test test/workspace/shelf_list_rail_preview_test.dart`，
/// 一张图一个 test（一次 run 里多个 `toImage` 会串图），字体手注册
/// （test 不加载 pubspec 字体，中文会成方块）。
Future<void> _pumpRail(
  WidgetTester tester, {
  required Size size,
  required bool dark,
  required List<String> lists,
  required int selected,
  required GlobalKey boundary,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final font = FontLoader('PreviewChinese')
    ..addFont(rootBundle.load('asset/fonts/LXGWWenKaiLite-Regular.ttf'));
  await font.load();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff81505c),
          brightness: dark ? Brightness.dark : Brightness.light,
        ),
        fontFamily: 'PreviewChinese',
      ),
      home: Scaffold(
        // 自己包一层并给 key：框架内部也有若干 RepaintBoundary，取「第一个」
        // 会拍到整棵树而不是这条轨。
        body: RepaintBoundary(
          key: boundary,
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: SizedBox(
                width: size.width - 20,
                child: ShelfListRail(
                  onCreate: () {},
                  onEdit: () {},
                  children: [
                    for (final (index, name) in lists.indexed)
                      ShelfListChip(
                        label: name,
                        identity: '/$name',
                        selected: index == selected,
                        onTap: () {},
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _dump(WidgetTester tester, GlobalKey boundary, String name) async {
  final output = Platform.environment['ROSSI_UI_PREVIEW_DIR'];
  if (output == null) return;
  final renderObject =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await renderObject.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

const _lists = ['全部', '未分类', '阅读计划', '深夜', '月光旅行者', '星河之间'];

void main() {
  testWidgets('出图：静止态（六档各不相同的不规则轮廓）', (tester) async {
    final boundary = GlobalKey();
    await _pumpRail(
      tester,
      size: const Size(560, 260),
      dark: false,
      lists: _lists,
      selected: 0,
      boundary: boundary,
    );
    await _dump(tester, boundary, 'shelf_rail_rest');
    expect(tester.takeException(), isNull);
  });

  testWidgets('出图：悬停态（收成一半并鼓起）', (tester) async {
    final boundary = GlobalKey();
    await _pumpRail(
      tester,
      size: const Size(560, 260),
      dark: false,
      lists: _lists,
      selected: 0,
      boundary: boundary,
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(-400, -400));
    addTearDown(gesture.removePointer);
    // 悬停第三档（「阅读计划」），让收平与鼓起都落在画面上。
    await gesture.moveTo(tester.getCenter(find.text('阅读计划')));
    // 固定帧数而不是 pumpAndSettle：要拍的是「正在回弹」途中那一帧。
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await _dump(tester, boundary, 'shelf_rail_hover');
    expect(tester.takeException(), isNull);
  });

  testWidgets('出图：暗色，选中档收成 stadium', (tester) async {
    final boundary = GlobalKey();
    await _pumpRail(
      tester,
      size: const Size(560, 260),
      dark: true,
      lists: _lists,
      selected: 4,
      boundary: boundary,
    );
    await _dump(tester, boundary, 'shelf_rail_dark_selected');
    expect(tester.takeException(), isNull);
  });
}
