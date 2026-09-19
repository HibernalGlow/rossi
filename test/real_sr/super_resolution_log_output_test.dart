import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/setting/real_sr/service/super_resolution_log.dart';

/// 「最近产物落点」的登记规则。
///
/// 日志页脚和「打开图片文件夹」都只读 [SuperResolutionLog.latestOutputPath]，
/// 所以它必须被**每一条产出超分图的链路**更新：
///
/// - 阅读器呈现链路 → [SuperResolutionLog.outputReady]（产物在 `rossi_sr_cache/sr_*.png`）；
/// - 图缓存就地替换链路 → [SuperResolutionLog.markOutput]（产物就是被替换后的原图文件）。
///
/// 少了后者，按钮就会一直指向 `rossi_sr_cache`，而日志里说的图在图缓存/下载目录里 ——
/// 也就是「打开文件夹后的位置和超分图真正对应的位置不一样」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rossi_sr_log_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
  });

  tearDown(() async {
    await SuperResolutionLog.flush();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    SuperResolutionLog.entries.value = [];
    SuperResolutionLog.latestOutputPath = null;
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('就地替换图缓存：落点改成原图路径，日志页脚跟着改口', () async {
    const replaced =
        '/Users/x/Library/Caches/com.zephyr.breeze/f_1/f_2/f_3/f_4';

    SuperResolutionLog.markOutput(
      replaced,
      note: '已就地替换原图（超分结果写回缓存文件）：$replaced',
    );

    expect(SuperResolutionLog.latestOutputPath, replaced);
    expect(SuperResolutionLog.text, contains('最近生成图片：$replaced'));
    expect(SuperResolutionLog.entries.value.last, contains('已就地替换原图'));
  });

  test('markOutput 不带说明时只改落点，不写日志行', () {
    SuperResolutionLog.markOutput('/caches/f_1/f_2/f_3');

    expect(SuperResolutionLog.latestOutputPath, '/caches/f_1/f_2/f_3');
    expect(SuperResolutionLog.entries.value, isEmpty);
  });

  test('呈现器链路：引擎产物先登记，定稿的 sr_*.png 覆盖它', () {
    // `upscale` 这个收口先登记引擎写出的中间文件（马上会被改名）。
    SuperResolutionLog.markOutput('/sr_cache/pending_a1b2.png');
    expect(SuperResolutionLog.latestOutputPath, '/sr_cache/pending_a1b2.png');

    // 改名定稿后由呈现器链路改口 —— 落点必须是**最终**文件。
    SuperResolutionLog.outputReady(
      '/sr_cache/sr_1_coreml.png',
      page: 0,
      model: 'coreml',
    );

    expect(SuperResolutionLog.latestOutputPath, '/sr_cache/sr_1_coreml.png');
    expect(
      SuperResolutionLog.text,
      contains('最近生成图片：/sr_cache/sr_1_coreml.png'),
    );
  });

  test('日志落盘目录就是超分缓存目录（同一处，别成了两个）', () async {
    final directory = await SuperResolutionLog.cacheDirectory();

    expect(directory.path, endsWith('rossi_sr_cache'));
    expect(await directory.exists(), isTrue);

    SuperResolutionLog.add('随便一条');
    await SuperResolutionLog.flush();
    expect(
      await File('${directory.path}/super_resolution.log').exists(),
      isTrue,
    );
  });
}
