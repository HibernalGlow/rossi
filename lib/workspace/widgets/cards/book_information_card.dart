import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/cards/info_card_kit.dart';

/// 书籍信息卡（对齐 Neo 信息面板的 `book-information`）：
/// 书名 / 类型 / 图源 / 章节 / 页码与进度。
///
/// 数据全部来自 [ReaderSessionCoordinator] 那份**唯一**的阅读会话中枢 ——
/// 卡片不另开一条获取路径，显示与实际读的永远是同一本书。
class BookInformationCard extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final bool isStandalone;

  const BookInformationCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.isStandalone = false,
  });

  @override
  Widget build(BuildContext context) {
    final coordinator = ReaderSessionCoordinator.instance;
    final target = context.select<WorkspaceCubit, dynamic>(
      (c) => c.state.readerTarget?.comicInfo,
    );

    return ListenableBuilder(
      listenable: coordinator,
      builder: (context, _) {
        final hasSession = coordinator.hasActiveSession;
        final total = coordinator.totalSlots;
        final current = coordinator.currentSlot;

        return CollapsibleCard(
          cardId: 'book_information',
          title: '书籍信息',
          icon: Icons.menu_book_rounded,
          isExpanded: isExpanded,
          onToggle: onToggle,
          onMoveUp: onMoveUp,
          onMoveDown: onMoveDown,
          onHide: onHide,
          trailing: hasSession
              ? InfoCardCounter('${current + 1} / $total')
              : null,
          child: hasSession
              ? _buildRows(coordinator, target)
              : const InfoEmpty(
                  icon: Icons.auto_stories_rounded,
                  text: '打开一本书后显示书籍信息',
                ),
        );
      },
    );
  }

  Widget _buildRows(ReaderSessionCoordinator coordinator, dynamic comicInfo) {
    final total = coordinator.totalSlots;
    final current = coordinator.currentSlot;
    final progress = total <= 0 ? '—' : '${(current / total * 100).round()}%';
    final epInfo = coordinator.epInfo;
    final from = coordinator.from ?? '';

    // comicInfo 是上游路由带过来的动态值（Map / 实体对象都可能出现），
    // 只认 Map 里那几个公共键；认不出来就不显示，不编。
    String? infoField(String key) {
      if (comicInfo is! Map) return null;
      final v = comicInfo[key]?.toString().trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoRow(label: '书名', value: coordinator.displayTitle, emphasis: true),
        if (infoField('author') != null)
          InfoRow(label: '作者', value: infoField('author')),
        if (infoField('status') != null)
          InfoRow(label: '状态', value: infoField('status')),
        InfoRow(
          label: '类型',
          value: coordinator.localSource != null ? '本地漫画' : '在线图源 · $from',
        ),
        InfoRow(label: '漫画 ID', value: coordinator.comicId),
        if (epInfo != null) InfoRow(label: '章节', value: epInfo.epName),
        if (epInfo != null && epInfo.epId.isNotEmpty)
          InfoRow(label: '章节 ID', value: epInfo.epId),
        InfoRow(label: '页码', value: '${current + 1} / $total'),
        InfoRow(label: '进度', value: progress),
        if (from.isNotEmpty && coordinator.localSource != null)
          InfoRow(label: '来源键', value: from),
      ],
    );
  }
}
