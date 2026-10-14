import 'package:auto_route/annotations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/color_theme_types.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/theme_color/theme_color.dart';

@RoutePage()
class ThemeColorPage extends StatefulWidget {
  const ThemeColorPage({super.key});

  @override
  State<ThemeColorPage> createState() => _ThemeColorPageState();
}

class _ThemeColorPageState extends State<ThemeColorPage> {
  late Color _currentColor;

  @override
  void initState() {
    super.initState();
    _currentColor = objectbox.userSettingBox.get(1)!.globalSetting.seedColor;
  }

  @override
  Widget build(BuildContext context) {
    return SettingPageShell(
      title: t.settings.themeColor,
      description: t.settings.themeColorSubtitle,
      child: SingleChildScrollView(
        padding: kSettingPagePadding,
        child: Column(
          children: [
            // 颜色选择器
            ColorPickerPage(
              currentColor: _currentColor,
              onColorChanged: _applyColor,
            ),
            // 预设色块
            SettingSectionCard(
              title: t.settings.colorPresets,
              icon: AppGlyphs.palette,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final colorInfo in colorThemeList)
                        ColorThemeItem(
                          colorInfo: colorInfo,
                          currentColor: _currentColor,
                          onColorSelected: _applyColor,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _applyColor(Color color) {
    setState(() {
      _currentColor = color;
    });
    context.read<GlobalSettingCubit>().updateState(
      (current) => current.copyWith(seedColor: color),
    );
  }
}
