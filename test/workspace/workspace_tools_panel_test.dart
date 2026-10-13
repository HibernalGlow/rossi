import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/workspace/widgets/containers/embedded_auxiliary_lane.dart';
import 'package:zephyr/workspace/widgets/tools/workspace_tools_panel.dart';

void main() {
  Widget subject({
    double width = 380,
    double height = 720,
    double scale = 1,
    int updates = 0,
    bool reduced = false,
    TextDirection direction = TextDirection.ltr,
    ValueChanged<WorkspaceTool>? onOpen,
  }) => MaterialApp(
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reduced,
      ),
      child: Directionality(textDirection: direction, child: child!),
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: height,
          child: WorkspaceToolsPanel(
            settingsSummary: '外观与反馈 · 阅读与画面\n跟随系统',
            updateCount: updates,
            onOpen: onOpen ?? (_) {},
          ),
        ),
      ),
    ),
  );

  Finder tool(WorkspaceTool tool) =>
      find.byKey(ValueKey('workspace-tool:${tool.name}'));

  testWidgets('设置在首屏顶部，其余入口完整可达', (tester) async {
    final opened = <WorkspaceTool>[];
    await tester.pumpWidget(subject(height: 400, onOpen: opened.add));
    await tester.pumpAndSettle();
    final rect = tester.getRect(tool(WorkspaceTool.settings));
    expect(rect.top, 16);
    expect(rect.bottom, lessThan(400));
    expect(find.byType(Image), findsNothing);
    await tester.tap(tool(WorkspaceTool.settings));
    expect(opened, [WorkspaceTool.settings]);
    for (final target in WorkspaceTool.values.skip(1)) {
      await tester.ensureVisible(tool(target));
      await tester.pumpAndSettle();
      await tester.tap(tool(target));
      await tester.pumpAndSettle();
      expect(opened.last, target);
      expect(tester.getSize(tool(target)).height, greaterThanOrEqualTo(48));
    }
    expect(opened, WorkspaceTool.values);
    expect(tester.takeException(), isNull);
  });

  testWidgets('分栏依据面板宽度，大字号和窄面板仍可操作', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(subject(width: 980));
    await tester.pumpAndSettle();
    final settings = tester.getRect(tool(WorkspaceTool.settings));
    final downloads = tester.getRect(tool(WorkspaceTool.downloads));
    expect(downloads.left, greaterThan(settings.right));
    for (final width in [240.0, 380.0]) {
      for (final direction in TextDirection.values) {
        final opened = <WorkspaceTool>[];
        await tester.pumpWidget(
          subject(
            width: width,
            scale: 2,
            height: 300,
            direction: direction,
            onOpen: opened.add,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final target in WorkspaceTool.values) {
          await tester.ensureVisible(tool(target));
          await tester.pumpAndSettle();
          await tester.tap(tool(target));
          expect(opened.last, target);
        }
        final primary = tester.getRect(tool(WorkspaceTool.settings));
        final common = tester.getRect(tool(WorkspaceTool.downloads));
        expect(common.top, greaterThan(primary.bottom));
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('追更徽标跟随真实数量，空时隐藏，超限不撑开行', (tester) async {
    for (final count in [0, 4, 140, 0]) {
      await tester.pumpWidget(subject(updates: count));
      await tester.pumpAndSettle();
      if (count == 0) {
        expect(find.byType(Badge), findsNothing);
      } else {
        expect(find.text(count > 99 ? '99+' : '$count'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('键盘首先到设置，Enter 可激活', (tester) async {
    final opened = <WorkspaceTool>[];
    await tester.pumpWidget(subject(onOpen: opened.add));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, [WorkspaceTool.settings]);
  });

  testWidgets('快捷入口沿用连续悬停，减少动画时立即反馈', (tester) async {
    await tester.pumpWidget(subject(width: 700, reduced: true));
    await tester.pumpAndSettle();
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    ActionBubblePainter painter() =>
        tester
                .widget<CustomPaint>(
                  find
                      .ancestor(
                        of: tool(WorkspaceTool.appearance),
                        matching: find.byWidgetPredicate(
                          (widget) =>
                              widget is CustomPaint &&
                              widget.foregroundPainter is ActionBubblePainter,
                        ),
                      )
                      .first,
                )
                .foregroundPainter!
            as ActionBubblePainter;
    await pointer.moveTo(tester.getCenter(tool(WorkspaceTool.appearance)));
    await tester.pump();
    final first = painter().rect();
    expect(painter().alpha(), 1);
    await pointer.moveTo(tester.getCenter(tool(WorkspaceTool.reader)));
    await tester.pump();
    expect(painter().rect(), isNot(first));
    expect(painter().alpha(), 1);
    await pointer.removePointer();
  });

  test('入口复用原页面路由，阅读仍使用共享弹层', () {
    final expected = {
      WorkspaceTool.settings: GlobalSettingRoute.name,
      WorkspaceTool.appearance: AppearanceSettingRoute.name,
      WorkspaceTool.layout: WorkspaceLayoutSettingRoute.name,
      WorkspaceTool.downloads: DownloadTaskRoute.name,
      WorkspaceTool.sync: SyncSettingRoute.name,
      WorkspaceTool.follow: ComicFollowRoute.name,
      WorkspaceTool.changelog: ChangelogRoute.name,
      WorkspaceTool.about: AboutRoute.name,
    };
    for (final entry in expected.entries) {
      expect(workspaceToolRoute(entry.key)?.routeName, entry.value);
    }
    expect(workspaceToolRoute(WorkspaceTool.reader), isNull);
    expect(t.settings.globalTitle, isNotEmpty);
  });
}
