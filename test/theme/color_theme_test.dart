import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/color_theme_types.dart';
import 'package:zephyr/page/theme_color/theme_color.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('色环取色器在 material_ui 树里可正常构建', (tester) async {
    Color? changed;
    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: ColorPickerPage(
            currentColor: const Color(0xFF3F51B5),
            onColorChanged: (color) => changed = color,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '#00FF00');
    await tester.pump();
    expect(changed, const Color(0xFF00FF00));
  });

  testWidgets('预设色块按可用宽度排多列，且带面具红', (tester) async {
    Color? picked;
    final items = [
      for (final info in colorThemeList)
        ColorThemeItem(
          colorInfo: info,
          currentColor: const Color(0xFF9C4B5E),
          onColorSelected: (color) => picked = color,
        ),
    ];

    // 窄到只放得下 3 列，验证每行几颗是跟着可用宽度走的。
    await tester.pumpWidget(
      _wrap(
        Center(
          child: SizedBox(
            width: 232,
            child: Wrap(spacing: 8, runSpacing: 8, children: items),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    final rects = [
      for (var i = 0; i < items.length; i++)
        tester.getRect(find.byType(ColorThemeItem).at(i)),
    ];
    final firstRowTop = rects.first.top;
    expect(
      rects.where((r) => r.top == firstRowTop).length,
      3,
      reason: '232px 里定宽 72 的色块应排 3 颗',
    );

    expect(colorThemeList.last.color, const Color(0xFF9C4B5E));
    // 面具红就是新装默认，所以整屏只该有它一颗打勾。
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.byType(ColorThemeItem).first);
    await tester.pump();
    expect(picked, colorThemeList.first.color);
  });
}
