import 'dart:ui';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comments/widgets/title.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_super_resolution.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/widgets/toast.dart';

class ComicReadAppBar extends StatelessWidget {
  final String title;
  final ValueChanged<int> changePageIndex;
  final bool isDesktopFullscreen;
  final VoidCallback? onToggleFullscreen;

  const ComicReadAppBar({
    super.key,
    required this.title,
    required this.changePageIndex,
    this.isDesktopFullscreen = false,
    this.onToggleFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    final isMenuVisible = context.select(
      (ReaderCubit cubit) => cubit.state.isMenuVisible,
    );
    final colorScheme = context.theme.colorScheme;
    const appBarRadius = 14.0;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !isMenuVisible,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          offset: isMenuVisible ? Offset.zero : const Offset(0, -1),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(appBarRadius),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
              child: AppBar(
                title: ScrollableTitle(text: title),
                titleSpacing: 6,
                actions: [
                  _buildUpscaleButton(context),
                  if (onToggleFullscreen != null)
                    IconButton(
                      tooltip: isDesktopFullscreen
                          ? t.reader.exitFullscreen
                          : t.reader.enterFullscreen,
                      onPressed: onToggleFullscreen,
                      icon: Icon(
                        isDesktopFullscreen
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                      ),
                    ),
                ],
                backgroundColor: colorScheme.surface.withValues(alpha: 0.78),
                surfaceTintColor: Colors.transparent,
                elevation: isMenuVisible ? 4.0 : 0.0,
                shadowColor: Colors.black.withValues(alpha: 0.2),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(appBarRadius),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUpscaleButton(BuildContext context) {
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
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                backgroundColor: bgColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: borderColor),
                ),
              ),
              onPressed: () async {
                if (!isEnabled) {
                  // 检查模型是否就绪
                  final available = await RealSrSuperResolution.isAvailable;
                  if (!context.mounted) return;
                  if (!available) {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('下载 AI 超分模型'),
                        content: const Text(
                          '当前设备尚未下载超分模型资源（约 3.3 MB），是否立即下载并启用？',
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
              icon: Icon(icon, color: fgColor, size: 16),
              label: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: fgColor,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
