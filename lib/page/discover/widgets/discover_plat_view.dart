import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:plat/plat.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/discover/service/discover_router.dart';
import 'package:zephyr/page/discover/service/discover_tab_scope.dart';
import 'package:zephyr/page/discover/service/discover_tabs.dart';
import 'package:zephyr/widgets/plat/rossi_plat_tab_menu.dart';
import 'package:zephyr/widgets/plat/rossi_plat_theme.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/page/search/view/search_page.dart';
import 'package:zephyr/widgets/plugin_icon.dart';

/// 发现页的标签宿主：一个 plat 的 `PlatTabGroup`。
///
/// 横向档（[TabBarSide.top]）时那一行标签条**就是**发现页的顶栏 —— 用户
/// 2026-09-20 的口径：另起一行与「发现」标题栏割裂。竖向档时同一份 chrome
/// 转到内容的左边或右边。
class DiscoverPlatView extends StatefulWidget {
  const DiscoverPlatView({
    super.key,
    required this.tabs,
    required this.setting,
    required this.onSearch,
    required this.onCustomizeOrder,
  });

  final DiscoverTabs tabs;
  final DiscoverSettingState setting;
  final VoidCallback onSearch;
  final VoidCallback onCustomizeOrder;

  /// 竖向轨厚度的可拖范围与兜底默认值（真正的值存在设置里）。
  /// 地板是量出来的，不是拍的：一条标签里**不是文字**的那部分（前导图标 +
  /// 两道间距 + 关闭钮 + 轨内边距）实测要 54 + 8 = 62 —— 轨厚 60 时 RenderFlex
  /// 溢 2px、61 溢 1px、62 起干净。再窄就会在设备更新相里抛布局异常，
  /// 那正是「每帧刷 `!_debugDuringDeviceUpdate` 直到卡死」的引信。
  static const double railMinWidth = 64;
  static const double railMaxWidth = 260;

  /// 横向档一条标签的上限（常量，不按朝向现算 —— 见 `_buildChip`）。
  static const double chipMaxWidth = 220;

  /// 内容区不能被压到比这更窄。
  ///
  /// 量出来的：轨厚 120 时整页 320 会把 `SearchPage` 的搜索栏压到 24 宽并报
  /// `RenderFlex overflowed`；留 280 给内容就干净。轨宽因此是「整页宽度 − 这个数」
  /// 的上限，用户拖也拖不过去。
  static const double contentMinWidth = 280;

  /// 把手本身的宽度（轨内侧那条边）。
  static const double _handleWidth = 6;

  /// 把手在树上的名字（判据要拖它）。
  static const Key railHandleKey = ValueKey<String>('discover-rail-handle');

  @override
  State<DiscoverPlatView> createState() => _DiscoverPlatViewState();
}

class _DiscoverPlatViewState extends State<DiscoverPlatView> {
  /// 拖动中的轨厚；`null` = 没在拖（读设置里的值）。
  double? _dragWidth;

  /// 这一片现在多大（右键分屏要拿它判断「切一半还摆得下吗」）。
  Size? _pageSize;

  @override
  void initState() {
    super.initState();
    // **必须自己听**：朝向存在 plat 的树上，树变了 `PlatView` 会立刻按新朝向
    // 排布，而轨厚（`PlatTabBarTheme.size`）是这一层 build 时算出来的。
    // 只靠宿主重建的话，宿主一旦没监听，就会出现「竖排轨道 + 横条的 40 厚」
    // 同帧混排 —— 标签被压到 24 宽、RenderFlex 溢出，那一帧的异常就是
    // MouseTracker 不复位的引信（实机表现为每帧刷断言直到卡死）。
    widget.tabs.controller.addListener(_onTabsChanged);
  }

