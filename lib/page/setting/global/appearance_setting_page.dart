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
import 'package:zephyr/page/setting/common/setting_route.dart';
import 'package:zephyr/page/setting/common/setting_group.dart';
import 'package:zephyr/page/setting/global/widgets/appearance_theme_picker.dart';
import 'package:zephyr/page/setting/global/widgets.dart';
import 'package:zephyr/page/theme_color/theme_color.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/navigation/navigation_customization_dialog.dart';
import 'package:zephyr/widgets/navigation/navigation_layout.dart';
import 'package:zephyr/widgets/navigation/navigation_entries.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/workspace/model/workspace_startup.dart';
import 'package:zephyr/icons/icons.dart';

// 「导航栏」那一段：两个壳的开关、窄屏自动切与阈值、自定义导航入口。
part 'parts/appearance_navigation_part.dart';

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
        padding: kSettingPagePadding,
        children: [
          SettingGroup(
            title: t.settings.theme,
            icon: AppGlyphs.palette,
            children: [
              AppearanceThemePicker(
                value: state.themeMode,
                seedColor: state.seedColor,
                onChanged: (value) => cubit.updateState(
                  (current) => current.copyWith(themeMode: value),
                ),
              ),
              _dynamicColor(state, cubit),
              // 以前只在关掉动态取色时才给这一项（种子色在动态色下没意义）。
              // 现在这页还承载「导入 tweakcn 主题」，而导入的 token 是**覆盖**在
              // 动态色 / fromSeed 之上的，两者可以共存 —— 入口不该再被动态色挡掉。
              changeThemeColor(context),
              _comicReadTopContainer(state, cubit),
              _isAMOLED(state, cubit),
            ],
          ),
          // 导入保留独立表单分组，避免在主题分组里再次套容器。
          const TweakcnImportCard(),
          SettingGroup(
            title: t.settings.language,
            icon: AppGlyphs.translate,
            children: [
              _languageTile(context, state, cubit),
              _fontSettings(context),
            ],
          ),
          if (_isDesktopPlatform)
            SettingGroup(
              title: t.settings.windowGroup,
              icon: AppGlyphs.devices,
              children: [
                // 桌面专属：那一条 40px 的自制标题栏改成透明浮层。
                if (_isDesktopPlatform)
                  _transparentDesktopTitleBar(state, cubit),
                // 摆放方式只在开关打开时才需要回答 —— 关着时摆出来只会让人犹豫。
                if (_isDesktopPlatform && state.transparentDesktopTitleBar)
                  _transparentTitleBarMode(state, cubit),
              ],
            ),
          // 导航栏那一段摆在「外观」这一屏：它和主题、标题栏一样是
          // 「应用外壳长什么样」，而不是工作台内部的事。
          SettingGroup(
            title: t.navigation.navigationChrome,
            icon: AppGlyphs.layoutTabs,
            children: navigationChromeTiles(
              context: context,
              state: state,
              cubit: cubit,
            ).skip(1).toList(),
          ),
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
      leading: const GlyphIcon(AppGlyphs.translate),
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

  Widget _dynamicColor(GlobalSettingState state, GlobalSettingCubit cubit) {
    return SwitchListTile(
      secondary: const GlyphIcon(AppGlyphs.palette),
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
      leading: const GlyphIcon(AppGlyphs.textSize),
      title: Text(t.settings.fontSettings),
      subtitle: Text(t.settings.fontSettingsSubtitle),
      trailing: const GlyphIcon(AppGlyphs.chevronForward),
      onTap: () {
        Navigator.of(context).push(
          settingPageRoute(
            context: context,
            builder: (_) => const FontSettingPage(),
          ),
        );
      },
    );
  }

  Widget _isAMOLED(GlobalSettingState state, GlobalSettingCubit cubit) {
    return SwitchListTile(
      secondary: const GlyphIcon(AppGlyphs.contrast),
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
      secondary: const GlyphIcon(AppGlyphs.openExternal),
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
      secondary: const GlyphIcon(AppGlyphs.devices),
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
