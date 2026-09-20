import 'package:material_ui/material_ui.dart';
import 'package:zephyr/gpu/gpu_present_bridge.dart' show GpuPresentState;
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/super_resolution_status.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/cards/info_card_kit.dart';

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
          icon: Icons.bolt_rounded,
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
                  icon: Icons.bolt_outlined,
                  text: '打开书本后显示呈现与预取状态',
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
        children: [
          InfoRow(label: '路径', value: 'CPU 解码 / 图片缓存预加载'),
          InfoRow(
            label: '页表',
            value: '${slot + 1} / ${coordinator.totalSlots}',
          ),
          const InfoRow(label: '纹理', value: '—'),
        ],
      );
    }

    final lastIsCurrent = presenter.lastPresentIndex == slot;
    final status = presenter.currentPageUpscaleStatus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoRow(
          label: '呈现器',
          value: switch (presenter.state) {
            GpuPresentState.ready => '就绪',
            GpuPresentState.loading => '创建中',
            GpuPresentState.failed => '失败 · ${presenter.error}',
            GpuPresentState.unsupported => '本平台不支持',
          },
        ),
        if (presenter.textureId != null)
          InfoRow(label: '纹理', value: '#${presenter.textureId}'),
        InfoRow(label: '已呈现页数', value: '${presenter.presentCount}'),
        InfoRow(
          label: '当前页耗时',
          value: lastIsCurrent && presenter.lastPresentMs != null
              ? '${presenter.lastPresentMs} ms'
              : '—',
        ),
        InfoRow(
          label: '就绪等待',
          value: presenter.readyAfterMs != null
              ? '${presenter.readyAfterMs} ms'
              : '—',
        ),
        InfoRow(
          label: '超分阶段',
          value: status.pageNumber == null
              ? superResolutionPhaseLabel(status.phase)
              : '第 ${status.pageNumber} 页 · '
                    '${superResolutionPhaseLabel(status.phase)}',
        ),
        InfoRow(
          label: '超分开关',
          value: presenter.isUpscaleEnabled
              ? (presenter.isOriginalPreview ? '开着（原图对比中）' : '开着')
              : '关着',
        ),
      ],
    );
  }
}