  @override
  void didUpdateWidget(DiscoverPlatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tabs, widget.tabs)) {
      oldWidget.tabs.controller.removeListener(_onTabsChanged);
      widget.tabs.controller.addListener(_onTabsChanged);
    }
  }

  @override
  void dispose() {
    widget.tabs.controller.removeListener(_onTabsChanged);
    super.dispose();
  }

  void _onTabsChanged() {
    if (mounted) setState(() {});
  }

  DiscoverTabs get tabs => widget.tabs;
  DiscoverSettingState get setting => widget.setting;
  VoidCallback get onSearch => widget.onSearch;
  VoidCallback get onCustomizeOrder => widget.onCustomizeOrder;
  bool get _vertical => widget.tabs.vertical;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _pageSize = constraints.biggest;
        final effective = _effectiveSide(constraints.maxWidth);
        // 朝向要变的那一帧**不布局**：拿旧朝向硬画新宽度会把标签内容压到布局
        // 溢出（实测窄页面里搜索栏被挤成 24 宽、竖轨里标签被挤成 24 宽），
        // 而那一帧的异常就是 MouseTracker 不复位的引信。
        //
        // 包装必须是**恒在**的：`Offstage` 换进换出等于给子树换了个祖先，
        // element 无法复用，标签内容会整棵重挂 —— 那正是用户说的
        // 「热切换触发页签重载」。所以这里只切标志位，绝不换包装。
        final transitioning = effective != tabs.tabSide;
        if (transitioning) _applySideSoon(context, effective);
        return Offstage(offstage: transitioning, child: _view(context));
      },
    );
  }

  /// 窄页面上把竖向档钳回横向：这里只**算**该用哪一档，不改树。
  DiscoverTabBarSide _effectiveSide(double pageWidth) {
    final preferred = setting.tabSide;
    if (preferred == DiscoverTabBarSide.top) return preferred;
    if (!pageWidth.isFinite ||
        pageWidth < _railWidth + DiscoverPlatView.contentMinWidth) {
      return DiscoverTabBarSide.top;
    }
    return preferred;
  }

  /// 当前轨厚：拖动中先用本地值（不写盘），松手才落设置。
  double get _railWidth =>
      _dragWidth ??
      widget.setting.tabRailWidth.clamp(
        DiscoverPlatView.railMinWidth,
        DiscoverPlatView.railMaxWidth,
      );

  void _dragRail(double dx, bool railOnLeft) {
    // 往内容方向拖是「变窄」还是「变宽」取决于轨在哪一边。
    final next = (_railWidth + (railOnLeft ? dx : -dx)).clamp(
      DiscoverPlatView.railMinWidth,
      DiscoverPlatView.railMaxWidth,
    );
    if (next == _dragWidth) return;
    setState(() => _dragWidth = next);
  }

  void _commitRailWidth() {
    final width = _dragWidth;
    if (width == null) return;
    _dragWidth = null;
    context.read<GlobalSettingCubit>().updateDiscoverSetting(
      (current) => current.copyWith(tabRailWidth: width),
    );
    if (mounted) setState(() {});
  }

  /// 改树排到帧尾：build 期间动 controller 等于在构建过程中改状态。
  ///
  /// 为什么不「照样竖着、让内容挤一挤」：挤出来的结果是布局溢出并抛异常，
  /// 而布局异常发生在设备更新相里会跳过 `MouseTracker` 的复位标志。
  /// 偏好不动，所以页面一变宽它自己会转回竖向。
  void _applySideSoon(BuildContext context, DiscoverTabBarSide effective) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) tabs.setSide(effective);
    });
  }

  /// 条/轨本身占掉之后，标签内容那一格还剩多大。
  Size? get _paneSize {
    final page = _pageSize;
    if (page == null) return null;
    return _vertical
        ? Size(page.width - _railWidth, page.height)
        : Size(page.width, page.height - _barThickness);
  }

  static const double _barThickness = 40;

  Widget _view(BuildContext context) {
    return RossiPlatTheme(
      // 竖向轨要窄：它是列表的边，不该吃掉内容的三分之一。
      barThickness: _vertical ? _railWidth : _barThickness,
      vertical: _vertical,
      child: Stack(
        children: [
          Positioned.fill(child: _platView(context)),
          if (_vertical) _railHandle(context),
        ],
      ),
    );
  }

  Widget _platView(BuildContext context) {
    return PlatView(
      controller: tabs.controller,
      // 不在挂载时抢键盘焦点：焦点一抢走，Cmd/Ctrl + Z 这类键就先被 plat 的
      // 标签命令看见（见 [_leafShortcuts]）。让用户点进这一片再生效。
      autofocus: false,
      leafBuilder: _buildLeaf,
      tabBar: (context, group) => PlatTabBar(
        tabBuilder: _buildChip,
        trailing: _BarActions(
          vertical: _vertical,
          onHome: tabs.onHome,
          onSearch: onSearch,
          onCustomizeOrder: onCustomizeOrder,
          tabs: tabs,
        ),
      ),
    );
  }

  /// 轨内侧那条可拖的边：改的是「轨从内容区扣走多少」，所以它得贴着内容那一侧。
  Widget _railHandle(BuildContext context) {
    final railOnLeft = tabs.side == TabBarSide.left;
    const handle = DiscoverPlatView._handleWidth;
    return Positioned(
      key: DiscoverPlatView.railHandleKey,
      top: 0,
      bottom: 0,
      left: railOnLeft ? _railWidth - handle : null,
      right: railOnLeft ? null : _railWidth - handle,
      width: handle,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) =>
              _dragRail(details.delta.dx, railOnLeft),
          onHorizontalDragEnd: (_) => _commitRailWidth(),
          child: Center(
            child: Container(
              width: 2,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeaf(BuildContext context, LeafSnapshot leaf) {
    final spec = DiscoverTabs.specOfLeaf(leaf);
    if (spec == null) return const SizedBox.shrink();
    return DiscoverTabScope(
      actions: _LeafActions(tabs: tabs, leafId: leaf.id, source: spec.source),
      child: _leafShortcuts(context, spec.content),
    );
  }

  /// 把 plat 抢走的撤销键还给输入框。
  ///
  /// `PlatView` 在自己的子树里装了 `Shortcuts`，其中 `Cmd/Ctrl + Z` 被映射成
  /// 「撤销一次标签操作」。它比应用层的文本编辑绑定更深，于是标签里那个搜索框
  /// 按 Cmd+Z 撤销不了字。这里在**更深**一层把这两个键重新映射回 `UndoTextIntent`：
  /// 焦点在输入框上时应用层的 Action 接得住；接不住时 `Shortcuts` 会返回
  /// `ignored` 继续往外找，plat 的标签撤销照常生效。
  Widget _leafShortcuts(BuildContext context, WidgetBuilder content) {
    final apple = defaultTargetPlatform == TargetPlatform.macOS;
    return Shortcuts(
      shortcuts: {
        SingleActivator(LogicalKeyboardKey.keyZ, meta: apple, control: !apple):
            const UndoTextIntent(SelectionChangedCause.keyboard),
        SingleActivator(
          LogicalKeyboardKey.keyZ,
          meta: apple,
          control: !apple,
          shift: true,
        ): const RedoTextIntent(
          SelectionChangedCause.keyboard,
        ),
      },
      child: Builder(builder: content),
    );
  }

  Widget _buildChip(BuildContext context, PlatTabDetails tab) {
    final child = tab.snapshot.child;
    final leaf = child is LeafSnapshot ? DiscoverTabs.specOfLeaf(child) : null;
    if (leaf == null) return const SizedBox.shrink();

    final label = DiscoverTabs.labelOf(
      leaf,
      showPluginShort: setting.tabPluginShortEnabled,
    );
    final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);

    // 横向档一条标签的上限。**是个常量，不按朝向现算**：
    // 先前按「轨厚 − 开销」现算，而朝向是切出来的、chip 不重建，旧档的上限
    // 会留在新布局里（竖轨溢出 20px 那次就是这么来的）。
    // 竖轨里 plat 给每条标签的是「轨厚 − 内边距」这一有界宽度，比这个数小，
    // 所以这一层在竖向是空操作，只把横向那条长标题（日文全名能到 60 字）掐住。
    final labelWidget = ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: DiscoverPlatView.chipMaxWidth,
      ),
      child: text,
    );

    return RossiPlatTabMenuRegion(
      controller: tabs.controller,
      tabId: tab.snapshot.id,
      // 复制 = 「在这一侧再开一条同内容的」；locked 的那条（首页）不给拆。
      duplicable: !tab.snapshot.locked,
      duplicateTab: () => tabs.duplicateTabOf(tab.snapshot.id),
      onClose: tab.snapshot.locked ? null : () => tabs.close(tab.snapshot.id),
      // 切一半之后每格还剩多宽/多高，决定四个方向里哪些点了会炸。
      paneSize: _paneSize,
      child: PlatTabChip(
        leading: setting.tabIconEnabled ? _chipLeading(context, leaf) : null,
        // 这里**不放 Tooltip**：它是这条标签条里唯一会在 hover 回调里往 Overlay
        // 插东西的东西，而「hover 时改命中树」正是 `!_debugDuringDeviceUpdate`
        // 那条断言唯一需要的燃料（上游 flutter/flutter#107063 至今没修）。
        label: labelWidget,
        // 首页那条是 locked 的，plat 自己会把关闭按钮藏掉。
        trailing: const PlatTabCloseButton(),
      ),
    );
  }

  Widget _chipLeading(BuildContext context, DiscoverLeafSpec leaf) {
    const size = 16.0;
    if (leaf.source.isEmpty) {
      return Icon(
        leaf.icon ?? Icons.explore,
        size: size,
        color: Theme.of(context).colorScheme.primary,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: size,
        height: size,
        child: PluginIcon(
          url: leaf.iconUrl,
          placeholder: GeneratedPluginIcon(
            seed: leaf.source,
            name: leaf.pluginName,
          ),
        ),
      ),
    );
  }
}

