import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/super_resolution_status.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/cards/info_card_kit.dart';

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
          icon: Icons.image_rounded,
          isExpanded: isExpanded,
          onToggle: onToggle,
          onMoveUp: onMoveUp,
          onMoveDown: onMoveDown,
          onHide: onHide,
          trailing: hasSession
              ? Text(
                  '#${slot + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                )
              : null,
          child: hasSession
              ? _buildRows(coordinator, presenter, slot)
              : const InfoEmpty(
                  icon: Icons.image_outlined,
                  text: '打开书本后显示当前页信息',
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
    final docs = coordinator.docs;
    final doc = slot < docs.length ? docs[slot] : null;

    final name = pageRef?.name ?? doc?.originalName;
    // 尺寸快照是**按页下标**记的，下标对不上就是上一页的，不能用。
    final raster = (presenter != null &&
            presenter.currentPageUpscaleStatus.index == slot)
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
      children: [
        InfoRow(label: '页码', value: '${slot + 1} / ${coordinator.totalSlots}'),
        InfoRow(label: '文件名', value: name),
        InfoRow(label: '格式', value: name == null ? null : formatInfoExt(name)),
        InfoRow(label: '编码大小', value: formatInfoBytes(pageRef?.size)),
        InfoRow(
          label: '像素尺寸',
          value: raster == null ? null : formatImageSize(raster.sourceSize),
        ),
        InfoRow(
          label: '超分后',
          value: raster == null ? null : formatImageSize(raster.enhancedSize),
        ),
        if (displaySize != null) InfoRow(label: '显示目标', value: displaySize),
        InfoRow(label: '渲染路径', value: renderPath),
        if (doc != null && source == null) ...[
          InfoRow(label: '页地址', value: doc.path),
          InfoRow(label: '服务器', value: doc.fileServer),
        ],
      ],
    );
  }
}
