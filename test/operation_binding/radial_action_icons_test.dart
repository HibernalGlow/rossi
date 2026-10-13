import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/setting/operation_binding/radial_icon_picker.dart';
import 'package:zephyr/service/operation_binding/radial_doc.dart';
import 'package:zephyr/widgets/radial/radial_action_icons.dart';
import 'package:zephyr/src/rust/frb_generated.dart';

class _Api implements RustLibApi {
  @override
  dynamic noSuchMethod(Invocation call) {
    if (call.memberName ==
        #crateApiOperationBindingOperationBindingActionCatalog) {
      return jsonEncode([
        for (final id in radialIconActionIds)
          {'id': id, 'label': id, 'category': 'view'},
      ]);
    }
    if (call.memberName == #crateApiFontListSystemFontFamilies) {
      return Future.value(const <String>[]);
    }
    throw UnsupportedError('${call.memberName}');
  }
}

void main() {
  test('首页、上一页、末页、下一页和缩放方向有不同图标', () {
    for (final pair in [
      ('reader.first-page', 'reader.previous-page'),
      ('reader.last-page', 'reader.next-page'),
      ('reader.zoom-in', 'reader.zoom-out'),
    ]) {
      expect(
        radialActionGlyph(action: pair.$1),
        isNot(same(radialActionGlyph(action: pair.$2))),
      );
    }
  });

  test('图标覆盖支持保存和清除，未知图标回退自动匹配', () {
    final item = RadialItemDoc({
      'id': 'a',
      'label': 'A',
      'slotIndex': 2,
      'extension': 42,
    });
    final changed = item.copyWith(iconId: 'reader.fullscreen');
    expect(changed.iconId, 'reader.fullscreen');
    expect(changed.raw['extension'], 42);
    expect(
      radialActionGlyph(action: 'reader.next-page', overrideId: changed.iconId),
      same(AppGlyphs.fullscreen),
    );
    final restored = changed.copyWith(iconId: '');
    expect(restored.raw.containsKey('iconId'), isFalse);
    expect(restored.id, item.id);
    final exported = RadialDoc({
      'menus': [
        {
          'id': 'default',
          'layers': [
            [changed.raw],
          ],
        },
      ],
    }).encode();
    expect(
      parseRadialDoc(exported)!.activeMenu!.item('a')!.iconId,
      'reader.fullscreen',
    );
    expect(
      radialActionGlyph(action: 'reader.next-page', overrideId: 'future-icon'),
      same(AppGlyphs.chevronForward),
    );
  });

  testWidgets('动作链和轮盘跳转都有标记，覆盖不改变跳转标记', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            radialActionIcon(
              item: null,
              action: 'reader.next-page',
              chained: true,
            ),
            radialActionIcon(
              item: RadialItemDoc({'iconId': 'reader.fullscreen'}),
              action: null,
              menuJump: true,
            ),
          ],
        ),
      ),
    );
    final glyphs = tester
        .widgetList<GlyphIcon>(find.byType(GlyphIcon))
        .map((w) => w.glyph)
        .toList();
    expect(glyphs, contains(AppGlyphs.layers));
    expect(glyphs, contains(AppGlyphs.chevronForward));
    expect(glyphs, contains(AppGlyphs.fullscreen));
  });

  testWidgets('统一弹层选择手动图标及恢复自动，不改变动作', (tester) async {
    RustLib.initMock(api: _Api());
    addTearDown(() {
      RustLib.dispose();
      // ignore: invalid_use_of_internal_member
      RustLib.instance.resetState();
    });
    String? override;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => RadialIconPickerTile(
              iconId: override,
              action: 'reader.next-page',
              menuJump: false,
              onChanged: (value) =>
                  setState(() => override = value.isEmpty ? null : value),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    final firstGlyph = find.byType(GlyphIcon).evaluate().where((element) {
      return (element.widget as GlyphIcon).glyph ==
          radialActionGlyph(action: 'reader.first-page');
    }).first;
    await tester.tap(find.byWidget(firstGlyph.widget));
    await tester.pumpAndSettle();
    expect(override, 'reader.first-page');
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按操作自动匹配').last);
    await tester.pumpAndSettle();
    expect(override, isNull);
    expect(tester.takeException(), isNull);
  });
}
