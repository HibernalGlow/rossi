import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_disclosure.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/widgets/expressive/expressive_blob.dart';
import 'package:zephyr/widgets/expressive/expressive_shape.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:zephyr/workspace/widgets/cards/expressive_widgets.dart';

/// 阅读设置那一套**行级控件**的唯一出处。
///
/// 原先它们是 `reader_settings_sheet.dart` 的私有类，于是「阅读设置面板」成了
/// 唯一的宿主。工作台控制面板要把同一批设置项做成卡片时，只有两条路：
/// 重抄一遍（两处必然漂移），或者把它们提出来。这里走第二条 ——
/// 面板与卡片渲染的是**同一份** section，所以拨哪边另一边当场跟着变。
///
/// 工作台侧默认启用 MD3 Expressive 多态图标座与撞色几何贴片底板，
/// 阅读面板由 SettingsPresentationScope 启用渐进说明。

/// 根据设置项标题自动推断语义图标（调用方显式传入 `icon` 时以传入值为准）。
Glyph inferSettingsGlyph(String title) {
  if (title.contains('动画')) return AppGlyphs.motion;
  if (title.contains('滤镜')) return AppGlyphs.moon;
  if (title.contains('墨水屏')) return AppGlyphs.contrast;
  if (title.contains('超分')) return AppGlyphs.sparkle;
  if (title.contains('对比原图')) return AppGlyphs.split;
  if (title.contains('图像处理') || title.contains('降噪')) return AppGlyphs.wand;
  if (title.contains('分辨率') || title.contains('阈值')) {
    return AppGlyphs.aspectRatio;
  }
  if (title.contains('分块')) return AppGlyphs.gridPlus;
  if (title.contains('自动译') || title.contains('翻译')) return AppGlyphs.translate;
  if (title.contains('引擎')) return AppGlyphs.rocket;
  if (title.contains('语言')) return AppGlyphs.language;
  if (title.contains('推理') || title.contains('后端')) return AppGlyphs.cpu;
  if (title.contains('权重') || title.contains('下载') || title.contains('模型')) {
    return AppGlyphs.download;
  }
  if (title.contains('缓存')) return AppGlyphs.box;
  if (title.contains('日志')) return AppGlyphs.article;
  return AppGlyphs.sliders;
}

/// 一节：一个带多态几何图标座的小标题 + 若干组。
class SettingsSection extends StatelessWidget {
  final String title;
  final Glyph? icon;
  final List<Widget> children;
  final Widget? trailing;

  /// `false` = 不画标题行。
  ///
  /// 给「宿主外壳已经有一模一样的标题」的落点用：控制面板那几张卡片
  /// 自己的标题行写的就是这一节的名字，里面再画一遍等于同一句话写两遍。
  /// 默认 `true`，阅读设置面板那边的观感一字不动。
  final bool showTitle;

