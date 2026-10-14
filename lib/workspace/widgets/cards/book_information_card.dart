import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/cards/info_card_kit.dart';
import 'package:zephyr/icons/icons.dart';

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
          icon: AppGlyphs.book,
          expressive: true,
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
                  icon: AppGlyphs.openBook,
                  text: '打开一本书后显示书籍信息',
                  hint: '开书后这几格会当场填上，量不到的留 —',
                  fields: [
                    ('书名', AppGlyphs.book),
                    ('作者', AppGlyphs.profiles),
                    ('类型', AppGlyphs.category),
                    ('章节', AppGlyphs.article),
                    ('页码', AppGlyphs.linearScale),
                    ('进度', AppGlyphs.speed),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildRows(ReaderSessionCoordinator coordinator, dynamic comicInfo) {
    final total = coordinator.totalSlots;
    final current = coordinator.currentSlot;
    final ratio = total <= 0 ? null : (current + 1) / total;
    final progress = ratio == null ? '—' : '${(ratio * 100).round()}%';
    final epInfo = coordinator.epInfo;
    final from = coordinator.from ?? '';
    final isLocal = coordinator.localSource != null;

    // comicInfo 是上游路由带过来的动态值（Map / 实体对象都可能出现），
    // 只认 Map 里那几个公共键；认不出来就不显示，不编。
    String? infoField(String key) {
      if (comicInfo is! Map) return null;
      final v = comicInfo[key]?.toString().trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 三个「读的时候真会瞄一眼」的数做成 Expressive 大数字格，
        // 进度那一格自带一条弹簧驱动的进度条。
        ExpressiveTileGrid(
          minTileWidth: 132,
          children: [
            ExpressiveStatTile(
              value: '${current + 1}',
              label: '当前页 · 共 $total 页',
              icon: AppGlyphs.layers,
              highlight: true,
              gauge: ratio,
            ),
            ExpressiveStatTile(
              value: progress,
              label: '阅读进度',
              icon: AppGlyphs.trend,
              caption: total <= 0 ? '页表未就绪' : '还剩 ${total - current - 1} 页',
            ),
            ExpressiveStatTile(
              value: isLocal ? '本地' : (from.isEmpty ? '在线' : from),
              label: '来源',
              icon: isLocal ? AppGlyphs.folder : AppGlyphs.globe,
              maxValueLines: 1,
            ),
          ],
        ),
        const SizedBox(height: 12),
        InfoFacts(
          children: [
            InfoRow(
              label: '书名',
              value: coordinator.displayTitle,
              emphasis: true,
              icon: AppGlyphs.book,
            ),
            if (infoField('author') != null)
              InfoRow(
                label: '作者',
                value: infoField('author'),
                icon: AppGlyphs.profiles,
              ),
            if (infoField('status') != null)
              InfoRow(
                label: '状态',
                value: infoField('status'),
                icon: AppGlyphs.info,
              ),
            InfoRow(
              label: '类型',
              value: isLocal ? '本地漫画' : '在线图源 · $from',
              icon: AppGlyphs.category,
            ),
            InfoRow(
              label: '漫画 ID',
              value: coordinator.comicId,
              icon: AppGlyphs.key,
            ),
            if (epInfo != null)
              InfoRow(
                label: '章节',
                value: epInfo.epName,
                icon: AppGlyphs.article,
              ),
            if (epInfo != null && epInfo.epId.isNotEmpty)
              InfoRow(label: '章节 ID', value: epInfo.epId, icon: AppGlyphs.tree),
            InfoRow(
              label: '页码',
              value: '${current + 1} / $total',
              icon: AppGlyphs.linearScale,
            ),
            InfoRow(label: '进度', value: progress, icon: AppGlyphs.speed),
            if (from.isNotEmpty && isLocal)
              InfoRow(label: '来源键', value: from, icon: AppGlyphs.link),
          ],
        ),
      ],
    );
  }
}
