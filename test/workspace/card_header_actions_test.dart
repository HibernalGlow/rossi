import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/widgets/card_header_actions.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/insights/insight_sections.dart';

Widget _host(Widget body, {Size size = const Size(240, 192)}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child!,
  ),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: CollapsibleCard(
          cardId: 'pager',
          title: '连续阅读',
          icon: AppGlyphs.trend,
          isExpanded: true,
          onToggle: () {},
          expressive: true,
          scrollContent: false,
          margin: EdgeInsets.zero,
          child: body,
        ),
      ),
    ),
  ),
);

Widget _pager() => const InsightSectionPager(
  labels: ['摘要', '趋势'],
  sections: [
    Center(child: Text('摘要正文')),
    Center(child: Text('趋势正文')),
  ],
  full: Text('完整详情'),
  fullHeight: 330,
  detailTitle: '连续阅读',
  tinySummary: '当前 40 天',
  dataRevision: 'fixture',
);

void main() {
  testWidgets('切段与展开在同一标题行，极小卡图标只占自身宽度', (tester) async {
    await tester.pumpWidget(_host(_pager()));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byType(CollapsibleCard));
    for (final finder in [
      find.byTooltip('上一段'),
      find.byType(InsightDetailButton),
      find.byTooltip('下一段'),
    ]) {
      expect(
        tester.getCenter(finder).dy,
        closeTo(tester.getCenter(find.text('连续阅读')).dy, 1),
      );
      expect(
        tester.getRect(finder).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(CardHeaderActions)).top),
      );
    }
    await tester.tap(find.byTooltip('下一段'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('趋势 · 2/2 · 展开连续阅读'), findsOneWidget);
    expect(tester.getRect(find.byType(CollapsibleCard)), rect);
    await tester.tap(find.byType(InsightDetailButton));
    await tester.pumpAndSettle();
    expect(find.text('完整详情'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsNothing);
    await tester.pumpWidget(_host(_pager(), size: const Size(180, 96)));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(InsightDetailButton)).width, 32);
    expect(find.byTooltip('下一段'), findsNothing);
    expect(find.text('当前 40 天'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未完成发布、替换正文和销毁外壳不留下标题操作', (tester) async {
    await tester.pumpWidget(_host(_pager()));
    await tester.pumpWidget(_host(const Text('加载中')));
    await tester.pumpAndSettle();
    expect(find.byType(InsightDetailButton), findsNothing);
    await tester.pumpWidget(_host(_pager()));
    await tester.pumpAndSettle();
    expect(find.byType(InsightDetailButton), findsOneWidget);
    await tester.pumpWidget(_host(const Text('没有记录')));
    await tester.pumpAndSettle();
    expect(find.byType(InsightDetailButton), findsNothing);
    await tester.pumpWidget(_host(_pager()));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
