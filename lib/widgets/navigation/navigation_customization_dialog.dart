// 「自定义导航栏」弹窗：两张页签（桌面侧栏 / 移动端 Dock），每张里是**两段**
// 可拖拽清单 —— 「主区」与「底部快捷区」—— 外加一排「待添加」胶囊。
//
// 来源：FlClash 的 `lib/features/navigation_custom/custom_navigation_dialog.dart`
// —— 那一份是**本仓作者自己的提交**（上游 fork 里的 `23337390`），不是上游
// 正文。搬到本仓时按本仓的栈重写了三处：
//
// 1. riverpod → 本仓不需要：弹窗自己持一份**草稿**，每次编辑立刻回调
//    [showCustomNavigationDialog] 的 `onChanged`，由调用方写进全局设置。
//    这样弹窗不认识 Cubit / ObjectBox，判据里可以直接挂在 `MaterialApp` 下断言。
// 2. `PageLabel` + `getGlyphForPageLabel` → [NavigationEntryId]，图标与文案
//    都从 `navigation_entries.dart` 那份唯一真相取。
// 3. 文案走 slang（上游是写死的中文）。
//
// 本仓自己加的两处：
//
// 4. 条目池里除了页面还有**动作**（工作台 / 打开本地漫画 / GPU 上屏 / 搜索 /
//    自定义导航）。动作行右侧挂一个「动作」小标 —— 它们点下去推路由、
//    不换当前页，与页面不是一回事，得让人一眼分得出来。
// 5. **一段变两段**（2026-10-10 用户提的口径）：上游只有一份清单，而本仓的
//    侧栏底部那块是**独立的一段**（`navigation_sidebar.dart` 的 `actions`），
//    过去写死在那儿、藏不掉也排不了序。于是这里也照两段排：主区（页面与动作
//    都能放）+ 底部快捷区（只放动作），各自拖拽、各自隐藏；动作行上的箭头
//    按钮在两段之间搬。待添加池里的胶囊按**类型的自然归属**落下 —— 页面进
//    主区、动作进底部快捷区，想换位置再用箭头搬。
//
// 许可口径见 `docs/adr/0021-flclash-navigation-port-and-gpl-relicense.md`。

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/navigation/navigation_entries.dart';
import 'package:zephyr/widgets/popup_panel.dart';

/// 一支布局的草稿：**主区** + **底部快捷区**。
///
/// 两段分开而不是合成一份：侧栏底部那块本来就是独立的一段（它由
/// `NavigationSidebar.actions` 渲染），合成一份就没法单独排它、也没法把它
/// 整段藏掉 —— 而那正是这次要修的东西。
class NavigationLayoutDraft {
  const NavigationLayoutDraft({required this.main, required this.actions});

  /// 主区（侧栏上半 / Dock 胶囊）。页面与动作都能放。
  final List<NavigationEntryId> main;

  /// 底部快捷区（侧栏底部 / Dock 尾部溢出菜单）。**只放动作**。
  final List<NavigationEntryId> actions;

  NavigationLayoutDraft copyWith({
    List<NavigationEntryId>? main,
    List<NavigationEntryId>? actions,
  }) => NavigationLayoutDraft(
    main: main ?? this.main,
    actions: actions ?? this.actions,
  );
}

/// 打开弹窗。
///
/// [onChanged] 在**每次**编辑（增 / 删 / 排序 / 两段之间搬 / 恢复默认）后
/// 立刻回调，与 FlClash 那份 notifier 的 `_persist()` 同一时机：用户不需要
/// 再点一次「保存」，而「完成」只是关窗。
Future<void> showCustomNavigationDialog(
  BuildContext context, {
  required NavigationLayoutDraft desktop,
  required NavigationLayoutDraft mobile,
  required List<NavigationEntryId> availableItems,
  required void Function(
    NavigationLayoutDraft desktop,
    NavigationLayoutDraft mobile,
  )
  onChanged,
}) {
  return showPopupPanel<void>(
    presentation: PopupPresentation.relative,
    context: context,
    builder: (_) => CustomNavigationDialog(
      desktop: desktop,
      mobile: mobile,
      availableItems: availableItems,
      onChanged: onChanged,
    ),
  );
}

