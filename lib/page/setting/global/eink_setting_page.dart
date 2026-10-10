import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/platform/eink/eink_device.dart';
import 'package:zephyr/platform/eink/eink_refresh.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/icons/icons.dart';

@RoutePage()
class EInkSettingPage extends StatefulWidget {
  const EInkSettingPage({super.key});

  @override
  State<EInkSettingPage> createState() => _EInkSettingPageState();
}

class _EInkSettingPageState extends State<EInkSettingPage> {
  late final Future<bool> _detected;

  @override
  void initState() {
    super.initState();
    _detected = EinkDevice.detect();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final eink = cubit.state.eInkSetting;
    final readSetting = cubit.state.readSetting;

    return SettingPageShell(
      title: t.settings.einkPageTitle,
      child: ListView(
        children: [
          settingSectionTitle(
            context,
            t.settings.eink,
            icon: AppGlyphs.devices,
          ),
          FutureBuilder<bool>(
            future: _detected,
            builder: (context, snapshot) {
              final detected = snapshot.data ?? false;
              return ListTile(
                leading: GlyphIcon(
                  detected ? AppGlyphs.checkCircle : AppGlyphs.info,
                ),
                title: Text(
                  detected
                      ? t.settings.einkDetected
                      : t.settings.einkNotDetected,
                ),
              );
            },
          ),
          SwitchListTile(
            secondary: const GlyphIcon(AppGlyphs.power),
            title: Text(t.settings.einkEnabled),
            subtitle: Text(t.settings.einkEnabledSubtitle),
            thumbIcon: kSettingSwitchThumbIcon,
            value: eink.enabled,
            onChanged: (value) => cubit.updateState(
              (current) => current.copyWith(
                eInkSetting: current.eInkSetting.copyWith(
                  enabled: value,
                  detectionHandled: true,
                ),
                // 开启时把阅读侧已有的「无动画」「墨水屏优化」一并打开；
                // 这两项只在阅读设置里单独调整，本页不重复列出。
                readSetting: value
                    ? current.readSetting.copyWith(
                        noAnimation: true,
                        einkOptimization: true,
                      )
                    : current.readSetting,
              ),
            ),
          ),
          if (eink.enabled) ...[
            settingSectionTitle(
              context,
              t.settings.einkSectionAnimation,
              icon: AppGlyphs.motion,
            ),
            SwitchListTile(
              secondary: const GlyphIcon(AppGlyphs.arrowBack),
              title: Text(t.settings.einkNoRouteTransition),
              subtitle: Text(t.settings.einkNoRouteTransitionSubtitle),
              thumbIcon: kSettingSwitchThumbIcon,
              value: eink.noRouteTransition,
              onChanged: (value) => cubit.updateEInkSetting(
                (current) => current.copyWith(noRouteTransition: value),
              ),
            ),
            SwitchListTile(
              secondary: const GlyphIcon(AppGlyphs.vAlignBottom),
              title: Text(t.settings.einkNoScrollBounce),
              subtitle: Text(t.settings.einkNoScrollBounceSubtitle),
              thumbIcon: kSettingSwitchThumbIcon,
              value: eink.noScrollBounce,
              onChanged: (value) => cubit.updateEInkSetting(
                (current) => current.copyWith(noScrollBounce: value),
              ),
            ),
            settingSectionTitle(
              context,
              t.settings.einkSectionLoading,
              icon: AppGlyphs.download,
            ),
            SwitchListTile(
              secondary: const GlyphIcon(AppGlyphs.hourglass),
              title: Text(t.settings.einkNoSpinner),
              subtitle: Text(t.settings.einkNoSpinnerSubtitle),
              thumbIcon: kSettingSwitchThumbIcon,
              value: eink.noLoadingSpinner,
              onChanged: (value) => cubit.updateEInkSetting(
                (current) => current.copyWith(noLoadingSpinner: value),
              ),
            ),
            settingSectionTitle(
              context,
              t.settings.einkSectionRefresh,
              icon: AppGlyphs.reset,
            ),
            _dropdownTile<EinkRefreshMode>(
              icon: AppGlyphs.refresh,
              title: t.settings.einkRefreshMode,
              subtitle: t.settings.einkRefreshHint,
              value: eink.refreshMode,
              values: EinkRefreshMode.values,
              label: (value) => value.label,
              onChanged: (value) => cubit.updateEInkSetting(
                (current) => current.copyWith(refreshMode: value),
              ),
            ),
            _dropdownTile(
              icon: AppGlyphs.loop,
              title: t.settings.einkAutoRefreshTurns,
              value: eink.autoRefreshEveryNTurns,
              values: _autoRefreshOptions,
              label: (value) =>
                  value == 0 ? t.settings.einkAutoRefreshOff : '$value',
              onChanged: (value) => cubit.updateEInkSetting(
                (current) => current.copyWith(autoRefreshEveryNTurns: value),
              ),
            ),
            SwitchListTile(
              secondary: const GlyphIcon(AppGlyphs.target),
              title: Text(t.settings.einkShowRefreshButton),
              subtitle: Text(t.settings.einkShowRefreshButtonSubtitle),
              thumbIcon: kSettingSwitchThumbIcon,
              value: eink.showRefreshButton,
              onChanged: (value) => cubit.updateEInkSetting(
                (current) => current.copyWith(showRefreshButton: value),
              ),
            ),
            if (eink.canFullRefresh)
              ListTile(
                leading: const GlyphIcon(AppGlyphs.bolt),
                title: Text(t.settings.einkRefreshNow),
                trailing: const GlyphIcon(AppGlyphs.play),
                onTap: () async {
                  await EinkRefresh.run(
                    eink.refreshMode,
                    holdMs: readSetting.einkDelayMs.clamp(50, 500),
                  );
                  showSuccessToast(t.settings.einkRefreshDone);
                },
              ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static const List<int> _autoRefreshOptions = <int>[0, 2, 3, 5, 8, 10, 15, 20];

  Widget _dropdownTile<T>({
    required Glyph icon,
    required String title,
    String? subtitle,
    required T value,
    required List<T> values,
    required String Function(T value) label,
    required ValueChanged<T> onChanged,
  }) {
    final safeValue = values.contains(value) ? value : values.first;
    return ListTile(
      leading: GlyphIcon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: FluentDropdown<T>(
        value: safeValue,
        displayValue: label(safeValue),
        items: {for (final item in values) item: label(item)},
        onChanged: onChanged,
      ),
    );
  }
}
