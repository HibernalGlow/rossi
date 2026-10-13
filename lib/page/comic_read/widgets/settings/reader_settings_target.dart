part of 'reader_settings_sheet.dart';

/// 阅读设置 sheet 内通用的“读目标值 + 按目标写”。
/// 读：[watchTargetReadSetting]——本漫 tab 读有效值（patch 已合并），其余只读全局。
/// 写：按当前编辑目标路由——改全局走 `GlobalSettingCubit`，
/// 改本漫走 `ComicReadPreferenceCubit.updateField`，只写变化的 key。
/// 需要震动反馈由调用方自己加；需要跳页（如切阅读模式）也由调用方自己调。
///
/// 写目标只看 [_PerComicScope]：外层恒包 `perComic: false`，
/// 第四个“本漫”tab 内层包 `perComic: true`，里面所有控件读写全钉本漫。
/// 加新设置项只写一遍 Section，第四 tab 复用同一个，不写第二遍。
extension EffectiveReadSettingX on BuildContext {
  /// 当前编辑目标是不是本漫：只看最近的 [_PerComicScope]，不回退读 cubit。
  ///
  /// 旧漫画的绑定状态漏不进全局页——全局入口与前三个 tab 恒为 false。
  bool get isEditingPerComic => _PerComicScope.maybeOf(this)?.perComic ?? false;

  /// 当前编辑目标的值：本漫 tab 读有效值，其余只读全局。
  ///
  /// 设置 UI 一律读这个，保证“显示什么就改什么”；渲染层继续用
  /// [ComicReadPreferenceContextX.watchEffectiveReadSetting]。
  ReadSettingState watchTargetReadSetting() {
    if (isEditingPerComic) return watchEffectiveReadSetting();
    return watch<GlobalSettingCubit>().state.readSetting;
  }

  /// 按编辑目标写入：本漫→patch（只含变化 key），全局→全局设置。
  Future<Set<String>> updateEffectiveReadSetting(
    ReadSettingState effective,
    ReadSettingState Function(ReadSettingState current) fn,
  ) {
    if (isEditingPerComic) {
      return read<ComicReadPreferenceCubit>().updateField(effective, fn);
    }
    read<GlobalSettingCubit>().updateReadSetting(fn);
    return Future.value(const <String>{});
  }
}

/// 钉死子树写目标：`perComic: true` 包住本漫 tab，里面全写本漫。
class _PerComicScope extends InheritedWidget {
  final bool perComic;

  const _PerComicScope({required this.perComic, required super.child});

  static _PerComicScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_PerComicScope>();
  }

  @override
  bool updateShouldNotify(_PerComicScope oldWidget) {
    return perComic != oldWidget.perComic;
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  /// 标题行右侧动作（如本漫 tab 阅读模式旁的“跟随全局”）。
  final Widget? trailing;

  const _SettingsSection({
    required this.title,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: context.theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ...?trailing != null ? [trailing!] : null,
          ],
        ),
        const SizedBox(height: 10),
        for (int i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _SettingsChoiceChip extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _SettingsChoiceChip({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;

    return ChoiceChip(
      label: Text(title),
      selected: selected,
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      backgroundColor: colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.45,
      ),
      selectedColor: colorScheme.primaryContainer.withValues(alpha: 0.92),
      side: BorderSide(
        color: selected
            ? colorScheme.primary
            : colorScheme.outlineVariant.withValues(alpha: 0.7),
        width: selected ? 1.4 : 1,
      ),
      labelStyle: context.theme.textTheme.bodyMedium?.copyWith(
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        color: selected
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSurface,
      ),
      onSelected: (_) => onTap(),
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  static const WidgetStateProperty<Icon> _thumbIcon =
      WidgetStateProperty<Icon>.fromMap(<WidgetStatesConstraint, Icon>{
        WidgetState.selected: Icon(Icons.check),
        WidgetState.any: Icon(Icons.close),
      });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.only(left: 12, right: 8),
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: context.theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Switch.adaptive(
          thumbIcon: _thumbIcon,
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _SettingsDropdownTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final int value;
  final List<int> values;
  final ValueChanged<int> onChanged;

  const _SettingsDropdownTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.only(left: 12, right: 8),
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: context.theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: FluentDropdown<int>(
          value: value,
          displayValue: value.toString(),
          items: {for (final option in values) option: option.toString()},
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _SettingsSliderCard extends StatelessWidget {
  final String title;
  final int value;
  final int min;
  final int max;
  final int divisions;
  final String suffix;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const _SettingsSliderCard({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(
          alpha: enabled ? 0.45 : 0.28,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: context.theme.textTheme.bodyMedium),
              const Spacer(),
              Text(
                '$value $suffix',
                style: context.theme.textTheme.bodyMedium?.copyWith(
                  color: enabled
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Slider(
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: divisions,
            value: value.clamp(min, max).toDouble(),
            label: '$value$suffix',
            onChanged: !enabled
                ? null
                : (newValue) {
                    final nextValue = newValue.round().clamp(min, max);
                    if (nextValue != value) {
                      HapticFeedback.selectionClick();
                      onChanged(nextValue);
                    }
                  },
          ),
        ],
      ),
    );
  }
}

class _SettingsNoticeCard extends StatelessWidget {
  final String text;

  const _SettingsNoticeCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Text(
        text,
        style: context.theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
