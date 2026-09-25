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

  /// 组与组之间的间距。MD3 的分组靠**间距分级**，不靠分隔线 ——
  /// 组内 4、组间 12，一眼能看出哪几颗是一回事。
  static const double gapBetweenGroups = 12;

  /// 分组槽的水平内边距。槽本身高度固定为 [buttonSize]，所以里头的图标钮
  /// 与槽外邻居仍然共用同一条 40 的高度带。
  static const double wellPadding = 2;

  /// 导航摊开成五颗标准键所需的最小**卡片宽度**；低于这条线收成一颗导航掌。
  ///
  /// 这笔账要连右边一起算，否则摊开了反而要横向滚（那正是导航掌存在的理由）：
  /// 导航五颗 5×40+4×4=216 再加槽的左右内边距 4 ⇒ 220，主工具组五颗 216，
  /// 两条组间间距 2×12=24，「更多」40 + 计数约 52 ⇒ 约 552。
  static const double expandedNavigationMinWidth = 560;
}

/// 工具栏里的一颗**瞬时动作**键：后退 / 前进 / 上一级 / 刷新 / 主页。
///
/// 它没有「选中」这一态 —— 按完就完，留下状态的是别的东西。以前这些键和
/// 开关共用一个带 `selected` 的按钮，于是「当前就在主页上」和「文件树开着」
/// 长成了同一个灰粉圆底，两种完全不同的事读起来是一回事。开关见
/// [FileManagerToolbarToggleButton]。
///
/// 配色：常态 `onSurfaceVariant` 图标 + 无底；禁用 `onSurfaceVariant` 38%
/// （MD3 的禁用档就是这个数）。悬停/按压的水波纹由官方 `IconButton` 的状态层承担。
class FileManagerToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;

  /// 「在这儿了，点了也没去处」：按禁用的样子画，但仍然可点。
  ///
  /// 主页那颗用得上 —— 已经站在主页上时它不再提供「回主页」，但长按/右键的
  /// 主页菜单还得留口，所以不能真的走 [enabled]。
  final bool muted;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  const FileManagerToolbarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.enabled = true,
    this.muted = false,
    this.onLongPress,
  });

  /// 整行共用的几何档。[selected] 为真画 `secondaryContainer` 底，
  /// 只有开关态（[FileManagerToolbarToggleButton] 与带值的菜单触发键）用得上；
  /// `FluentPopupMenuButton` 那颗菜单触发键也走它，整行才只有一个几何口径。
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
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      onLongPress: enabled ? onLongPress : null,
      style: style(context).copyWith(
        foregroundColor: muted
            ? WidgetStatePropertyAll(
                colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
              )
            : null,
      ),
      icon: Icon(icon),
    );
  }
}

/// 工具栏里的一颗**开关**键：文件树、穿透模式、搜索展开。
///
/// 与瞬时动作键唯一的区别就是它有 `on` 这一态，用 MD3 的 tonal 底
/// （`secondaryContainer`）表达「这个功能现在开着」。
class FileManagerToolbarToggleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool on;
  final bool enabled;
  final VoidCallback? onPressed;

  const FileManagerToolbarToggleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.on,
    required this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      isSelected: on,
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      style: FileManagerToolbarIconButton.style(context, selected: on),
      icon: Icon(icon),
    );
  }
}

/// 一组控件共用的下沉槽。
///
/// 取代原来的竖分隔线：MD3 表达分组靠**容器 + 间距**，不靠画线。卡片底是
/// `surfaceContainerHigh`（见 `collapsible_card.dart`），所以槽取低一档的
/// `surfaceContainer` —— 读作「这里是一片可操作区」，而不是又加一层海拔。
/// 高度锁死在 [FileManagerToolbarMetrics.buttonSize]，槽里的图标钮与槽外
/// 邻居因此仍共用同一条高度带。
class FileManagerToolbarGroup extends StatelessWidget {
  final List<Widget> children;

  const FileManagerToolbarGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: FileManagerToolbarMetrics.buttonSize,
      padding: const EdgeInsets.symmetric(
        horizontal: FileManagerToolbarMetrics.wellPadding,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(
          FileManagerToolbarMetrics.buttonSize / 2,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
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
              // 「就在主页上」不是开关态，画成 muted：它和文件树那种
              // 「功能开着」再也不是同一个圆底。
              muted: atHome,
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
