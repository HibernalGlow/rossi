import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/registry/workspace_ids.dart';
import 'package:zephyr/workspace/widgets/cards/history_insights_window.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/grid/card_resize_handle.dart';
import 'package:zephyr/workspace/widgets/panels/lane_panel_host.dart';

import '../test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(TestObjectBoxHelper.setUpTestObjectBox);
  tearDownAll(TestObjectBoxHelper.tearDownTestObjectBox);

  testWidgets('真实统计面板保存尺寸立即更新局部导航首页，历史订阅保留', (tester) async {
    final cubit = WorkspaceCubit();
    addTearDown(cubit.close);
    cubit.setActivePanel(LaneId.left, WorkspacePanelId.insights);
    cubit.resizeCardInPanel('daily_trend', 2, 1);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const Scaffold(
            body: SizedBox(
              width: 640,
              child: LanePanelHost(side: WorkspacePanelSide.left),
            ),
          ),
        ),
      ),
    );
    // ObjectBox 查询由真实 IO 派发，让占位加载先到达稳定状态。
    for (
      var i = 0;
      i < 50 && find.text('暂无历史访问记录').evaluate().length < 8;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(find.text('暂无历史访问记录'), findsNWidgets(8));
    await tester.pumpAndSettle();
    final card = find.byWidgetPredicate(
      (widget) => widget is CollapsibleCard && widget.cardId == 'daily_trend',
    );
    final window = find.descendant(
      of: card,
      matching: find.byType(HistoryInsightsWindow),
    );
    final subscriptionOwner = tester.state(window);
    final original = tester.getSize(card);
    expect(tester.getSize(find.byType(PanelHeaderBar)).height, 44);

    cubit.resizeCardInPanel('daily_trend', 4, 3);
    await tester.pumpAndSettle();
    final enlarged = tester.getSize(card);
    expect(enlarged.width, greaterThan(original.width));
    expect(enlarged.height, greaterThan(original.height));
    expect(tester.state(window), same(subscriptionOwner));

    await tester.tap(find.text('自定义布局'));
    await tester.pumpAndSettle();
    final grip = find.descendant(
      of: card,
      matching: find.byType(CardResizeHandle),
    );
    expect(grip, findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(grip));
    await gesture.moveBy(const Offset(-170, -90));
    await tester.pump();
    expect(cubit.state.board.cards['daily_trend']!.heightSpan, 3);
    expect(tester.state(window), same(subscriptionOwner));
    await gesture.up();
    await tester.pumpAndSettle();
    final saved = cubit.state.board.cards['daily_trend']!;
    expect(saved.widthSpan, 3);
    expect(saved.heightSpan, 2);
    expect(tester.getSize(card).width, lessThan(enlarged.width));
    expect(tester.getSize(card).height, lessThan(enlarged.height));
    expect(tester.state(window), same(subscriptionOwner));
    expect(tester.takeException(), isNull);
    // 关闭查询监听后再关闭临时 Store。
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
