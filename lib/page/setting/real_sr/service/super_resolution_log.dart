import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 独立于控制台的超分诊断。保留本次运行最近 300 条，并异步落盘。
abstract final class SuperResolutionLog {
  static final entries = ValueNotifier<List<String>>([]);
  static String? latestOutputPath;
  static Future<void> _writeQueue = Future<void>.value();

  /// 等待已经记录的日志落盘，再复制缓存或清理临时目录。
  static Future<void> flush() => _writeQueue;

  static Future<Directory> cacheDirectory() async {
    final directory = Directory(
      p.join((await getTemporaryDirectory()).path, 'rossi_sr_cache'),
    );
    await directory.create(recursive: true);
    return directory;
  }

  static String get text => [
    'Breeze 超分日志（本次运行）',
    '系统：${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    '最近生成图片：${latestOutputPath ?? "尚未生成"}',
    '',
    ...entries.value,
  ].join('\n');

  static void add(String message, {Object? error, StackTrace? stackTrace}) {
    final entry =
        '[${DateTime.now().toIso8601String()}] $message'
        '${error == null ? "" : "\n$error"}'
        '${stackTrace == null ? "" : "\n$stackTrace"}';
    final next = [...entries.value, entry];
    entries.value = List.unmodifiable(
      next.length > 300 ? next.sublist(next.length - 300) : next,
    );
    final snapshot = text;
    _writeQueue = _writeQueue
        .then((_) async {
          final root = await cacheDirectory();
          await File(
            p.join(root.path, 'super_resolution.log'),
          ).writeAsString(snapshot);
        })
        .catchError((Object _) {});
  }

  static void outputReady(
    String path, {
    required int page,
    required String model,
    bool prefetched = false,
  }) {
    latestOutputPath = path;
    add(
      '第 ${page + 1} 页：${prefetched ? '预超分完成，翻到此页时直接复用' : '超分文件已就绪，等待呈现器确认替换'}；模型=$model\n输出=$path',
    );
  }

  static Future<void> openOutputFolder() async {
    final output = latestOutputPath;
    final exists = output != null && await File(output).exists();
    final directory = exists
        ? p.dirname(output)
        : (await cacheDirectory()).path;
    final ProcessResult result;
    if (Platform.isMacOS) {
      result = await Process.run('open', exists ? ['-R', output] : [directory]);
    } else if (Platform.isWindows) {
      result = await Process.run(
        'explorer.exe',
        exists ? ['/select,', output] : [directory],
      );
    } else if (Platform.isLinux) {
      result = await Process.run('xdg-open', [directory]);
    } else {
      throw UnsupportedError('当前平台无法打开文件夹：$directory');
    }
    if (result.exitCode != 0) throw StateError('打开文件夹失败：${result.stderr}');
  }
}
