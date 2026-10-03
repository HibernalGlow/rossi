import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/widgets/settings/sections/super_resolution_section.dart';
import 'package:zephyr/page/setting/real_sr/widgets/real_sr_model_management_section.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';

/// 「AI 超分辨率」卡片 —— 阅读设置「画面」那一排里的超分节搬进控制面板。
///
/// 正文就是 [SuperResolutionSection]，与阅读设置面板渲染的是**同一个 widget**：
/// 开关落在 `RealSrSettings` / `RealSrBookScope` 那一份 SharedPreferences 上，
/// 两边靠 `RealSrBookScope.changes` 互相跟随，所以这里没有任何同步代码。
/// 额外挂上 [RealSrModelManagementSection]：卡片弹不掉路由，模型下载得就地能点。
class SuperResolutionCard extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final bool isStandalone;
  final String? disabledHint;

  const SuperResolutionCard({
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
      children: [
        SuperResolutionSection(),
        RealSrModelManagementSection(grouped: true),
      ],
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
      cardId: WorkspaceCardRegistry.superResolution,
      title: 'AI 超分辨率',
      icon: Icons.auto_awesome_outlined,
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
