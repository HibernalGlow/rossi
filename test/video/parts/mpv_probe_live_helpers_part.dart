part of '../mpv_property_probe_test.dart';
// 活体



/// 找一个能 dlopen 的 libmpv，返回它的路径；找不到返回 null。
///
/// 显式把路径交给 `MediaKit.ensureInitialized(libmpv:)`，而不是靠
/// `LIBMPV_LIBRARY_PATH` 环境变量：那个变量在 `flutter test` 起的测试 VM 里读不到
/// （实测设置后 `Platform.environment` 为空），而 media_kit 在 macOS 上会把这个
/// 参数原样转发给 `NativeLibrary`，所以传参是这条路上唯一稳的口子。
String? _loadableLibmpv() {
  final env = Platform.environment['LIBMPV_LIBRARY_PATH'];
  final candidates = <String>[
    if (env != null && env.isNotEmpty) env,
    ...switch (Platform.operatingSystem) {
      'macos' => const [
        '/opt/homebrew/opt/mpv/lib/libmpv.2.dylib',
        '/opt/homebrew/lib/libmpv.2.dylib',
        '/usr/local/lib/libmpv.2.dylib',
      ],
      'linux' => const [
        '/usr/lib/x86_64-linux-gnu/libmpv.so.2',
        '/usr/lib/libmpv.so.2',
      ],
      'windows' => const ['libmpv-2.dll'],
      _ => const <String>[],
    },
  ];
  for (final path in candidates) {
    try {
      DynamicLibrary.open(path);
      return path;
    } catch (_) {
      // 换下一个候选：这里没有需要保留的失败信息，skip 时会把候选列表报出来。
    }
  }
  return null;
}


/// 轮询到某个异步值满足条件为止（默认 12 s）。
///
/// 这套探针原先靠 `delay(120ms/400ms)` 猜 mpv 什么时候把值落下去，在同一台机器上
/// 和别的 mpv 实例抢 CPU 时会随机输 —— 一条时好时坏的探针比没有探针更糟。
/// 现在一律「读到满意为止」，超时就把最后一次读到的值报出来。
Future<T> _until<T>(
  Future<T> Function() read,
  bool Function(T) ok, {
  required String what,
  Duration within = const Duration(seconds: 12),
}) async {
  final deadline = DateTime.now().add(within);
  while (true) {
    final value = await read();
    if (ok(value)) return value;
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('$what 在 ${within.inSeconds}s 内没到位（最后一次读到：$value）');
    }
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }
}


/// 打开并等到「有结论」为止。
///
/// 这里**只等一次结论，不自己重试**：卡住时原地重开是传输层的职责
/// （`MpvVideoTransport._awaitFirstFrame` 的 allowRetry —— 同进程已经起过别的
/// mpv 实例时，第一次 load 偶尔什么都不上报，实测 5 次撞 2 次，第二次立刻成功）。
/// 超时给到 50 s > 内层的两次 20 s：内层那道重试要是失效了，这条就该红。
Future<VideoEnginePhase> _openAndAwait(
  MpvVideoTransport transport,
  String uri, {
  VideoOpenOptions options = const VideoOpenOptions(autoplay: false),
}) async {
  final seen = transport.phaseStream.firstWhere(
    (p) => p == VideoEnginePhase.ready || p == VideoEnginePhase.failed,
  );
  await transport.open(uri, options: options);
  return seen.timeout(const Duration(seconds: 50));
}
