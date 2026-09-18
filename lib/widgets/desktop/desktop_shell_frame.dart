import 'package:material_ui/material_ui.dart';
import 'package:zephyr/service/reader/reader_desktop_fullscreen_service.dart';
import 'package:zephyr/widgets/desktop/custom_title_bar.dart';

/// 桌面外壳：自制标题栏 + 内容。
///
/// **窗口全屏时标题栏整条不建**（不是「透明 / 隐藏但仍占 40px」，是根本
/// 不占位）—— 全屏的意义就是把这一行还给内容。
///
/// 判据来自 `ReaderDesktopFullscreenService.fullscreenNotifier`，那个状态
/// 由**窗口自己的全屏事件**驱动（见该服务的文档），所以无论是按应用里的
/// 全屏按钮、⌃⌘F 还是视图菜单，这里都会让位；不再出现「窗口已经全屏、
/// 顶上还挂着一条写着应用名的标题栏」。
class DesktopShellFrame extends StatelessWidget {
  const DesktopShellFrame({super.key, required this.child});

  /// 标题栏下面的内容（导航栈）。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable:
          ReaderDesktopFullscreenService.instance.fullscreenNotifier,
      builder: (context, isFullscreen, _) {
        return Column(
          children: [
            if (!isFullscreen) const CustomTitleBar(),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}
