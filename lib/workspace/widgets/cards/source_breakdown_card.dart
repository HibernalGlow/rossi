import 'package:material_ui/material_ui.dart';
import 'package:zephyr/plugin/utils/plugin_display_name.dart';
import 'package:zephyr/workspace/model/history_insights.dart';
import 'package:zephyr/workspace/model/shelf_library_query.dart';
import 'package:zephyr/workspace/widgets/cards/history_insights_window.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/widgets/insights/source_mix_view.dart';
import 'package:zephyr/i18n/strings.g.dart';

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
      expressive: true,
      cardId: 'source_breakdown',
      title: t.workspace.sourceBreakdown,
      icon: AppGlyphs.pieChart,
      isExpanded: isExpanded,
      onToggle: onToggle,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onHide: onHide,
      child: HistoryInsightsWindow(
        skeletonHeight: 72,
        builder: (context, events) {
          final names = pluginDisplayNames();
          return SourceMixView(
            summary: buildSourceBreakdown(events),
            sourceLabel: (key) => _sourceLabel(names, key),
          );
        },
      ),
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
