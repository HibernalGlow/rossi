import 'package:material_ui/material_ui.dart';
import 'package:zephyr/gpu/gpu_present_bridge.dart' show GpuPresentState;
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/super_resolution_status.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/cards/info_card_kit.dart';
import 'package:zephyr/icons/icons.dart';

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
          title: '预加载状态',
          icon: AppGlyphs.bolt,
          expressive: true,
          isExpanded: isExpanded,
          onToggle: onToggle,
          onMoveUp: onMoveUp,
          onMoveDown: onMoveDown,
          onHide: onHide,
          trailing: presenter != null && hasSession
              ? InfoCardCounter(
                  presenter.canPresent ? 'GPU 就绪' : 'GPU 建链中',
                  emphasize: presenter.canPresent,
                )
              : null,
          child: !hasSession
              ? const InfoEmpty(
                  icon: AppGlyphs.bolt,
                  text: '打开书本后显示呈现与预取状态',
                  hint: '每一项都来自记账字段，不来自「我调过所以应该好了」',
                  fields: [
                    ('呈现器', AppGlyphs.devices),
                    ('已呈现页数', AppGlyphs.photos),
                    ('当前页耗时', AppGlyphs.speed),
                    ('超分阶段', AppGlyphs.sparkle),
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
                label: '预加载路径',
                icon: AppGlyphs.cpu,
                highlight: true,
                caption: '解码缓冲 + 图片缓存',
              ),
              ExpressiveStatTile(
                value: '${slot + 1} / ${coordinator.totalSlots}',
                label: '页表',
                icon: AppGlyphs.layers,
              ),
            ],
          ),
          const SizedBox(height: 12),
          InfoFacts(
            children: [
              InfoRow(
                label: '路径',
                value: 'CPU 解码 / 图片缓存预加载',
                emphasis: true,
                icon: AppGlyphs.cpu,
              ),
              InfoRow(
                label: '页表',
                value: '${slot + 1} / ${coordinator.totalSlots}',
                icon: AppGlyphs.layers,
              ),
              const InfoRow(label: '纹理', value: '—', icon: AppGlyphs.devices),
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
              label: '已呈现页数',
              icon: AppGlyphs.photos,
              highlight: ready,
              caption: ready ? '纹理就绪' : '建链中',
            ),
            ExpressiveStatTile(
              value: lastIsCurrent && presenter.lastPresentMs != null
                  ? '${presenter.lastPresentMs}'
                  : '—',
              label: '当前页交页耗时 (ms)',
              icon: AppGlyphs.speed,
            ),
            ExpressiveStatTile(
              value: imageEnhancementPhaseLabel(status),
              label: '图像处理阶段',
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
              label: '呈现器',
              valueWidget: ExpressiveStatusPill(
                text: switch (presenter.state) {
                  GpuPresentState.ready => '就绪',
                  GpuPresentState.loading => '创建中',
                  GpuPresentState.failed => '失败 · ${presenter.error}',
                  GpuPresentState.unsupported => '本平台不支持',
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
                label: '纹理',
                value: '#${presenter.textureId}',
                icon: AppGlyphs.layers,
              ),
            InfoRow(
              label: '已呈现页数',
              value: '${presenter.presentCount}',
              icon: AppGlyphs.photos,
            ),
            InfoRow(
              label: '当前页耗时',
              value: lastIsCurrent && presenter.lastPresentMs != null
                  ? '${presenter.lastPresentMs} ms'
                  : '—',
              icon: AppGlyphs.speed,
            ),
            InfoRow(
              label: '就绪等待',
              value: presenter.readyAfterMs != null
                  ? '${presenter.readyAfterMs} ms'
                  : '—',
              icon: AppGlyphs.hourglass,
            ),
            InfoRow(
              label: '图像处理阶段',
              value: status.pageNumber == null
                  ? imageEnhancementPhaseLabel(status)
                  : '第 ${status.pageNumber} 页 · '
                        '${imageEnhancementPhaseLabel(status)}',
              icon: AppGlyphs.sparkle,
            ),
            InfoRow(
              label: '超分开关',
              value: presenter.isUpscaleEnabled
                  ? (presenter.isOriginalPreview ? '开着（原图对比中）' : '开着')
                  : '关着',
              emphasis: presenter.isUpscaleEnabled,
              icon: AppGlyphs.power,
            ),
          ],
        ),
      ],
    );
  }
}
