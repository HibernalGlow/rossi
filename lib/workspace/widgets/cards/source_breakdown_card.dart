import 'package:material_ui/material_ui.dart';
import 'package:zephyr/plugin/utils/plugin_display_name.dart';
import 'package:zephyr/workspace/model/history_insights.dart';
import 'package:zephyr/workspace/model/shelf_library_query.dart';
import 'package:zephyr/workspace/widgets/cards/history_insights_window.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';

/// 来源拆分（neoview `SourceBreakdownCard` 的同位物）。
///
/// 拆的轴与 neoview **有意不同**：那边只有本地文件，所以按文件类型拆
/// （压缩包 / 文件夹 / 图片…）；Rossi 的历史自带图源标识，于是这里按
/// 「条目从哪来」拆 —— 本地一类，每个插件图源一类。分类规则在
/// [classifyHistorySource]，卡片负责两件事：把聚合出来的**分组键**换成插件名
/// （口径与历史行一致，见 [shelfSourceLabel]），以及把占比画出来。
class SourceBreakdownCard extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;

  const SourceBreakdownCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    return CollapsibleCard(
      cardId: 'source_breakdown',
      title: '来源拆分',
      icon: Icons.pie_chart_outline_rounded,
      isExpanded: isExpanded,
      onToggle: onToggle,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onHide: onHide,
      child: HistoryInsightsWindow(
        skeletonHeight: 72,
        builder: (context, events) =>
            _Content(summary: buildSourceBreakdown(events)),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.summary});

  final SourceBreakdownSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 插件 id 是一串 uuid，摆在行上等于没显示；一次取全表，别让每行去问数据库。
    final pluginNames = pluginDisplayNames();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '样本窗口',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              '${summary.total} 条',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final item in summary.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _sourceLabel(pluginNames, item.source),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      '${item.count} (${item.percent}%)',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: item.percent / 100,
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 分组键 ⇒ 显示名。
///
/// [comicId] 传空串是有意的：`classifyHistorySource` 已经把本地折成「本地」这个键，
/// 到这一步只剩「uuid ⇒ 插件名，查不到就退回 8 位前缀」那一半逻辑，与历史行同一口径。
String _sourceLabel(Map<String, String> pluginNames, String key) =>
    shelfSourceLabel(
      source: key,
      comicId: '',
      pluginName: shelfPluginName(pluginNames, key),
    );