/// 标签条末尾那一组动作。横向档排在行的最右，竖向档排在轨的最下。
class _BarActions extends StatelessWidget {
  const _BarActions({
    required this.vertical,
    required this.onHome,
    required this.onSearch,
    required this.onCustomizeOrder,
    required this.tabs,
  });

  final bool vertical;
  final bool onHome;
  final VoidCallback onSearch;
  final VoidCallback onCustomizeOrder;
  final DiscoverTabs tabs;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      // 「自定义插件顺序」改的是首页那张列表，只在首页摆出来。
      if (onHome)
        _barIcon(
          tooltip: t.discover.customOrder,
          icon: Icons.reorder,
          onPressed: onCustomizeOrder,
        ),
      _barIcon(
        tooltip: t.discover.search,
        icon: Icons.search,
        onPressed: onSearch,
      ),
      _DisplayOptionsButton(tabs: tabs),
    ];
    // 横向档那一行只有 40 高，竖着叠三颗按钮必然溢出 —— 朝向跟着标签条走。
    return vertical
        ? Column(mainAxisSize: MainAxisSize.min, children: children)
        : Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// 标签条上的那颗图标按钮。默认 `IconButton` 是 48 见方的，塞不进 40 高的横条。
Widget _barIcon({
  required String tooltip,
  required IconData icon,
  required VoidCallback? onPressed,
}) {
  return IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    iconSize: 18,
    padding: EdgeInsets.zero,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
  );
}

