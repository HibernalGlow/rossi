import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/super_resolution_status.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/cards/info_card_kit.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/i18n/strings.g.dart';

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
          title: t.workspace.imageInformation,
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
              : InfoEmpty(
                  icon: AppGlyphs.photos,
                  text: t.workspace.showCurrentPageWhenOpen,
                  hint: t.workspace.refreshPerPageNoGuessing,
                  fields: [
                    (t.workspace.fileNameLabel, AppGlyphs.article),
                    (t.workspace.encodedSize, AppGlyphs.compress),
                    (t.workspace.pixelSize, AppGlyphs.cropFree),
                    (t.workspace.renderPath, AppGlyphs.devices),
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
        ? t.workspace.networkImageCached
        : (presenter != null && presenter.canPresent)
        ? t.workspace.gpuSharedTexture
        : t.workspace.cpuDecodeFallback;

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
              label: t.workspace.encodedFormat,
              icon: AppGlyphs.code,
              highlight: true,
            ),
            ExpressiveStatTile(
              value: formatInfoBytes(pageRef?.size),
              label: t.workspace.encodedSize,
              icon: AppGlyphs.compress,
            ),
            ExpressiveStatTile(
              value:
                  (raster == null
                      ? null
                      : formatImageSize(raster.sourceSize)) ??
                  '—',
              label: t.workspace.pixelSize,
              icon: AppGlyphs.cropFree,
              caption: raster == null
                  ? t.workspace.imageHeaderUnmeasured
                  : '超分后 ${formatImageSize(raster.enhancedSize) ?? '—'}',
            ),
          ],
        ),
        const SizedBox(height: 12),
        InfoFacts(
          children: [
            InfoRow(
              label: t.workspace.pageNumber,
              value: '${slot + 1} / ${coordinator.totalSlots}',
              icon: AppGlyphs.cardMedium,
            ),
            InfoRow(
              label: t.workspace.fileNameLabel,
              value: name,
              icon: AppGlyphs.article,
            ),
            InfoRow(
              label: t.workspace.encodedSize,
              value: formatInfoBytes(pageRef?.size),
              icon: AppGlyphs.compress,
            ),
            InfoRow(
              label: t.workspace.pixelSize,
              value: raster == null ? null : formatImageSize(raster.sourceSize),
              icon: AppGlyphs.cropFree,
            ),
            InfoRow(
              label: t.workspace.afterUpscale,
              value: raster == null
                  ? null
                  : formatImageSize(raster.enhancedSize),
              icon: AppGlyphs.sparkle,
            ),
            if (displaySize != null)
              InfoRow(
                label: t.workspace.showTarget,
                value: displaySize,
                icon: AppGlyphs.fitScreen,
              ),
            InfoRow(
              label: t.workspace.renderPath,
              value: renderPath,
              emphasis: source == null || (presenter?.canPresent ?? false),
              icon: AppGlyphs.devices,
            ),
            if (doc != null && source == null) ...[
              InfoRow(
                label: t.workspace.pageUrl,
                value: doc.path,
                icon: AppGlyphs.link,
              ),
              InfoRow(
                label: t.workspace.serverLabel,
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
