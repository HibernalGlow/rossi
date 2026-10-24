import 'package:zephyr/page/setting/common/setting_group.dart';
import 'dart:async';

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/setting/global/widgets/swimlane_panel_kanban_card.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_interaction_settings.dart';
import 'package:zephyr/workspace/model/workspace_lane_interaction.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/model/workspace_pointer_mode.dart';
import 'package:zephyr/workspace/model/workspace_reveal_zones.dart';
import 'package:zephyr/workspace/model/workspace_startup.dart';
import 'package:zephyr/workspace/service/workspace_layout_bridge.dart';
import 'package:zephyr/icons/icons.dart';

// 悬停唤出区：卡片、可拖拽画布编辑器、四个编辑量与画布 CustomPainter。
part 'parts/workspace_layout_reveal_zone_part.dart';
// 毫秒级驻留延时条目与整数数字框。
part 'parts/workspace_layout_delay_controls_part.dart';
part 'parts/workspace_layout_lane_interaction_part.dart';

/// 「设置 → 布局」：工作台走哪条呈现、泳道与面板看板、焦点与独占什么时候响应、
/// 以及**悬停唤出区**那块可以拖的画布。
@RoutePage()
class WorkspaceLayoutSettingPage extends StatefulWidget {
  const WorkspaceLayoutSettingPage({super.key});

  @override
  State<WorkspaceLayoutSettingPage> createState() =>
      _WorkspaceLayoutSettingPageState();
}

