import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 一个子系统一份的**诊断日志**：内存环形 + 异步落盘 + 给界面的 `ValueListenable`。
///
/// 与 `logger`（package:logger，控制台那份、Sentry 也从它走）的分工：
/// [AppLog] 是**给用户的** —— 界面上能直接翻、落盘能事后回看，所以它得自己管长度与文件。
///
/// 为什么要收成一个：超分与 OCR 之前各写了一份**一模一样**的机制
/// （环形 300 条 + 每次写整份快照 + `ValueNotifier` + 查看/复制/打开三个按钮），
/// 第二份刚要写出来的时候被叫停。现在两边只留自己的三件事：
/// **叫什么、写到哪、页脚补哪一行**，机制在这里。
class AppLog {
  AppLog({
    required this.name,
    required this.filePath,
    this.header,
    String? title,
  }) : title = title ?? '$name日志（本次运行）';

  /// 子系统名（出现在默认标题里）。
  final String name;

  /// 日志正文的第一行。
  final String title;

  /// 这份日志写到哪个文件（父目录由写的那一方建）。
  final FutureOr<String> Function() filePath;

  /// 标题与系统信息之下、正文之上的那几行（超分用它显示「最近生成图片」）。
  final List<String> Function()? header;

  /// 内存里保留的条数。超出的从最旧那头丢 —— 产物是可重生成的，日志不是。
  static const int keep = 300;

  /// 给界面滚的那一份（`ValueListenableBuilder` 直接吃它）。
  final ValueNotifier<List<String>> entries = ValueNotifier<List<String>>(
    const [],
  );

  Future<void> _writeQueue = Future<void>.value();

  /// 等已经记录的日志真的落盘（复制前、搬缓存前都要先 flush）。
  Future<void> flush() => _writeQueue;

  /// 完整的可复制文本：标题 + 系统信息 + 这一路自己的页脚 + 正文。
  String get text => [
    title,
    '系统：${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    ...?header?.call(),
    '',
    ...entries.value,
  ].join('\n');

  static void _append(ValueNotifier<List<String>> box, String entry) {
    final next = [...box.value, entry];
    box.value = List.unmodifiable(
      next.length > keep ? next.sublist(next.length - keep) : next,
    );
  }

  /// 记一条。`error` / `stackTrace` 会跟在正文后面同一条里，方便整条复制走。
  void add(String message, {Object? error, StackTrace? stackTrace}) {
    _append(
      entries,
      '[${DateTime.now().toIso8601String()}] $message'
      '${error == null ? '' : '\n$error'}'
      '${stackTrace == null ? '' : '\n$stackTrace'}',
    );
    _scheduleWrite();
  }

  void _scheduleWrite() {
    final snapshot = text;
    _writeQueue = _writeQueue
        .then((_) async {
          final path = await filePath();
          final file = File(path);
          await file.parent.create(recursive: true);
          await file.writeAsString(snapshot);
        })
        // 日志写不下去不该把被记录的那件事弄失败（磁盘满、目录被外部删掉）。
        .catchError((Object _) {});
  }

  /// 在文件管理器里定位这份日志。
  ///
  /// 返回一句说清「打开了什么」：文件还没落盘时打开的是它所在的目录，
  /// 这时候含糊地说「已定位到日志」就是在骗人。
  Future<String> revealFile() async {
    final path = await filePath();
    final exists = await File(path).exists();
    final directory = p.dirname(path);
    final ProcessResult result;
    if (Platform.isMacOS) {
      result = await Process.run('open', exists ? ['-R', path] : [directory]);
    } else if (Platform.isWindows) {
      result = await Process.run(
        'explorer.exe',
        exists ? ['/select,', path] : [directory],
      );
    } else if (Platform.isLinux) {
      result = await Process.run('xdg-open', [directory]);
    } else {
      throw UnsupportedError('当前平台无法打开文件夹：$directory');
    }
    if (result.exitCode != 0) throw StateError('打开文件夹失败：${result.stderr}');
    return exists ? '已定位到日志文件：$path' : '日志还没落盘，已打开它所在的目录：$directory';
  }
}
