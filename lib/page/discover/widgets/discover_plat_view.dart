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
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/page/search/view/search_page.dart';
import 'package:zephyr/page/discover/service/plugin_display_label.dart';
import 'package:zephyr/widgets/plugin_icon.dart';

/// 发现页的标签宿主：一个 plat 的 `PlatTabGroup`。
///
/// 横向档（[TabBarSide.top]）时那一行标签条**就是**发现页的顶栏 —— 用户
/// 2026-09-20 的口径：另起一行与「发现」标题栏割裂。竖向档时同一份 chrome
/// 转到内容的左边或右边。
class DiscoverPlatView extends StatelessWidget {
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

  /// 横向档一条标签最多占多宽。超出的字走省略号，全名在 tooltip 里。
  static const double _chipMaxWidth = 180;

  /// 竖向轨的厚度（= 一条标签可用的全部宽度）。
  ///
  /// 不能贪宽：这一档是**从内容区里扣出来的**。发现页住在泳道里时整页常常只有
  /// 320~500 宽，轨给到 152 之后剩下的宽度连标签内容自己的工具栏都摆不下
  /// （实测 `SearchPage` 那条搜索栏要 ~160，被压到 152 就报 RenderFlex overflowed，
  /// 而布局异常会跳过 MouseTracker 的复位标志 → 每帧刷断言直到卡死）。
  static const double _railThickness = 120;

  /// 竖排一条标签里**不是标签名**的那部分：前导图标 + 两道间距 + 关闭钮 + 标签内边距。
  static const double _railChromeWidth = 72;

  /// 竖排标签名的上限。
  ///
  /// 必须自己算：竖排时 `PlatTabStrip` 给每条标签的是**无界**宽度，
  /// `PlatTabChip` 于是 `mainAxisSize.min` 按内容取宽 —— 标签名一长就把整条轨撑破
  /// （实测溢出 8px，报 RenderFlex overflowed，而布局异常会把 MouseTracker 的
  /// 复位标志跳过去，表现就是每帧刷断言直到界面卡死）。
  static const double _railLabelMaxWidth = _railThickness - _railChromeWidth;

  bool get _vertical => tabs.vertical;

  @override
  Widget build(BuildContext context) {
    return PlatTheme(
      data: PlatThemeData(
        tabBar: PlatTabBarTheme(
          // 竖向轨要窄：它是列表的边，不该吃掉内容的三分之一。
          size: _vertical ? _railThickness : 40,
          fit: TabStripFit.scrollable,
          spacing: 2,
        ),
      ),
      child: PlatView(
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

    return PlatTabChip(
      leading: setting.tabIconEnabled ? _chipLeading(context, leaf) : null,
      label: Tooltip(
        // tooltip 用**全名**：标签上截的是缩写，窄轨上那截字到底属于哪个插件，
        // 得有个地方能看全。
        message: joinTabLabel(shortName: leaf.pluginName, label: leaf.label),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _vertical ? _railLabelMaxWidth : _chipMaxWidth,
          ),
          child: text,
        ),
      ),
      // 首页那条是 locked 的，plat 自己会把关闭按钮藏掉。
      trailing: const PlatTabCloseButton(),
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
    return PopupMenuButton<Object>(
      tooltip: t.discover.tabDisplay,
      icon: const Icon(Icons.tune_rounded, size: 18),
      iconSize: 18,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
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
