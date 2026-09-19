import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/util/toast/toast_style.dart';
import 'package:zephyr/widgets/toast.dart';

/// 提示样式设置：位置、时长、尺寸、外观。
///
/// 口径参考 neoview 的「提示悬浮窗」——位置/边距/透明度/液态玻璃都可调，
/// 这里额外把「自动关闭时长」「宽度」「同屏条数」也做成可调项。
@RoutePage()
class ToastSettingPage extends StatelessWidget {
  const ToastSettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final setting = cubit.state.toastSetting;

    void update(ToastSettingState Function(ToastSettingState current) change) {
      cubit.updateToastSetting(change);
    }

    return SettingPageShell(
      title: t.settings.toastStyle,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          settingSectionTitle(
            context,
            t.settings.toastSectionLayout,
            icon: Icons.grid_view_outlined,
          ),
          SettingSectionCard(
            title: t.settings.toastPosition,
            icon: Icons.place_outlined,
            children: [
              _PositionPicker(
                value: setting.position,
                onChanged: (value) =>
                    update((current) => current.copyWith(position: value)),
              ),
              _IntSliderTile(
                icon: Icons.space_bar_outlined,
                title: t.settings.toastEdgePadding,
                subtitle: t.settings.toastEdgePaddingSubtitle,
                value: setting.edgePadding,
                min: ToastStyleLimits.minEdgePadding,
                max: ToastStyleLimits.maxEdgePadding,
                divisions: 8,
                label: (value) => '$value px',
                onChanged: (value) =>
                    update((current) => current.copyWith(edgePadding: value)),
              ),
              _IntSliderTile(
                icon: Icons.straighten_outlined,
                title: t.settings.toastMaxWidth,
                subtitle: t.settings.toastMaxWidthSubtitle,
                value: setting.maxWidth,
                min: ToastStyleLimits.minWidth,
                max: ToastStyleLimits.maxWidth,
                divisions: 25,
                label: (value) => '$value px',
                onChanged: (value) =>
                    update((current) => current.copyWith(maxWidth: value)),
              ),
              _IntSliderTile(
                icon: Icons.layers_outlined,
                title: t.settings.toastMaxVisible,
                subtitle: t.settings.toastMaxVisibleSubtitle,
                value: setting.maxVisible,
                min: ToastStyleLimits.minVisible,
                max: ToastStyleLimits.maxVisible,
                divisions:
                    ToastStyleLimits.maxVisible - ToastStyleLimits.minVisible,
                label: (value) => '$value',
                onChanged: (value) =>
                    update((current) => current.copyWith(maxVisible: value)),
              ),
            ],
          ),
          settingSectionTitle(
            context,
            t.settings.toastSectionAppearance,
            icon: Icons.auto_awesome_outlined,
          ),
          SettingSectionCard(
            title: t.settings.toastSectionBehavior,
            icon: Icons.timer_outlined,
            children: [
              _IntSliderTile(
                icon: Icons.hourglass_empty_outlined,
                title: t.settings.toastDuration,
                subtitle: t.settings.toastDurationSubtitle,
                value: setting.durationMs,
                min: ToastStyleLimits.minDurationMs,
                max: ToastStyleLimits.maxDurationMs,
                divisions: 30,
                label: (value) => value == 0
                    ? t.settings.toastDurationPermanent
                    : '${(value / 1000).toStringAsFixed(1)} s',
                onChanged: (value) =>
                    update((current) => current.copyWith(durationMs: value)),
              ),
              _IntSliderTile(
                icon: Icons.opacity_outlined,
                title: t.settings.toastOpacity,
                subtitle: t.settings.toastOpacitySubtitle,
                value: setting.opacityPercent,
                min: ToastStyleLimits.minOpacityPercent,
                max: ToastStyleLimits.maxOpacityPercent,
                divisions:
                    (ToastStyleLimits.maxOpacityPercent -
                        ToastStyleLimits.minOpacityPercent) ~/
                    5,
                label: (value) => '$value%',
                onChanged: (value) => update(
                  (current) => current.copyWith(opacityPercent: value),
                ),
              ),
              _IntSliderTile(
                icon: Icons.animation_outlined,
                title: t.settings.toastAnimation,
                subtitle: t.settings.toastAnimationSubtitle,
                value: setting.animationDurationMs,
                min: ToastStyleLimits.minAnimationMs,
                max: ToastStyleLimits.maxAnimationMs,
                divisions: 16,
                label: (value) => '$value ms',
                onChanged: (value) => update(
                  (current) => current.copyWith(animationDurationMs: value),
                ),
              ),
            ],
          ),
          SettingSectionCard(
            title: t.settings.toastSectionStyle,
            icon: Icons.palette_outlined,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.blur_on_outlined),
                title: Text(t.settings.toastLiquidGlass),
                subtitle: Text(t.settings.toastLiquidGlassSubtitle),
                thumbIcon: kSettingSwitchThumbIcon,
                value: setting.liquidGlass,
                onChanged: (value) =>
                    update((current) => current.copyWith(liquidGlass: value)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.linear_scale_outlined),
                title: Text(t.settings.toastShowProgressBar),
                subtitle: Text(t.settings.toastShowProgressBarSubtitle),
                thumbIcon: kSettingSwitchThumbIcon,
                value: setting.showProgressBar,
                onChanged: (value) => update(
                  (current) => current.copyWith(showProgressBar: value),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.emoji_emotions_outlined),
                title: Text(t.settings.toastShowIcon),
                subtitle: Text(t.settings.toastShowIconSubtitle),
                thumbIcon: kSettingSwitchThumbIcon,
                value: setting.showIcon,
                onChanged: (value) =>
                    update((current) => current.copyWith(showIcon: value)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.close_outlined),
                title: Text(t.settings.toastShowCloseButton),
                subtitle: Text(t.settings.toastShowCloseButtonSubtitle),
                thumbIcon: kSettingSwitchThumbIcon,
                value: setting.showCloseButton,
                onChanged: (value) => update(
                  (current) => current.copyWith(showCloseButton: value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.tonalIcon(
            onPressed: () {
              showSuccessToast(
                t.settings.toastPreviewLongMessage,
                title: t.settings.toastPreviewTitle,
                context: context,
              );
            },
            icon: const Icon(Icons.play_circle_outline),
            label: Text(t.settings.toastPreview),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () {
              final defaults = const ToastSettingState();
              cubit.updateToastSetting((_) => defaults);
              showInfoToast(t.settings.toastResetDone, context: context);
            },
            icon: const Icon(Icons.restart_alt_outlined),
            label: Text(t.settings.toastReset),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// 九宫格位置选择器：每个格子画一个小屏 + 一个代表提示条的小条。
class _PositionPicker extends StatelessWidget {
  const _PositionPicker({required this.value, required this.onChanged});

  final ToastPosition value;
  final ValueChanged<ToastPosition> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final position in ToastPosition.values)
                  _cell(context, position),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, ToastPosition position) {
    final scheme = Theme.of(context).colorScheme;
    final selected = position == value;

    return Tooltip(
      message: position.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onChanged(position),
          child: Container(
            width: 56,
            height: 38,
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Align(
              alignment: toastAlignmentOf(position),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Container(
                  width: 16,
                  height: 6,
                  decoration: BoxDecoration(
                    color: selected ? scheme.primary : scheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 整数型滑块设置项：标题 + 说明 + 当前值 + 滑块。
class _IntSliderTile extends StatelessWidget {
  const _IntSliderTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int value;
  final int min;
  final int max;
  final int divisions;
  final String Function(int value) label;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clamped = value.clamp(min, max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: Text(
            label(clamped),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Slider(
            value: clamped.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: divisions <= 0 ? null : divisions,
            label: label(clamped),
            onChanged: (raw) => onChanged(raw.round()),
          ),
        ),
      ],
    );
  }
}
