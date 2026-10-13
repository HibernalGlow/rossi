import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/setting/global/file_manager_setting_page.dart';
import 'package:zephyr/type/breadcrumb_style.dart';
import 'package:zephyr/widgets/navigation/path_breadcrumb.dart';

class _Settings extends GlobalSettingCubit {
  @override
  void updateState(GlobalSettingState Function(GlobalSettingState) updates) =>
      emit(updates(state));
}

void main() {
  testWidgets('设置页提供两个真实预览，选择写回原设置且可恢复', (tester) async {
    final settings = _Settings();
    addTearDown(settings.close);
    await tester.pumpWidget(
      BlocProvider<GlobalSettingCubit>.value(
        value: settings,
        child: const MaterialApp(home: FileManagerSettingPage()),
      ),
    );
    final expressive = find.byKey(
      const ValueKey('breadcrumb-style:expressive'),
    );
    await tester.ensureVisible(expressive);
    await tester.pumpAndSettle();
    await tester.tap(expressive);
    await tester.pumpAndSettle();
    expect(
      settings.state.fileManagerSetting.breadcrumbStyle,
      BreadcrumbStyle.expressive,
    );
    final restored = GlobalSettingState.fromJson(settings.state.toJson());
    expect(
      restored.fileManagerSetting.breadcrumbStyle,
      BreadcrumbStyle.expressive,
    );
    expect(find.byType(PathBreadcrumb), findsNWidgets(2));
    final restrained = find.byKey(
      const ValueKey('breadcrumb-style:restrained'),
    );
    await tester.ensureVisible(restrained);
    await tester.pumpAndSettle();
    await tester.tap(restrained);
    await tester.pumpAndSettle();
    expect(
      settings.state.fileManagerSetting.breadcrumbStyle,
      BreadcrumbStyle.restrained,
    );
    expect(tester.takeException(), isNull);
  });
}
