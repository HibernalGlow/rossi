import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/registry/workspace_ids.dart';
import 'package:zephyr/workspace/registry/workspace_panel_registry.dart';

/// 移动端**阅读数据页**：洞察面板的 8 张卡在手机/展台上的整页呈现。
///
/// 与 [WorkspaceMobileCardPage] 的区别只在前者收「一张卡」，这里收
/// 「一个面板的全部卡片」——卡片清单、次序与可见性都从
/// [WorkspaceCardRegistry.cardsForPanel] 来，本页不做第二份清单；
/// 卡片自己带数据窗口（`HistoryInsightsWindow`），加载/空/错三态都在卡内。
///
/// chrome 走**非 standalone**：洞察卡在泳道里长什么样（标题行 + 折叠），
/// 这里就长什么样，位置语义（上移/下移/隐藏）属于泳道轨道，整页形态不提供。
///
/// 布局两档：手机单列纵排；`≥ 760` 逻辑宽（平板 / 展台）两列并排，
/// 每列宽由可用宽度对半，卡高仍由内容自报 —— 洞察卡不依赖泳道宽度，
/// 窄列下热力图自己横向滚动（见 `ReadingHeatmapView`）。
@RoutePage()
class WorkspaceMobileInsightsPage extends StatefulWidget {
  const WorkspaceMobileInsightsPage({super.key});

  @override
  State<WorkspaceMobileInsightsPage> createState() =>
      _WorkspaceMobileInsightsPageState();
}

class _WorkspaceMobileInsightsPageState
    extends State<WorkspaceMobileInsightsPage> {
  static const double _kStandBreakpoint = 760;

  /// 与页面布局判断共用的「桌面布局看板」：洞察卡没有用户覆盖时,
  /// `const WorkspaceBoardLayout()` 与桌面泳道读到的是同一份默认归属。
  final WorkspaceBoardLayout _board = const WorkspaceBoardLayout();

  /// 折叠是页内局部状态：移动端没有泳道轨道，不落盘、不进快照。
  final Set<String> _collapsed = <String>{};

  @override
  Widget build(BuildContext context) {
    final registry = WorkspaceCardRegistry.I;
    final cards = registry.cardsForPanel(WorkspacePanelId.insights, _board);

    return Scaffold(
      appBar: AppBar(title: Text(_panelTitle())),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= _kStandBreakpoint;
          if (!wide) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
              children: [for (final card in cards) _cardTile(context, card)],
            );
          }
          final columnWidth =
              (constraints.maxWidth - 20 - 16 /* 两侧 padding */ ) / 2;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
            child: Wrap(
              spacing: 20,
              runSpacing: 4,
              children: [
                for (final card in cards)
                  SizedBox(width: columnWidth, child: _cardTile(context, card)),
              ],
            ),
          );
        },
      ),
    );
  }

  String _panelTitle() {
    return WorkspacePanelRegistry.I.find(WorkspacePanelId.insights)?.title ??
        WorkspacePanelId.insights;
  }

  Widget _cardTile(BuildContext context, WorkspaceCardDefinition card) {
    final layout = WorkspaceCardRegistry.I.effectiveLayout(card, _board);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: card.builder(
        context,
        WorkspaceCardChrome(
          expanded: !_collapsed.contains(card.id),
          onToggle: () => setState(() {
            if (!_collapsed.remove(card.id)) _collapsed.add(card.id);
          }),
          index: 0,
          count: 1,
          supported: card.supportedHere?.call() ?? true,
          unsupportedHint: card.unsupportedHint,
          widthSpan: layout.widthSpan ?? card.defaultWidthSpan,
          heightSpan: layout.heightSpan ?? card.defaultHeightSpan,
        ),
      ),
    );
  }
}
