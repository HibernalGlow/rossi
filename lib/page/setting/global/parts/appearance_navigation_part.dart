part of '../appearance_setting_page.dart';

// 「设置 → 外观」里的**导航栏**那一段：两个壳（Arc 侧栏 / 悬浮 Dock）各自的
// 开关、窄屏自动切与它的阈值、以及「自定义导航」的入口。
//
// 为什么放在这一页而不是「设置 → 布局」：那一页是**工作台**的布局
// （泳道、面板、唤出区，值落在 `workspace_layout.json`）；这里问的是应用外壳
// 长什么样，与工作台开关同类，用户没进过工作台也要能设。
//
// 为什么不进 `GlobalSettingState`（工作台那份是另一个文件）：导航栏这两支
// 清单要跟着云同步走（`sync_service_rossi_part.dart` 的 `_shellBlockKeys`），
// 而工作台布局刻意不进同步。

/// 这一段的条目。返回列表是因为它在 `ListView` 里是**一叠平铺的条目**
/// （与这一页其它段落一致），不是一张 `Card`。
List<Widget> navigationChromeTiles({
  required BuildContext context,
  required GlobalSettingState state,
  required GlobalSettingCubit cubit,
}) {
  final nav = state.navigationSetting;
  // 「这台设备有没有侧栏这一支」= 本机有没有工作台入口（桌面三平台与平板）。
  // 手机上摆一颗按了没反应的侧栏开关、以及只有侧栏才用得上的阈值，
  // 比不摆更糟 —— 与 `workspace_layout_setting_page.dart` 里那条同一条口径。
  final sidebarCapable = hasWorkspaceEntry(context);

  void patch(NavigationSettingState Function(NavigationSettingState) change) {
    cubit.updateNavigationSetting(change);
  }

  return [
    settingSectionTitle(
      context,
      t.navigation.navigationChrome,
      icon: AppGlyphs.layoutTabs,
    ),
    if (sidebarCapable)
      SettingGroup.switchTile(
        leading: const GlyphIcon(AppGlyphs.layoutTabs),
        title: Text(t.navigation.sidebarEnabled),
        subtitle: Text(t.navigation.sidebarEnabledSubtitle),
        value: nav.sidebarEnabled,
        onChanged: (value) =>
            patch((current) => current.copyWith(sidebarEnabled: value)),
      ),
    // 展开态只在侧栏开着时才需要回答 —— 关着时摆出来只会让人犹豫。
    if (sidebarCapable && nav.sidebarEnabled)
      SettingGroup.switchTile(
        leading: const GlyphIcon(AppGlyphs.unfold),
        title: Text(t.navigation.sidebarExpanded),
        subtitle: Text(t.navigation.sidebarExpandedSubtitle),
        value: nav.sidebarExpanded,
        onChanged: (value) =>
            patch((current) => current.copyWith(sidebarExpanded: value)),
      ),
    // Dock 那一支在手机上就是主力，所以这一项不按平台收 ——
    // 它在桌面上也不是摆设：窗口被拉窄（见下面那条阈值）时露出的就是它。
    SettingGroup.switchTile(
      leading: const GlyphIcon(AppGlyphs.dashboard),
      title: Text(t.navigation.dockEnabled),
      subtitle: Text(t.navigation.dockEnabledSubtitle),
      value: nav.dockEnabled,
      onChanged: (value) =>
          patch((current) => current.copyWith(dockEnabled: value)),
    ),
    if (sidebarCapable)
      SettingGroup.switchTile(
        leading: const GlyphIcon(AppGlyphs.linearScale),
        title: Text(t.navigation.autoNarrowMobileLayout),
        subtitle: Text(t.navigation.autoNarrowMobileLayoutSubtitle),
        value: nav.autoNarrowMobileLayout,
        onChanged: (value) =>
            patch((current) => current.copyWith(autoNarrowMobileLayout: value)),
      ),
    if (sidebarCapable && nav.autoNarrowMobileLayout)
      _NarrowWidthTile(
        value: nav.narrowNavigationWidth,
        onChanged: (value) =>
            patch((current) => current.copyWith(narrowNavigationWidth: value)),
      ),
    // 长按 Dock 进「自定义导航」的开关与阈值。Dock 不按平台收（手机主力、
    // 桌面窄窗口也露出），这两条同口径；阈值只在开关开着时才有答案。
    SettingGroup.switchTile(
      leading: const GlyphIcon(AppGlyphs.hand),
      title: Text(t.navigation.dockLongPressCustomize),
      subtitle: Text(t.navigation.dockLongPressCustomizeSubtitle),
      value: nav.dockLongPressCustomize,
      onChanged: (value) =>
          patch((current) => current.copyWith(dockLongPressCustomize: value)),
    ),
    if (nav.dockLongPressCustomize)
      _DockLongPressTile(
        value: nav.dockLongPressMilliseconds,
        onChanged: (value) => patch(
          (current) => current.copyWith(dockLongPressMilliseconds: value),
        ),
      ),
    ListTile(
      leading: const GlyphIcon(AppGlyphs.sliders),
      title: Text(t.navigation.customize),
      subtitle: Text(t.navigation.customizeHint),
      trailing: const GlyphIcon(AppGlyphs.chevronForward),
      onTap: () => showCustomNavigationDialogFor(
        context,
        storedDesktopPageIds: nav.desktopPageIds,
        storedDesktopActionIds: nav.desktopActionIds,
        storedMobilePageIds: nav.mobilePageIds,
        storedMobileActionIds: nav.mobileActionIds,
        onChanged: (desktop, mobile) {
          patch(
            (current) => current.copyWith(
              desktopPageIds: encodeNavigationEntryIds(desktop.main),
              mobilePageIds: encodeNavigationEntryIds(mobile.main),
              desktopActionIds: encodeNavigationEntryIds(desktop.actions),
              mobileActionIds: encodeNavigationEntryIds(mobile.actions),
            ),
          );
        },
      ),
    ),
  ];
}

