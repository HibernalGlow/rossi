// 只用 material_ui：它自带一套 MaterialApp / Scaffold / Icons（与主应用同一套），
// 再 import flutter/material 会得到一堆二义名。
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/discover/service/plugin_function_kind.dart';
import 'package:zephyr/type/pipe.dart';
import 'package:zephyr/util/json/json_value.dart';
import 'package:zephyr/util/text/chinese_convert.dart';

/// 插件卡上那一排功能胶囊。
///
/// 一排同色同形的描边药丸辨识度低，但解法**不是**给每类刷一种颜色 ——
/// MD3 的调色板只有 primary / secondary / tertiary / error 四条轴线，
/// 硬凑十种色相只会变成一坨与主题无关的彩虹（换套主题就全乱）。
/// 这里按 MD3 自己的两条分工来做：
/// - **档位**（[PluginFunctionTone]）用容器色分开：浏览类走 `secondaryContainer` 实心
///   tonal，用户自己的东西走 `tertiaryContainer` 实心 tonal，工具与兜底退成
///   透明底 + `outline` 描边的 assist chip。三档的显眼程度递减，
///   「进去看内容」的那两颗自然浮出来。
/// - **具体是哪一项**交给 leading icon —— 形状比字扫得快，而且图标是主题无关的，
///   插件作者把「最新」写成「新番」也还是那个时钟。
class PluginFunctionChips extends StatelessWidget {
  const PluginFunctionChips({
    super.key,
    required this.functions,
    required this.onAction,
  });

  final List<Map<String, dynamic>> functions;
  final Future<void> Function(Map<String, dynamic> action) onAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final function in functions)
          _buildChip(context, colorScheme, function),
      ],
    );
  }

  Widget _buildChip(
    BuildContext context,
    ColorScheme colorScheme,
    Map<String, dynamic> function,
  ) {
    final id = function['id']?.toString().trim() ?? '';
    final rawTitle = function['title']?.toString().trim() ?? '';
    final title = rawTitle.isEmpty ? t.discover.unnamed : rawTitle;

    final action = asJsonMap(function['action']);
    final kind = classifyPluginFunction(
      id: id,
      title: rawTitle,
      actionType: action['type']?.toString().trim() ?? '',
    );

    // 插件只给 id 不给 action 时，宿主自己补一颗「按 id 打开功能页」的默认动作；
    // 连 id 都没有的那颗点不动。
    var resolved = action;
    if (resolved.isEmpty && id.isNotEmpty) {
      resolved = {
        'type': 'openPluginFunction',
        'payload': {'id': id, 'title': title, 'presentation': 'page'},
      };
    }
    final enabled = resolved.isNotEmpty;

    final background = !enabled
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.12)
        : switch (kind.tone) {
            PluginFunctionTone.browse => colorScheme.secondaryContainer,
            PluginFunctionTone.library => colorScheme.tertiaryContainer,
            PluginFunctionTone.tool => Colors.transparent,
          };
    final foreground = !enabled
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : switch (kind.tone) {
            PluginFunctionTone.browse => colorScheme.onSecondaryContainer,
            PluginFunctionTone.library => colorScheme.onTertiaryContainer,
            PluginFunctionTone.tool => colorScheme.onSurfaceVariant,
          };
    // 实心两档不带描边（MD3 的 tonal chip 就是没有边的）；只有描边档需要一条边。
    // 用 outline 而不是 outlineVariant：后者在深色主题上几乎看不见，
    // 而这一档整颗胶囊就靠那条边表达「这是个能点的东西」。
    final side = enabled && kind.tone == PluginFunctionTone.tool
        ? BorderSide(color: colorScheme.outline)
        : BorderSide.none;

    return ActionChip(
      avatar: Icon(_iconOf(kind), size: 16, color: foreground),
      label: ConstrainedBox(
        // 标题是插件作者写的，长度没有上限；不给个顶，一颗长名胶囊就能把整排撑成
        // 一行一个，比原来那排药丸还难扫。
        // 160 是**宽度预算**的最后一项，不是随手取的数：
        // 8 + 16(图标) + 6 + 160 + 8 = 198dp，而最窄手机上卡片的内容区有
        // 320 − 32(卡边距) − 40(内边距) = 248dp，所以单颗胶囊撑不破一行，
        // 超出的字由 ellipsis 收掉。
        constraints: const BoxConstraints(maxWidth: 160),
        child: Text(
          title.let(convertChineseForDisplay),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      onPressed: enabled ? () => onAction(resolved) : null,
      backgroundColor: background,
      disabledColor: background,
      side: side,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      labelPadding: const EdgeInsets.only(left: 6),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: foreground,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  IconData _iconOf(PluginFunctionKind kind) {
    return switch (kind) {
      PluginFunctionKind.latest => Icons.schedule,
      PluginFunctionKind.ranking => Icons.leaderboard,
      PluginFunctionKind.popular => Icons.local_fire_department,
      PluginFunctionKind.recommend => Icons.auto_awesome,
      PluginFunctionKind.random => Icons.casino_outlined,
      PluginFunctionKind.favorite => Icons.favorite_border,
      PluginFunctionKind.cloudFavorite => Icons.cloud_outlined,
      PluginFunctionKind.history => Icons.history,
      PluginFunctionKind.search => Icons.search,
      PluginFunctionKind.category => Icons.category_outlined,
      PluginFunctionKind.unknown => Icons.apps_outlined,
    };
  }
}
