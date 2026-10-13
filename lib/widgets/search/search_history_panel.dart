import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';

/// 两个历史入口共用现成的 Expressive 分组列表与全仓弹层表面。
class SearchHistoryPanel extends StatefulWidget {
  const SearchHistoryPanel({
    super.key,
    required this.queries,
    required this.onSelected,
    required this.onClear,
    this.highlighted = -1,
  });

  final List<String> queries;
  final ValueChanged<String> onSelected;
  final VoidCallback onClear;
  final int highlighted;

  @override
  State<SearchHistoryPanel> createState() => _SearchHistoryPanelState();
}

class _SearchHistoryPanelState extends State<SearchHistoryPanel> {
  final _rowKeys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _revealHighlight();
  }

  @override
  void didUpdateWidget(SearchHistoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlighted != widget.highlighted ||
        oldWidget.queries != widget.queries) {
      _revealHighlight();
    }
  }

  void _revealHighlight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final row = _rowKeys[widget.highlighted]?.currentContext;
      if (row != null) Scrollable.ensureVisible(row, alignment: .5);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final animate =
        !eInkInstantRoutes && !MediaQuery.disableAnimationsOf(context);
    return TextFieldTapRegion(
      child: ExcludeFocus(
        child: CommonPopupSurface(
          padding: const EdgeInsets.all(8),
          child: ActionBubbleRegion(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
                  child: Semantics(
                    header: true,
                    child: Row(
                      children: [
                        GlyphIcon(
                          AppGlyphs.history,
                          size: 20,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            t.search.history,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.queries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                    child: Text(
                      t.search.noHistory,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else ...[
                  Flexible(
                    child: SingleChildScrollView(
                      child: M3EList(
                        itemCount: widget.queries.length,
                        outerRadius: 20,
                        innerRadius: 4,
                        gap: 2,
                        color: scheme.surfaceContainerLow,
                        colorBuilder: (index) => index == widget.highlighted
                            ? scheme.secondaryContainer
                            : null,
                        semanticLabelBuilder: (index) => widget.queries[index],
                        haptic: M3EHapticFeedback.light,
                        onTap: (index) =>
                            widget.onSelected(widget.queries[index]),
                        itemBuilder: (context, index) => Semantics(
                          key: _rowKeys.putIfAbsent(index, GlobalKey.new),
                          selected: index == widget.highlighted,
                          child: ActionBubbleTarget(
                            enabled: animate,
                            observeFocus: false,
                            corner: 20,
                            child: ElasticPress(
                              enabled: animate,
                              child: M3EListItem(
                                headline: widget.queries[index],
                                selected: index == widget.highlighted,
                                leading: GlyphIcon(
                                  AppGlyphs.history,
                                  size: 20,
                                  color: index == widget.highlighted
                                      ? scheme.onSecondaryContainer
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElasticPress(
                    enabled: animate,
                    child: TextButton.icon(
                      style: ElasticPress.buttonStyle.merge(
                        TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          shape: const StadiumBorder(),
                        ),
                      ),
                      onPressed: widget.onClear,
                      icon: const GlyphIcon(AppGlyphs.delete, size: 18),
                      label: Text(t.search.clearHistory),
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