/// 窄屏阈值：一条能拖的滑块 + 一颗「恢复默认」。
///
/// 用滑块而不是数字框 —— 这一页别处的延时量用的是数字框（见
/// `workspace_layout_setting_page.dart` 的 `_DelayTile`），那里的理由是「180 还是
/// 250 毫秒」要对表；而宽度阈值只跟窗口宽度比一次大小，320..1600 之间没有
/// 「必须精确到某一格」的点，滑块把整段范围摊在手上、也能一眼看出当前值
/// 落在重侧（靠 320 就是「几乎总是移动端」）还是轻侧。
class _NarrowWidthTile extends StatelessWidget {
  const _NarrowWidthTile({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  /// 拖动步长（逻辑像素）。取 20：更细的差别在真机上换不出布局，
  /// 更粗会让人够不到想要的数。
  static const double _step = 20;

  @override
  Widget build(BuildContext context) {
    final clamped = clampNarrowNavigationWidth(value);
    // 存进来的值可能越界（老版本存的、或云端同步来的），按夹取后的值判
    // 「是不是默认」—— 否则会出现「显示着 320、按键却是灰的」这种自相矛盾。
    final isDefault = clamped == kDefaultNarrowNavigationWidth;
    final theme = Theme.of(context);
    return ListTile(
      leading: const GlyphIcon(AppGlyphs.resize),
      title: Text(t.navigation.narrowNavigationWidth),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.navigation.narrowNavigationWidthSubtitle),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: clamped,
                  min: kMinNarrowNavigationWidth,
                  max: kMaxNarrowNavigationWidth,
                  divisions:
                      ((kMaxNarrowNavigationWidth - kMinNarrowNavigationWidth) /
                              _step)
                          .round(),
                  label: '${clamped.round()}',
                  onChanged: onChanged,
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '${clamped.round()}',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              IconButton(
                icon: const GlyphIcon(AppGlyphs.reset),
                tooltip: t.navigation.narrowNavigationWidthReset(
                  value: kDefaultNarrowNavigationWidth.round(),
                ),
                onPressed: isDefault
                    ? null
                    : () => onChanged(kDefaultNarrowNavigationWidth),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 长按阈值：一条能拖的滑块 + 一颗「恢复默认」。
///
/// 照 [_NarrowWidthTile] 的样式。取滑块而不是数字框：这里与那边的「宽度
/// 阈值」同类 —— 没有必须精确到某一格的点，300..1500 毫秒摊在手上，
/// 100ms 一格（更细的差别在真机上换不出手感）。
class _DockLongPressTile extends StatelessWidget {
  const _DockLongPressTile({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  static const int _min = 300;
  static const int _max = 1500;
  static const int _step = 100;

  /// 出厂值。比平台的 500ms 稳一档：500 常常是「想切页却弹了设置」。
  static const int _default = 800;

  int get _clamped => value.clamp(_min, _max);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: const GlyphIcon(AppGlyphs.clock),
      title: Text(t.navigation.dockLongPressDuration),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.navigation.dockLongPressDurationSubtitle),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _clamped.toDouble(),
                  min: _min.toDouble(),
                  max: _max.toDouble(),
                  divisions: (_max - _min) ~/ _step,
                  label: '${_clamped.round()}',
                  onChanged: (value) => onChanged(value.round()),
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  t.navigation.millisecondUnit(value: _clamped.round()),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              IconButton(
                icon: const GlyphIcon(AppGlyphs.reset),
                tooltip: t.navigation.dockLongPressDurationReset(
                  value: _default,
                ),
                onPressed: _clamped == _default
                    ? null
                    : () => onChanged(_default),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
