import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/expressive/expressive_shape.dart';
import 'package:zephyr/widgets/navigation/navigation_shape.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_fill.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_fill_settings.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_settings_controls.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_weight_selector.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_cover_tap_settings.dart';
import 'package:zephyr/i18n/strings.g.dart';

Future<LibraryPresentation?> showLibrarySizeSettings(
  BuildContext context,
  LibraryPresentation value,
  List<LibraryWeightSignal> signals, {
  LibraryPresentation defaults = const LibraryPresentation(),
  List<LibraryGapWidgetSpec> gapWidgets = const [],
  bool fileStats = false,
  bool hasReading = true,
  double? availableWidth,
  LibraryCoverTapAction? defaultCoverTapAction,
  Set<LibraryWeight> availableWeights = const {
    LibraryWeight.order,
    LibraryWeight.balanced,
    LibraryWeight.imageShape,
  },
}) => showPopupPanel<LibraryPresentation>(
  context: context,
  presentation: PopupPresentation.relative,
  anchorOf: () {
    final box = context.findRenderObject() as RenderBox?;
    return box == null || !box.hasSize
        ? Rect.zero
        : box.localToGlobal(Offset.zero) & box.size;
  },
  builder: (_) => _LibrarySizeSettings(
    value: value,
    signals: signals,
    defaults: defaults,
    gapWidgets: gapWidgets,
    fileStats: fileStats,
    hasReading: hasReading,
    availableWidth: availableWidth,
    defaultCoverTapAction: defaultCoverTapAction,
    availableWeights: availableWeights,
  ),
);

class _LibrarySizeSettings extends StatefulWidget {
  const _LibrarySizeSettings({
    required this.value,
    required this.signals,
    required this.defaults,
    this.gapWidgets = const [],
    required this.fileStats,
    required this.hasReading,
    this.availableWidth,
    this.defaultCoverTapAction,
    required this.availableWeights,
  });
  final LibraryPresentation value;
  final List<LibraryWeightSignal> signals;
  final LibraryPresentation defaults;
  final List<LibraryGapWidgetSpec> gapWidgets;
  final bool fileStats, hasReading;
  final double? availableWidth;
  final LibraryCoverTapAction? defaultCoverTapAction;
  final Set<LibraryWeight> availableWeights;
  @override
  State<_LibrarySizeSettings> createState() => _LibrarySizeSettingsState();
}

class _LibrarySizeSettingsState extends State<_LibrarySizeSettings> {
  late LibraryPresentation value = widget.value;

  Widget slider(
    String label,
    double current,
    double min,
    double max,
    ValueChanged<double> change, {
    bool percent = false,
    String unit = '',
  }) => LibrarySettingsSlider(
    label: label,
    value: current,
    min: min,
    max: max,
    percent: percent,
    unit: unit,
    onChanged: (v) => setState(() => change(v)),
  );

  Widget toggle(String label, bool selected, ValueChanged<bool> change) =>
      LibrarySettingsToggle(
        label: label,
        selected: selected,
        onChanged: (v) => setState(() => change(v)),
      );

