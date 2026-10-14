import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/setting/global/widgets/swimlane_panel_kanban_card.dart';
import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';
import 'package:zephyr/workspace/service/workspace_layout_bridge.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 专门的「泳道与面板看板」设置页面：
///
/// 使用三栏看板调整：
/// - 泳道顺序（左泳道 / 阅读器 / 右泳道）；
/// - 每个泳道上面板的顺序与跨泳道归属；
/// - 面板的显示与彻底隐藏（隐藏后从面板栏彻底移除，不显示隐藏图标；「图源扩展」默认隐藏）。
@RoutePage()
class SwimlanePanelSettingPage extends StatefulWidget {
  const SwimlanePanelSettingPage({super.key});

  @override
  State<SwimlanePanelSettingPage> createState() =>
      _SwimlanePanelSettingPageState();
}

class _SwimlanePanelSettingPageState extends State<SwimlanePanelSettingPage> {
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

  void _applySnapshot(WorkspaceLayoutSnapshot next) {
    setState(() => _snapshot = next);
    unawaited(
      WorkspaceLayoutBridge.instance.write(
        layout: next.layout,
        board: next.board,
        activePanel: next.activePanel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return SettingPageShell(
      title: t.settings.swimlanePanelKanban,
      description: t.settings.swimlanePanelKanbanDesc,
      maxWidth: 1160,
      child: snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: kSettingPagePadding,
              children: [
                settingSectionTitle(
                  context,
                  t.settings.swimlanePanelKanbanConfigTitle,
                  icon: AppGlyphs.dashboard,
                ),
                WorkspaceSwimlanePanelKanbanCard(
                  snapshot: snapshot,
                  onChanged: _applySnapshot,
                  showHeader: false,
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}
