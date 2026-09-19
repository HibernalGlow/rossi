import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 独立于控制台的超分诊断。保留本次运行最近 300 条，并异步落盘。
abstract final class SuperResolutionLog {
  static final entries = ValueNotifier<List<String>>([]);

  /// 最近一次**真的落在盘上**的超分产物路径。
  ///
  /// 日志页脚与「打开图片文件夹」都只读这一个值，所以它必须由**每一条产出超分图的
  /// 链路**在文件定稿之后更新。漏掉任何一条，按钮就会指向另一条链路的旧落点 ——
  /// 表现出来就是「打开的文件夹和我刚超分的那张图对不上」。产出超分图的链路有两条：
  ///
  /// - **阅读器呈现链路**：产物在 `rossi_sr_cache/sr_*.png`（登记入口 [outputReady]）；
  /// - **图缓存就地替换链路**：产物就是**被替换后的原图文件本身**（登记入口
  ///   [markOutput]）。这条链路会持续写日志，却从不产出 `rossi_sr_cache` 里的文件，
  ///   所以它必须自己登记，否则按钮永远停在呈现器链路的目录里。
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

  /// 登记「超分产物已经定稿在 [path] 上」。
  ///
  /// 与 [outputReady] 的分工：那条是**阅读器呈现链路**的专用入口（顺带把「第 N 页」
  /// 的结论写进日志）；这条是通用的落点登记，服务那些**没有页号、也不需要呈现器
  /// 确认**的产出路径 —— 典型的是「就地替换图缓存」：超分结果写回原图文件本身，
  /// 所以落点就是那个原图路径，[note] 用来在日志里把「位置变了」这件事说清楚。
  ///
  /// 只该在文件**定稿之后**调（转换/改名都做完）：先登记再改名，等于记了一个
  /// 马上不存在的路径。
  static void markOutput(String path, {String? note}) {
    latestOutputPath = path;
    if (note != null) add(note);
  }

  /// 打开**最近产物**的所在位置；没有产物时打开超分缓存目录。
  ///
  /// 返回一句说清楚「打开了什么」的话：产物不存在时静默改开缓存目录，会让人以为
  /// 超分图就在那儿 —— 那又是另一种「打开的文件夹和图对不上」。
  static Future<String> openOutputFolder() async {
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
    // 不写成「已在文件管理器中定位」：Linux 只能开目录，没有「选中这个文件」这回事。
    return exists ? '已打开最近产物的所在位置：$output' : '尚无超分产物，已打开超分缓存目录：$directory';
  }
}
