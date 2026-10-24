import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/workspace/mobile/reader_info_sheet.dart';
import 'package:zephyr/workspace/mobile/workspace_mobile_card_page.dart';
import 'package:zephyr/workspace/mobile/workspace_mobile_home_page.dart';
import 'package:zephyr/workspace/mobile/workspace_mobile_insights_page.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/registry/workspace_ids.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';

import '../test_helper.dart';

/// 移动端三页的组成测试：首页展开态、阅读数据页（洞察 8 卡复用）、
/// 单卡整页宿主。这里验「宿主装的是注册表里那张卡」，卡片内部的
/// 三态（加载 / 空 / 错）由 `HistoryInsightsWindow` 自己的链路负责。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(TestObjectBoxHelper.setUpTestObjectBox);
  tearDownAll(TestObjectBoxHelper.tearDownTestObjectBox);
  setUp(() {
    TestObjectBoxHelper.cleanComicFolderBoxes();
  });

  Widget host(Widget child) => BlocProvider<GlobalSettingCubit>(
    // 首页「阅读工具」区嵌入的控制面板三卡要读全局设置
    // (生产里由 main.dart 根部提供)。
    create: (_) => GlobalSettingCubit(),
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(body: child),
    ),
  );

  Finder card(String id) =>
      find.byWidgetPredicate((w) => w is CollapsibleCard && w.cardId == id);

  testWidgets('首页：无历史时 hero 走空态，区块与入口齐全', (tester) async {
    await tester.pumpWidget(host(const WorkspaceMobileHomePage()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(t.workspace.workspaceHome), findsOneWidget);
    expect(find.text(t.workspace.noReadingYet), findsOneWidget);
    expect(find.text(t.workspace.readingInsights), findsOneWidget);
    expect(find.text(t.workspace.readingHistory), findsOneWidget);
    expect(find.text(t.workspace.fileManagement), findsOneWidget);
    // 阅读工具区嵌入的是控制面板那三张卡(经注册表 builder),
    // 不再是通往设置页的入口行。
    expect(
      card(WorkspaceCardRegistry.superResolution),
      findsOneWidget,
      reason: '超分卡应作为阅读工具的展开态嵌在首页',
    );
    expect(card(WorkspaceCardRegistry.translate), findsOneWidget);
    expect(card(WorkspaceCardRegistry.imageTuning), findsOneWidget);
  });

  testWidgets('首页：有历史时 hero 露出书名与继续入口', (tester) async {
    objectbox.unifiedHistoryBox.put(createTestHistory('widget-home-1'));
    await tester.pumpWidget(host(const WorkspaceMobileHomePage()));
    await tester.pump(const Duration(milliseconds: 100));

    // 书名出现两处是设计使然：hero 标题行 + 封面占位块上的书名。
    expect(find.text('Test Comic widget-home-1'), findsWidgets);
    // hero 标签是「继续阅读 · <相对日期>」拼接串。
    expect(find.textContaining(t.workspace.continueReading), findsOneWidget);
  });

  testWidgets('阅读数据页：洞察面板的 8 张卡全部上屏', (tester) async {
    // 只走 pumpWidget 这一帧：这里验「8 张卡的外壳都在」，数据窗口的
    // 三态转换（骨架 → 数据的 AnimatedSize 尺寸过渡）不在本页职责内，
    // 多余的一帧在 widget 测试环境里会触发 RenderAnimatedSize 布局断言。
    await tester.pumpWidget(host(const WorkspaceMobileInsightsPage()));

    const board = WorkspaceBoardLayout();
    final cards = WorkspaceCardRegistry.I.cardsForPanel(
      WorkspacePanelId.insights,
      board,
    );
    expect(cards.length, 8);
    for (final def in cards) {
      expect(
        card(def.id),
        findsOneWidget,
        reason: '洞察卡 ${def.id} 应当在移动数据页上',
      );
    }
  });

  testWidgets('单卡宿主：reading_streak 整页复用注册表卡片', (tester) async {
    await tester.pumpWidget(
      host(
        const WorkspaceMobileCardPage(
          cardId: WorkspaceCardRegistry.readingStreak,
        ),
      ),
    );

    expect(card(WorkspaceCardRegistry.readingStreak), findsOneWidget);
  });

  testWidgets('Reader 信息底部面板：信息面板五张卡全部在册', (tester) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showReaderInfoBottomSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    const board = WorkspaceBoardLayout();
    final cards = WorkspaceCardRegistry.I.cardsForPanel(
      WorkspacePanelId.info,
      board,
    );
    expect(cards.length, 5);
    // 面板高度不足五张卡，ListView 惰性构建 —— 逐卡滚动到可见再断言。
    final scrollable = find
        .descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    for (final def in cards) {
      await tester.scrollUntilVisible(card(def.id), 160, scrollable: scrollable);
      expect(
        card(def.id),
        findsOneWidget,
        reason: '信息卡 ${def.id} 应当在 Reader 底部面板里',
      );
    }
  });
}
