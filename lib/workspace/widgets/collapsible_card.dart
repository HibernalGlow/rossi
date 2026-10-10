import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/config/global/theme_shape.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_menu_button.dart';

/// M3 的动效缓动档。这个版本的 `material_ui` / Flutter 都没有导出
/// `MaterialCurves`（`Curves` 上也没有 `emphasized*` / `standard*`），
/// 所以按规范给的 cubic-bezier 自己声明，避免继续用 M2 的裸 easeOut*。
/// 规范里 emphasized 与 standard 是同一条曲线，差异只在各自的 decelerate /
/// accelerate 变体，因此这里不复制出两个同名常量。
const Curve _m3Standard = Cubic(0.2, 0.0, 0.0, 1.0);
const Curve _m3EmphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);

/// 通用可折叠卡片组件外壳（支持泳道与边栏中 100% 复用）
///
/// 轨道上关于「位置」的三个动作 —— 上移 / 下移 / 收起 —— 都由宿主
/// （面板 / 抽屉）通过 [onMoveUp] / [onMoveDown] / [onHide] 传进来。
/// 卡片自己不需要知道自己在第几位，也不需要知道有没有下家。
class CollapsibleCard extends StatelessWidget {
  final String cardId;
  final String title;
  final IconData icon;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? contentPadding;

  /// 在所属面板里上移 / 下移。`null` = 已经在头/尾（菜单项置灰）。
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  /// 把这张卡从当前面板收起来（可从面板标题行的「已收起」入口恢复）。
  final VoidCallback? onHide;

  /// 非 null = 这张卡在**当前这台机器上用不了**：内容整体灰掉、不吃点击，
  /// 标题行挂一颗说明 tag（例如「仅桌面」）。
  ///
  /// 为什么不是干脆不画：面板会把「一张卡都没有」的整个页签藏掉，
  /// 于是「这个功能不存在」和「这台机器暂时做不到」在界面上长得一模一样。
  final String? disabledHint;

  const CollapsibleCard({
    super.key,
    required this.cardId,
    required this.title,
    required this.icon,
    required this.isExpanded,
    required this.onToggle,
    this.trailing,
    required this.child,
    this.margin,
    this.contentPadding,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.disabledHint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // MD3 的 filled 卡片靠**容器色**分层，不描边、不投影；圆角跟主题的形状档走。
    final radius = themeRadius(context, fallback: 12);

    // 卡片可直接挂在泳道/抽屉里，由自身提供与应用同库的 Material。
    // 用 Material 绘制背景并裁剪，保证标题栏和内容的墨水反馈也在圆角内。
    return Padding(
      padding:
          margin ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (trailing != null) ...[
                      trailing!,
                      const SizedBox(width: 8),
                    ],
                    if (disabledHint case final hint?) ...[
                      _DisabledTag(text: hint),
                      const SizedBox(width: 6),
                    ],
                    if (onMoveUp != null ||
                        onMoveDown != null ||
                        onHide != null)
                      _buildTrackMenu(context),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      // MD3 动效档位：会停下来的变换走 decelerate，不用裸的 easeOutCubic。
                      curve: _m3EmphasizedDecelerate,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Content
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding:
                    contentPadding ?? const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: applyCardGate(child, disabledHint: disabledHint),
              ),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
              // 淡入淡出走 standard，容器尺寸变化走 emphasized —— M3 的分工。
              firstCurve: _m3Standard,
              secondCurve: _m3Standard,
              sizeCurve: _m3Standard,
            ),
          ],
        ),
      ),
    );
  }

  /// 卡片在轨道上的位置菜单（上移 / 下移 / 收起）。
  ///
  /// 放在卡片的**标题栏里**而不是卡内：这几个动作改的是「卡片在面板里的位置」，
  /// 与卡片内容无关；收进一个菜单也让标题栏在窄泳道里不至于被按钮挤爆。
  ///
  /// 走 [ShelfMenuButton] 而不是 `PopupMenuButton`：后者在这个 `material_ui`
  /// 里仍按 M2 的 `PopupMenuTheme` 画菜单面，拿不到 MD3 的 `surfaceContainer` +
  /// 4dp 圆角。触发键也并入本区图标钮的 40/20 口径，于是标题栏里不会再同时
  /// 出现 32 与 40 两种高度。
  Widget _buildTrackMenu(BuildContext context) {
    return ShelfMenuButton(
      tooltip: '卡片位置',
      glyph: AppGlyphs.more,
      menuChildren: [
        ShelfMenuItem(
          label: '上移',
          glyph: AppGlyphs.arrowUp,
          // `onPressed: null` 就是 MD3 的禁用态：项永远在场，只是点不动。
          onPressed: onMoveUp,
        ),
        ShelfMenuItem(
          label: '下移',
          glyph: AppGlyphs.arrowDown,
          onPressed: onMoveDown,
        ),
        if (onHide != null) ...[
          const ShelfMenuDivider(),
          ShelfMenuItem(
            label: '从该面板收起',
            glyph: AppGlyphs.eyeOff,
            onPressed: onHide,
            destructive: true,
          ),
        ],
      ],
    );
  }
}

/// 标题行上那颗「这台机器做不到」的小标签。
class _DisabledTag extends StatelessWidget {
  final String text;

  const _DisabledTag({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 平台判不动这张卡时，把内容**灰掉且不吃点击**，但照样画出来。
///
/// 单独抽出来是因为它有两个落点：折叠外壳的内容区，以及独占面板
/// （`WorkspaceCardChrome.standalone` —— 那条路上根本没有 [CollapsibleCard]）。
/// 只在壳里做的话，卡片一旦独占整个面板，灰显就静默失效了。
///
/// 灰掉但留着：看得见「有这颗开关、这台机器暂时拨不动」，
/// 比整张卡凭空消失少一次「那功能去哪了」。
Widget applyCardGate(Widget child, {String? disabledHint}) {
  if (disabledHint == null) return child;
  return Opacity(
    opacity: 0.55,
    child: IgnorePointer(ignoring: true, child: child),
  );
}
