import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/toast.dart';

/// 自动滚屏快捷启停按钮 (带指示状态与长按关闭)。
class AutoScrollQuickButton extends StatelessWidget {
  final bool isEnabled;
  final bool isPaused;
  final ValueChanged<bool> onToggleAutoScroll;
  final VoidCallback? onTogglePause;

  const AutoScrollQuickButton({
    super.key,
    required this.isEnabled,
    required this.isPaused,
    required this.onToggleAutoScroll,
    this.onTogglePause,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = isEnabled && !isPaused;

    return Tooltip(
      message: !isEnabled
          ? '一键开启自动滚屏'
          : (isPaused ? '继续自动滚屏' : '暂停自动滚屏 (长按彻底关闭)'),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onLongPress: isEnabled
            ? () {
                onToggleAutoScroll(false);
                showInfoToast('已关闭自动滚屏');
              }
            : null,
        onTap: () {
          if (!isEnabled) {
            onToggleAutoScroll(true);
            showInfoToast('已开启自动滚屏');
          } else if (onTogglePause != null) {
            onTogglePause!();
          } else {
            onToggleAutoScroll(false);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            color: isActive
                ? colorScheme.tertiaryContainer.withValues(alpha: 0.8)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive
                  ? colorScheme.tertiary.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          child: Icon(
            isActive
                ? Icons.pause_circle_filled_rounded
                : (isEnabled
                      ? Icons.play_circle_filled_rounded
                      : Icons.play_circle_outline_rounded),
            size: 20,
            color: isActive
                ? colorScheme.onTertiaryContainer
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
