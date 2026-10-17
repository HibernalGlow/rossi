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

/// 上游 Section 的呈现适配；业务回调与本漫写入路由仍来自原调用方。
class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  const _SettingsSection({
    required this.title,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final content = <Widget>[];
    for (var i = 0; i < children.length;) {
      final child = children[i];
      if (child is _SettingsSwitchTile) {
        final toggles = <_SettingsSwitchTile>[];
        while (i < children.length && children[i] is _SettingsSwitchTile) {
          toggles.add(children[i++] as _SettingsSwitchTile);
        }
        content.add(
          toggles.length == 1 ? toggles.single : _settingsToggleGroup(toggles),
        );
      } else {
        i++;
        content.add(
          child is Wrap && child.children.every((w) => w is _SettingsChoiceChip)
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: _SettingsChoiceGroup(
                    choices: child.children.cast<_SettingsChoiceChip>(),
                  ),
                )
              : child is _SettingsDropdownTile || child is _SettingsSliderCard
              ? child
              : Padding(padding: const EdgeInsets.all(12), child: child),
        );
      }
    }
    return SettingsSection(
      title: title,
      icon: _settingsGlyph(title),
      trailing: trailing,
      children: [SettingsCardGroup(children: content)],
    );
  }
}

class _SettingsChoiceChip extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;
  final Glyph? icon;
  final bool autoHideText;

  const _SettingsChoiceChip({
    required this.title,
    required this.selected,
    required this.onTap,
    this.icon,
    this.autoHideText = false,
  });

  @override
  Widget build(BuildContext context) =>
      SettingsChoiceChip(title: title, selected: selected, onTap: onTap);
}

/// 互斥选项共享 Dock 的惯性 lens；窄屏改为竖轨，避免文字被截断。
/// 支持在宽度不足时自动隐藏文字，仅显示图标以保持单行横排。
class _SettingsChoiceGroup extends StatelessWidget {
  const _SettingsChoiceGroup({required this.choices, this.autoHideText});
  final List<_SettingsChoiceChip> choices;
  final bool? autoHideText;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final style = DefaultTextStyle.of(
        context,
      ).style.merge(context.theme.textTheme.labelLarge);
      var naturalWidth = 0.0;
      for (final choice in choices) {
        final painter = TextPainter(
          text: TextSpan(text: choice.title, style: style),
          textScaler: scaler,
          textDirection: Directionality.of(context),
        )..layout();
        final choiceWidth = painter.width + scaler.scale(20) + 32;
        if (choiceWidth > naturalWidth) naturalWidth = choiceWidth;
        painter.dispose();
      }

      final canHideText = autoHideText ?? choices.any((c) => c.autoHideText);
      final availableWidth = constraints.maxWidth - 8;
      final fitsWithText = naturalWidth * choices.length <= availableWidth;
      final iconOnlyWidth = scaler.scale(20) + 28;
      final fitsWithIconOnly = iconOnlyWidth * choices.length <= availableWidth;

      final bool hideText;
      final bool vertical;

      if (fitsWithText) {
        hideText = false;
        vertical = false;
      } else if (canHideText && fitsWithIconOnly) {
        hideText = true;
        vertical = false;
      } else {
        hideText = false;
        vertical = naturalWidth * choices.length > availableWidth;
      }

      final extent = (scaler.scale(20) + 32).clamp(52.0, 100.0);
      return Container(
        decoration: BoxDecoration(
          color: context.theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.all(4),
        child: SizedBox(
          height: vertical ? choices.length * extent : extent,
          child: SpringLensBar(
            axis: vertical ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            selectedIndex: choices.indexWhere((choice) => choice.selected),
            onSelected: (index) => choices[index].onTap(),
            lensCorner: 20,
            tintColor: context.theme.colorScheme.onSecondaryContainer,
            tabs: [
              for (final choice in choices)
                SpringLensTab(
                  semanticLabel: choice.title,
                  tooltip: choice.title,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GlyphIcon(
                            choice.icon ?? _settingsGlyph(choice.title),
                            size: 20,
                          ),
                          if (!hideText) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                choice.title,
                                style: style,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

Glyph _settingsGlyph(String title) {
  final icons = <String, Glyph>{
    t.reader.readingMode: AppGlyphs.openBook,
    t.reader.webtoon: AppGlyphs.layoutList,
    t.reader.singlePageLtr: AppGlyphs.chevronForward,
    t.reader.singlePageRtl: AppGlyphs.chevronBack,
    t.reader.doublePage: AppGlyphs.layers,
    t.reader.doublePageSeamless: AppGlyphs.link,
    t.reader.doublePageLeadingBlank: AppGlyphs.add,
    t.reader.readingDirectionToggleSetting: AppGlyphs.sync,
    t.reader.swipePreview: AppGlyphs.photos,
    t.reader.readWhileDownloading: AppGlyphs.cloudDownload,
    t.reader.themeMode: AppGlyphs.palette,
    t.common.lightMode: AppGlyphs.sun,
    t.common.darkMode: AppGlyphs.moon,
    t.common.followSystem: AppGlyphs.themeAuto,
    t.reader.pageNumber: AppGlyphs.openBook,
    t.reader.networkStatus: AppGlyphs.networkCheck,
    t.reader.battery: AppGlyphs.battery6,
    t.reader.time: AppGlyphs.clock,
    t.reader.infoDisplay: AppGlyphs.info,
    t.reader.preload: AppGlyphs.cloudDownload,
    t.reader.autoRead: AppGlyphs.playCircle,
    t.reader.background: AppGlyphs.palette,
    t.reader.readingExperience: AppGlyphs.sparkle,
    t.reader.disableAnimation: AppGlyphs.motion,
    t.reader.readFilter: AppGlyphs.eye,
    t.reader.einkOptimization: AppGlyphs.openBook,
    t.reader.sidePadding: AppGlyphs.layers,
  };
  return icons[title] ?? AppGlyphs.sliders;
}

class _SettingsSwitchTile extends StatelessWidget {
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
  Widget build(BuildContext context) => SettingsSwitchTile(
    title: title,
    subtitle: subtitle,
    value: value,
    onChanged: onChanged,
  );
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
  Widget build(BuildContext context) => SettingsDropdownTile<int>(
    title: title,
    subtitle: subtitle,
    value: value,
    values: values,
    onChanged: onChanged,
  );
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
  Widget build(BuildContext context) => SettingsSliderCard(
    title: title,
    value: value,
    min: min,
    max: max,
    divisions: divisions,
    suffix: suffix,
    enabled: enabled,
    onChanged: onChanged,
  );
}

class _SettingsNoticeCard extends StatelessWidget {
  final String text;
  const _SettingsNoticeCard({required this.text});
  @override
  Widget build(BuildContext context) => SettingsNoticeCard(text: text);
}

Widget _settingsToggleGroup(List<_SettingsSwitchTile> toggles) =>
    SettingsToggleGroup(
      options: [
        for (final toggle in toggles)
          SettingsToggleOption(
            title: toggle.title,
            description: toggle.subtitle,
            icon: _settingsGlyph(toggle.title),
            selected: toggle.value,
            onChanged: toggle.onChanged,
          ),
      ],
    );
