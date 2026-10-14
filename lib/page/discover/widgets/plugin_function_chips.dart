// 只用 material_ui：它自带一套 MaterialApp / Scaffold / Icons（与主应用同一套），
// 再 import flutter/material 会得到一堆二义名。
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/discover/service/plugin_function_kind.dart';
import 'package:zephyr/type/pipe.dart';
import 'package:zephyr/util/json/json_value.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/widgets/spring_lens/jelly_hover.dart';

/// 插件卡上那一排 MD3 Expressive 功能胶囊。
///
/// 按 MD3E 语义分工与流体形态设计：
/// - **档位**（[PluginFunctionTone]）用主题语义容器色分层：
///   - 浏览类（`browse`）走 `secondaryContainer` 实心 tonal；
///   - 用户个人类（`library`）走 `primaryContainer` 实心 tonal（跟随全局主色，避免旧版暗黄褐色突兀）；
///   - 工具与兜底类（`tool`）走透明底 + `outline` 描边的 assist chip；
/// - **形态与物理动效**：静止态为超椭圆圆角（`RoundedSuperellipseBorder`），悬停时经 [JellyHover]
///   双轴弹簧连续收成全圆角胶囊（stadium），按压时经 [ElasticButton] 触发空间弹簧形变与触觉反馈。
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
    final animate =
        enabled &&
        !eInkInstantRoutes &&
        !MediaQuery.disableAnimationsOf(context);

    final background = !enabled
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.12)
        : switch (kind.tone) {
            PluginFunctionTone.browse => colorScheme.secondaryContainer,
            PluginFunctionTone.library => colorScheme.primaryContainer,
            PluginFunctionTone.tool => Colors.transparent,
          };
    final foreground = !enabled
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : switch (kind.tone) {
            PluginFunctionTone.browse => colorScheme.onSecondaryContainer,
            PluginFunctionTone.library => colorScheme.onPrimaryContainer,
            PluginFunctionTone.tool => colorScheme.onSurfaceVariant,
          };
    // 实心两档不带描边（MD3 的 tonal chip 就是没有边的）；只有描边档需要一条边。
    // 用 outline 而不是 outlineVariant：后者在深色主题上几乎看不见，
    // 而这一档整颗胶囊就靠那条边表达「这是个能点的东西」。
    final side = enabled && kind.tone == PluginFunctionTone.tool
        ? BorderSide(color: colorScheme.outline)
        : BorderSide.none;

    return JellyHover(
      enabled: animate,
      builder: (context, swellX, _) {
        final morph = swellX.clamp(0.0, 1.0);
        // 静止态为 14dp 超椭圆圆角，悬停/按压时平滑过渡为 24dp 胶囊（Stadium）。
        final cornerRadius = 14.0 + 10.0 * morph;
        return ElasticButton(
          enabled: animate,
          child: ActionChip(
            avatar: GlyphIcon(_iconOf(kind), size: 16, color: foreground),
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
            onPressed: enabled
                ? () {
                    HapticFeedback.lightImpact();
                    onAction(resolved);
                  }
                : null,
            backgroundColor: background,
            disabledColor: background,
            side: side,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(cornerRadius),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            labelPadding: const EdgeInsets.only(left: 6, right: 2),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }

  Glyph _iconOf(PluginFunctionKind kind) {
    return switch (kind) {
      PluginFunctionKind.latest => AppGlyphs.clock,
      PluginFunctionKind.ranking => AppGlyphs.trophy,
      PluginFunctionKind.popular => AppGlyphs.fire,
      PluginFunctionKind.recommend => AppGlyphs.sparkle,
      PluginFunctionKind.random => AppGlyphs.dice,
      PluginFunctionKind.favorite => AppGlyphs.heart,
      PluginFunctionKind.cloudFavorite => AppGlyphs.cloud,
      PluginFunctionKind.history => AppGlyphs.history,
      PluginFunctionKind.search => AppGlyphs.search,
      PluginFunctionKind.category => AppGlyphs.category,
      PluginFunctionKind.unknown => AppGlyphs.apps,
    };
  }
}
