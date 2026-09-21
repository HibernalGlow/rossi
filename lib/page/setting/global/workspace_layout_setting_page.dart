import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/workspace/model/workspace_interaction_settings.dart';
import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/model/workspace_reveal_zones.dart';
import 'package:zephyr/workspace/service/workspace_layout_bridge.dart';

// 悬停唤出区：卡片、可拖拽画布编辑器、四个编辑量与画布 CustomPainter。
part 'parts/workspace_layout_reveal_zone_part.dart';
// 毫秒级驻留延时条目与整数数字框。
part 'parts/workspace_layout_delay_controls_part.dart';

/// 「设置 → 布局」：工作台走哪条呈现、焦点与独占什么时候响应、
/// 以及**悬停唤出区**那块可以拖的画布。
///
/// 复刻的是 neoview 的 `BoardLayoutSettingsCard`（「泳道与布局」卡片的泳道页）。
/// 那里头的另一半「布局看板」（面板 / 卡片拖到左栏 / 右栏 / 隐藏）不在这一页 ——
/// 它改的是面板记账，与这里的「指针停在哪儿会把东西调出来」是两件事。
///
/// # 值存在哪儿
///
/// 全部落在 `workspace_layout.json` 的 `mode` 与 `interaction` 两块里，
/// **不进** `GlobalSettingState`。理由与 `WorkspaceLayoutSnapshot` 同源：
/// 这些是布局的偏好，与泳道宽度、面板记账是同一批要一起备份、一起重置的东西；
/// 拆到全局设置里就会有两个真相（改一处、另一处仍然生效）。
/// 读写走 [WorkspaceLayoutBridge]：工作台在场时改的是活的 cubit
/// （直接写盘会被它的去抖落盘覆盖回去），不在场时才读盘改写。
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
  }) {
    unawaited(
      WorkspaceLayoutBridge.instance.write(
        mode: mode,
        interaction: interaction,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return SettingPageShell(
      title: t.settings.workspaceLayout,
      child: snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: kSettingPagePadding,
              children: [
                settingSectionTitle(
                  context,
                  t.settings.laneAndLayout,
                  icon: Icons.view_column_outlined,
                ),
                _StartupViewCard(
                  mode: snapshot.mode,
                  onChanged: (mode) {
                    setState(() => _snapshot = _snapshot!.copyWithMode(mode));
                    _write(mode: mode);
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
      icon: Icons.tab_outlined,
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
                    Icons.vertical_align_center,
                  ),
                  _Segment(
                    WorkspaceMode.swimlane,
                    t.settings.startupViewSwimlane,
                    Icons.view_column,
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
      icon: Icons.center_focus_strong_outlined,
      children: [
        ListTile(
          title: Text(t.settings.laneFocusSoloSubtitle),
          subtitle: Text(t.settings.delayRangeHint),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.filter_center_focus_outlined),
          title: Text(t.settings.readerSoloOnFocus),
          subtitle: Text(t.settings.readerSoloOnFocusSubtitle),
          thumbIcon: kSettingSwitchThumbIcon,
          value: interaction.autoSoloOnFocus,
          onChanged: (value) =>
              _patch((c) => c.copyWith(autoSoloOnFocus: value)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.view_kanban_outlined),
          title: Text(t.settings.showLaneNavigatorInSolo),
          subtitle: Text(t.settings.showLaneNavigatorInSoloSubtitle),
          thumbIcon: kSettingSwitchThumbIcon,
          value: interaction.showLaneNavigatorInSolo,
          onChanged: (value) =>
              _patch((c) => c.copyWith(showLaneNavigatorInSolo: value)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.swipe),
          title: Text(t.settings.manualScrollEnabled),
          subtitle: Text(t.settings.manualScrollEnabledSubtitle),
          thumbIcon: kSettingSwitchThumbIcon,
          value: interaction.manualScrollEnabled,
          onChanged: (value) =>
              _patch((c) => c.copyWith(manualScrollEnabled: value)),
        ),
        _DelayTile(
          icon: Icons.speed_outlined,
          title: t.settings.edgeRevealDelay,
          value: interaction.edgeRevealDelayMs,
          min: 100,
          max: 5000,
          onChanged: (value) =>
              _patch((c) => c.copyWith(edgeRevealDelayMs: value)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.center_focus_weak_outlined),
          title: Text(t.settings.revealFocusesLane),
          subtitle: Text(t.settings.revealFocusesLaneSubtitle),
          thumbIcon: kSettingSwitchThumbIcon,
          value: interaction.revealFocusesLane,
          onChanged: (value) =>
              _patch((c) => c.copyWith(revealFocusesLane: value)),
        ),
        _DelayTile(
          icon: Icons.mouse_outlined,
          title: t.settings.readerHoverFocusDelay,
          subtitle: t.settings.readerHoverFocusEnable,
          value: interaction.hoverFocusDelayMs,
          min: 200,
          max: 5000,
          enabled: interaction.hoverFocusEnabled,
          switchValue: interaction.hoverFocusEnabled,
          onSwitchChanged: (value) =>
              _patch((c) => c.copyWith(hoverFocusEnabled: value)),
          onChanged: (value) =>
              _patch((c) => c.copyWith(hoverFocusDelayMs: value)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.view_sidebar_outlined),
          title: Text(t.settings.panelLaneHoverFocus),
          subtitle: Text(t.settings.panelLaneHoverFocusSubtitle),
          thumbIcon: kSettingSwitchThumbIcon,
          value: interaction.panelHoverFocusEnabled,
          onChanged: (value) =>
              _patch((c) => c.copyWith(panelHoverFocusEnabled: value)),
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
  final IconData? icon;

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
                      Icon(entry.icon, size: 15),
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
