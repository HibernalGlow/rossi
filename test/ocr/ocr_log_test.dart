/// OCR 日志的**落点** —— 这件事最容易骗自己。
///
/// 落错地方的两种样子当场都看不出来：
/// - 落系统临时目录：这台机器的 dirhelper 每天 03:35 扫 tmp，第二天日志就没了一份
///   （超分已经为同款问题踩过「每次启动都要重下权重」）；
/// - 落成品页缓存目录：设置页「清空成品页缓存」会把 `manga_translated/` 整个删掉，
///   而那正是用户翻不出原因、最需要回头翻日志的时刻。
///
/// 所以钉的是：**与权重同目录** —— 权重目录既持久，也不归「清空缓存」管。
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/service/ocr/ocr_log.dart';
import 'package:zephyr/service/ocr/ocr_models.dart';

const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appRoot;

  setUp(() async {
    appRoot = await Directory.systemTemp.createTemp('rossi_ocr_log_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, (call) async => appRoot.path);
    OcrLog.log.entries.value = const [];
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    await appRoot.delete(recursive: true);
  });

  test('日志写在 manga_ocr/ocr.log，与权重同一个目录', () async {
    OcrLog.add('第 1 页 冒烟一条');
    await OcrLog.flush();

    final path = await OcrLog.log.filePath();
    final weights = await OcrModels.directory();
    expect(path, p.join(weights.path, 'ocr.log'));
    expect(
      File(path).existsSync(),
      isTrue,
      reason: '父目录不存在时得自己建出来 —— 否则第一次失败就永远没有日志',
    );
    expect(await File(path).readAsString(), contains('冒烟一条'));
    expect(
      path,
      isNot(contains('manga_translated')),
      reason: '不能落在成品页缓存里：「清空成品页缓存」会连日志一起删',
    );
  });

  test('日志里的页号是 1 基，与界面显示一致', () async {
    expect(
      OcrLog.page(0),
      '第 1 页',
      reason: '界面显示「第 5 页」而日志写「第 4 页」，对不上号的那一次一定被当成「没记这一页」',
    );
  });
}
