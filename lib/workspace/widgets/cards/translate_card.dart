import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/widgets/settings/sections/translate_section.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';

/// 「翻译」卡片 —— 阅读设置「翻译」那一排搬进控制面板。
///
/// 正文是 [TranslateSettingsSection]，与面板那份**同一个 widget**。
/// 差别只有一条：这里不给 `onOpenFullSettings` —— 卡片没有路由可弹，
/// 于是那一行自己变成「就地展开完整设置」（端点 / 模型 / Key / 术语表都在卡里改）。
/// 配置落在 `OcrSettings` 那一份 SharedPreferences 上，两边靠 `OcrSettings.changes`
/// 互相跟随。
class TranslateCard extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final bool isStandalone;
  final String? disabledHint;

  const TranslateCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.isStandalone = false,
    this.disabledHint,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [TranslateSettingsSection()],
    );

    if (isStandalone) {
      content = SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        // 独占面板没有折叠外壳，标题行那颗 tag 画不出来，灰显至少得生效。
        child: applyCardGate(content, disabledHint: disabledHint),
      );
      return Material(type: MaterialType.transparency, child: content);
    }

    return CollapsibleCard(
      cardId: WorkspaceCardRegistry.translate,
      title: '翻译',
      icon: Icons.translate_outlined,
      isExpanded: isExpanded,
      onToggle: onToggle,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onHide: onHide,
      disabledHint: disabledHint,
      child: content,
    );
  }
}
