import 'package:auto_route/annotations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/color_theme_types.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/main.dart';
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
    return Scaffold(
      appBar: AppBar(title: Text(t.settings.themeColor)),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 颜色选择器
            ColorPickerPage(
              currentColor: _currentColor,
              onColorChanged: _applyColor,
            ),
            // 预设色块
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.settings.colorPresets,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
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
                ],
              ),
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
