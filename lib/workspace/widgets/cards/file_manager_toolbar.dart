import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/action_group.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_navigation_pad.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 文件管理器工具栏的度量档：**画图与「摊开还是收成掌」的判断读同一份常数**。
///
/// 三颗按钮的几何与配色**不在这里定义** —— 它们是全应用一份的
/// [ActionGroupMetrics] / [ActionIconButton] / [ActionToggleButton]
/// （书架页右上角那两颗、侧栏底部那排动作读的是同一份）。
/// 这个类只留给**文件管理器自己**的那个数：导航摊开成五颗的宽度门槛。
///
/// 保留这层命名是因为它已经被这张卡片与别的判据引了几十处；
/// `buttonSize` 那几条转发过去，数值只会有一处能漂。
abstract final class FileManagerToolbarMetrics {
  /// 图标按钮的见方边长。
  static const double buttonSize = ActionGroupMetrics.buttonSize;

  /// 图标本身的边长。
  static const double iconSize = ActionGroupMetrics.iconSize;

  /// 同一组之内的间距。
  static const double gapWithinGroup = ActionGroupMetrics.gapWithinGroup;

  /// 组与组之间的间距。
  static const double gapBetweenGroups = ActionGroupMetrics.gapBetweenGroups;

  /// 分组槽的内边距。
  static const double wellPadding = ActionGroupMetrics.wellPadding;

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
/// **几何与配色不在这里** —— 它就是全应用那一颗
/// [ActionIconButton]（书架页右上角、侧栏底部动作读的是同一个）。
/// 这层名字留着是因为这张卡片与别的判据已经引了几十处。
typedef FileManagerToolbarIconButton = ActionIconButton;

/// 工具栏里的一颗**开关**键：文件树、穿透模式、搜索展开。
///
/// 同上：实现是全应用那一颗 [ActionToggleButton]。
typedef FileManagerToolbarToggleButton = ActionToggleButton;

/// 一组控件共用的下沉槽。
///
/// 取代原来的竖分隔线：MD3 表达分组靠**容器 + 间距**，不靠画线。卡片底是
/// `surfaceContainerHigh`（见 `collapsible_card.dart`），所以槽取低一档的
/// `surfaceContainer`（[ActionGroup] 的默认档）—— 读作「这里是一片可操作区」，
/// 而不是又加一层海拔。
typedef FileManagerToolbarGroup = ActionGroup;

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
    if (!hasHome) return t.workspace.homeNotSetYet;
    return atHome
        ? t.workspace.homeCurrentManageHint
        : t.workspace.homeManageHint;
  }

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return ActionBubbleTarget(
        enabled: !busy,
        child: FileManagerNavigationPad(
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
        ),
      );
    }
    final gap = const SizedBox(width: FileManagerToolbarMetrics.gapWithinGroup);
    return Row(
      children: [
        FileManagerToolbarIconButton(
          glyph: AppGlyphs.arrowBack,
          tooltip: t.workspace.back,
          enabled: !busy && canGoBack,
          onPressed: onNavigateBack,
        ),
        gap,
        FileManagerToolbarIconButton(
          glyph: AppGlyphs.arrowForward,
          tooltip: t.workspace.forward,
          enabled: !busy && canGoForward,
          onPressed: onNavigateForward,
        ),
        gap,
        FileManagerToolbarIconButton(
          glyph: AppGlyphs.arrowUp,
          tooltip: t.workspace.parentDirectory,
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
              glyph: AppGlyphs.home,
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
          glyph: AppGlyphs.refresh,
          tooltip: '刷新',
          enabled: !busy,
          onPressed: onRefresh,
        ),
      ],
    );
  }
}
