import 'dart:async';
import 'dart:io';

import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_super_resolution.dart';
import 'package:zephyr/page/setting/real_sr/widgets/super_resolution_engine_settings.dart';
import 'package:zephyr/page/setting/real_sr/widgets/upscale_conditions_card.dart';
import 'package:zephyr/type/enum.dart';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/video/model/video_media_kind.dart';
import 'package:zephyr/video/view/active_video_scope.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/util/debouncer.dart';
import 'package:zephyr/util/reader/reader_top_bar_style.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';

part 'reader_settings_gesture_tab.dart';
part 'reader_settings_info_tab.dart';
part 'reader_settings_read_tab.dart';

Future<void> showReaderSettingsSheet(
  BuildContext context, {
  ValueChanged<int>? changePageIndex,
  ValueChanged<bool>? onLandscapeChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _ReaderSettingsSheetEscScope(
        child: _ReaderSettingsSheet(
          changePageIndex: changePageIndex ?? (_) {},
          onLandscapeChanged: onLandscapeChanged,
        ),
      );
    },
  );
}

/// 给面板一个自己的 Esc 出口：桌面端按 Esc 即可关闭面板。
///
/// 这个处理必须在面板子树内**先行消费**掉 Esc —— 否则按键会沿焦点树
/// 冒泡到工作台的 `CallbackShortcuts`（见 `breeze_workspace_page`），
/// 按一下退出的不是面板、而是整个工作台。
class _ReaderSettingsSheetEscScope extends StatefulWidget {
  final Widget child;

  const _ReaderSettingsSheetEscScope({required this.child});

  @override
  State<_ReaderSettingsSheetEscScope> createState() =>
      _ReaderSettingsSheetEscScopeState();
}

class _ReaderSettingsSheetEscScopeState
    extends State<_ReaderSettingsSheetEscScope> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'reader_settings_sheet');
  bool _closing = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (!_closing) {
      _closing = true;
      // 与 main.dart 的全局 Esc 处理同款顺序：先让焦点失焦，pop 推迟到
      // 下一帧，让失焦引发的重建在当前帧完成。
      FocusManager.instance.primaryFocus?.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: widget.child,
    );
  }
}

class _ReaderSettingsSheet extends StatelessWidget {
  final ValueChanged<int> changePageIndex;
  final ValueChanged<bool>? onLandscapeChanged;

  const _ReaderSettingsSheet({
    required this.changePageIndex,
    this.onLandscapeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.7;
    final isAndroidPhone =
        !kIsWeb && Platform.isAndroid && mediaQuery.size.shortestSide < 600;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SizedBox(
              height: maxHeight,
              child: _ReaderSettingsCard(
                changePageIndex: changePageIndex,
                isAndroidPhone: isAndroidPhone,
                onLandscapeChanged: onLandscapeChanged,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderSettingsCard extends StatelessWidget {
  final ValueChanged<int> changePageIndex;
  final bool isAndroidPhone;
  final ValueChanged<bool>? onLandscapeChanged;

  const _ReaderSettingsCard({
    required this.changePageIndex,
    required this.isAndroidPhone,
    this.onLandscapeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainerLow,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: DefaultTabController(
        length: 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _ReaderSettingsHeader(),
            Expanded(
              child: TabBarView(
                children: [
                  _ReaderSettingsReadTab(
                    changePageIndex: changePageIndex,
                    onLandscapeChanged: onLandscapeChanged,
                  ),
                  _ReaderSettingsGestureTab(isAndroidPhone: isAndroidPhone),
                  const _ReaderSettingsInfoTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderSettingsHeader extends StatelessWidget {
  const _ReaderSettingsHeader();

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            decoration: BoxDecoration(
              color: colorScheme.outlineVariant.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelStyle: context.theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelStyle: context.theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w500),
                  tabs: [
                    Tab(text: t.reader.settings),
                    Tab(text: t.reader.gesture),
                    Tab(text: t.reader.infoBar),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: t.common.close,
                icon: const Icon(Icons.close, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ],
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

class _SettingsTabContent extends StatelessWidget {
  final Widget child;

  const _SettingsTabContent({required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: child,
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final IconData? icon;
  final List<Widget> children;

  const _SettingsSection({
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
class _SettingsCardGroup extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCardGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1 &&
                children[i] is! _SettingsAnimatedCollapse &&
                children[i + 1] is! _SettingsAnimatedCollapse)
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
    );
  }
}

/// MD3 分段选择器封装
class _SettingsSegmentedTile<T> extends StatelessWidget {
  final T selected;
  final List<ButtonSegment<T>> segments;
  final ValueChanged<T> onSelectionChanged;

  const _SettingsSegmentedTile({
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
class _SettingsAnimatedCollapse extends StatelessWidget {
  final bool isExpanded;
  final Widget child;
  final bool showDivider;

  const _SettingsAnimatedCollapse({
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

class _SettingsSwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchTile({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
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
      trailing: Switch.adaptive(
        value: value,
        activeTrackColor: colorScheme.primary,
        onChanged: onChanged,
      ),
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(!value);
      },
    );
  }
}

class _SettingsDropdownTile<T> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  static String _toStringLabel(Object? value) => '$value';

  const _SettingsDropdownTile({
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
