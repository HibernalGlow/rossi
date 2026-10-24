import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/registry/workspace_ids.dart';
import 'package:zephyr/workspace/registry/workspace_panel_registry.dart';

/// Reader 的**上下文信息底部面板**（移动端宿主）。
///
/// 桌面上「书籍 / 图像 / 存储 / 时间 / 预加载」五张信息卡住在右泳道的
/// 信息面板里；手机上用户不该为了看一眼图片尺寸退出阅读——从 Reader
/// 底部工具栏唤起这块底部面板，同一批卡以紧凑形态盖在阅读器上。
///
/// 与 [WorkspaceMobileCardPage] 同一条复用口径：卡片清单来自
/// [WorkspaceCardRegistry.cardsForPanel]（信息面板），本文件不写第二份
/// 卡片清单；卡片数据自己读 [ReaderSessionCoordinator] 单例，宿主只补上
/// `BookInformationCard` 依赖的 [WorkspaceCubit]（构造零副作用，
/// `BlocProvider` 会在面板关闭时负责 close）。
///
/// 展台（宽屏）：`showModalBottomSheet` 自身随可用宽度收缩，
/// 卡片单列滚动 —— 信息卡是键值对行，宽列反而难读，不为宽屏硬拆两列。
void showReaderInfoBottomSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (sheetContext) => BlocProvider<WorkspaceCubit>(
      create: (_) => WorkspaceCubit(),
      child: const _ReaderInfoSheet(),
    ),
  );
}

class _ReaderInfoSheet extends StatefulWidget {
  const _ReaderInfoSheet();

  @override
  State<_ReaderInfoSheet> createState() => _ReaderInfoSheetState();
}

class _ReaderInfoSheetState extends State<_ReaderInfoSheet> {
  /// 折叠是面板的局部状态：信息卡的「隐藏」语义属于泳道轨道，
  /// 底部面板里只提供「收起内容 / 展开内容」。
  final Set<String> _collapsed = <String>{};

  @override
  Widget build(BuildContext context) {
    final registry = WorkspaceCardRegistry.I;
    const board = WorkspaceBoardLayout();
    final cards = registry.cardsForPanel(WorkspacePanelId.info, board);
    final title =
        WorkspacePanelRegistry.I.find(WorkspacePanelId.info)?.title ??
        WorkspacePanelId.info;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              children: [
                GlyphIcon(
                  AppGlyphs.info,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          Expanded(
            child: cards.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        t.workspace.mobileCardUnsupported,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    children: [
                      for (final card in cards)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: card.builder(
                            context,
                            WorkspaceCardChrome(
                              expanded: !_collapsed.contains(card.id),
                              onToggle: () => setState(() {
                                if (!_collapsed.remove(card.id)) {
                                  _collapsed.add(card.id);
                                }
                              }),
                              index: 0,
                              count: 1,
                              supported: card.supportedHere?.call() ?? true,
                              unsupportedHint: card.unsupportedHint,
                              widthSpan: card.defaultWidthSpan,
                              heightSpan: card.defaultHeightSpan,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
