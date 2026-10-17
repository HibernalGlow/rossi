import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/navigation/navigation_shape.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_fill.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_preview.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_shape.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_settings_controls.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 「展墙自定义」面板「组件」页签的主体。
///
/// 三件事必须同时成立，所以它单独成一块：
///
/// 1. **统一**：总口径（不填充 / 随机图形 / 小组件 / 组件 + 图形）、随机图形
///    总开关、每一款组件、每一款图形都在这一屏里，不再散落在「布局」分组
///    的一串胶囊里；
/// 2. **可视化预览**：顶部先给「当前效果」（一颗实际会用到的组件 + 一款实际
///    会抽到的图形），网格里每一项都用**真实 builder / painter** 在真实槽位
///    尺寸下渲染 —— 预览与上墙是同一份代码，不另做缩略图；
/// 3. **作用域明确**：「全部开启 / 全部关闭」只作用于当前页签，「恢复默认」
///    由宿主面板统一负责（只还原空隙相关项，尺寸、排序与权重不动）。
///
/// 不自己持有 `value`：改一项就通过 [onChanged] 交回宿主，与设置面板其余
/// 分组共用同一次「应用」落盘。
class LibraryGapSettingsBody extends StatefulWidget {
  const LibraryGapSettingsBody({
    super.key,
    required this.value,
    required this.widgets,
    required this.onChanged,
  });

  final LibraryPresentation value;

  /// 本面墙的完整套件（含被关掉的那些，否则再也打不开）。
  final List<LibraryGapWidgetSpec> widgets;
  final ValueChanged<LibraryPresentation> onChanged;

  @override
  State<LibraryGapSettingsBody> createState() => _LibraryGapSettingsBodyState();
}

enum _GapTab { widgets, shapes }

class _LibraryGapSettingsBodyState extends State<LibraryGapSettingsBody> {
  late final List<LibraryEntry> _entries = libraryGapPreviewEntries();
  _GapTab _tab = _GapTab.widgets;

  LibraryPresentation get _value => widget.value;

  void _update(LibraryPresentation next) => widget.onChanged(next);

  bool _widgetOn(LibraryGapWidgetSpec spec) =>
      _value.gapWidgets[spec.id] ?? true;

  bool _shapeOn(LibraryGapShapeStyle style) =>
      _value.gapShapeStyles[style.name] ?? true;

  int get _widgetCount => widget.widgets.where(_widgetOn).length;

  int get _shapeCount => kLibraryGapShapeStyles.where(_shapeOn).length;

  void _setFill(LibraryGapFill mode) {
    HapticFeedback.selectionClick();
    _update(_value.copyWith(gapFill: mode));
  }

  void _toggleWidget(String id) {
    HapticFeedback.selectionClick();
    _update(
      _value.copyWith(
        gapWidgets: {
          ..._value.gapWidgets,
          id: !(_value.gapWidgets[id] ?? true),
        },
      ),
    );
  }

  void _toggleShape(LibraryGapShapeStyle style) {
    HapticFeedback.selectionClick();
    _update(
      _value.copyWith(
        gapShapeStyles: {
          ..._value.gapShapeStyles,
          style.name: !(_value.gapShapeStyles[style.name] ?? true),
        },
      ),
    );
  }

  /// 「全部开启 / 关闭」只作用于当前页签：用户在小组件页点「全部关闭」，
  /// 不该顺手把随机图形也关掉。
  void _setAll(bool enabled) {
    HapticFeedback.selectionClick();
    if (_tab == _GapTab.widgets) {
      _update(
        _value.copyWith(
          gapWidgets: {for (final spec in widget.widgets) spec.id: enabled},
        ),
      );
      return;
    }
    _update(
      _value.copyWith(
        gapShapeStyles: {
          for (final style in kLibraryGapShapeStyles) style.name: enabled,
        },
      ),
    );
  }

  /// 当前生效口径下第一颗可用小组件：给「当前效果」预览。
  LibraryGapWidgetSpec? get _firstEnabledWidget =>
      widget.widgets.where(_widgetOn).firstOrNull;

