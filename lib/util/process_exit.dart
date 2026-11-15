import 'dart:ffi';
import 'dart:io';

/// 立刻终止当前进程，跳过 Dart VM 与 Flutter 引擎的清理流程。
///
/// 桌面端退出时 `objectbox.close()` 之后仍有肉眼可见的 VM 回收延迟，
/// 因此退出路径统一走这里：调用方应先隐藏窗口，让用户感知不到这段延迟。
///
/// 注意：这是不可恢复的强杀，不会 flush 任何未落盘的数据。
void nuclearKillProcess() {
  if (Platform.isWindows) {
    // TerminateProcess(GetCurrentProcess(), 0)
    final kernel32 = DynamicLibrary.open('kernel32.dll');

    // 获取当前进程伪句柄 (-1)
    final getCurrentProcess = kernel32
        .lookup<NativeFunction<IntPtr Function()>>('GetCurrentProcess')
        .asFunction<int Function()>();

    final terminateProcess = kernel32
        .lookup<NativeFunction<Int32 Function(IntPtr, Uint32)>>(
          'TerminateProcess',
        )
        .asFunction<int Function(int, int)>();

    terminateProcess(getCurrentProcess(), 0);
  } else if (Platform.isMacOS || Platform.isLinux) {
    // kill(getpid(), 9)
    final dylib = Platform.isMacOS
        ? DynamicLibrary.process()
        : DynamicLibrary.open('libc.so.6');

    final getpid = dylib
        .lookup<NativeFunction<Int32 Function()>>('getpid')
        .asFunction<int Function()>();

    final kill = dylib
        .lookup<NativeFunction<Int32 Function(Int32, Int32)>>('kill')
        .asFunction<int Function(int, int)>();

    kill(getpid(), 9); // 9 就是 SIGKILL
  }

  // 兜底：上面的强杀理论上不会返回。
  exit(0);
}