/// 「标签上显示什么」：图标、缩写两颗开关，加一档朝向。
///
/// 为什么不搬去设置页：这几颗改的是**眼前这一条**标签条的长相，就地调、就地看到。
/// 值本身仍写进全局设置（见 `DiscoverSettingState`），所以跨重启留着。
class _DisplayOptionsButton extends StatelessWidget {
  const _DisplayOptionsButton({required this.tabs});

  final DiscoverTabs tabs;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GlobalSettingCubit>();
    final setting = context.watch<GlobalSettingCubit>().state.discoverSetting;
    return SizedBox(
      width: 32,
      height: 32,
      child: PopupMenuButton<Object>(
        tooltip: t.discover.tabDisplay,
        icon: const Icon(Icons.tune_rounded, size: 18),
        iconSize: 18,
        padding: EdgeInsets.zero,
        // 这里**不要**设 `constraints`：`PopupMenuButton.constraints` 是**菜单**的
        // 尺寸，不是这颗按钮的（SDK 原文「Optional size constraints for the menu」，
        // 直接转给 `showMenu(constraints:)`）。先前按按钮尺寸填了 32×32，
        // 菜单被掐成 32×32、五项内容当场撑破布局 —— 而那一帧的布局异常就是
        // MouseTracker 不复位的引信：点这颗按钮之后每帧刷断言直到界面卡死。
        onSelected: (value) {
          if (value == _TabDisplayOption.icon) {
            cubit.updateDiscoverSetting(
              (current) =>
                  current.copyWith(tabIconEnabled: !current.tabIconEnabled),
            );
            return;
          }
          if (value == _TabDisplayOption.pluginShort) {
            cubit.updateDiscoverSetting(
              (current) => current.copyWith(
                tabPluginShortEnabled: !current.tabPluginShortEnabled,
              ),
            );
            return;
          }
          if (value is DiscoverTabBarSide) {
            cubit.updateDiscoverSetting(
              (current) => current.copyWith(tabSide: value),
            );
            // 朝向是**树**上的状态（plat 把它记在标签组节点里），只改设置
            // 不会让眼前这一条转过去；两处一起动，才不会出现「下次才是这样」。
            tabs.setSide(value);
          }
        },
        itemBuilder: (context) => [
          CheckedPopupMenuItem(
            value: _TabDisplayOption.icon,
            checked: setting.tabIconEnabled,
            child: Text(t.discover.tabShowIcon),
          ),
          CheckedPopupMenuItem(
            value: _TabDisplayOption.pluginShort,
            checked: setting.tabPluginShortEnabled,
            child: Text(t.discover.tabShowPluginShort),
          ),
          const PopupMenuDivider(),
          for (final side in DiscoverTabBarSide.values)
            CheckedPopupMenuItem(
              value: side,
              checked: setting.tabSide == side,
              child: Text(side.label),
            ),
        ],
      ),
    );
  }
}

