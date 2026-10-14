import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/comic_read/widgets/settings/sections/image_tuning_section.dart';
import 'package:zephyr/widgets/expressive/expressive_blob.dart';
import 'package:zephyr/widgets/expressive/expressive_shape.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/widgets/cards/expressive_widgets.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';

/// 「画面调节」卡片 —— 滤镜 / 墨水屏 / 禁用动画 / 自动裁边。
///
/// 读写走 app 级 `GlobalSettingCubit.state.readSetting`，与阅读设置面板那一排
/// 是同一个 cubit 的同一份状态：拨哪边另一边当场跟着变，不需要任何通信层。
///
/// 卡顶的状态概览网格读的是**同一份** `readSetting`（只读、不另开写入路径），
/// 以 M3E 撞色几何贴片卡片呈现当前各维度的开启状态与数值。
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
    // 与正文那排读同一个值：谁先变都行，两边都是同一份 state 的投影。
    final readSetting = context.watch<GlobalSettingCubit>().state.readSetting;
    final strip = _TuningStateStrip(
      autoTrim: readSetting.autoTrimPageMargins,
      filterOn: readSetting.readFilterEnabled,
      filterPercent: readSetting.readFilterOpacityPercent,
      noAnimation: readSetting.noAnimation,
      eink: readSetting.einkOptimization,
      einkDelayMs: readSetting.einkDelayMs,
    );

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [strip, const ImageTuningSection()],
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
      expressive: true,
      title: '画面调节',
      icon: AppGlyphs.wand,
      isExpanded: isExpanded,
      onToggle: onToggle,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onHide: onHide,
      disabledHint: disabledHint,
      trailing: ExpressiveStatusPill(
        text: _summary(readSetting),
        dot: false,
        compact: true,
        tone: _anyOn(readSetting)
            ? ExpressiveTone.primary
            : ExpressiveTone.neutral,
      ),
      child: content,
    );
  }

  static bool _anyOn(ReadSettingState readSetting) =>
      readSetting.readFilterEnabled ||
      readSetting.noAnimation ||
      readSetting.einkOptimization;

  static String _summary(ReadSettingState readSetting) {
    final on = <String>[
      if (readSetting.readFilterEnabled) '滤镜',
      if (readSetting.noAnimation) '无动画',
      if (readSetting.einkOptimization) '墨水屏',
    ];
    return on.isEmpty ? '全部关闭' : on.join(' · ');
  }
}

/// 卡顶的响应式状态概览磁贴网格：用 M3E 撞色几何贴片与多态图标徽章展示核心档位。
///
/// 只读不写 —— 写入仍然只有正文 [ImageTuningSection] 那一条路。
class _TuningStateStrip extends StatelessWidget {
  const _TuningStateStrip({
    required this.autoTrim,
    required this.filterOn,
    required this.filterPercent,
    required this.noAnimation,
    required this.eink,
    required this.einkDelayMs,
  });

  final bool autoTrim;
  final bool filterOn;
  final int filterPercent;
  final bool noAnimation;
  final bool eink;
  final int einkDelayMs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ExpressiveTileGrid(
        minTileWidth: 132,
        spacing: 8,
        children: [
          _TuningOverviewTile(
            seed: expressiveBlobSeed('tuning-trim'),
            label: '自动裁边',
            value: autoTrim ? '已开启' : '未开启',
            icon: AppGlyphs.cropFree,
            shape: ExpressiveButtonShape.clover8Leaf,
            tone: ExpressiveTone.primary,
            active: autoTrim,
          ),
          _TuningOverviewTile(
            seed: expressiveBlobSeed('tuning-filter'),
            label: '阅读滤镜',
            value: filterOn ? '$filterPercent%' : '已关闭',
            icon: AppGlyphs.moon,
            shape: ExpressiveButtonShape.clover4Leaf,
            tone: ExpressiveTone.secondary,
            active: filterOn,
          ),
          _TuningOverviewTile(
            seed: expressiveBlobSeed('tuning-motion'),
            label: '翻页动画',
            value: noAnimation ? '已禁用' : '正常',
            icon: AppGlyphs.motion,
            shape: ExpressiveButtonShape.softBurst,
            tone: ExpressiveTone.tertiary,
            active: noAnimation,
          ),
          _TuningOverviewTile(
            seed: expressiveBlobSeed('tuning-eink'),
            label: '墨水屏刷屏',
            value: eink ? '${einkDelayMs}ms' : '已关闭',
            icon: AppGlyphs.contrast,
            shape: ExpressiveButtonShape.puffyDiamond,
            tone: ExpressiveTone.primary,
            active: eink,
          ),
        ],
      ),
    );
  }
}

class _TuningOverviewTile extends StatelessWidget {
  const _TuningOverviewTile({
    required this.seed,
    required this.label,
    required this.value,
    required this.icon,
    required this.shape,
    required this.tone,
    required this.active,
  });

  final int seed;
  final String label;
  final String value;
  final Glyph icon;
  final ExpressiveButtonShape shape;
  final ExpressiveTone tone;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final effectiveTone = active ? tone : ExpressiveTone.sunken;
    final tones = expressiveToneColors(scheme, effectiveTone);

    return ExpressivePatchBackdrop(
      seed: seed,
      tone: effectiveTone,
      active: active,
      intensity: active ? 1.05 : 0.72,
      borderRadius: expressiveCornerSm,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      child: Row(
        children: [
          ExpressiveShapeBadge(
            icon: icon,
            shape: shape,
            seed: seed,
            size: 32,
            glyphSize: 16,
            tone: tone,
            active: active,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: tones.onContainer,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: tones.onContainer.withValues(alpha: .78),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
