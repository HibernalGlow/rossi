// `SettingGroup.switchTile` 是旧 `SwitchListTile` 的落点，这里守它四条契约：
// 画的是 M3E 那颗、整行可点（旧控件的定义性行为）、关 onChanged 就是灰显、
// title 收 String 或 Widget 都要能落字。
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/setting/common/setting_group.dart';

void main() {
  Widget host(Widget tile) => MaterialApp(
    home: Scaffold(body: Column(children: [tile])),
  );

  testWidgets('renders the M3E switch with the check glyph', (tester) async {
    var value = true;
    await tester.pumpWidget(
      host(
        SettingGroup.switchTile(
          title: '墨水屏即时刷新',
          value: value,
          onChanged: (v) => value = v,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(M3ESwitch), findsOneWidget);
    // 断言「画出了勾号」而不是「我传了个 selectedIcon」——后者恒真。
    expect(find.byIcon(Icons.check), findsOneWidget);
    // 字符串标题要仍然落在行里，而不是被 Widget-only 的 ListTile 吞掉。
    expect(find.text('墨水屏即时刷新'), findsOneWidget);
  });

  testWidgets('tapping the label toggles once, not zero and not twice', (
    tester,
  ) async {
    var flips = 0;
    var value = false;
    // 必须真的重建：不 setState 的话第二次点击读到的是过期的 value，
    // 测出来的是夹具自己的账，不是控件的账。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                SettingGroup.switchTile(
                  title: Text('跟随系统'),
                  value: value,
                  onChanged: (v) {
                    flips++;
                    setState(() => value = v);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('跟随系统'));
    await tester.pumpAndSettle();
    expect(flips, 1);
    expect(value, isTrue);

    // 直接拨开关也只算一次：行 onTap 不能和拨块的手势重复计数。
    await tester.tap(find.byType(M3ESwitch));
    await tester.pumpAndSettle();
    expect(flips, 2);
    expect(value, isFalse);
  });

  testWidgets('onChanged null greys the switch out but keeps the row', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        SettingGroup.switchTile(title: '本书超分', value: false, onChanged: null),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('本书超分'), findsOneWidget);
    expect(tester.widget<M3ESwitch>(find.byType(M3ESwitch)).onChanged, isNull);
  });
}
