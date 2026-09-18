import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_super_resolution.dart';
import 'package:zephyr/widgets/toast.dart';

/// AI 超分辨率胶囊按钮。
///
/// 具备原图与 AI 超分切换、对比预览、长按关闭、模型资源引导下载能力。
class ReaderUpscaleButton extends StatelessWidget {
  const ReaderUpscaleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final session = LocalReadSession.instance;
    final presenter = session.presenter;
    if (presenter == null) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        if (!presenter.canPresent) {
          return const SizedBox.shrink();
        }

        final isEnabled = presenter.isUpscaleEnabled;
        final isOrig = presenter.isOriginalPreview;
        final primaryColor = Theme.of(context).colorScheme.primary;

        String tooltip;
        String label;
        IconData icon;
        Color? fgColor;
        Color bgColor;
        Color borderColor;

        if (!isEnabled) {
          tooltip = '点击启用 AI 超分辨率 (实时画质增强)';
          label = '超分关';
          icon = Icons.auto_awesome_outlined;
          fgColor = Colors.grey;
          bgColor = Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
          borderColor = Colors.grey.withValues(alpha: 0.3);
        } else if (isOrig) {
          tooltip = '当前显示原图 (点击切回 AI 超分，长按关闭超分)';
          label = '原图';
          icon = Icons.image_outlined;
          fgColor = Colors.amber.shade700;
          bgColor = Colors.amber.withValues(alpha: 0.15);
          borderColor = Colors.amber.withValues(alpha: 0.5);
        } else {
          tooltip = 'AI 超分已启用 (点击对比原图，长按关闭超分)';
          label = '超分';
          icon = Icons.auto_awesome;
          fgColor = primaryColor;
          bgColor = primaryColor.withValues(alpha: 0.18);
          borderColor = primaryColor.withValues(alpha: 0.6);
        }

        return Tooltip(
          message: tooltip,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onLongPress: () {
              if (isEnabled) {
                presenter.setUpscaleEnabled(false);
                showInfoToast('已关闭 AI 超分');
              }
            },
            onTap: () async {
              if (!isEnabled) {
                final available = await RealSrSuperResolution.isAvailable;
                if (!context.mounted) return;
                if (!available) {
                  final confirm = await showDialog<bool>(
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
                  if (confirm == true) {
                    showInfoToast('正在后台下载超分模型...');
                    try {
                      await RealSrSuperResolution.downloadModel();
                      if (context.mounted) {
                        presenter.setUpscaleEnabled(true);
                        showInfoToast('超分模型就绪，AI 超分已启用');
                      }
                    } catch (e) {
                      showInfoToast('下载模型失败: $e');
                    }
                  }
                  return;
                }
                await presenter.setUpscaleEnabled(true);
                showInfoToast('AI 超分已启用');
              } else {
                final willBeOrig = !isOrig;
                await presenter.setOriginalPreview(willBeOrig);
                showInfoToast(willBeOrig ? '已切换为原图对比' : '已切回 AI 超分');
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: fgColor, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: fgColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
