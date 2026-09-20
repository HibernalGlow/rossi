import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:zephyr/config/global/global.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/platform/desktop/native_window.dart';

bool _runningInSandbox() {
  return Platform.environment.containsKey('FLATPAK_ID') ||
      Platform.environment.containsKey('SNAP') ||
      (Platform.environment['container']?.isNotEmpty ?? false) ||
      File('/.dockerenv').existsSync();
}

Future<void> initSystemTray() async {
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

  try {
    final iconPath = Platform.isWindows
        ? 'asset/image/app_icon.ico'
        : (Platform.isLinux && _runningInSandbox())
        ? 'io.github.windy.breeze'
        : Platform.isMacOS
        ? 'asset/image/menu_bar_icon.png'
        : 'asset/image/app-icon.png';
    // macOS 菜单栏只接受单色 + 透明底的模板图，浅/深色外观与按下高亮由系统着色。
    await trayManager.setIcon(iconPath, isTemplate: Platform.isMacOS);

    final Menu menu = Menu(
      items: [
        MenuItem(key: 'show_window', label: t.settings.showMainWindow),
        MenuItem.separator(),
        MenuItem(key: 'exit_app', label: t.settings.exitApp),
      ],
    );
    await trayManager.setContextMenu(menu);

    try {
      await trayManager.setToolTip(appDisplayName);
    } catch (e) {
      logger.d('setToolTip is unsupported on this platform: $e');
    }
    logger.d('System tray initialized successfully');
  } catch (e, stack) {
    logger.e('Failed to init system tray: $e', error: e, stackTrace: stack);
  }
}

Future<void> showMainWindow() async {
  if (Platform.isWindows) {
    NativeWindow.show();
  } else {
    await windowManager.show();
    await windowManager.focus();
  }
}
