part of '../workspace_layout_setting_page.dart';

/// 共用一份交互表单，通过 Tab 选择正在编辑的泳道。
class _LaneInteractionCard extends StatelessWidget {
  const _LaneInteractionCard({
    required this.laneIds,
    required this.laneTitles,
    required this.interaction,
    required this.onChanged,
  });

  final List<String> laneIds;
  final Map<String, String> laneTitles;
  final WorkspaceInteractionSettings interaction;
  final void Function(String, WorkspaceLaneInteraction) onChanged;

  @override
  Widget build(BuildContext context) {
    if (laneIds.isEmpty) return const SizedBox.shrink();
    return DefaultTabController(
      length: laneIds.length,
      child: SettingSectionCard(
        title: t.settings.laneInteraction,
        icon: AppGlyphs.mouse,
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            onTap: (_) => FocusScope.of(context).unfocus(),
            tabs: [
              for (final laneId in laneIds)
                Tab(text: laneTitles[laneId] ?? laneId),
            ],
          ),
          Builder(
            builder: (context) {
              final tabs = DefaultTabController.of(context);
              return AnimatedBuilder(
                animation: tabs,
                builder: (context, _) {
                  final laneId = laneIds[tabs.index];
                  return _LaneInteractionFields(
                    key: ValueKey(laneId),
                    laneId: laneId,
                    interaction: interaction,
                    onChanged: (value) => onChanged(laneId, value),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 值与回写路径按泳道隔离，切换页签时数字输入框也重新绑定。
class _LaneInteractionFields extends StatelessWidget {
  const _LaneInteractionFields({
    super.key,
    required this.laneId,
    required this.interaction,
    required this.onChanged,
  });

  final String laneId;
  final WorkspaceInteractionSettings interaction;
  final ValueChanged<WorkspaceLaneInteraction> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = interaction.interactionForLane(laneId);
    final inheritsDelay = value.hoverDelayMs == null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingGroup.switchTile(
          title: Text(t.settings.laneKeyboardFollowsMouse),
          subtitle: Text(t.settings.laneKeyboardFollowsMouseSubtitle),
          value: value.inputTargetOnHover,
          onChanged: (enabled) =>
              onChanged(value.copyWith(inputTargetOnHover: enabled)),
        ),
        const Divider(height: 1),
        SettingGroup.switchTile(
          title: Text(t.settings.laneHoverReveal),
          subtitle: Text(t.settings.laneHoverRevealSubtitle),
          value: value.autoReveal,
          onChanged: (enabled) =>
              onChanged(value.copyWith(autoReveal: enabled)),
        ),
        const Divider(height: 1),
        ListTile(
          title: Text(t.settings.laneHoverDelay),
          subtitle: Text(
            inheritsDelay
                ? '继承全局：${interaction.hoverFocusDelayMs} 毫秒'
                : '本泳道自定义 · 毫秒',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NumberBox(
                value: interaction.hoverDelayForLane(laneId),
                min: 1,
                max: 5000,
                enabled: value.autoReveal,
                onCommit: (delay) =>
                    onChanged(value.copyWith(hoverDelayMs: () => delay)),
              ),
              IconButton(
                tooltip: t.settings.laneHoverDelayInherit,
                icon: const GlyphIcon(AppGlyphs.reset),
                onPressed: inheritsDelay
                    ? null
                    : () => onChanged(value.copyWith(hoverDelayMs: () => null)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
