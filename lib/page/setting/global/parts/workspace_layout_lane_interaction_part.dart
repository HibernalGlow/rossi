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
        title: '泳道交互',
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
        SwitchListTile(
          title: const Text('键盘目标跟随鼠标'),
          subtitle: const Text('鼠标进入本泳道后，将键盘操作交给本泳道'),
          thumbIcon: kSettingSwitchThumbIcon,
          value: value.inputTargetOnHover,
          onChanged: (enabled) =>
              onChanged(value.copyWith(inputTargetOnHover: enabled)),
        ),
        const Divider(height: 1),
        SwitchListTile(
          title: const Text('悬停后完整显示'),
          subtitle: const Text('停留后自动移动工作台，让本泳道完整显示'),
          thumbIcon: kSettingSwitchThumbIcon,
          value: value.autoReveal,
          onChanged: (enabled) =>
              onChanged(value.copyWith(autoReveal: enabled)),
        ),
        const Divider(height: 1),
        ListTile(
          title: const Text('悬停定位延迟'),
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
                tooltip: '恢复继承全局延迟',
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
