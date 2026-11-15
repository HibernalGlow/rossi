import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:window_manager/window_manager.dart';

/// 应用主窗口句柄的缓存。
///
/// window_manager 0.7 起窗口操作都挂在 [Window] 实例上，而
/// `WindowManager.instance.getCurrent()` 每次调用都会新建一个句柄对象，
/// 因此这里只查询一次并复用，避免频繁 FFI 调用与句柄对象堆积。
Window? _mainWindow;

/// Windows runner 的窗口类名与固定标题（见 `windows/runner/win32_window.cpp`
/// 与 `windows/runner/main.cpp`）。
const String _kWindowsRunnerWindowClass = 'FLUTTER_RUNNER_WIN32_WINDOW';
const String _kWindowsRunnerWindowTitle = 'zephyr';

/// 当前应用主窗口；窗口尚未创建时返回 null。
///
/// Windows 上不能用 `WindowManager.getCurrent()` / `getAll()` 作为主路径：
/// - `getCurrent()` 是 `GetActiveWindow()`，窗口隐藏/不在前台时返回 null；
/// - `getAll()` 枚举的是全系统可见窗口，不是本进程窗口，可能拿到 Brave。
///
/// 这里直接用 `FindWindowW` 按 runner 的类名 + 标题找 HWND，隐藏窗口也能找到，
/// 再交给 nativeapi 包装成 [Window]。
Window? get mainWindow {
  final cached = _mainWindow;
  if (cached != null) return cached;

  if (Platform.isWindows) {
    final native = _findWindowsRunnerWindow();
    if (native != null) return _mainWindow = native;
    final current = WindowManager.instance.getCurrent();
    if (current != null && current.title == _kWindowsRunnerWindowTitle) {
      return _mainWindow = current;
    }
    return null;
  }

  final current = WindowManager.instance.getCurrent();
  if (current != null) return _mainWindow = current;

  final windows = WindowManager.instance.getAll();
  if (windows.isEmpty) return null;
  return _mainWindow = windows.first;
}

Window? _findWindowsRunnerWindow() {
  try {
    final user32 = DynamicLibrary.open('user32.dll');
    final findWindow = user32
        .lookupFunction<
          IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
          int Function(Pointer<Utf16>, Pointer<Utf16>)
        >('FindWindowW');

    final className = _kWindowsRunnerWindowClass.toNativeUtf16();
    final windowName = _kWindowsRunnerWindowTitle.toNativeUtf16();
    try {
      final hwnd = findWindow(className, windowName);
      if (hwnd == 0) return null;
      return Window.createWithNativeWindow(Pointer<Void>.fromAddress(hwnd));
    } finally {
      calloc.free(className);
      calloc.free(windowName);
    }
  } catch (_) {
    return null;
  }
}
