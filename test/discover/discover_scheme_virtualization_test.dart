import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/discover/view/discover_scheme_renderer.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/widgets/comic_simplify_entry/cover.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await TestObjectBoxHelper.setUpTestObjectBox();
    objectbox.userSettingBox.put(UserSetting());
  });
  tearDownAll(TestObjectBoxHelper.tearDownTestObjectBox);

  testWidgets('2000 个分类共享视口，只挂载可见封面且滚远后回收前面的封面', (tester) async {
    var reachedBottom = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => const DiscoverSchemeRenderer().buildPage(
              context,
              from: 'test',
              scheme: const {
                'body': {
                  'type': 'list',
                  'children': [
                    {'type': 'action-grid', 'key': 'categories'},
                  ],
                },
              },
              data: {
                'categories': [
                  for (var i = 0; i < 2000; i++) {'title': '分类 $i'},
                ],
              },
              onReachBottom: () async {
                reachedBottom++;
              },
              onAction: (_) async {},
              isLoadingMore: false,
              showLoadMoreRetry: false,
              onRetryLoadMore: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final covers = find.byWidgetPredicate(
      (w) => w is CoverWidget && w.pictureType == PictureType.category,
    );
    final initialCount = covers.evaluate().length;
    expect(initialCount, inInclusiveRange(1, 50));
    expect(find.text('分类 1999'), findsNothing);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    for (var i = 1; i <= 20; i++) {
      position.jumpTo(i * 1600);
      await tester.pump();
      expect(covers.evaluate().length, lessThanOrEqualTo(50));
    }
    expect(find.text('分类 0'), findsNothing);
    expect(reachedBottom, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
  });
}