/// 从设置里那份**持久化形状**直接开弹窗。
///
/// 抽这一层是因为导航栏与「设置 → 外观」两处都要开它，而两边都得先把规矩
/// 解一遍 —— 主区那一段：存的是 `NavigationEntryId.name`、空清单 = 用出厂
/// 清单、关掉「旧版页面」之后残留的旧首页 / 旧排行不该继续占位、一条页面都
/// 不剩也退回出厂（见 [decodeNavigationEntryIds]）；底部那一段：`null` =
/// 没设置过用出厂、`[]` = 用户全隐藏、只收动作（见
/// [decodeNavigationActionIds]）。解两遍迟早分叉。
Future<void> showCustomNavigationDialogFor(
  BuildContext context, {
  required List<String> storedDesktopPageIds,
  required List<String>? storedDesktopActionIds,
  required List<String> storedMobilePageIds,
  required List<String>? storedMobileActionIds,
  required bool oldPageRollbackEnabled,
  required void Function(
    NavigationLayoutDraft desktop,
    NavigationLayoutDraft mobile,
  )
  onChanged,
}) {
  final allowed = availableNavigationEntries(oldPageRollbackEnabled);
  final mainFallback = defaultNavigationEntries(oldPageRollbackEnabled);
  final actionFallback = defaultNavigationActions(allowed);

  NavigationLayoutDraft draft(List<String> main, List<String>? actions) {
    final mainItems = resolveNavigationEntryIds(
      stored: main,
      allowed: allowed,
      fallback: mainFallback,
    );
    final actionItems = resolveNavigationActionIds(
      stored: actions,
      allowed: allowed,
      fallback: actionFallback,
    );
    // 两段是互斥的：同步来的旧数据可能两边都有同一条，以**主区**为准
    // （它在上面，用户先看见的就是它）。
    return NavigationLayoutDraft(
      main: mainItems,
      actions: [
        for (final id in actionItems)
          if (!mainItems.contains(id)) id,
      ],
    );
  }

  return showCustomNavigationDialog(
    context,
    desktop: draft(storedDesktopPageIds, storedDesktopActionIds),
    mobile: draft(storedMobilePageIds, storedMobileActionIds),
    availableItems: allowed,
    onChanged: onChanged,
  );
}

class CustomNavigationDialog extends StatefulWidget {
  const CustomNavigationDialog({
    super.key,
    required this.desktop,
    required this.mobile,
    required this.availableItems,
    required this.onChanged,
  });

  final NavigationLayoutDraft desktop;
  final NavigationLayoutDraft mobile;
  final List<NavigationEntryId> availableItems;
  final void Function(
    NavigationLayoutDraft desktop,
    NavigationLayoutDraft mobile,
  )
  onChanged;

  @override
  State<CustomNavigationDialog> createState() => _CustomNavigationDialogState();
}

/// 一条条目当前待在**哪一段**里。
enum _NavSection { main, actions }

class _CustomNavigationDialogState extends State<CustomNavigationDialog> {
  late NavigationLayoutDraft _desktop = widget.desktop;
  late NavigationLayoutDraft _mobile = widget.mobile;

  void _commit() => widget.onChanged(_desktop, _mobile);

  void _apply(bool isDesktop, NavigationLayoutDraft next) {
    setState(() {
      if (isDesktop) {
        _desktop = next;
      } else {
        _mobile = next;
      }
    });
    _commit();
  }

  NavigationLayoutDraft _draftOf(bool isDesktop) =>
      isDesktop ? _desktop : _mobile;

  void _add(bool isDesktop, _NavSection section, NavigationEntryId id) {
    final draft = _draftOf(isDesktop);
    _apply(
      isDesktop,
      section == _NavSection.main
          ? draft.copyWith(main: [...draft.main, id])
          : draft.copyWith(actions: [...draft.actions, id]),
    );
  }

  void _remove(bool isDesktop, _NavSection section, NavigationEntryId id) {
    final draft = _draftOf(isDesktop);
    if (section == _NavSection.main) {
      // 不能删就什么也不做（按钮本来就是灰的，这是二道保险）。
      final next = toggleNavigationEntry(draft.main, id);
      if (next == null) return;
      _apply(isDesktop, draft.copyWith(main: next));
      return;
    }
    _apply(
      isDesktop,
      draft.copyWith(actions: toggleNavigationAction(draft.actions, id)),
    );
  }

  void _reorder(
    bool isDesktop,
    _NavSection section,
    int oldIndex,
    int newIndex,
  ) {
    final draft = _draftOf(isDesktop);
    final items = section == _NavSection.main ? draft.main : draft.actions;
    final next = reorderNavigationEntry(items, oldIndex, newIndex);
    _apply(
      isDesktop,
      section == _NavSection.main
          ? draft.copyWith(main: next)
          : draft.copyWith(actions: next),
    );
  }

