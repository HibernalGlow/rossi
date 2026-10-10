import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/widgets/settings/sections/image_tuning_section.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/icons/icons.dart';

/// 「画面调节」卡片 —— 滤镜 / 墨水屏 / 禁用动画。
///
/// 读写走 app 级 `GlobalSettingCubit.state.readSetting`，与阅读设置面板那一排
/// 是同一个 cubit 的同一份状态：拨哪边另一边当场跟着变，不需要任何通信层。
class ImageTuningCard extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final bool isStandalone;
  final String? disabledHint;

  const ImageTuningCard({
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
      children: [ImageTuningSection()],
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
      cardId: WorkspaceCardRegistry.imageTuning,
      title: '画面调节',
      icon: AppGlyphs.wand,
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