enum _TabDisplayOption { icon, pluginShort }

/// 每个叶子内容拿到的那份把手（见 [DiscoverTabScope]）。
class _LeafActions implements DiscoverTabActions {
  const _LeafActions({
    required this.tabs,
    required this.leafId,
    required this.source,
  });

  final DiscoverTabs tabs;
  final String leafId;

  /// 当前这条标签的插件来源；从结果页跳回搜索输入页时接着用同一份，
  /// 不然「在 e-hentai 的搜索结果里点搜索框」会跳成一个没来源的搜索。
  final String source;

  @override
  void openComicInfo({
    required String comicId,
    required String from,
    required String title,
    String? collectionTargetId,
    String? collectionTargetName,
  }) {
    DiscoverRouter.openComicInfoTab(
      tabs,
      comicId: comicId,
      from: from,
      title: title,
      collectionTargetId: collectionTargetId,
      collectionTargetName: collectionTargetName,
    );
  }

  @override
  void openPage({
    required String label,
    required String source,
    required WidgetBuilder content,
    IconData? icon,
  }) {
    tabs.open(label: label, source: source, content: content, icon: icon);
  }

  @override
  void openSearchInput(SearchStates state, {required bool aggregateMode}) {
    tabs.open(
      label: t.discover.search,
      // 聚合搜索跨全部插件，不隶属某一个插件（与发现页顶栏那颗同口径）。
      source: aggregateMode ? '' : source,
      icon: aggregateMode ? Icons.search : null,
      content: (context) =>
          SearchPage(searchState: state, aggregateMode: aggregateMode),
    );
  }

  @override
  void closeCurrentTab() => tabs.close(leafId);

  @override
  void goHome() => tabs.goHome();
}
