import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/navigation/navigation_dock.dart';

/// 底部导航「长按进自定义」的手势契约（见 `navigation_dock.dart` 头部第 7 条）。
///
/// bar 用裸 `Listener` 自己判定长按,不进手势竞技场 —— 这里验的是三件事:
/// 长按触发且回调只来一次;长按后的松手**不**选中(这次按压被消费掉);
/// 滑动(超出触控位移)取消长按,松手照常选中滑到的那一项。
void main() {
  Widget host({
    required ValueChanged<int> onSelected,
    required VoidCallback? onLongPress,
    Duration? longPressDuration,
  }) => MaterialApp(
    home: Scaffold(
      bottomNavigationBar: NavigationDock(
        destinations: [
          for (final id in [1, 2, 3])
            NavigationDockDestination(glyph: AppGlyphs.book, label: '项$id'),
        ],
        selectedIndex: 0,
        onSelected: onSelected,
        onLongPress: onLongPress,
        longPressDuration: longPressDuration,
      ),
    ),
  );

  Future<Offset> itemCenter(WidgetTester tester, int index) async {
    await tester.pumpAndSettle();
    final bar = tester.getRect(find.byType(FloatingNavigationBar));
    final extent = bar.width / 3;
    return Offset(bar.left + extent * (index + 0.5), bar.center.dy);
  }

  testWidgets('长按触发 onLongPress,松手不切换选中项', (tester) async {
    var longPresses = 0;
    var selections = 0;
    await tester.pumpWidget(
      host(
        onSelected: (_) => selections++,
        onLongPress: () => longPresses++,
      ),
    );
    final center = await itemCenter(tester, 1);

    final gesture = await tester.startGesture(center);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    expect(longPresses, 1, reason: '按住超过长按阈值应当触发一次');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(selections, 0, reason: '长按已消费这次按压,松手不应选中');
    expect(longPresses, 1, reason: '松手不重复触发');
  });

  testWidgets('按下后滑动取消长按,松手选中滑到的那一项', (tester) async {
    var longPresses = 0;
    var selected = -1;
    await tester.pumpWidget(
      host(
        onSelected: (index) => selected = index,
        onLongPress: () => longPresses++,
      ),
    );
    final center = await itemCenter(tester, 0);
    // 一格的宽度:滑到相邻一项的中点,不越过它。
    final bar = tester.getRect(find.byType(FloatingNavigationBar));
    final extent = bar.width / 3;

    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 50));
    // 滑过触控位移到第二项,再按住超过长按阈值。
    await gesture.moveBy(Offset(extent, 0));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    expect(longPresses, 0, reason: '滑动应当取消长按计时');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(longPresses, 0);
    expect(selected, 1, reason: '滑动松手应选中滑到的那一项');
  });

  testWidgets('自定义阈值生效:2400ms 的出厂阈值下 500ms 不触发', (tester) async {
    var longPresses = 0;
    await tester.pumpWidget(
      host(
        onSelected: (_) {},
        onLongPress: () => longPresses++,
        // 与 `NavigationSettingState.dockLongPressMilliseconds` 的出厂值同源。
        longPressDuration: const Duration(milliseconds: 2400),
      ),
    );
    final center = await itemCenter(tester, 1);

    final gesture = await tester.startGesture(center);
    await tester.pump(kLongPressTimeout);
    expect(longPresses, 0, reason: '500ms 时远不到 2400ms 阈值,不应触发');

    await tester.pump(const Duration(milliseconds: 2000));
    expect(longPresses, 1, reason: '按满 2400ms 应当触发');

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('没有 onLongPress 时一切照旧:长按等价于普通按压', (tester) async {
    var selected = -1;
    await tester.pumpWidget(
      host(onSelected: (index) => selected = index, onLongPress: null),
    );
    final center = await itemCenter(tester, 2);

    final gesture = await tester.startGesture(center);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, 2);
  });
}
