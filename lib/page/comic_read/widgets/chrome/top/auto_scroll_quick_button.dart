import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart';
import 'package:zephyr/widgets/toast.dart';

/// 自动滚屏快捷启停按钮 (带指示状态与长按关闭)。
///
/// 三态压在一颗芯片上（关 / 运行中 / 暂停），外形与主行其余开关同一份
/// （[ReaderToolbarToggleChip]）：运行中 = 亮 `secondaryContainer`，
/// 暂停与关都是不填的描边态 —— 差别靠图标与 tooltip 说清楚。
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
    final isActive = isEnabled && !isPaused;

    return ReaderToolbarToggleChip(
      icon: isActive
          ? Icons.pause_circle_filled_rounded
          : (isEnabled
                ? Icons.play_circle_filled_rounded
                : Icons.play_circle_outline_rounded),
      tooltip: !isEnabled
          ? '一键开启自动滚屏'
          : (isPaused ? '继续自动滚屏' : '暂停自动滚屏 (长按彻底关闭)'),
      selected: isActive,
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
      onLongPress: isEnabled
          ? () {
              onToggleAutoScroll(false);
              showInfoToast('已关闭自动滚屏');
            }
          : null,
    );
  }
}
