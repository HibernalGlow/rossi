import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/super_resolution_status.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/cards/info_card_kit.dart';
import 'package:zephyr/icons/icons.dart';

/// 图像信息卡（对齐 Neo 的 `image-information`）：
/// 当前页的文件名 / 格式 / 编码大小 / 像素尺寸 / 呈现路径。
///
/// 尺寸只报**量到的**：GPU 路的原图尺寸是超分流水线量的图头（
/// `currentPageUpscaleStatus.sourceSize`），量不到就显示 `—`，
/// 不为了填满格子去解一遍码。
class ImageInformationCard extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final bool isStandalone;

  const ImageInformationCard({
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
    final presenter = LocalReadSession.instance.presenter;
    final listenable = presenter == null
        ? coordinator
        : Listenable.merge(<Listenable>[coordinator, presenter]);

    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final slot = coordinator.currentSlot;
        final hasSession = coordinator.hasActiveSession;
        return CollapsibleCard(
          cardId: 'image_information',
          title: '图像信息',
          icon: AppGlyphs.photos,
          expressive: true,
          isExpanded: isExpanded,
          onToggle: onToggle,
          onMoveUp: onMoveUp,
          onMoveDown: onMoveDown,
          onHide: onHide,
          trailing: hasSession ? InfoCardCounter('#${slot + 1}') : null,
          child: hasSession
              ? _buildRows(coordinator, presenter, slot)
              : const InfoEmpty(
                  icon: AppGlyphs.photos,
                  text: '打开书本后显示当前页信息',
                  hint: '随翻页刷新；量不到的项不猜',
                  fields: [
                    ('文件名', AppGlyphs.article),
                    ('编码大小', AppGlyphs.compress),
                    ('像素尺寸', AppGlyphs.cropFree),
                    ('渲染路径', AppGlyphs.devices),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildRows(
    ReaderSessionCoordinator coordinator,
    GpuPresentController? presenter,
    int slot,
  ) {
    final source = coordinator.localSource;
    final pageRef = (source != null && slot < source.pages.length)
        ? source.pages[slot]
        : null;
    final docs = coordinator.orderedDocs;
    final doc = slot < docs.length ? docs[slot] : null;

    final name = pageRef?.name ?? doc?.originalName;
    // 尺寸快照是**按页下标**记的，下标对不上就是上一页的，不能用。
    final raster =
        (presenter != null && presenter.currentPageUpscaleStatus.index == slot)
        ? presenter.currentPageUpscaleStatus
        : null;

    final String renderPath = source == null
        ? '网络图片 · 下载后走图片缓存'
        : (presenter != null && presenter.canPresent)
        ? 'GPU 共享纹理'
        : 'CPU 解码兜底';

    final stats = presenter?.stats;
    final displaySize = (stats != null && stats.width > 0 && stats.height > 0)
        ? '${stats.width}×${stats.height}'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ExpressiveTileGrid(
          minTileWidth: 104,
          children: [
            ExpressiveStatTile(
              value: name == null ? '—' : formatInfoExt(name),
              label: '编码格式',
              icon: AppGlyphs.code,
              highlight: true,
            ),
            ExpressiveStatTile(
              value: formatInfoBytes(pageRef?.size),
              label: '编码大小',
              icon: AppGlyphs.compress,
            ),
            ExpressiveStatTile(
              value:
                  (raster == null
                      ? null
                      : formatImageSize(raster.sourceSize)) ??
                  '—',
              label: '像素尺寸',
              icon: AppGlyphs.cropFree,
              caption: raster == null
                  ? '量不到图头'
                  : '超分后 ${formatImageSize(raster.enhancedSize) ?? '—'}',
            ),
          ],
        ),
        const SizedBox(height: 12),
        InfoFacts(
          children: [
            InfoRow(
              label: '页码',
              value: '${slot + 1} / ${coordinator.totalSlots}',
              icon: AppGlyphs.cardMedium,
            ),
            InfoRow(label: '文件名', value: name, icon: AppGlyphs.article),
            InfoRow(
              label: '编码大小',
              value: formatInfoBytes(pageRef?.size),
              icon: AppGlyphs.compress,
            ),
            InfoRow(
              label: '像素尺寸',
              value: raster == null ? null : formatImageSize(raster.sourceSize),
              icon: AppGlyphs.cropFree,
            ),
            InfoRow(
              label: '超分后',
              value: raster == null
                  ? null
                  : formatImageSize(raster.enhancedSize),
              icon: AppGlyphs.sparkle,
            ),
            if (displaySize != null)
              InfoRow(
                label: '显示目标',
                value: displaySize,
                icon: AppGlyphs.fitScreen,
              ),
            InfoRow(
              label: '渲染路径',
              value: renderPath,
              emphasis: source == null || (presenter?.canPresent ?? false),
              icon: AppGlyphs.devices,
            ),
            if (doc != null && source == null) ...[
              InfoRow(label: '页地址', value: doc.path, icon: AppGlyphs.link),
              InfoRow(
                label: '服务器',
                value: doc.fileServer,
                icon: AppGlyphs.router,
              ),
            ],
          ],
        ),
      ],
    );
  }
}
