part of '../main.dart';
// 启动兜底 UI 与启动日志：启动失败时落盘原因并显示可读错误页，而不是黑屏

/// 启动失败时把原因落盘。
///
/// 这不是调试残留，是这条路径**唯一**的可观测手段：这个进程属于 GUI 子系统，
/// `print` / `logger` / 未配置 DSN 的 Sentry 都不会把任何东西送到人能看见的地方。
/// 而启动期抛异常的直接后果是**根本不会调用 `runApp`** —— 窗口永远停在一片黑，
/// 看起来像渲染坏了，其实是启动就死在了初始化里。
///
/// 这个坑已经咬过两次，两次都是同一个原因（见下）：仓库里 `rust/target/release/
/// libwindcore.dylib` 与 `frb_generated` 的 content hash 对不上，`RustLib.init()`
/// 抛 `Content hash on Dart side (…) is different from Rust side (…)`
/// —— 从仓库根目录启动时，FRB 的 `ioDirectory: 'rust/target/release/'`
/// 是按**当前工作目录**解析的，于是加载的是仓库里那份旧库、而不是 App 包里那份新的。
/// 修法是 `cd rust && cargo build -p windcore --release` 重新生成它。
/// 但真正要修的是「黑屏且零线索」这件事本身。
Future<void> _writeBootLog(
  String stage, [
  Object? error,
  StackTrace? stack,
]) async {
  try {
    final String text = error == null
        ? '${DateTime.now().toIso8601String()} [$stage]\n'
        : '${DateTime.now().toIso8601String()} [$stage] $error\n$stack\n\n';
    await File(
      '/tmp/breeze_boot.log',
    ).writeAsString(text, mode: FileMode.append, flush: true);
  } catch (_) {
    // 连日志都写不出去时不再往上抛。
  }
}

/// 启动失败时的**可见**界面。
///
/// 原来这里是「吞掉异常 + 直接 return」，而 `return` 意味着永远不会调用 `runApp`：
/// 用户看到的是一片永远不动的黑，且没有控制台、没有 Sentry、没有日志 ——
/// 一个本来一行命令就能修的问题，被表现成「渲染坏了」。
/// 宁可显示一个丑但能读的错误页，也不要一片黑。
void _runBootFailureApp(String stage, Object error, StackTrace stack) {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF101014),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.error_outline,
                    color: Color(0xFFFF6B6B),
                    size: 44,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '应用启动失败',
                    style: TextStyle(
                      color: Color(0xFFE6EDF3),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    '阶段: $stage',
                    style: const TextStyle(
                      color: Color(0xFF8B949E),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SelectableText(
                    '$error',
                    style: const TextStyle(
                      color: Color(0xFFFF9C6B),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SelectableText(
                    '$stack',
                    style: const TextStyle(
                      color: Color(0xFF6E7681),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
