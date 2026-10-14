import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/expressive/expressive_blob.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/widgets/spring_lens/jelly_hover.dart';

/// 分类轨里的单选项（书签面板那条「全部 / 未分类 / 各列表」）。
///
/// ## 形状：一颗随种子生成的不规则轮廓
///
/// 每一档的轮廓由 [ExpressiveBlob] 按 **seed** 现生成（边上点的有无与位置、
/// 内缩深度、每颗角的半径与连续曲率都来自 PRNG），不是从固定枚举里挑 ——
/// 所以新增一档列表不需要任何人再决定「它该用什么形状」，而同名列表回到轨上
/// 还是同一个形状（seed 取自列表的稳定标识）。规范口径见
/// `expressive_blob.dart` 顶部：角半径只取 M3 Expressive 的
/// `none/extra-small/small/medium` 令牌，扰动只往盒子**内侧**走，选中态收成
/// **stadium**（「Active states in navigation should always use a pill/stadium
/// shape」）。
///
/// ## 状态用形状表达，切换用弹簧表达
///
/// | 状态 | 形状进度 | 触感 |
/// |---|---|---|
/// | 未选中、静止 | 0（不规则原形） | — |
/// | 鼠标悬停 | 0.55（收成一半） | [JellyHover] 两轴不同步的鼓 + 回弹 |
/// | 选中 | 1（胶囊） | 同上，另有按下形变 |
///
/// 悬停时轮廓「收一半」而不是直接变胶囊，是为了让三态读起来是一条连续的形变
/// 序列（规范的 Fluid Morphing），而不是一步跳到另一个极端。
///
/// ## 文字安全区的数从哪来
///
/// 形状自己封顶：`ExpressiveBlobBorder.safeInset` 收到的是这里的纵向内缩 11，
/// 于是轮廓的最大变形量（角令牌上界 0.30 与边上点内缩上界 0.17 里更深的那一档）
/// 永远不超过 11dp —— 字号放大让 chip 变高时，被缩掉的是**夸张程度**，
/// 不是标签的一角。内/外两档内边距（14 / 11）与这个封顶是同一个来源
/// （[_labelHPadding] / [_labelVPadding]），不可能一处改了另一处忘了。
/// 包含关系由 `test/widgets/shelf_list_chip_expressive_test.dart` 逐 seed、
/// 逐进度（0 / 0.5 / 1）、逐高度断言，不是「看着没被切到」就算过。
class ShelfListChip extends StatelessWidget {
  const ShelfListChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.identity,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// 形状的定种子依据。默认用 `label`，但**列表应该传自己的路径**：重命名
  /// 之后路径不变，形状就不跟着换（重命名不该让一档看起来变成另一档）。
  final String? identity;

  /// 悬停收成多少：0.55 = 不规则与胶囊的正中间略靠不规则。
  static const double _hoverProgress = 0.55;

  /// 标签内缩。**同时**作为形状的文字安全区传给 [ExpressiveBlobBorder]：
  /// 轮廓的最大变形量按纵向那一档封顶，所以这两个数不可能各走各的。
  static const double _labelHPadding = 14;
  static const double _labelVPadding = 11;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final motion = ExpressiveMotion.duration(
      context,
      ExpressiveMotion.spatialDuration,
    );
    final seed = expressiveBlobSeed(identity ?? label);
    final animate = !MediaQuery.disableAnimationsOf(context);

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: JellyHover(
        enabled: animate,
        builder: (context, swellX, _) => ElasticButton(
          enabled: animate,
          child: ChoiceChip(
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            selected: selected,
            showCheckmark: false,
            // 悬停把轮廓收成一半，选中收满，取两者里更大的那一个（选中之上
            // 再悬停不该「退回」不规则）。状态切换本身交给 Chip 的
            // selectAnimation —— 它经 `ExpressiveBlobBorder.lerpTo` 插的就是
            // progress，于是底色淡入与形状收平是同一条动画，不会各走各的。
            shape: ExpressiveBlobBorder(
              seed: seed,
              progress: _progress(selected, swellX),
              safeInset: _labelVPadding,
            ),
            visualDensity: VisualDensity.standard,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(
              horizontal: _labelHPadding,
              vertical: _labelVPadding,
            ),
            // 比那条轨（`surfaceContainer` 的下沉槽）**高一档**：形状是这档
            // 状态的载体，底色与槽同色时轮廓根本读不出来（渲染台实测：
            // 静止态六档只剩文字，不规则形状完全看不见）。
            backgroundColor: scheme.surfaceContainerHigh,
            selectedColor: scheme.secondaryContainer,
            chipAnimationStyle: ChipAnimationStyle(
              selectAnimation: AnimationStyle(
                duration: motion,
                curve: Curves.easeOut,
              ),
            ),
            labelStyle: theme.textTheme.labelLarge?.copyWith(
              color: selected
                  ? scheme.onSecondaryContainer
                  : scheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
            side: BorderSide.none,
            onSelected: (_) => onTap(),
          ),
        ),
      ),
    );
  }

  /// 状态 → 形状进度。悬停弹簧的过冲会越过 1，那里由 border 自己夹住：
  /// 过冲交给缩放那一层表达，轮廓不跟着抖。
  static double _progress(bool selected, double swellX) {
    final hover = swellX <= 0 ? 0.0 : swellX * _hoverProgress;
    final base = selected ? 1.0 : hover;
    return hover > base ? hover : base;
  }
}
