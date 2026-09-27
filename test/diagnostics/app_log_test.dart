/// [AppLog] 的机制：落盘内容、环形上限丢哪头、写不下去时不许把正事带崩。
///
/// 超分与漫画翻译现在共用这一份实现（之前是两份一模一样的），所以这里钉的是
/// **共用**的那部分；各自「写到哪个目录」由自己的测试钉（见 `test/ocr/ocr_log_test.dart`）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/service/diagnostics/app_log.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rossi_app_log_');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  AppLog make({List<String> Function()? header, String name = '样例'}) => AppLog(
    name: name,
    filePath: () => '${root.path}/sample.log',
    header: header,
  );

  test('落盘的是整份快照：标题、系统行、页脚、正文与 error', () async {
    final log = make(header: () => ['最近生成图片：/tmp/x.png']);
    log.add('第一条');
    log.add('第二条', error: StateError('炸了'));
    await log.flush();

    final written = await File('${root.path}/sample.log').readAsString();
    expect(written.split('\n').first, '样例日志（本次运行）');
    expect(written, contains('系统：'), reason: '日志要给人看，机器与系统版本得在');
    expect(written, contains('最近生成图片：/tmp/x.png'));
    expect(written, contains('第一条'));
    expect(
      written,
      contains('炸了'),
      reason: 'error 跟在条目里，整份复制走才有上下文；只留一句「失败了」等于没记',
    );
  });

  test('超过上限丢最旧的，留最新的', () async {
    final log = make();
    for (var i = 0; i < AppLog.keep + 5; i++) {
      log.add('第 $i 条');
    }
    expect(log.entries.value, hasLength(AppLog.keep));
    expect(
      log.entries.value.first,
      contains('第 5 条'),
      reason: '丢的必须是最前面那 5 条 —— 反过来就是「刚发生的查不到」',
    );
    expect(log.entries.value.last, contains('第 ${AppLog.keep + 4} 条'));
  });

  test('写不下去也不该把被记录的那件事弄失败', () async {
    // 路径的父目录是一个普通文件 → `create(recursive: true)` 必然失败。
    await File('${root.path}/afile').writeAsString('我不是目录');
    final log = AppLog(
      name: '样例',
      filePath: () => '${root.path}/afile/sample.log',
    );
    expect(() => log.add('还在跑'), returnsNormally);
    await log.flush();
    expect(
      log.entries.value,
      hasLength(1),
      reason: '磁盘写失败只该吞掉那一次写，条目本身还得在界面上',
    );
  });
}
