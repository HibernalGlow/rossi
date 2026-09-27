import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/service/diagnostics/app_log.dart';
import 'package:zephyr/util/get_path.dart';

/// 超分诊断日志的**门面**：环形、落盘、复制、定位文件这些机制都在 [AppLog]，
/// 与漫画翻译共用同一份；这里只留超分特有的三件事与产物缓存的收封顶。
abstract final class SuperResolutionLog {
  /// 机制在 [AppLog]（与漫画翻译共用同一份实现），这里只留超分自己的
  /// 「写到哪、标题叫什么、页脚补哪一行」。日志文件的位置**没有变**，
  /// 还在超分缓存目录里，`trimCache` 只收 `.png` 产物、不动它。
  static final AppLog log = AppLog(
    name: '超分',
    title: 'Rossi 超分日志（本次运行）',
    filePath: () async =>
        p.join((await cacheDirectory()).path, 'super_resolution.log'),
    header: () => ['最近生成图片：${latestOutputPath ?? "尚未生成"}'],
  );

  static ValueNotifier<List<String>> get entries => log.entries;

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

  /// 等待已经记录的日志落盘，再复制缓存或清理临时目录。
  static Future<void> flush() => log.flush();

  /// 超分产物与本次运行日志的落点：`getFilePath()/super_resolution/rossi_sr_cache`。
  ///
  /// 以前在 `$TMPDIR` 下，好处是 macOS 每天清临时目录时顺手替我们收了尾，代价是
  /// **跨启动不复用** —— 上一轮看过的页每次都要重新推理一遍。搬到持久目录后由
  /// [trimCache] 自己封顶（启动期调，见 `main.dart`）。
  static Future<Directory> cacheDirectory() async {
    final directory = _under(await getFilePath());
    await directory.create(recursive: true);
    return directory;
  }

  static Directory _under(String filesRoot) =>
      Directory(p.join(filesRoot, 'super_resolution', 'rossi_sr_cache'));

  /// 缓存里允许留下的产物总字节数。
  static const int cacheBudget = 2 * 1024 * 1024 * 1024;

  /// 产物是可重生成的，所以超预算时按修改时间从最旧的开始删；日志不参与。
  static Future<void> trimCache() async {
    final root = _under(await getFilePath());
    if (!await root.exists()) return;
    final products = <(File, int, DateTime)>[];
    for (final file in root.listSync().whereType<File>()) {
      if (!file.path.endsWith('.png')) continue;
      products.add((file, file.lengthSync(), file.statSync().modified));
    }
    var total = products.fold<int>(0, (sum, e) => sum + e.$2);
    if (total <= cacheBudget) return;
    products.sort((a, b) => a.$3.compareTo(b.$3));
    for (final (file, size, _) in products) {
      if (total <= cacheBudget) return;
      try {
        await file.delete();
        total -= size;
      } on FileSystemException {
        continue;
      }
    }
  }

  static String get text => log.text;

  static void add(String message, {Object? error, StackTrace? stackTrace}) =>
      log.add(message, error: error, stackTrace: stackTrace);

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
