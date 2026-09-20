import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_ray_menu/flutter_ray_menu.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/operation_binding/radial_binding_editor.dart';
import 'package:zephyr/service/operation_binding/radial_doc.dart';
import 'package:zephyr/src/rust/frb_generated.dart';

class _Api implements RustLibApi {
  @override
  dynamic noSuchMethod(Invocation call) {
    if (call.memberName ==
        #crateApiOperationBindingOperationBindingActionCatalog) {
      return '[]';
    }
    if (call.memberName ==
        #crateApiOperationBindingOperationBindingRadialLayout) {
      return jsonEncode([
        {
          'menuId': 'default',
          'level': 1,
          'index': 0,
          'itemId': 'settings',
          'label': '设置',
          'selectable': true,
        },
      ]);
    }
    throw UnsupportedError('${call.memberName}');
  }
}

void main() {
  testWidgets('编辑器在没有 Material 的宿主中开关、选择槽位、预览均不报错', (tester) async {
    RustLib.initMock(api: _Api());
    addTearDown(() {
      RustLib.dispose();
      // ignore: invalid_use_of_internal_member
      RustLib.instance.resetState();
    });
    var doc = RadialDoc({
      'enabled': true,
      'activeMenuId': 'default',
      'menus': [
        {
          'id': 'default',
          'name': '默认',
          'layers': [
            [
              {'id': 'settings', 'label': '设置', 'slotIndex': 0},
            ],
          ],
        },
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: RadialBindingEditor(
              doc: doc,
              bindings: const [],
              catalog: const [],
              onChanged: (next, _) => setState(() => doc = next),
              onSave: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(doc.enabled, isFalse);
    await tester.tap(find.byKey(const ValueKey('radial-slot:1:0')));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsNWidgets(2));
    await tester.tap(find.byTooltip(t.settings.operationBindingRadialPreview));
    await tester.pumpAndSettle();
    expect(find.byType(RayMenu), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
