// 只用 material_ui：它自带一套 MaterialApp / Scaffold / Icons（与主应用同一套），
// 再 import flutter/material 会得到一堆二义名。
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/plugin_settings/widgets/delete_plugin_confirm_dialog.dart';

void main() {
  setUpAll(() {
    LocaleSettings.setLocale(AppLocale.zhCn);
  });
  tearDownAll(() => LocaleSettings.useDeviceLocale());

  Future<void> openDialog(
    WidgetTester tester,
    void Function(bool?) onResult,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  onResult(await showDeletePluginConfirmDialog(context));
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('默认关闭：不勾选清理源数据，确认返回 false', (tester) async {
    bool? result;
    await openDialog(tester, (value) => result = value);

    final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(tile.value, isFalse);
    expect(find.text(t.plugin.deletePluginKeepDataHint), findsOneWidget);
    expect(find.text(t.plugin.deletePluginRemoveDataHint), findsNothing);

    await tester.tap(find.text(t.common.confirm));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('打开开关后确认返回 true，并显示删除后果', (tester) async {
    bool? result;
    await openDialog(tester, (value) => result = value);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(tile.value, isTrue);
    expect(find.text(t.plugin.deletePluginRemoveDataHint), findsOneWidget);
    expect(find.text(t.plugin.deletePluginKeepDataHint), findsNothing);

    await tester.tap(find.text(t.common.confirm));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('取消返回 null', (tester) async {
    bool? result;
    await openDialog(tester, (value) => result = value);

    await tester.tap(find.text(t.common.cancel));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
