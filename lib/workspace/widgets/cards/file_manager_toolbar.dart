import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_navigation_pad.dart';

/// 文件管理器工具栏的度量档：**画图与「摊开还是收成掌」的判断读同一份常数**。
///
/// MD3 口径与阅读器顶栏（`page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart`）
/// 一致 —— 图标钮 40 见方、图标 20、选中态 `secondaryContainer`。那一份住在阅读器的
/// chrome 里、命名与依赖都是阅读器专属，所以这里单独一份，而不是让 workspace 的卡片
/// 去挂阅读器代码。
abstract final class FileManagerToolbarMetrics {
  /// 图标按钮的见方边长 —— MD3 图标按钮的规范尺寸。
  static const double buttonSize = 40;

  /// 图标本身的边长。一行要塞十几颗控件，MD3 缺省的 24 会把整条拉得比内容还抢眼。
  static const double iconSize = 20;

  /// 同一组之内的间距。
  static const double gapWithinGroup = 4;

  /// 组间竖分隔线：线宽 1、长 20、左右各 6 的呼吸。
  static const double separatorThickness = 1;
  static const double separatorHeight = 20;
  static const double separatorMargin = 6;

  /// 导航摊开成五颗标准键所需的最小**卡片宽度**；低于这条线收成一颗导航掌。
  ///
  /// 这笔账要连右边一起算，否则摊开了反而要横向滚（那正是导航掌存在的理由）：
  /// 导航五颗 5×40+4×4=216，主工具组五颗 216，两条分隔线 2×(1+12)=26，
  /// 「更多」40 + 计数约 52 ⇒ 约 550。
  static const double expandedNavigationMinWidth = 550;
}

/// 工具栏里的一颗图标按钮：三种态各用一处角色，不自己叠透明度。
///
/// - 常态：`onSurfaceVariant` 图标 + 无底
/// - 按下（选中 / 开关开着）：`secondaryContainer` 底 + `onSecondaryContainer`
/// - 禁用：`onSurfaceVariant` 38%（MD3 的禁用档就是这个数）
///
/// 悬停/按压的水波纹由官方 `IconButton` 的状态层承担。[style] 是同一份样式的出口，
/// `FluentPopupMenuButton` 那颗菜单触发键也走它，整行才只有一个几何口径。
class FileManagerToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final bool enabled;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  const FileManagerToolbarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.enabled = true,
    this.onLongPress,
  });

  static ButtonStyle style(BuildContext context, {bool selected = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    final fg = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;
    return ButtonStyle(
      iconSize: const WidgetStatePropertyAll(
        FileManagerToolbarMetrics.iconSize,
      ),
      fixedSize: const WidgetStatePropertyAll(
        Size.square(FileManagerToolbarMetrics.buttonSize),
      ),
      minimumSize: const WidgetStatePropertyAll(
        Size.square(FileManagerToolbarMetrics.buttonSize),
      ),
      maximumSize: const WidgetStatePropertyAll(
        Size.square(FileManagerToolbarMetrics.buttonSize),
      ),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      // 见方的可点区缩到画出来的这一圈：一行要塞十几颗，
      // MD3 的 48 触摸外扩留给正文里的按钮，不留在这条带上。
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const WidgetStatePropertyAll(CircleBorder(side: BorderSide.none)),
      backgroundColor: WidgetStatePropertyAll(
        selected ? colorScheme.secondaryContainer : Colors.transparent,
      ),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colorScheme.onSurfaceVariant.withValues(alpha: 0.38);
        }
        return fg;
      }),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return fg.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.hovered)) {
          return fg.withValues(alpha: 0.08);
        }
        if (states.contains(WidgetState.focused)) {
          return fg.withValues(alpha: 0.12);
        }
        return Colors.transparent;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      isSelected: selected,
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      onLongPress: enabled ? onLongPress : null,
      style: style(context, selected: selected),
      icon: Icon(icon),
    );
  }
}

