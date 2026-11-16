import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';
import 'package:zephyr/platform/desktop/desktop_window.dart';
import 'package:zephyr/config/global/global.dart';
import 'package:zephyr/icons/icons.dart';

/// Material 3 风格的自定义标题栏（仅桌面平台使用）
///
/// [transparent] 打开时**整条不带底色**（`Colors.transparent`），
/// 由 `DesktopShellFrame` 把它当浮层叠在内容之上 —— 这就是「透明标题栏」。
/// 前景色仍是主题的 `onSurface*`，所以浅色主题下浮在浅色画面上会不易看清，
/// 这一条代价写在设置项副标题里。
class CustomTitleBar extends StatefulWidget {
  const CustomTitleBar({super.key, this.transparent = false});

  /// 不画底色（浮在内容上的那一档）。
  final bool transparent;

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<CustomTitleBar> {
  bool _isMaximized = false;
  ListenerId? _windowListenerId;

  @override
  void initState() {
    super.initState();
    _windowListenerId = mainWindow?.addListener(_handleWindowEvent);
    _isMaximized = mainWindow?.isMaximized ?? false;
  }

  @override
  void dispose() {
    final listenerId = _windowListenerId;
    if (listenerId != null) {
      mainWindow?.removeListener(listenerId);
      _windowListenerId = null;
    }
    super.dispose();
  }

  void _handleWindowEvent(WindowEvent event) {
    switch (event) {
      // nativeapi 的「还原」同时覆盖取消最大化和从最小化恢复，
      // 因此统一回读窗口真实状态，而不是靠事件类型推断。
      case WindowMaximizedEvent():
      case WindowRestoredEvent():
        final maximized = mainWindow?.isMaximized ?? false;
        if (mounted && maximized != _isMaximized) {
          setState(() => _isMaximized = maximized);
        }
      case _:
        break;
    }
  }

  void _minimize() => mainWindow?.minimize();

  void _toggleMaximize() {
    final window = mainWindow;
    if (window == null) return;
    // 以窗口真实状态为准，避免本地 _isMaximized 与窗口脱节。
    if (window.isMaximized) {
      window.unmaximize();
    } else {
      window.maximize();
    }
  }

  void _handleClose() {
    // 必须走 window.close() 而不是直接发 WM_CLOSE：只有前者会先询问
    // 关闭监听（nativeapi 把裸 WM_CLOSE 当作不可取消的强制关闭）。
    mainWindow?.close();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMacOS = Platform.isMacOS; // 检测是否为 macOS

    return Container(
      height: 40,
      // 透明档 = 不画底色，内容从底下透出来。
      color: widget.transparent ? Colors.transparent : colorScheme.surface,
      child: Row(
        children: [
          // --- macOS 专属占位 ---
          if (isMacOS) const SizedBox(width: 80), // 为系统“红绿灯”按钮留出空间
          // 1. 左侧和中间区域：负责拖拽和双击
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => mainWindow?.startDragging(),
              onDoubleTap: _toggleMaximize,
              child: Row(
                children: [
                  // 仅在非 macOS 平台（如 Windows）显示图标和标题
                  if (!isMacOS) ...[
                    const SizedBox(width: 12),
                    Image.asset(
                      'asset/image/app_icon.ico',
                      width: 18,
                      height: 18,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      appDisplayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],

                  // 如果是 macOS，可以让标题居中（可选）
                  if (isMacOS) const Spacer(),
                  if (isMacOS)
                    Text(
                      appDisplayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                        fontSize: 13, // macOS 标题通常更小更精致
                      ),
                    ),
                  if (isMacOS) const Spacer(),
                ],
              ),
            ),
          ),

          // 2. 右侧按钮区域（仅在非 macOS 平台显示）
          // macOS 的控制按钮在左边，所以右边的自定义按钮应该隐藏
          if (!isMacOS) ...[
            _TitleBarButton(
              icon: AppGlyphs.windowMinimize,
              onPressed: _minimize,
              hoverColor: colorScheme.onSurface.withValues(alpha: 0.08),
              iconColor: colorScheme.onSurfaceVariant,
            ),
            _TitleBarButton(
              icon: _isMaximized
                  ? AppGlyphs.windowRestore
                  : AppGlyphs.windowMaximize,
              onPressed: _toggleMaximize,
              hoverColor: colorScheme.onSurface.withValues(alpha: 0.08),
              iconColor: colorScheme.onSurfaceVariant,
            ),
            _TitleBarButton(
              icon: AppGlyphs.close,
              onPressed: _handleClose,
              hoverColor: Colors.red,
              hoverIconColor: Colors.white,
              iconColor: colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }
}

/// 标题栏上的单个按钮
class _TitleBarButton extends StatefulWidget {
  final Glyph icon;
  final VoidCallback onPressed;
  final Color hoverColor;
  final Color iconColor;
  final Color? hoverIconColor;

  const _TitleBarButton({
    required this.icon,
    required this.onPressed,
    required this.hoverColor,
    required this.iconColor,
    this.hoverIconColor,
  });

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: 40,
          color: _isHovered ? widget.hoverColor : Colors.transparent,
          child: GlyphIcon(
            widget.icon,
            size: 18,
            color: _isHovered
                ? (widget.hoverIconColor ?? widget.iconColor)
                : widget.iconColor,
          ),
        ),
      ),
    );
  }
}