  /// 在两段之间搬一条。
  ///
  /// **只有动作能这么搬** —— 底部快捷区里放页面没有意义（页面得在主区里当
  /// 「当前视图」），所以按钮只出现在动作行上。
  void _move(bool isDesktop, _NavSection from, NavigationEntryId id) {
    final draft = _draftOf(isDesktop);
    if (from == _NavSection.main) {
      _apply(
        isDesktop,
        draft.copyWith(
          main: [
            for (final item in draft.main)
              if (item != id) item,
          ],
          actions: [...draft.actions, id],
        ),
      );
      return;
    }
    _apply(
      isDesktop,
      draft.copyWith(
        main: [...draft.main, id],
        actions: [
          for (final item in draft.actions)
            if (item != id) item,
        ],
      ),
    );
  }

  void _reset() {
    setState(() {
      final desktop = NavigationLayoutDraft(
        main: defaultNavigationEntries(true)
            .where(widget.availableItems.contains)
            .toList(),
        actions: defaultNavigationActions(widget.availableItems),
      );
      _desktop = desktop;
      // 两支恢复的是同一份出厂清单（出厂值本来就不分桌面 / 移动）。
      _mobile = NavigationLayoutDraft(
        main: desktop.main,
        actions: desktop.actions,
      );
    });
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // 上游是写死的 440×500。手机上那两个数放不下，于是按屏幕收一收 ——
    // 收的是**外框**，列表里该怎么滚还怎么滚。
    final width = size.width - 64 < 440 ? size.width - 64 : 440.0;
    final height = size.height - 200 < 500 ? size.height - 200 : 500.0;

    return PopupPanel(
      title: Text(t.navigation.customizeTitle),
      content: SizedBox(
        width: width,
        height: height,
        child: DefaultTabController(
          length: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  t.navigation.customizeHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TabBar(
                tabs: [
                  Tab(text: t.navigation.customizeDesktopTab),
                  Tab(text: t.navigation.customizeMobileTab),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _LayoutTab(
                      scope: 'desktop',
                      draft: _desktop,
                      availableItems: widget.availableItems,
                      onAdd: (section, id) => _add(true, section, id),
                      onRemove: (section, id) => _remove(true, section, id),
                      onReorder: (section, oldIndex, newIndex) =>
                          _reorder(true, section, oldIndex, newIndex),
                      onMove: (section, id) => _move(true, section, id),
                    ),
                    _LayoutTab(
                      scope: 'mobile',
                      draft: _mobile,
                      availableItems: widget.availableItems,
                      onAdd: (section, id) => _add(false, section, id),
                      onRemove: (section, id) => _remove(false, section, id),
                      onReorder: (section, oldIndex, newIndex) =>
                          _reorder(false, section, oldIndex, newIndex),
                      onMove: (section, id) => _move(false, section, id),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _reset,
          child: Text(t.navigation.customizeReset),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.navigation.customizeDone),
        ),
      ],
    );
  }
}

/// 一张页签的内容：两段清单 + 待添加池。
class _LayoutTab extends StatelessWidget {
  const _LayoutTab({
    required this.scope,
    required this.draft,
    required this.availableItems,
    required this.onAdd,
    required this.onRemove,
    required this.onReorder,
    required this.onMove,
  });

  /// 这一页的前缀（`desktop` / `mobile`）。
  ///
  /// 行 key 必须带上它：`SliverReorderableList` 会给每一行套一个**全局键**
  /// （`_ReorderableItemGlobalKey`），两张页签同时在树上时（滑动切页那一瞬）
  /// 值相同的键会撞成 duplicate-GlobalKey。段名同理。
  final String scope;
  final NavigationLayoutDraft draft;
  final List<NavigationEntryId> availableItems;
  final void Function(_NavSection section, NavigationEntryId id) onAdd;
  final void Function(_NavSection section, NavigationEntryId id) onRemove;
  final void Function(_NavSection section, int oldIndex, int newIndex) onReorder;
  final void Function(_NavSection section, NavigationEntryId id) onMove;

  /// 待添加池里的胶囊往哪儿落：按**类型的自然归属**。
  ///
  /// 页面进主区（它就是「当前视图」的候选），动作进底部快捷区（那一段的
  /// 语义就是快捷入口）。想换个位置，行上的箭头一步就搬到对面。
  static _NavSection _sectionFor(NavigationEntryId id) =>
      id.isAction ? _NavSection.actions : _NavSection.main;

  @override
  Widget build(BuildContext context) {
    final placed = {...draft.main, ...draft.actions};
    final pool = [
      for (final id in availableItems)
        if (!placed.contains(id)) id,
    ];
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _sectionHeader(context, t.navigation.customizeMainSection),
        ),
        _section(_NavSection.main, draft.main),
        SliverToBoxAdapter(
          child: _sectionHeader(
            context,
            t.navigation.customizeActionsSection,
            note: t.navigation.customizeActionsHint,
          ),
        ),
        _section(_NavSection.actions, draft.actions),
        if (pool.isNotEmpty)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 24),
                Text(
                  t.navigation.customizeAvailable,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final item in pool)
                      ActionChip(
                        avatar: GlyphIcon(item.glyph, size: 16),
                        label: Text(item.label),
                        onPressed: () => onAdd(_sectionFor(item), item),
                      ),
                  ],
                ),
              ],
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String title, {String? note}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                note,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _section(_NavSection section, List<NavigationEntryId> items) {
    return SliverReorderableList(
      itemCount: items.length,
      onReorderItem: (oldIndex, newIndex) =>
          onReorder(section, oldIndex, newIndex),
      // 拖拽起手的一刻，框架把整行当作**拖拽代理**提到最近一层 Overlay 里
      // —— 那层在弹窗 `AlertDialog` 的 `Material` 之外。`SliverReorderableList`
      // 裸用时默认代理**不包 Material**（`ReorderableListView` 才有带 Material
      // 的默认），行里的 ListTile 会当场抛「No Material widget found」
      // （2026-10-10 用户截图）。这里自己包一层，顺手做出「拖起来带影子」的
      // 观感 —— 与 `ReorderableListView` 的默认一致（easeInOut 从 0 升到 6）。
      proxyDecorator: _dragProxyDecorator,
      itemBuilder: (context, index) => _row(
        context: context,
        section: section,
        item: items[index],
        index: index,
      ),
    );
  }

  static Widget _dragProxyDecorator(
    Widget child,
    int index,
    Animation<double> animation,
  ) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final scheme = Theme.of(context).colorScheme;
        final t = Curves.easeInOut.transform(animation.value);
        return Material(
          elevation: t * 6,
          shadowColor: scheme.shadow,
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          child: child,
        );
      },
    );
  }

  Widget _row({
    required BuildContext context,
    required _NavSection section,
    required NavigationEntryId item,
    required int index,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final inMain = section == _NavSection.main;
    return Container(
      key: ValueKey('$scope/${section.name}/${item.name}'),
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        leading: GlyphIcon(item.glyph, size: 20),
        title: Text(item.label),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.isAction) _ActionTag(scheme: scheme),
            // 在两段之间搬。只有动作能搬 —— 底部快捷区里放页面没有意义
            // （页面得在主区里当「当前视图」）。
            if (item.isAction)
              IconButton(
                tooltip: inMain
                    ? t.navigation.customizeMoveToActions
                    : t.navigation.customizeMoveToMain,
                onPressed: () => onMove(section, item),
                visualDensity: VisualDensity.compact,
                icon: GlyphIcon(
                  inMain ? AppGlyphs.arrowDown : AppGlyphs.arrowUp,
                  size: 18,
                ),
              ),
            IconButton(
              tooltip: t.navigation.customizeHide,
              // 不能删就禁用：主区有一条下限（页面不能少于
              // `kMinNavigationPageCount` 条 —— 旧版手机底栏要 2..6 条且只
              // 渲染页面），判定在纯函数里（`canRemoveNavigationEntry`）；
              // 底部快捷区**没有**下限，全隐藏是合法的（那时底部整块不出现）。
              onPressed: inMain
                  ? (canRemoveNavigationEntry(draft.main, item)
                        ? () => onRemove(section, item)
                        : null)
                  : () => onRemove(section, item),
              visualDensity: VisualDensity.compact,
              icon: const GlyphIcon(AppGlyphs.remove, size: 18),
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: GlyphIcon(AppGlyphs.dragHandle, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 动作行右侧那个「动作」小标。
///
/// 不是装饰：动作点了推路由、不换当前页，行为与页面不同；不标出来，用户
/// 把它拖到主区上之后会以为「这一格怎么按了不高亮」。
class _ActionTag extends StatelessWidget {
  const _ActionTag({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsetsDirectional.only(end: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        t.navigation.customizeActionTag,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
