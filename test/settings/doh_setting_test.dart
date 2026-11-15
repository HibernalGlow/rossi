import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/global/doh_setting_page.dart';

class _TestGlobalSettingCubit extends GlobalSettingCubit {
  @override
  void updateState(GlobalSettingState Function(GlobalSettingState) updates) {
    emit(updates(state));
  }
}

void main() {
  Future<_TestGlobalSettingCubit> pumpPage(WidgetTester tester) async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    final cubit = _TestGlobalSettingCubit();
    await tester.pumpWidget(
      BlocProvider<GlobalSettingCubit>.value(
        value: cubit,
        child: const MaterialApp(home: DohSettingPage()),
      ),
    );
    await tester.pump();
    return cubit;
  }

  testWidgets('DoH 开关与端点增删', (tester) async {
    final cubit = await pumpPage(tester);
    expect(cubit.state.dohSetting.enabled, isTrue);
    expect(cubit.state.dohSetting.providers, defaultDohProviders);
    expect(find.text(t.settings.dohIpHint), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(cubit.state.dohSetting.enabled, isFalse);

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pump();
    expect(
      cubit.state.dohSetting.providers.length,
      defaultDohProviders.length - 1,
    );

    await tester.tap(find.text(t.settings.dohAdd));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'https://example.com/dns-query',
    );
    await tester.tap(find.text(t.common.ok));
    await tester.pumpAndSettle();
    expect(
      cubit.state.dohSetting.providers,
      contains('https://example.com/dns-query'),
    );

    // 非 https 地址必须被拒绝，且不写进设置。
    final before = cubit.state.dohSetting.providers.length;
    await tester.tap(find.text(t.settings.dohAdd));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'http://insecure.example/dns-query',
    );
    await tester.tap(find.text(t.common.ok));
    await tester.pump();
    expect(find.text(t.settings.dohInvalidUrl), findsOneWidget);
    expect(cubit.state.dohSetting.providers.length, before);
  });
}