  LibraryGapShapeStyle? get _firstEnabledShape =>
      kLibraryGapShapeStyles.where(_shapeOn).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _modeSection(theme),
        const SizedBox(height: 12),
        _effectPreview(theme),
        const SizedBox(height: 14),
        _tabs(theme),
        const SizedBox(height: 10),
        if (_tab == _GapTab.widgets) _widgetGrid(theme) else _shapeGrid(theme),
      ],
    );
  }

  /// 总口径：不填充 / 随机图形 / 小组件 / 组件 + 图形。
  Widget _modeSection(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.workspace.gapFill, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final mode in LibraryGapFill.values)
              ElasticButton(
                enabled: !MediaQuery.disableAnimationsOf(context),
                child: ChoiceChip(
                  label: Text(mode.label),
                  selected: mode == _value.gapFill,
                  side: BorderSide.none,
                  shape: mode == _value.gapFill ? AppShape.xl : AppShape.md,
                  selectedColor: scheme.secondaryContainer,
                  backgroundColor: scheme.surfaceContainerHigh,
                  onSelected: (_) => _setFill(mode),
                ),
              ),
            const SizedBox(width: 4),
            LibrarySettingsToggle(
              label: t.workspace.randomShapes,
              selected: _value.gapShapes,
              onChanged: (next) {
                _update(_value.copyWith(gapShapes: next));
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          switch (_value.gapFill) {
            LibraryGapFill.off => t.workspace.keepGapIrregularOutline,
            LibraryGapFill.shapes => t.workspace.fillWithExpressiveShapes,
            LibraryGapFill.widgets => t.workspace.onlyFittingWidgetsRepeat,
            LibraryGapFill.both => t.workspace.widgetsOnceThenShapes,
          },
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// 「当前效果」：一颗实际生效的小组件 + 一款实际生效的随机图形。
  ///
  /// 逐项预览说明的是「这一颗长什么样」，这一条说明的是「现在这面墙会先
  /// 出现什么」—— 两者合起来才算把口径讲清楚。
  Widget _effectPreview(ThemeData theme) {
    final spec = _firstEnabledWidget;
    final shape = _firstEnabledShape;
    final scheme = theme.colorScheme;
    Widget slot({required Widget child, required String caption, Key? key}) =>
        Expanded(
          child: Column(
            key: key,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 86,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: const BorderRadius.all(Radius.circular(16)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: child,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                caption,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
    final showsWidgets =
        _value.gapFill == LibraryGapFill.both ||
        _value.gapFill == LibraryGapFill.widgets;
    final showsShapes =
        _value.gapFill == LibraryGapFill.shapes ||
        _value.gapFill == LibraryGapFill.both;
    final widgetPreview = spec != null && showsWidgets
        ? slot(
            key: const ValueKey('gap-effect-widget'),
            child: LibraryGapWidgetPreview(spec: spec, entries: _entries),
            caption: spec.label,
          )
        : slot(
            key: const ValueKey('gap-effect-widget'),
            child: _emptySlot(theme, t.workspace.gapWidgetsSection),
            caption: t.workspace.gapWidgetsSection,
          );
    final shapePreview = shape != null && showsShapes && _value.gapShapes
        ? slot(
            key: const ValueKey('gap-effect-shape'),
            child: Center(
              child: AspectRatio(
                aspectRatio: 1.2,
                child: LibraryGapShapePreview(style: shape),
              ),
            ),
            caption: shape.label,
          )
        : slot(
            key: const ValueKey('gap-effect-shape'),
            child: _emptySlot(theme, t.workspace.gapShapesSection),
            caption: t.workspace.gapShapesSection,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.workspace.gapPreviewLabel,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [widgetPreview, const SizedBox(width: 10), shapePreview],
        ),
      ],
    );
  }

  Widget _emptySlot(ThemeData theme, String caption) => Center(
    child: Text(
      caption,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _tabs(ThemeData theme) {
    final scheme = theme.colorScheme;
    Widget tab(_GapTab value, String label, int count, Key key) {
      final selected = _tab == value;
      return ElasticButton(
        enabled: !MediaQuery.disableAnimationsOf(context),
        child: ChoiceChip(
          key: key,
          label: Text('$label · $count'),
          selected: selected,
          side: BorderSide.none,
          shape: selected ? AppShape.xl : AppShape.md,
          selectedColor: scheme.secondaryContainer,
          backgroundColor: scheme.surfaceContainerHigh,
          onSelected: (_) {
            HapticFeedback.selectionClick();
            setState(() => _tab = value);
          },
        ),
      );
    }

    // 用 Wrap 而不是 Row：窄屏 + 大字号下两颗页签加两个动作会顶出面板，
    // 折行比裁掉更诚实。
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        tab(
          _GapTab.widgets,
          t.workspace.gapWidgetsSection,
          _widgetCount,
          const ValueKey('gap-tab-widgets'),
        ),
        tab(
          _GapTab.shapes,
          t.workspace.gapShapesSection,
          _shapeCount,
          const ValueKey('gap-tab-shapes'),
        ),
        TextButton(
          key: const ValueKey('gap-enable-all'),
          onPressed: () => _setAll(true),
          child: Text(t.workspace.gapEnableAll),
        ),
        TextButton(
          key: const ValueKey('gap-disable-all'),
          onPressed: () => _setAll(false),
          child: Text(t.workspace.gapDisableAll),
        ),
      ],
    );
  }

  Widget _widgetGrid(ThemeData theme) => _grid(theme, [
    for (final spec in widget.widgets)
      _gapCard(
        theme,
        key: ValueKey('gap-widget-card-${spec.id}'),
        enabled: _widgetOn(spec),
        label: spec.label,
        meta: t.workspace.gapMinSize(
          w: spec.minWidth.round(),
          h: spec.minHeight.round(),
        ),
        previewHeight: 112,
        onTap: () => _toggleWidget(spec.id),
        child: KeyedSubtree(
          key: ValueKey('gap-widget-preview-${spec.id}'),
          child: LibraryGapWidgetPreview(spec: spec, entries: _entries),
        ),
      ),
  ]);

  Widget _shapeGrid(ThemeData theme) => _grid(theme, [
    for (final (index, style) in kLibraryGapShapeStyles.indexed)
      _gapCard(
        theme,
        key: ValueKey('gap-shape-card-${style.name}'),
        enabled: _shapeOn(style),
        label: style.label,
        meta: null,
        previewHeight: 92,
        onTap: () => _toggleShape(style),
        child: KeyedSubtree(
          key: ValueKey('gap-shape-preview-${style.name}'),
          // 近方形 + 不同种子：八张卡并排时既看得出轮廓差异，
          // 也看得到配色不是只有一种。
          child: Center(
            child: AspectRatio(
              aspectRatio: 1.35,
              child: LibraryGapShapePreview(style: style, seed: 7 + index),
            ),
          ),
        ),
      ),
  ]);

  Widget _grid(ThemeData theme, List<Widget> cards) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : 640.0;
      // 宽面板固定 3 列（预览大一点才看得清组件到底长什么样）；
      // 手机按 150dp 下限折 2 列，再窄才退成一列。
      final columns = width >= 560 ? 3 : (width / 150).floor().clamp(1, 2);
      final cardWidth = (width - (columns - 1) * 10) / columns;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final card in cards) SizedBox(width: cardWidth, child: card),
        ],
      );
    },
  );

  /// 一张「预览 + 名字 + 开关」卡：点整张卡切换，不再单独找一颗小开关。
  Widget _gapCard(
    ThemeData theme, {
    required Key key,
    required bool enabled,
    required String label,
    required String? meta,
    required double previewHeight,
    required VoidCallback onTap,
    required Widget child,
  }) {
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: enabled,
      label: label,
      child: ElasticButton(
        enabled: !MediaQuery.disableAnimationsOf(context),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            decoration: BoxDecoration(
              color: enabled
                  ? scheme.surfaceContainerLow
                  : scheme.surfaceContainerLow.withValues(alpha: .45),
              borderRadius: const BorderRadius.all(Radius.circular(18)),
              border: Border.all(
                color: enabled
                    ? scheme.primary.withValues(alpha: .55)
                    : scheme.outlineVariant.withValues(alpha: .28),
                width: enabled ? 1.4 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: previewHeight,
                  child: Opacity(opacity: enabled ? 1 : .45, child: child),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    GlyphIcon(
                      enabled ? AppGlyphs.checkCircle : AppGlyphs.dot,
                      size: 14,
                      color: enabled
                          ? scheme.primary
                          : scheme.onSurfaceVariant.withValues(alpha: .5),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: enabled
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                if (meta != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant.withValues(alpha: .7),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