  const SettingsSection({
    super.key,
    required this.title,
    this.icon,
    required this.children,
    this.trailing,
    this.showTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;
    final seed = expressiveBlobSeed(title);
    final tone = expressiveAccentToneForSeed(seed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
            child: Row(
              children: [
                if (icon != null) ...[
                  ExpressiveShapeBadge(
                    icon: icon!,
                    seed: seed,
                    size: 28,
                    glyphSize: 15,
                    tone: tone,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: context.theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                ?trailing,
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

/// MD3 Expressive 分组卡片容器：将相关的多个设置项统一收纳在带撞色几何贴片的容器中，
/// 内部自动以微弱分割线隔开。
///
/// 底色必须落在 [Material] 上（[ExpressivePatchBackdrop] 根就是 [Material]），
/// 保证内部 `ListTile` 的水波与背景色不会触发遮挡断言。
class SettingsCardGroup extends StatelessWidget {
  final List<Widget> children;
  final int? seed;
  final ExpressiveTone tone;

  const SettingsCardGroup({
    super.key,
    required this.children,
    this.seed,
    this.tone = ExpressiveTone.sunken,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;
    final expressive = SettingsPresentationScope.maybeOf(context) != null;
    final groupSeed =
        seed ??
        expressiveBlobSeed(
          'group-${children.length}-${children.firstOrNull?.runtimeType}',
        );

    return ExpressivePatchBackdrop(
      seed: groupSeed,
      tone: tone,
      intensity: expressive ? 0.75 : 0.95,
      borderRadius: expressive ? BorderRadius.circular(24) : expressiveCornerMd,
      borderSide: expressive
          ? BorderSide.none
          : BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.42),
              width: 1,
            ),
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
                color: colorScheme.outlineVariant.withValues(alpha: 0.22),
              ),
          ],
        ],
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
      duration:
          (SettingsPresentationScope.maybeOf(context)?.animate ?? true) &&
              !MediaQuery.disableAnimationsOf(context)
          ? ExpressiveMotion.spatialDuration
          : Duration.zero,
      curve: ExpressiveMotion.spatialCurve,
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
    final seed = expressiveBlobSeed(title);

    return ChoiceChip(
      label: Text(title),
      selected: selected,
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      shape: ExpressiveBlobBorder(
        seed: seed,
        progress: selected ? 1.0 : 0.2,
        safeInset: 8,
        side: BorderSide(
          color: selected
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.7),
          width: selected ? 1.4 : 1,
        ),
      ),
      backgroundColor: colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.45,
      ),
      selectedColor: colorScheme.primaryContainer.withValues(alpha: 0.92),
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
  final Glyph? icon;
  final ExpressiveButtonShape? badgeShape;
  final ExpressiveTone? badgeTone;

  /// 关掉交互但保留原样排版：用于「这里没有书可读，所以这颗拨了也没地方生效」。
  final bool disabled;

  const SettingsSwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.icon,
    this.badgeShape,
    this.badgeTone,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;

    if (SettingsPresentationScope.maybeOf(context) != null) {
      return SettingsDetailTile(
        title: title,
        description: subtitle,
        enabled: !disabled,
        trailing: M3ESwitch(
          semanticLabel: title,
          value: value,
          selectedIcon: const Icon(Icons.check, size: 16),
          onChanged: disabled ? null : onChanged,
        ),
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!value);
        },
      );
    }

    final seed = expressiveBlobSeed(title);
    final effectiveIcon = icon ?? inferSettingsGlyph(title);
    final effectiveTone = badgeTone ?? expressiveAccentToneForSeed(seed);

    final tile = ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: ExpressiveShapeBadge(
        icon: effectiveIcon,
        shape: badgeShape,
        seed: seed,
        size: 36,
        glyphSize: 18,
        tone: effectiveTone,
        active: value,
      ),
      title: Text(
        title,
        style: context.theme.textTheme.bodyMedium?.copyWith(
          fontWeight: value ? FontWeight.w700 : FontWeight.w600,
          color: value ? colorScheme.primary : colorScheme.onSurface,
        ),
      ),
      subtitle: subtitle != null && subtitle!.isNotEmpty
          ? Text(
              subtitle!,
              style: context.theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.25,
              ),
            )
          : null,
      trailing: M3ESwitch(
        semanticLabel: title,
        selectedIcon: const Icon(Icons.check, size: 16),
        value: value,
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
  final Glyph? icon;
  final ExpressiveButtonShape? badgeShape;
  final ExpressiveTone? badgeTone;

  static String _toStringLabel(Object? value) => '$value';

  const SettingsDropdownTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.values,
    required this.onChanged,
    this.labelOf = _toStringLabel,
    this.icon,
    this.badgeShape,
    this.badgeTone,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;

    if (SettingsPresentationScope.maybeOf(context) != null) {
      return SettingsDetailTile(
        title: title,
        description: subtitle,
        stackControlOnNarrow: true,
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: FluentDropdown<T>(
            value: value,
            displayValue: labelOf(value),
            items: {for (final option in values) option: labelOf(option)},
            onChanged: onChanged,
          ),
        ),
      );
    }

    final seed = expressiveBlobSeed(title);
    final effectiveIcon = icon ?? inferSettingsGlyph(title);
    final effectiveTone = badgeTone ?? expressiveAccentToneForSeed(seed);
    final tones = expressiveToneColors(colorScheme, effectiveTone);

    final dropdownPill = Container(
      decoration: ShapeDecoration(
        color: tones.container.withValues(alpha: 0.72),
        shape: ExpressiveBlobBorder(
          seed: seed ^ 0x13579bdf,
          progress: 0.65,
          safeInset: 6,
          side: BorderSide(
            color: tones.onContainer.withValues(alpha: 0.24),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: FluentDropdown<T>(
        value: value,
        displayValue: labelOf(value),
        items: {for (final option in values) option: labelOf(option)},
        onChanged: onChanged,
      ),
    );

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: ExpressiveShapeBadge(
        icon: effectiveIcon,
        shape: badgeShape,
        seed: seed,
        size: 36,
        glyphSize: 18,
        tone: effectiveTone,
      ),
      title: Text(
        title,
        style: context.theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle != null && subtitle!.isNotEmpty
          ? Text(
              subtitle!,
              style: context.theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.25,
              ),
            )
          : null,
      trailing: dropdownPill,
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
  final Glyph? icon;

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
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;
    final seed = expressiveBlobSeed(title);
    final effectiveIcon = icon ?? inferSettingsGlyph(title);
    final tone = expressiveAccentToneForSeed(seed);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExpressiveShapeBadge(
                icon: effectiveIcon,
                seed: seed,
                size: 28,
                glyphSize: 15,
                tone: tone,
                active: enabled,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: context.theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: enabled
                        ? null
                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 4,
                ),
                decoration: ShapeDecoration(
                  color: enabled
                      ? colorScheme.secondaryContainer
                      : colorScheme.surfaceContainerHighest,
                  shape: ExpressiveBlobBorder(
                    seed: seed,
                    progress: 0.55,
                    safeInset: 5,
                  ),
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
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
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
/// 几何与 [SettingsSwitchTile] 对齐：左侧带多态几何图标座。
class SettingsActionTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget trailing;
  final bool enabled;
  final Glyph? icon;
  final ExpressiveTone? badgeTone;

  const SettingsActionTile({
    super.key,
    required this.title,
    required this.trailing,
    this.subtitle,
    this.enabled = true,
    this.icon,
    this.badgeTone,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;

    if (SettingsPresentationScope.maybeOf(context) != null) {
      return SettingsDetailTile(
        title: title,
        description: subtitle,
        trailing: trailing,
        enabled: enabled,
        stackControlOnNarrow: true,
      );
    }

    final seed = expressiveBlobSeed(title);
    final effectiveIcon = icon ?? inferSettingsGlyph(title);
    final effectiveTone = badgeTone ?? expressiveAccentToneForSeed(seed);

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: ExpressiveShapeBadge(
          icon: effectiveIcon,
          seed: seed,
          size: 36,
          glyphSize: 18,
          tone: effectiveTone,
          active: enabled,
        ),
        title: Text(
          title,
          style: context.theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: subtitle != null && subtitle!.isNotEmpty
            ? Text(
                subtitle!,
                style: context.theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.25,
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
    final seed = expressiveBlobSeed(text);

    return ExpressivePatchBackdrop(
      seed: seed,
      tone: ExpressiveTone.secondary,
      intensity: 0.85,
      borderRadius: expressiveCornerSm,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExpressiveShapeBadge(
            icon: AppGlyphs.info,
            seed: seed,
            size: 28,
            glyphSize: 15,
            tone: ExpressiveTone.primary,
          ),
          const SizedBox(width: 10),
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