class _WorkspaceLayoutSettingPageState
    extends State<WorkspaceLayoutSettingPage> {
  /// 读盘是异步的：读回来之前先画一个空的骨架，而不是让整页在
  /// `null` 与真值之间闪一次。
  WorkspaceLayoutSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final snapshot = await WorkspaceLayoutBridge.instance.read();
    if (!mounted) return;
    setState(() => _snapshot = snapshot);
  }

  void _write({
    WorkspaceMode? mode,
    WorkspaceInteractionSettings? interaction,
    WorkspaceLayoutConfig? layout,
    WorkspaceBoardLayout? board,
    Map<String, String>? activePanel,
  }) {
    unawaited(
      WorkspaceLayoutBridge.instance.write(
        mode: mode,
        interaction: interaction,
        layout: layout,
        board: board,
        activePanel: activePanel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return SettingPageShell(
      title: t.settings.workspaceLayout,
      description: t.settings.workspaceLayoutSubtitle,
      child: snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: kSettingPagePadding,
              children: [
                settingSectionTitle(
                  context,
                  t.settings.laneAndLayout,
                  icon: AppGlyphs.columnsThree,
                ),
                // 手机端没有那颗侧栏按钮 —— `hasWorkspaceEntry` 回答的是
                // 「四边栏布局的 trailing 上有没有按钮」，那边真正的入口就在这一页。
                // 桌面/平板不摆：那颗按钮本来就在导航栏上，重复一个入口只会多一行。
                // 触摸设备进的是**移动端首页**（展开态面板），不是桌面泳道 ——
                // 同一套注册表与卡片，只是宿主不同（见 workspace/mobile/）。
                if (!hasWorkspaceEntry(context)) ...[
                  settingCategoryTile(
                    icon: AppGlyphs.gridPlus,
                    title: t.settings.enterWorkspace,
                    subtitle: t.settings.enterWorkspaceSubtitle,
                    onTap: () =>
                        context.pushRoute(const WorkspaceMobileHomeRoute()),
                  ),
                  const SizedBox(height: 12),
                ],
                // 桌面端窄窗口时工作台开哪个宿主。只在桌面三平台摆：触摸
                // 平台（手机 / 平板）的宿主永远是移动首页，这颗开关在那边
                // 是死数据，摆出来只会让人怀疑它没生效。
                if (isWorkspaceDesktopPlatform(defaultTargetPlatform))
                  SettingGroup.switchTile(
                    leading: const GlyphIcon(AppGlyphs.columnsThree),
                    title: Text(t.settings.workspaceNarrowMobileHost),
                    subtitle: Text(
                      t.settings.workspaceNarrowMobileHostSubtitle,
                    ),
                    value: context
                        .watch<GlobalSettingCubit>()
                        .state
                        .workspaceDesktopNarrowHostsMobile,
                    onChanged: (value) =>
                        context.read<GlobalSettingCubit>().updateState(
                          (current) => current.copyWith(
                            workspaceDesktopNarrowHostsMobile: value,
                          ),
                        ),
                  ),
                _StartupViewCard(
                  mode: snapshot.mode,
                  onChanged: (mode) {
                    setState(() => _snapshot = _snapshot!.copyWithMode(mode));
                    _write(mode: mode);
                  },
                ),
                const SizedBox(height: 12),
                WorkspaceSwimlanePanelKanbanCard(
                  snapshot: snapshot,
                  onChanged: (next) {
                    setState(() => _snapshot = next);
                    _write(
                      layout: next.layout,
                      board: next.board,
                      activePanel: next.activePanel,
                    );
                  },
                ),
                const SizedBox(height: 12),
                _FocusAndSoloCard(
                  interaction: snapshot.interaction,
                  onChanged: (next) {
                    setState(
                      () => _snapshot = _snapshot!.copyWithInteraction(next),
                    );
                    _write(interaction: next);
                  },
                ),
                const SizedBox(height: 12),
                _LaneInteractionCard(
                  laneIds: snapshot.layout.laneOrder,
                  laneTitles: {
                    for (final entry in snapshot.layout.lanes.entries)
                      entry.key: entry.value.title,
                  },
                  interaction: snapshot.interaction,
                  onChanged: (laneId, value) {
                    final current = _snapshot!.interaction;
                    final next = current.copyWith(
                      laneInteractions: {
                        ...current.laneInteractions,
                        laneId: value,
                      },
                    );
                    setState(
                      () => _snapshot = _snapshot!.copyWithInteraction(next),
                    );
                    _write(interaction: next);
                  },
                ),
                const SizedBox(height: 12),
                _LaneHeaderCard(
                  interaction: snapshot.interaction,
                  onChanged: (next) {
                    setState(
                      () => _snapshot = _snapshot!.copyWithInteraction(next),
                    );
                    _write(interaction: next);
                  },
                ),
                const SizedBox(height: 12),
                _RevealZoneCard(
                  zones: snapshot.interaction.revealZones,
                  onChanged: (zones) {
                    final next = snapshot.interaction.copyWith(
                      revealZones: zones,
                    );
                    setState(
                      () => _snapshot = _snapshot!.copyWithInteraction(next),
                    );
                    _write(interaction: next);
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  t.settings.delayRangeHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

// ── 默认启动视图 ──────────────────────────────────────────────────────────

class _StartupViewCard extends StatelessWidget {
  const _StartupViewCard({required this.mode, required this.onChanged});

  final WorkspaceMode mode;
  final ValueChanged<WorkspaceMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingSectionCard(
      title: t.settings.defaultStartupView,
      icon: AppGlyphs.layoutTabs,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SegmentedPicker<WorkspaceMode>(
                value: mode,
                onChanged: onChanged,
                entries: [
                  _Segment(
                    WorkspaceMode.edges,
                    t.settings.startupViewEdges,
                    AppGlyphs.alignVerticalCenter,
                  ),
                  _Segment(
                    WorkspaceMode.swimlane,
                    t.settings.startupViewSwimlane,
                    AppGlyphs.columnsThree,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                t.settings.startupViewHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── 泳道焦点与独占 ────────────────────────────────────────────────────────

class _FocusAndSoloCard extends StatelessWidget {
  const _FocusAndSoloCard({required this.interaction, required this.onChanged});

  final WorkspaceInteractionSettings interaction;
  final ValueChanged<WorkspaceInteractionSettings> onChanged;

  void _patch(
    WorkspaceInteractionSettings Function(WorkspaceInteractionSettings) change,
  ) => onChanged(change(interaction));

  @override
  Widget build(BuildContext context) {
    return SettingSectionCard(
      title: t.settings.laneFocusSolo,
      icon: AppGlyphs.target,
      children: [
        ListTile(
          title: Text(t.settings.laneFocusSoloSubtitle),
          subtitle: Text(t.settings.delayRangeHint),
        ),
        SettingGroup.switchTile(
          leading: const GlyphIcon(AppGlyphs.arrowForward),
          title: Text(t.settings.autoFocusReaderOnOpen),
          subtitle: Text(t.settings.autoFocusReaderOnOpenSubtitle),
          value: interaction.autoFocusReaderOnOpen,
          onChanged: (value) =>
              _patch((c) => c.copyWith(autoFocusReaderOnOpen: value)),
        ),
        SettingGroup.switchTile(
          leading: const GlyphIcon(AppGlyphs.locate),
          title: Text(t.settings.readerSoloOnFocus),
          subtitle: Text(t.settings.readerSoloOnFocusSubtitle),
          value: interaction.autoSoloOnFocus,
          onChanged: (value) =>
              _patch((c) => c.copyWith(autoSoloOnFocus: value)),
        ),
        SettingGroup.switchTile(
          leading: const GlyphIcon(AppGlyphs.columnsThree),
          title: Text(t.settings.showLaneNavigatorInSolo),
          subtitle: Text(t.settings.showLaneNavigatorInSoloSubtitle),
          value: interaction.showLaneNavigatorInSolo,
          onChanged: (value) =>
              _patch((c) => c.copyWith(showLaneNavigatorInSolo: value)),
        ),
        SettingGroup.switchTile(
          leading: const GlyphIcon(AppGlyphs.gesture),
          title: Text(t.settings.manualScrollEnabled),
          subtitle: Text(t.settings.manualScrollEnabledSubtitle),
          value: interaction.manualScrollEnabled,
          onChanged: (value) =>
              _patch((c) => c.copyWith(manualScrollEnabled: value)),
        ),
        SettingGroup.switchTile(
          leading: const GlyphIcon(AppGlyphs.lock),
          title: Text(t.settings.blockManualScrollInReaderFullscreen),
          subtitle: Text(
            t.settings.blockManualScrollInReaderFullscreenSubtitle,
          ),
          value: interaction.blockManualScrollInReaderFullscreen,
          onChanged: (value) => _patch(
            (c) => c.copyWith(blockManualScrollInReaderFullscreen: value),
          ),
        ),
        // 面板页签条的两种手势模式。放在这一段是因为它问的也是
        // 「工作台上手怎么分」而不是「某条泳道长什么样」——
        // 与上面那几颗（开书要不要跟过去、独占要不要自动、手动滚动）同类。
        //
        // 与页签条**右键把手那个菜单**里的是同一颗（同一份
        // `interaction.panelTabSortMode`）：栏头挂进栏头时把手不画，那边够不着，
        // 所以设置页这一条不能省。
        SettingGroup.switchTile(
          leading: const GlyphIcon(AppGlyphs.sort),
          title: Text(t.settings.panelTabSortMode),
          subtitle: Text(t.settings.panelTabSortModeSubtitle),
          value: interaction.panelTabSortMode,
          onChanged: (value) =>
              _patch((c) => c.copyWith(panelTabSortMode: value)),
        ),
        // 面板图标右键收起：与上面那颗同一段，因为它问的也是「面板栏上右键 /
        // 长按这一下算什么」。关掉后图标只剩「切换面板」一件事。
        //
        // 只在这里给入口：面板栏的**把手**那颗右键菜单管的是这一条栏怎么摆
        // （钉住 / 悬浮 / 停靠 / 排序模式），收起动作挂在**页签图标**本身，
        // 把手菜单够不着它。
        SettingGroup.switchTile(
          leading: const GlyphIcon(AppGlyphs.eyeOff),
          title: Text(t.settings.panelTabRightClickHide),
          subtitle: Text(t.settings.panelTabRightClickHideSubtitle),
          value: interaction.panelTabRightClickHide,
          onChanged: (value) =>
              _patch((c) => c.copyWith(panelTabRightClickHide: value)),
        ),
        _DelayTile(
          icon: AppGlyphs.speed,
          title: t.settings.edgeRevealDelay,
          value: interaction.edgeRevealDelayMs,
          min: 100,
          max: 5000,
          onChanged: (value) =>
              _patch((c) => c.copyWith(edgeRevealDelayMs: value)),
        ),
        SettingGroup.switchTile(
          leading: const GlyphIcon(AppGlyphs.locate),
          title: Text(t.settings.revealFocusesLane),
          subtitle: Text(t.settings.revealFocusesLaneSubtitle),
          value: interaction.revealFocusesLane,
          onChanged: (value) =>
              _patch((c) => c.copyWith(revealFocusesLane: value)),
        ),
        _DelayTile(
          icon: AppGlyphs.mouse,
          title: t.settings.defaultHoverDelay,
          subtitle: t.settings.defaultHoverDelaySubtitle,
          value: interaction.hoverFocusDelayMs,
          min: 60,
          max: 5000,
          onChanged: (value) =>
              _patch((c) => c.copyWith(hoverFocusDelayMs: value)),
        ),
      ],
    );
  }
}

// ── 泳道栏头 ──────────────────────────────────────────────────────────────

/// 栏头这一行的**显示**项（不涉及交互时机，所以与「焦点与独占」那张卡分开）。
///
/// 目前只有一颗：宽度徽标。它默认关 —— 栏头那点预算本来就紧，而徽标是让位顺序里
/// 最先走的（见 `SwimlaneColumn._fitHeader`），默认画它等于「有时有、有时没有」。
class _LaneHeaderCard extends StatelessWidget {
  const _LaneHeaderCard({required this.interaction, required this.onChanged});

  final WorkspaceInteractionSettings interaction;
  final ValueChanged<WorkspaceInteractionSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingSectionCard(
      title: t.settings.laneHeaderChrome,
      icon: AppGlyphs.resize,
      children: [
        ListTile(title: Text(t.settings.laneHeaderChromeSubtitle)),
        SettingGroup.switchTile(
          leading: const GlyphIcon(AppGlyphs.resize),
          title: Text(t.settings.showLaneWidthBadge),
          subtitle: Text(t.settings.showLaneWidthBadgeSubtitle),
          value: interaction.showLaneWidthBadge,
          onChanged: (value) =>
              onChanged(interaction.copyWith(showLaneWidthBadge: value)),
        ),
      ],
    );
  }
}

// ── 通用小件 ──────────────────────────────────────────────────────────────

class _Segment<T> {
  const _Segment(this.value, this.label, this.icon, {this.dot});

  final T value;
  final String label;
  final Glyph? icon;

  /// 色点：唤出区的四条边靠它把「chip」和「画布上那块颜色」对起来。
  final Color? dot;
}

/// 圆角容器里的一排互斥选项（neoview 的 `TabsList` / `variant=default|ghost`）。
class _SegmentedPicker<T> extends StatelessWidget {
  const _SegmentedPicker({
    required this.value,
    required this.onChanged,
    required this.entries,
  });

  final T value;
  final ValueChanged<T> onChanged;
  final List<_Segment<T>> entries;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .7)),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: entry.value == value
                      ? scheme.primary
                      : Colors.transparent,
                  foregroundColor: entry.value == value
                      ? scheme.onPrimary
                      : scheme.onSurfaceVariant,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => onChanged(entry.value),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (entry.dot != null) ...[
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: entry.dot!.withValues(alpha: .85),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ] else if (entry.icon != null) ...[
                      GlyphIcon(entry.icon!, size: 15),
                      const SizedBox(width: 6),
                    ],
                    Text(entry.label, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 一行紧凑的复选框（联动开关）。
class _LinkCheck extends StatelessWidget {
  const _LinkCheck({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 22,
              child: FittedBox(
                child: Checkbox(
                  value: value,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (next) => onChanged(next ?? false),
                ),
              ),
            ),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
