import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_super_resolution.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/super_resolution_status.dart';
import 'package:zephyr/widgets/toast.dart';

/// 顶栏上的「当前页超分」芯片：**状态 + 超分后分辨率 + 超分开关**。
///
/// # 三块，各自回答一个问题
///
/// | 位置 | 回答 | 依据 |
/// |---|---|---|
/// | 图标 + 状态字 | 这一页现在到哪一步了 | `GpuPresentController.currentPageUpscaleStatus` |
/// | 分辨率 | 超分之后是多少像素 | 量超分产物的图片头（量不出就不显示） |
/// | 右侧开关 | 超分开着没有 | `isUpscaleEnabled`（与阅读设置面板同一个） |
///
/// # 为什么不是一个按钮
///
/// 从前这枚胶囊是「点一下切原图对比、长按关闭超分」，两件事都藏在手势里：
/// 用户既不知道现在超分到底跑没跑（状态不可见），也不知道开关在哪（手势不可见）。
/// 现在**开关是看得见的控件**，手势只保留一件事：点主体切「对比原图」。
/// 长按不再是「关闭超分」—— 那件事现在由开关承担，留着只会让人误触。
///
/// # 为什么窄屏不写分辨率
///
/// 顶栏其他控件的固定宽度之和已经占掉六百多逻辑像素，再硬塞十多字的分辨率，
/// `Row` 就会溢出（黄黑斜纹）。所以分辨率文字在
/// [superResolutionSizeMinWidth] 以上才出现，**窄屏仍然能在 tooltip 里看到它**。
/// 判据在 `super_resolution_status.dart` 里，是纯函数，有单测钉着。
///
/// 网络来源（插件漫画）没有呈现器 —— 那条路的超分在文件下载层发生，没有「当前页」
/// 可言，所以这里整块不显示（它的总闸在阅读设置面板与全局设置里）。
class ReaderUpscaleStatusChip extends StatelessWidget {
  const ReaderUpscaleStatusChip({
    super.key,
    this.availableWidth = double.infinity,
  });

  /// 顶栏的可用宽度（逻辑像素）。决定要不要写分辨率文字。
  final double availableWidth;

