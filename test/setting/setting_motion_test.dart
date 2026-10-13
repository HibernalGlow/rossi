import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/setting/common/setting_browser.dart';
import 'package:zephyr/page/setting/common/setting_route.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/popup_panel.dart';

void main() {
  Widget host({bool reduced = false}) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
      child: child!,
    ),
    home: Scaffold(
      body: SettingBrowser(
        summary: '',
        groups: [
          SettingDestinationGroup(
            title: '分组',
            entries: [
              for (final (id, label) in [('a', '外观'), ('b', '文件')])
                SettingDestination(
                  id: id,
                  title: label,
                  subtitle: '',
                  icon: AppGlyphs.settings,
                  onOpen: () {},
                  detailBuilder: (_) => TextField(key: ValueKey('input-$id')),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  Future<void> viewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  ActionBubblePainter bubble(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.foregroundPainter)
      .whereType<ActionBubblePainter>()
      .first;

  testWidgets('分类高亮连续移动，途中反向不跳位；切换保留详情编辑状态', (tester) async {
    await viewport(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('外观')));
    await tester.pumpAndSettle();
    final first = bubble(tester).rect();
    await mouse.moveTo(tester.getCenter(find.text('文件')));
    await tester.pump();
    expect(bubble(tester).rect(), first);
    await tester.pump(const Duration(milliseconds: 80));
    final travelling = bubble(tester).rect();
    expect(travelling.center.dy, greaterThan(first.center.dy));
    await mouse.moveTo(tester.getCenter(find.text('外观')));
    await tester.pump();
    expect(bubble(tester).rect().center.dy, closeTo(travelling.center.dy, .01));
    await tester.pumpAndSettle();
    expect(bubble(tester).rect().center.dy, closeTo(first.center.dy, .01));
    await mouse.removePointer();
    await tester.enterText(find.byKey(const ValueKey('input-a')), '保留的内容');
    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();
    expect(find.text('保留的内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('减少动画时悬停立即落位，不留下弹簧帧', (tester) async {
    await viewport(tester);
    await tester.pumpWidget(host(reduced: true));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('外观')));
    await tester.pump();
    final first = bubble(tester).rect();
    await mouse.moveTo(tester.getCenter(find.text('文件')));
    await tester.pump();
    expect(bubble(tester).rect().center.dy, greaterThan(first.center.dy));
    final landed = bubble(tester).rect();
    await tester.pump(const Duration(milliseconds: 200));
    expect(bubble(tester).rect(), landed);
    await mouse.removePointer();
  });

  testWidgets('居中确认框与设置子页面使用统一弹层，返回保护仍生效', (tester) async {
    CommonPopupRoute<void>? page;
    var prevented = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => showPopupPanel<void>(
                    context: context,
                    builder: (_) => const PopupPanel(content: Text('确认内容')),
                  ),
                  child: const Text('确认'),
                ),
                TextButton(
                  onPressed: () {
                    page = settingPageRoute<void>(
                      context: context,
                      builder: (context) => PopScope(
                        canPop: false,
                        onPopInvokedWithResult: (didPop, result) =>
                            prevented = !didPop,
                        child: const Scaffold(body: Text('受保护的页面')),
                      ),
                    );
                    Navigator.of(context).push(page!);
                  },
                  child: const Text('子页面'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    final route = ModalRoute.of(tester.element(find.text('确认内容')));
    expect(route, isA<CommonPopupRoute<void>>());
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(
      tester.getRect(find.byType(PopupPanel)).center,
      screen.center(Offset.zero),
    );
    Navigator.of(tester.element(find.text('确认内容'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('子页面'));
    await tester.pumpAndSettle();
    expect(page!.fullscreen, isTrue);
    await Navigator.of(tester.element(find.text('受保护的页面'))).maybePop();
    await tester.pumpAndSettle();
    expect(prevented, isTrue);
    expect(find.text('受保护的页面'), findsOneWidget);
  });
}
