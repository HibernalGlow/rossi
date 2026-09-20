import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart';
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
/// # 为什么窄屏不写文字
///
/// 顶栏其他控件的固定宽度之和已经占掉六百多逻辑像素，再硬塞十多字的分辨率，
/// `Row` 就会溢出（黄黑斜纹）。所以**状态字**在
/// [superResolutionLabelMinWidth] 以上才写、分辨率文字在
/// [superResolutionSizeMinWidth] 以上才写，**窄屏仍然能在 tooltip 里看到两者**。
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final SuperResolutionPageStatus status = presenter.currentPageUpscaleStatus;
    final bool enabled = presenter.isUpscaleEnabled;
    final String? sizeText = superResolutionSizeText(status, availableWidth);
    final bool showLabel = superResolutionShowsLabel(availableWidth);

    // 三档容器角色，宁可少也不要花：**失败**必须一眼看出来（errorContainer），
    // **有超分产物 / 正在跑**才配强调（secondaryContainer），其余一律中性实色。
    // 这里一个 `withValues` 都没有 —— MD3 的 container 角色本就是拿来直接用的。
    final bool hasResult = superResolutionPhaseHasEnhancedResult(status.phase);
    final bool busy = superResolutionPhaseIsBusy(status.phase);
    final (Color bg, Color fg) = switch (status.phase) {
      SuperResolutionPagePhase.failed => (
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
      _ when hasResult || busy => (
        colorScheme.secondaryContainer,
        colorScheme.onSecondaryContainer,
      ),
      _ => (colorScheme.surfaceContainerHigh, colorScheme.onSurfaceVariant),
    };

    return Tooltip(
      message: superResolutionTooltip(status),
      child: Container(
        height: ReaderToolbarMetrics.chipHeight,
        padding: const EdgeInsets.only(left: 10, right: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(ReaderToolbarMetrics.fullRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 主体：状态 + 分辨率。点它只做一件事 —— 对比原图（开着时）。
            InkWell(
              borderRadius: BorderRadius.circular(
                ReaderToolbarMetrics.fullRadius,
              ),
              onTap: () => _onBodyTap(context, presenter, status, enabled),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildLeading(context, status.phase, fg),
                    if (showLabel) ...[
                      const SizedBox(width: 4),
                      Text(
                        superResolutionPhaseLabel(status.phase),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (sizeText != null) ...[
                      const SizedBox(width: 5),
                      // 分辨率是**事实**，弱一档：状态字才是主角。
                      Text(
                        sizeText,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: fg.withValues(alpha: 0.85),
                          fontFeatures: const [FontFeature.tabularFigures()],
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
        width: ReaderToolbarMetrics.chipIconSize,
        height: ReaderToolbarMetrics.chipIconSize,
        child: CircularProgressIndicator(
          strokeWidth: 1.8,
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
          content: const Text('当前设备尚未下载 mImage ONNX 超分模型（约 5.4 MB），是否立即下载并启用？'),
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
