import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';

/// 阅读设置那一套**行级控件**的唯一出处。
///
/// 原先它们是 `reader_settings_sheet.dart` 的私有类，于是「阅读设置面板」成了
/// 唯一的宿主。工作台控制面板要把同一批设置项做成卡片时，只有两条路：
/// 重抄一遍（两处必然漂移），或者把它们提出来。这里走第二条 ——
/// 面板与卡片渲染的是**同一份** section，所以拨哪边另一边当场跟着变。
///
/// 命名去掉下划线是为了跨库可见，语义与几何一个字都没改。

/// 一节：一个带图标的小标题 + 若干组。
class SettingsSection extends StatelessWidget {
  final String title;
  final IconData? icon;
  final List<Widget> children;

  const SettingsSection({
    super.key,
    required this.title,
    this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
              ],
              Text(
                title,
                style: context.theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
        for (int i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// MD3 分组卡片容器：将相关的多个设置项统一收纳在一个容器中，
/// 内部自动以微弱分割线隔开，消除碎片小盒子感。
///
/// 底色必须落在 [Material] 上，不能落在 [Container] 的 `BoxDecoration` 上：
/// `ListTile` 的水波与背景色画在**最近的 Material 祖先**上，被一层带色
/// DecoratedBox 挡住就永远看不见（Flutter 会直接抛
/// 「ListTile background color or ink splashes may be invisible」）。
/// 之前这里就是那个形状，所以这一组开关点下去**没有任何按压反馈**。
class SettingsCardGroup extends StatelessWidget {
  final List<Widget> children;

  const SettingsCardGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        type: MaterialType.canvas,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1 &&
                  children[i] is! SettingsAnimatedCollapse &&
                  children[i + 1] is! SettingsAnimatedCollapse)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 16,
                  endIndent: 16,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// MD3 分段选择器封装
class SettingsSegmentedTile<T> extends StatelessWidget {
  final T selected;
  final List<ButtonSegment<T>> segments;
  final ValueChanged<T> onSelectionChanged;

  const SettingsSegmentedTile({
    super.key,
    required this.selected,
    required this.segments,
    required this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<T>(
        showSelectedIcon: false,
        segments: segments,
        selected: {selected},
        onSelectionChanged: (selection) {
          if (selection.isNotEmpty) {
            HapticFeedback.selectionClick();
            onSelectionChanged(selection.first);
          }
        },
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
    );
  }
}

/// 平滑展开与收起容器
class SettingsAnimatedCollapse extends StatelessWidget {
  final bool isExpanded;
  final Widget child;
  final bool showDivider;

  const SettingsAnimatedCollapse({
    super.key,
    required this.isExpanded,
    required this.child,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: isExpanded
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showDivider)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 16,
                    endIndent: 16,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                  ),
                child,
              ],
            )
          : const SizedBox.shrink(),
    );
  }
}

/// 上游阅读页设置里的那颗选项胶囊（本漫独立模式与阅读模式都用它）。
class SettingsChoiceChip extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const SettingsChoiceChip({
    super.key,
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

class SettingsSwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// 关掉交互但保留原样排版：用于「这里没有书可读，所以这颗拨了也没地方生效」。
  final bool disabled;

  const SettingsSwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;

    final tile = ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(
        title,
        style: context.theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle != null && subtitle!.isNotEmpty
          ? Text(
              subtitle!,
              style: context.theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: Switch.adaptive(
        value: value,
        activeTrackColor: colorScheme.primary,
        onChanged: disabled ? null : onChanged,
      ),
      onTap: disabled
          ? null
          : () {
              HapticFeedback.selectionClick();
              onChanged(!value);
            },
    );

    if (!disabled) return tile;
    return Opacity(opacity: 0.55, child: tile);
  }
}

class SettingsDropdownTile<T> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  static String _toStringLabel(Object? value) => '$value';

  const SettingsDropdownTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.values,
    required this.onChanged,
    this.labelOf = _toStringLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(
        title,
        style: context.theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle != null && subtitle!.isNotEmpty
          ? Text(
              subtitle!,
              style: context.theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: FluentDropdown<T>(
          value: value,
          displayValue: labelOf(value),
          items: {for (final option in values) option: labelOf(option)},
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class SettingsSliderCard extends StatelessWidget {
  final String title;
  final int value;
  final int min;
  final int max;
  final int divisions;
  final String suffix;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const SettingsSliderCard({
    super.key,
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: context.theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: enabled
                        ? null
                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: enabled
                      ? colorScheme.secondaryContainer
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$value $suffix',
                  style: context.theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: enabled
                        ? colorScheme.onSecondaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
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
          ),
        ],
      ),
    );
  }
}

/// 「一行说明 + 一颗动作按钮」的设置条目（下载、清空、看日志这类不是开关的东西）。
///
/// 几何与 [SettingsSwitchTile] 对齐：同一张卡里混两种行高会看出是拼的。
class SettingsActionTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget trailing;
  final bool enabled;

  const SettingsActionTile({
    super.key,
    required this.title,
    required this.trailing,
    this.subtitle,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        title: Text(
          title,
          style: context.theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: subtitle != null && subtitle!.isNotEmpty
            ? Text(
                subtitle!,
                style: context.theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        trailing: trailing,
      ),
    );
  }
}

class SettingsNoticeCard extends StatelessWidget {
  final String text;

  const SettingsNoticeCard({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: context.theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSecondaryContainer,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
