import 'package:material_ui/material_ui.dart';
import 'package:zephyr/gpu/gpu_present_bridge.dart' show GpuPresentState;
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/super_resolution_status.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/cards/info_card_kit.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 预加载状态卡（对齐 Neo 的 `preload-status`）：
/// 呈现器就绪状态、已呈现页数、最近一次交页耗时、当前页超分阶段。
///
/// 每一项都来自**记账字段**而不是推断：`presentCount` 只数「真的把页
/// 交出去过」，`lastPresentMs` 只在 native 侧画完之后才写 —— 卡片跟着
/// [GpuPresentController] 的通知刷新，绝不显示「我调过所以应该好了」。
class PreloadStatusCard extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final bool isStandalone;

  const PreloadStatusCard({
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
        final hasSession = coordinator.hasActiveSession;
        return CollapsibleCard(
          cardId: 'preload_status',
          title: t.workspace.preloadStatus,
          icon: AppGlyphs.bolt,
          expressive: true,
          isExpanded: isExpanded,
          onToggle: onToggle,
          onMoveUp: onMoveUp,
          onMoveDown: onMoveDown,
          onHide: onHide,
          trailing: presenter != null && hasSession
              ? InfoCardCounter(
                  presenter.canPresent
                      ? t.workspace.gpuReady
                      : t.workspace.gpuLinking,
                  emphasize: presenter.canPresent,
                )
              : null,
          child: !hasSession
              ? InfoEmpty(
                  icon: AppGlyphs.bolt,
                  text: t.workspace.showPresentPrefetchWhenOpen,
                  hint: t.workspace.everyFieldIsMeasured,
                  fields: [
                    (t.workspace.presenter, AppGlyphs.devices),
                    (t.workspace.pagesPresented, AppGlyphs.photos),
                    (t.workspace.currentPageCost, AppGlyphs.speed),
                    (t.workspace.upscaleStage, AppGlyphs.sparkle),
                  ],
                )
              : _buildRows(coordinator, presenter),
        );
      },
    );
  }

  Widget _buildRows(
    ReaderSessionCoordinator coordinator,
    GpuPresentController? presenter,
  ) {
    final slot = coordinator.currentSlot;

    if (presenter == null) {
      // 网络 / CPU 路径没有呈现器：页表与槽位是真的，其余显示 —。
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ExpressiveTileGrid(
            minTileWidth: 140,
            children: [
              ExpressiveStatTile(
                value: 'CPU',
                label: t.workspace.preloadPath,
                icon: AppGlyphs.cpu,
                highlight: true,
                caption: t.workspace.decodeBufferPlusCache,
              ),
              ExpressiveStatTile(
                value: '${slot + 1} / ${coordinator.totalSlots}',
                label: t.workspace.pageList,
                icon: AppGlyphs.layers,
              ),
            ],
          ),
          const SizedBox(height: 12),
          InfoFacts(
            children: [
              InfoRow(
                label: t.workspace.pathLabel,
                value: t.workspace.cpuDecodePreload,
                emphasis: true,
                icon: AppGlyphs.cpu,
              ),
              InfoRow(
                label: t.workspace.pageList,
                value: '${slot + 1} / ${coordinator.totalSlots}',
                icon: AppGlyphs.layers,
              ),
              InfoRow(
                label: t.workspace.texture,
                value: '—',
                icon: AppGlyphs.devices,
              ),
            ],
          ),
        ],
      );
    }

    final lastIsCurrent = presenter.lastPresentIndex == slot;
    final status = presenter.currentPageUpscaleStatus;
    final ready = presenter.canPresent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ExpressiveTileGrid(
          minTileWidth: 104,
          children: [
            ExpressiveStatTile(
              value: '${presenter.presentCount}',
              label: t.workspace.pagesPresented,
              icon: AppGlyphs.photos,
              highlight: ready,
              caption: ready ? t.workspace.textureReady : t.workspace.linking,
            ),
            ExpressiveStatTile(
              value: lastIsCurrent && presenter.lastPresentMs != null
                  ? '${presenter.lastPresentMs}'
                  : '—',
              label: t.workspace.currentPageHandoffMs,
              icon: AppGlyphs.speed,
            ),
            ExpressiveStatTile(
              value: imageEnhancementPhaseLabel(status),
              label: t.workspace.imageProcessingStage,
              icon: AppGlyphs.sparkle,
              caption: status.pageNumber == null
                  ? null
                  : '第 ${status.pageNumber} 页',
            ),
          ],
        ),
        const SizedBox(height: 12),
        InfoFacts(
          children: [
            InfoRow(
              label: t.workspace.presenter,
              valueWidget: ExpressiveStatusPill(
                text: switch (presenter.state) {
                  GpuPresentState.ready => t.workspace.readyState,
                  GpuPresentState.loading => t.workspace.creating,
                  GpuPresentState.failed => t.workspace.failedWith(
                    error: presenter.error,
                  ),
                  GpuPresentState.unsupported =>
                    t.workspace.platformUnsupported,
                },
                compact: true,
                tone: switch (presenter.state) {
                  GpuPresentState.ready => ExpressiveTone.primary,
                  GpuPresentState.failed => ExpressiveTone.warning,
                  _ => ExpressiveTone.neutral,
                },
              ),
              icon: AppGlyphs.devices,
            ),
            if (presenter.textureId != null)
              InfoRow(
                label: t.workspace.texture,
                value: '#${presenter.textureId}',
                icon: AppGlyphs.layers,
              ),
            InfoRow(
              label: t.workspace.pagesPresented,
              value: '${presenter.presentCount}',
              icon: AppGlyphs.photos,
            ),
            InfoRow(
              label: t.workspace.currentPageCost,
              value: lastIsCurrent && presenter.lastPresentMs != null
                  ? '${presenter.lastPresentMs} ms'
                  : '—',
              icon: AppGlyphs.speed,
            ),
            InfoRow(
              label: t.workspace.readyWaiting,
              value: presenter.readyAfterMs != null
                  ? '${presenter.readyAfterMs} ms'
                  : '—',
              icon: AppGlyphs.hourglass,
            ),
            InfoRow(
              label: t.workspace.imageProcessingStage,
              value: status.pageNumber == null
                  ? imageEnhancementPhaseLabel(status)
                  : '${t.reader.pageNumberN(page: status.pageNumber!)} · '
                        '${imageEnhancementPhaseLabel(status)}',
              icon: AppGlyphs.sparkle,
            ),
            InfoRow(
              label: t.workspace.upscaleSwitch,
              value: presenter.isUpscaleEnabled
                  ? (presenter.isOriginalPreview
                        ? t.workspace.onComparingOriginal
                        : t.workspace.switchedOn)
                  : t.workspace.turnedOff,
              emphasis: presenter.isUpscaleEnabled,
              icon: AppGlyphs.power,
            ),
          ],
        ),
      ],
    );
  }
}