  void reset() {
    HapticFeedback.selectionClick();
    setState(
      () => value = widget.defaults.copyWith(
        signalWeights: {
          ...value.signalWeights,
          ...widget.defaults.signalWeights,
          for (final s in widget.signals) s.id: s.defaultWeight,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupPanel(
      title: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 240 ||
              MediaQuery.textScalerOf(context).scale(14) > 20) {
            return Text(
              t.workspace.displayWallCustom,
              style: theme.textTheme.titleSmall,
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: ShapeDecoration(
                  shape: expressiveButtonBorder(
                    ExpressiveButtonShape.cookie4Sided,
                    0,
                    48,
                  ),
                  color: theme.colorScheme.primaryContainer,
                ),
                child: GlyphIcon(
                  AppGlyphs.gradient,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.workspace.displayWallCustom,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t.workspace.layoutFitsPanel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LibrarySettingsGroup(
            title: '尺寸',
            glyph: AppGlyphs.resize,
            description: t.workspace.cardWidthAutoColumns,
            children: [
              if (widget.availableWidth != null) _densityChoices(context),
              slider(
                t.workspace.cardWidth,
                value.cardWidth,
                80,
                420,
                (v) => value = value.copyWith(cardWidth: v),
                unit: ' dp',
              ),
              slider(
                t.workspace.cardHeight,
                value.cardHeight,
                180,
                600,
                (v) => value = value.copyWith(cardHeight: v),
                unit: ' dp',
              ),
              slider(
                t.workspace.cardSpacing,
                value.gap,
                4,
                32,
                (v) => value = value.copyWith(gap: v),
                unit: ' dp',
              ),
              slider(
                t.workspace.imageSize,
                value.imageScale,
                .5,
                1,
                (v) => value = value.copyWith(imageScale: v),
                percent: true,
              ),
            ],
          ),
          LibrarySettingsGroup(
            title: '布局',
            glyph: AppGlyphs.layers,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    toggle(
                      t.workspace.displayWall,
                      value.editorial,
                      (v) => value = value.copyWith(editorial: v),
                    ),
                    if (widget.hasReading)
                      toggle(
                        t.workspace.heroVisual,
                        value.hero,
                        (v) => value = value.copyWith(hero: v),
                      ),
                    toggle(
                      t.workspace.contentSections,
                      value.sections,
                      (v) => value = value.copyWith(sections: v),
                    ),
                    toggle(
                      t.workspace.asymmetric,
                      value.asymmetric,
                      (v) => value = value.copyWith(asymmetric: v),
                    ),
                    if (widget.fileStats)
                      toggle(
                        t.workspace.includeSubdirStats,
                        value.recursiveStats,
                        (v) => value = value.copyWith(recursiveStats: v),
                      ),
                  ],
                ),
              ),
              LibraryGapFillChoices(
                value: value.gapFill,
                widgets: widget.gapWidgets,
                shapesEnabled: value.gapShapes,
                widgetToggles: value.gapWidgets,
                onChanged: (mode) =>
                    setState(() => value = value.copyWith(gapFill: mode)),
                onShapesChanged: (next) =>
                    setState(() => value = value.copyWith(gapShapes: next)),
                onWidgetChanged: (id, next) => setState(
                  () => value = value.copyWith(
                    gapWidgets: {...value.gapWidgets, id: next},
                  ),
                ),
              ),
              LibraryWeightSelector(
                value: value.weight,
                available: widget.availableWeights,
                onChanged: (w) =>
                    setState(() => value = value.copyWith(weight: w)),
              ),
              slider(
                t.workspace.sizeCompare,
                value.emphasis,
                0,
                1,
                (v) => value = value.copyWith(emphasis: v),
                percent: true,
              ),
            ],
          ),
          if (widget.defaultCoverTapAction != null)
            LibraryCoverTapSettings(
              value: value.coverTapAction ?? widget.defaultCoverTapAction!,
              onChanged: (action) => setState(
                () => value = value.copyWith(coverTapAction: action),
              ),
            ),
          if (widget.signals.isNotEmpty)
            LibrarySettingsGroup(
              title: t.workspace.favouriteTagWeight,
              glyph: AppGlyphs.sell,
              description: t.workspace.weightBiggerWins,
              children: [
                for (final signal in widget.signals)
                  slider(
                    signal.label,
                    value.signalWeights[signal.id] ?? signal.defaultWeight,
                    0,
                    10,
                    (v) => value = value.copyWith(
                      signalWeights: {...value.signalWeights, signal.id: v},
                    ),
                  ),
              ],
            ),
        ],
      ),
      actions: [
        M3EButton.text(onPressed: reset, child: const Text('恢复默认')),
        M3EButton.tonal(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        M3EButton.filled(
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context, value);
          },
          child: const Text('应用'),
        ),
      ],
    );
  }

  Widget _densityChoices(BuildContext context) {
    final width = widget.availableWidth!;
    final columns = libraryCanvasColumns(width, value);
    final choices = [2, 3, 4, 5, 6].where((count) {
      final target = libraryCardWidthForColumns(width, count, value.gap);
      return target >= 80 && target <= 420;
    });
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.workspace.columnsPerRow(columns: columns),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            t.workspace.normalOneWideTwoSlots,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final count in choices)
                ElasticButton(
                  enabled: !MediaQuery.disableAnimationsOf(context),
                  child: ChoiceChip(
                    label: Text(t.workspace.slotCount(count: count)),
                    selected: columns == count,
                    side: BorderSide.none,
                    shape: columns == count ? AppShape.xl : AppShape.md,
                    selectedColor: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHigh,
                    onSelected: (_) {
                      HapticFeedback.selectionClick();
                      setState(
                        () => value = value.copyWith(
                          cardWidth: libraryCardWidthForColumns(
                            width,
                            count,
                            value.gap,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