  @override
  Widget build(BuildContext context) {
    final GpuPresentController? presenter = LocalReadSession.instance.presenter;
    if (presenter == null) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        if (!presenter.canPresent) {
          return const SizedBox.shrink();
        }
        return _buildChip(context, presenter);
      },
    );
  }

  Widget _buildChip(BuildContext context, GpuPresentController presenter) {
    final colorScheme = Theme.of(context).colorScheme;
    final SuperResolutionPageStatus status =
        presenter.currentPageUpscaleStatus;
    final bool enabled = presenter.isUpscaleEnabled;
    final String? sizeText = superResolutionSizeText(status, availableWidth);

    // 配色只有四档，宁可少也不要花：**失败**必须一眼看出来（红），
    // **有超分产物**才配强调色（蓝/主题色），**正在跑**用中性偏亮，
    // 其余（关着、不支持、无需超分）一律压暗 —— 顶栏是压在漫画上的，
    // 花哨的芯片会跟画面抢注意力。
    final bool hasResult = superResolutionPhaseHasEnhancedResult(status.phase);
    final bool busy = superResolutionPhaseIsBusy(status.phase);
    final Color fgColor = switch (status.phase) {
      SuperResolutionPagePhase.failed => colorScheme.error,
      _ when hasResult => colorScheme.primary,
      _ when busy => colorScheme.primary,
      _ => colorScheme.onSurfaceVariant,
    };
    final Color bgColor = switch (status.phase) {
      SuperResolutionPagePhase.failed => colorScheme.error.withValues(
        alpha: 0.12,
      ),
      _ when hasResult || busy => colorScheme.primary.withValues(alpha: 0.16),
      _ => colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
    };
    final Color borderColor = fgColor.withValues(alpha: hasResult ? 0.5 : 0.3);

    return Tooltip(
      message: superResolutionTooltip(status),
      child: Container(
        padding: const EdgeInsets.only(left: 8, right: 2),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 主体：状态 + 分辨率。点它只做一件事 —— 对比原图（开着时）。
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _onBodyTap(context, presenter, status, enabled),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 2,
                  vertical: 4.5,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildLeading(context, status.phase, fgColor),
                    const SizedBox(width: 4),
                    Text(
                      superResolutionPhaseLabel(status.phase),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: fgColor,
                      ),
                    ),
                    if (sizeText != null) ...[
                      const SizedBox(width: 5),
                      Text(
                        sizeText,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          // 分辨率是**事实**，用弱一档的颜色：状态字才是主角，
                          // 但两者都要在漫画上读得清。
                          color: fgColor.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 2),
            _UpscaleSwitch(
              value: enabled,
              onChanged: (value) =>
                  value ? _enable(context, presenter) : _disable(presenter),
            ),
          ],
        ),
      ),
    );
  }

  /// 图标：**忙的时候转圈**，好过换一个「转」的图标 —— 一眼就知道还在跑。
  Widget _buildLeading(
    BuildContext context,
    SuperResolutionPagePhase phase,
    Color color,
  ) {
    if (phase == SuperResolutionPagePhase.running) {
      return SizedBox(
        width: 13,
        height: 13,
        child: CircularProgressIndicator(
          strokeWidth: 1.6,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      );
    }
    final IconData icon = switch (phase) {
      SuperResolutionPagePhase.unsupported => Icons.block_rounded,
      SuperResolutionPagePhase.disabled => Icons.auto_awesome_outlined,
      SuperResolutionPagePhase.originalPreview => Icons.image_outlined,
      SuperResolutionPagePhase.queued => Icons.hourglass_empty_rounded,
      SuperResolutionPagePhase.running => Icons.auto_awesome,
      SuperResolutionPagePhase.ready => Icons.auto_awesome,
      SuperResolutionPagePhase.applied => Icons.auto_awesome,
      SuperResolutionPagePhase.skipped => Icons.check_circle_outline_rounded,
      SuperResolutionPagePhase.failed => Icons.error_outline_rounded,
      SuperResolutionPagePhase.idle => Icons.auto_awesome_outlined,
    };
    return Icon(icon, color: color, size: 14);
  }

  /// 点主体：开着就切「对比原图」，关着就当按下开关。
  Future<void> _onBodyTap(
    BuildContext context,
    GpuPresentController presenter,
    SuperResolutionPageStatus status,
    bool enabled,
  ) async {
    if (!enabled) {
      await _enable(context, presenter);
      return;
    }
    final bool willBeOriginal =
        status.phase != SuperResolutionPagePhase.originalPreview;
    await presenter.setOriginalPreview(willBeOriginal);
    showInfoToast(willBeOriginal ? '已切换为原图对比' : '已切回 AI 超分');
  }

  /// 打开超分。**模型没下载时不偷偷失败** —— 先问一句再下。
  Future<void> _enable(
    BuildContext context,
    GpuPresentController presenter,
  ) async {
    final bool available = await RealSrSuperResolution.isAvailable;
    if (!context.mounted) return;
    if (!available) {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('下载 AI 超分模型'),
          content: const Text(
            '当前设备尚未下载 mImage ONNX 超分模型（约 5.4 MB），是否立即下载并启用？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('立即下载'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      showInfoToast('正在后台下载超分模型...');
      try {
        await RealSrSuperResolution.downloadModel();
        if (!context.mounted) return;
        await presenter.setUpscaleEnabled(true);
        showInfoToast('超分模型就绪，AI 超分已启用');
      } catch (e) {
        showInfoToast('下载模型失败: $e');
      }
      return;
    }
    await presenter.setUpscaleEnabled(true);
    showInfoToast('AI 超分已启用');
  }

  Future<void> _disable(GpuPresentController presenter) async {
    await presenter.setUpscaleEnabled(false);
    showInfoToast('已关闭 AI 超分（当前页回到原图）');
  }
}

/// 顶栏里那个放得下的开关。
///
/// 单独包的唯一理由是**尺寸**：`Switch` 自带 48 逻辑像素的最小点击目标，
/// 直接放进 48 高的顶栏行里会把它撑爆（纵向溢出同样画黄黑斜纹）。
/// 用 [FittedBox] 按比例缩到 ~22 高，命中区域跟着一起缩 —— 顶栏本来就密，
/// 这里不能再要 48。
class _UpscaleSwitch extends StatelessWidget {
  const _UpscaleSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Switch(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