/// 组间竖分隔线（MD3 divider：`outlineVariant`，实色不透明）。
class FileManagerToolbarSeparator extends StatelessWidget {
  const FileManagerToolbarSeparator({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: FileManagerToolbarMetrics.separatorThickness,
      height: FileManagerToolbarMetrics.separatorHeight,
      margin: const EdgeInsets.symmetric(
        horizontal: FileManagerToolbarMetrics.separatorMargin,
      ),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

/// 导航那一组：后退 / 前进 / 上一级 / 主页 / 刷新，两种画法按宽度二选一。
///
/// [expanded] 为真画五颗标准图标钮；为假把五个方向收成一颗
/// [FileManagerNavigationPad]。动作与主页菜单在两种画法下**完全一致**，
/// 所以调用方只需要给一个布尔，不需要关心画成什么样。
class FileManagerNavigation extends StatelessWidget {
  /// 有请求在飞：整组禁用，避免叠动作。
  final bool busy;

  /// 仅用于掌形中心圆点的呼吸动画（加载中），不影响可用性。
  final bool loading;

  final bool expanded;
  final bool canGoBack;
  final bool canGoForward;
  final bool canGoUp;

  /// 挂在主页键上的 key：主页菜单要按它的位置弹出来，两种画法共用同一个。
  final GlobalKey homeKey;

  /// 「设置 → 文件管理器 → 启用主页键」。关掉时主页那颗整个消失，其余不受影响。
  final bool homeEnabled;

  /// 当前就站在主页上（主页键高亮，且不再提供「回主页」）。
  final bool atHome;

  /// 设过主页 —— 没设过时主页键点下去是「把当前目录设为主页」。
  final bool hasHome;

  final VoidCallback onNavigateBack;
  final VoidCallback onNavigateForward;
  final VoidCallback onNavigateUp;
  final VoidCallback onGoHome;
  final VoidCallback onHomeMenu;
  final VoidCallback onRefresh;

  const FileManagerNavigation({
    super.key,
    required this.busy,
    required this.loading,
    required this.expanded,
    required this.canGoBack,
    required this.canGoForward,
    required this.canGoUp,
    required this.homeKey,
    required this.homeEnabled,
    required this.atHome,
    required this.hasHome,
    required this.onNavigateBack,
    required this.onNavigateForward,
    required this.onNavigateUp,
    required this.onGoHome,
    required this.onHomeMenu,
    required this.onRefresh,
  });

  String get _homeTooltip {
    if (!hasHome) return '主页：还没设置 · 单击把当前目录设为主页';
    return atHome ? '主页（当前）· 右键/长按管理' : '主页 · 右键/长按管理';
  }

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return FileManagerNavigationPad(
        busy: busy,
        loading: loading,
        canGoBack: canGoBack,
        canGoForward: canGoForward,
        canGoUp: canGoUp,
        homeKey: homeKey,
        homeEnabled: homeEnabled,
        atHome: atHome,
        hasHome: hasHome,
        onNavigateBack: onNavigateBack,
        onNavigateForward: onNavigateForward,
        onNavigateUp: onNavigateUp,
        onGoHome: onGoHome,
        onHomeMenu: onHomeMenu,
        onRefresh: onRefresh,
      );
    }
    final gap = const SizedBox(width: FileManagerToolbarMetrics.gapWithinGroup);
    return Row(
      children: [
        FileManagerToolbarIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: '后退',
          enabled: !busy && canGoBack,
          onPressed: onNavigateBack,
        ),
        gap,
        FileManagerToolbarIconButton(
          icon: Icons.arrow_forward_rounded,
          tooltip: '前进',
          enabled: !busy && canGoForward,
          onPressed: onNavigateForward,
        ),
        gap,
        FileManagerToolbarIconButton(
          icon: Icons.arrow_upward_rounded,
          tooltip: '上一级',
          enabled: !busy && canGoUp,
          onPressed: onNavigateUp,
        ),
        if (homeEnabled) ...[
          gap,
          // 触摸端没有右键，长按是它唯一的菜单入口；桌面端两条都给。
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onSecondaryTapUp: (_) => onHomeMenu(),
            child: FileManagerToolbarIconButton(
              key: homeKey,
              icon: Icons.home_rounded,
              tooltip: _homeTooltip,
              selected: atHome,
              enabled: !busy,
              onPressed: onGoHome,
              onLongPress: onHomeMenu,
            ),
          ),
        ],
        gap,
        FileManagerToolbarIconButton(
          icon: Icons.refresh_rounded,
          tooltip: '刷新',
          enabled: !busy,
          onPressed: onRefresh,
        ),
      ],
    );
  }
}
