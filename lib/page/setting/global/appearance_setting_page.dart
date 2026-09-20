import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/i18n_helper.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/i18n/system_locale_service.dart';
import 'package:zephyr/page/font_setting/view/font_setting_page.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/setting/global/widgets.dart';
import 'package:zephyr/page/theme_color/theme_color.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/toast.dart';

/// 桌面三平台。自制标题栏只在这三个平台上有（见 `main.dart` 里
/// `DesktopShellFrame` 的挂载条件），所以这一项也只在这三个平台上出现 ——
/// 手机上摆一颗按了没反应的开关比不摆更糟。
bool get _isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

@RoutePage()
class AppearanceSettingPage extends StatelessWidget {
  const AppearanceSettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final state = cubit.state;

    return SettingPageShell(
      title: t.settings.appearance,
      child: ListView(
        children: [
          settingSectionTitle(
            context,
            t.settings.appearance,
            icon: Icons.palette_outlined,
          ),
          _languageTile(context, state, cubit),
          _systemTheme(state, cubit),
          _dynamicColor(state, cubit),
          // 以前只在关掉动态取色时才给这一项（种子色在动态色下没意义）。
          // 现在这页还承载「导入 tweakcn 主题」，而导入的 token 是**覆盖**在
          // 动态色 / fromSeed 之上的，两者可以共存 —— 入口不该再被动态色挡掉。
          changeThemeColor(context),
          // 导入入口放在这一屏：它和「主题颜色 / 动态取色」是同一层的决定，
          // 藏在子页里没人找得到（用户实测就是在这一屏找的）。
          const TweakcnImportCard(),
          _comicReadTopContainer(state, cubit),
          _isAMOLED(state, cubit),
          // 桌面专属：那一条 40px 的自制标题栏改成透明浮层。
          if (_isDesktopPlatform) _transparentDesktopTitleBar(state, cubit),
          // 摆放方式只在开关打开时才需要回答 —— 关着时摆出来只会让人犹豫。
          if (_isDesktopPlatform && state.transparentDesktopTitleBar)
            _transparentTitleBarMode(state, cubit),
          _fontSettings(context),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _languageTile(
    BuildContext context,
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    final labels = {
      null: t.settings.followSystemLanguage,
      for (final appLocale in AppLocale.values)
        I18nHelper.toFlutterLocale(appLocale): I18nHelper.displayName(
          appLocale,
        ),
    };

    final currentValue = state.localeFollowsSystem ? null : state.locale;
    final currentLabel = labels[currentValue]!;

    return ListTile(
      leading: const Icon(Icons.language_outlined),
      title: Text(t.settings.language),
      subtitle: Text(t.settings.languageSubtitle),
      trailing: FluentDropdown<Locale?>(
        value: currentValue,
        displayValue: currentLabel,
        items: labels,
        onChanged: (value) async {
          if (value == currentValue) return;
          if (value == null) {
            final systemInfo = await SystemLocaleService.getInfo();
            await cubit.setSystemLocale(systemInfo.locale);
          } else {
            await cubit.setLocale(value, followsSystem: false);
          }
          if (context.mounted) {
            showInfoToast(t.settings.languageChangedRestartHint);
          }
        },
      ),
    );
  }

  Widget _systemTheme(GlobalSettingState state, GlobalSettingCubit cubit) {
    final themeItems = <ThemeMode, String>{
      ThemeMode.system: t.common.followSystem,
      ThemeMode.light: t.common.lightMode,
      ThemeMode.dark: t.common.darkMode,
    };

    return ListTile(
      leading: const Icon(Icons.dark_mode_outlined),
      title: Text(t.settings.theme),
      subtitle: Text(t.settings.themeSubtitle),
      trailing: FluentDropdown<ThemeMode>(
        value: state.themeMode,
        displayValue: themeItems[state.themeMode]!,
        items: themeItems,
        onChanged: (ThemeMode value) {
          cubit.updateState((current) => current.copyWith(themeMode: value));
        },
      ),
    );
  }

  Widget _dynamicColor(GlobalSettingState state, GlobalSettingCubit cubit) {
    return SwitchListTile(
      secondary: const Icon(Icons.color_lens_outlined),
      title: Text(t.settings.dynamicColor),
      subtitle: Text(t.settings.dynamicColorSubtitle),
      thumbIcon: kSettingSwitchThumbIcon,
      value: state.dynamicColor,
      onChanged: (bool value) {
        cubit.updateState((current) => current.copyWith(dynamicColor: value));
      },
    );
  }

  Widget _fontSettings(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.font_download_outlined),
      title: Text(t.settings.fontSettings),
      subtitle: Text(t.settings.fontSettingsSubtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const FontSettingPage()));
      },
    );
  }

  Widget _isAMOLED(GlobalSettingState state, GlobalSettingCubit cubit) {
    return SwitchListTile(
      secondary: const Icon(Icons.contrast_outlined),
      title: Text(t.settings.amoled),
      subtitle: Text(t.settings.amoledSubtitle),
      thumbIcon: kSettingSwitchThumbIcon,
      value: state.isAMOLED,
      onChanged: (bool value) {
        cubit.updateState((current) => current.copyWith(isAMOLED: value));
      },
    );
  }

  /// 桌面端自制标题栏：开 = 不占位、浮在内容上（透明）；关 = 原来的实色一行。
  Widget _transparentDesktopTitleBar(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return SwitchListTile(
      secondary: const Icon(Icons.web_asset_outlined),
      title: Text(t.settings.transparentDesktopTitleBar),
      subtitle: Text(t.settings.transparentDesktopTitleBarSubtitle),
      thumbIcon: kSettingSwitchThumbIcon,
      value: state.transparentDesktopTitleBar,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(transparentDesktopTitleBar: value),
        );
      },
    );
  }

  /// 透明档的摆放方式：独立行（默认）/ 融合浮层。缩进挂在开关下面，
  /// 归属关系一眼可见；两个 Radio 共享同一个 groupValue。
  Widget _transparentTitleBarMode(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    void select(bool fused) {
      cubit.updateState(
        (current) => current.copyWith(transparentTitleBarFused: fused),
      );
    }

    // RadioGroup 管组值与回调（3.35 起 RadioListTile 自带的两个参数已废弃）。
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: RadioGroup<bool>(
        groupValue: state.transparentTitleBarFused,
        onChanged: (value) => select(value ?? false),
        child: Column(
          children: [
            RadioListTile<bool>(
              title: Text(t.settings.transparentTitleBarRow),
              subtitle: Text(t.settings.transparentTitleBarRowSubtitle),
              value: false,
            ),
            RadioListTile<bool>(
              title: Text(t.settings.transparentTitleBarOverlay),
              subtitle: Text(t.settings.transparentTitleBarOverlaySubtitle),
              value: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _comicReadTopContainer(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return SwitchListTile(
      secondary: const Icon(Icons.smartphone_outlined),
      title: Text(t.settings.notchAdaptation),
      subtitle: Text(t.settings.notchAdaptationSubtitle),
      thumbIcon: kSettingSwitchThumbIcon,
      value: state.readSetting.comicReadTopContainer,
      onChanged: (bool value) {
        cubit.updateReadSetting(
          (current) => current.copyWith(comicReadTopContainer: value),
        );
      },
    );
  }
}
