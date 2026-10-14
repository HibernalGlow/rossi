import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scroll_spy/scroll_spy.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/setting/common/setting_scroll_spy.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';

/// 相邻设置共享外轮廓，内部只留短圆角与间隙，不给每行另套一张卡片。
///
/// 同时自动接入 [SettingScrollSpyScope]（基于 `scroll_spy` 包）：
/// 当提供 [sectionId] 或非空 [title] 时，自动注册为 `ScrollSpyItem<String>`，
/// 支持滚动位置实时检测、侧栏子树同步高亮、吸顶目录胶囊跳转及脉冲反馈。
class SettingGroup extends StatelessWidget {
  const SettingGroup({
    super.key,
    this.sectionId,
    this.title,
    required this.children,
    this.icon,
  });

  /// 稳定的分组锚点 ID（例如 `'appearance.theme'`）。
  /// 若未显式传入且 [title] 非空，将自动通过 [SettingPageScrollSpyController]
  /// 映射回预设分组 ID 或以标题生成稳定 ID。
  final String? sectionId;

  /// 分组标题。页面大标题已经写过一遍的事情不再重复，所以可以不给。
  final String? title;
  final Glyph? icon;
  final List<Widget> children;

  /// 设置行 + M3E 开关，替代旧 `SwitchListTile`。
  ///
  /// 拨块走 M3E 的弹簧轨道，勾号固定，配色由主题给（active 轨 = primary）。
  /// 留白与行高不在这里收紧：各页原有的 `ListTileTheme` 继续生效，换控件不该顺带改排版。
  static Widget switchTile({
    Widget? leading,
    required Object? title,
    Object? subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    EdgeInsets? contentPadding,
  }) {
    final label = title is String
        ? title
        : title is Text
        ? title.data
        : null;
    return ListTile(
      leading: leading,
      title: _asRowText(title),
      subtitle: _asRowText(subtitle),
      contentPadding: contentPadding,
      // 旧 `SwitchListTile` 整行可点，这是它的定义性行为，不是附加功能：
      // 只把点击留给拨块会让「点标题没反应」变成回归（switch_toast_test 守这条）。
      onTap: onChanged == null ? null : () => onChanged(!value),
      trailing: M3ESwitch(
        semanticLabel: label,
        value: value,
        selectedIcon: const Icon(Icons.check, size: 16),
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final spyScope = SettingScrollSpyScope.maybeOf(context);
    final resolvedId = spyScope?.resolveAndRegisterGroup(
      explicitId: sectionId,
      title: title,
      icon: icon,
    );

    Widget groupBody(bool highlighted) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title case final text? when text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
                child: Semantics(
                  header: true,
                  child: Row(
                    children: [
                      if (icon != null) ...[
                        GlyphIcon(
                          icon!,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          text,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            AnimatedContainer(
              duration: ExpressiveMotion.duration(
                context,
                ExpressiveMotion.spatialDuration,
              ),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: highlighted
                      ? theme.colorScheme.primary.withValues(alpha: 0.65)
                      : Colors.transparent,
                  width: highlighted ? 1.5 : 0,
                ),
              ),
              child: ActionBubbleRegion(
                child: M3EList(
                  itemCount: children.length,
                  // Material ListTile 的水波纹必须画在分组表面的上方。
                  itemBuilder: (_, index) => Material(
                    type: MaterialType.transparency,
                    child: ActionBubbleTarget(
                      enabled: !eInkInstantRoutes,
                      corner: 20,
                      child: ElasticPress(
                        enabled:
                            !eInkInstantRoutes &&
                            !MediaQuery.disableAnimationsOf(context),
                        child: children[index],
                      ),
                    ),
                  ),
                  padding: EdgeInsets.zero,
                  outerRadius: 24,
                  innerRadius: 4,
                  gap: 2,
                  color: highlighted
                      ? Color.alphaBlend(
                          theme.colorScheme.primary.withValues(alpha: 0.08),
                          theme.colorScheme.surfaceContainerLow,
                        )
                      : theme.colorScheme.surfaceContainerLow,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (resolvedId == null || spyScope == null) {
      return groupBody(false);
    }

    return ScrollSpyItem<String>(
      key: ValueKey<String>('setting-spy-item:$resolvedId'),
      id: resolvedId,
      child: ValueListenableBuilder<String?>(
        valueListenable: spyScope.highlightedSectionId,
        builder: (context, highlightedId, _) =>
            groupBody(highlightedId == resolvedId),
      ),
    );
  }
}

/// 旧 `SwitchListTile` 的 title/subtitle 收 String 或 Widget，ListTile 只收
/// Widget —— 补上当初控件替调用方做的那步转换，字符串走 ListTileTheme 的字号。
Widget? _asRowText(Object? value) =>
    value is String ? Text(value) : value as Widget?;
