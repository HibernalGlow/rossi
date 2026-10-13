import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';

/// 相邻设置共享外轮廓，内部只留短圆角与间隙，不给每行另套一张卡片。
class SettingGroup extends StatelessWidget {
  const SettingGroup({
    super.key,
    required this.title,
    required this.children,
    this.icon,
  });

  final String title;
  final Glyph? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                      title,
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
          ActionBubbleRegion(
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
              color: theme.colorScheme.surfaceContainerLow,
            ),
          ),
        ],
      ),
    );
  }
}
