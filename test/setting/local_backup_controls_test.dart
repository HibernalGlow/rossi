import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/data_backup/data_backup_page.dart';
import 'package:zephyr/page/setting/global/sync_setting_page.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets('未配置云同步时仍显示本地导入导出 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cubit = GlobalSettingCubit();
      addTearDown(cubit.close);
      await tester.pumpWidget(
        BlocProvider.value(
          value: cubit,
          child: const MaterialApp(home: SyncSettingPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(t.dataBackup.title), findsOneWidget);
      expect(find.byType(DataBackupControls), findsOneWidget);
      for (final title in [t.dataBackup.exportData, t.dataBackup.importData]) {
        final label = find.text(title);
        await tester.ensureVisible(label);
        final tile = tester.widget<ListTile>(
          find.ancestor(of: label, matching: find.byType(ListTile)),
        );
        expect(tile.onTap, isNotNull);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('独立备份页复用相同操作', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DataBackupPage()));
    await tester.pumpAndSettle();
    expect(find.byType(DataBackupControls), findsOneWidget);
    expect(find.text(t.dataBackup.exportData), findsOneWidget);
    expect(find.text(t.dataBackup.importData), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
