import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/service/app_identity/desktop_preferences.dart';

/// 旧版 macOS 偏好里真实的形态：Flutter 的 `flutter.*` 标量，混着 AppKit 自己
/// 写进去的 `<data>`（保存面板上次目录）。`plutil -convert json` 会因为这个
/// `<data>` 整个文件失败，所以解析必须按 XML 走、并且跳过它。
const _legacyPlist = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSNavPanelExpandedSizeForOpenMode</key>
	<string>{880, 448}</string>
	<key>NSOSPLastRootDirectory</key>
	<data>
	Ym9va8wDAAAAAAUQQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
	AAAAAAAAAAAAAAAAANACAAAEAAAAAwMAAAAAACAHAAAAAQEAAFZvbHVtZXMAAwAAAAEB
	</data>
	<key>flutter.desktop_window_maximized</key>
	<true/>
	<key>flutter.image_denoise_model_revision</key>
	<integer>1791967860513228</integer>
	<key>flutter.image_denoise_scale</key>
	<real>1.5</real>
	<key>flutter.ocr_api_key</key>
	<string>sk-&lt;redacted&gt; &amp; more</string>
	<key>flutter.reader_profiles</key>
	<dict>
		<key>flutter.inner</key>
		<string>不该被当成顶层偏好</string>
	</dict>
	<key>flutter.desktop_close_behavior</key>
	<string>exit</string>
	<key>flutter.rossi.search_history.v1.bookshelf.favorite</key>
	<array>
		<string>葬送的芙莉莲</string>
		<string>a &amp; b</string>
	</array>
	<key>NSWindow Frame main</key>
	<string>0 0 1200 800</string>
</dict>
</plist>
''';

void main() {
  test('XML plist：跳过原生 <data>，只取顶层标量', () {
    final data = parsePlistDictionary(_legacyPlist);

    expect(data['flutter.desktop_window_maximized'], isTrue);
    expect(data['flutter.image_denoise_model_revision'], 1791967860513228);
    expect(data['flutter.image_denoise_scale'], 1.5);
    expect(data['flutter.desktop_close_behavior'], 'exit');
    // XML 实体要还原，否则写回偏好的是 `sk-&lt;redacted&gt;`。
    expect(data['flutter.ocr_api_key'], 'sk-<redacted> & more');
    // 原生键不是不能读，只是不该 import（调用方按 `flutter.` 前缀过滤）；
    // 关键是它们不能把整个解析带崩。
    expect(data['NSNavPanelExpandedSizeForOpenMode'], '{880, 448}');
    // List<String> 的偏好是顶层 <array>，不能因为「只取标量」就丢掉。
    expect(data['flutter.rossi.search_history.v1.bookshelf.favorite'], [
      '葬送的芙莉莲',
      'a & b',
    ]);
    // 嵌套 dict 里的同名风格键不能漏到顶层。
    expect(data.containsKey('flutter.inner'), isFalse);
    // <data> 整项跳过，而不是解析成半截字符串。
    expect(data.containsKey('NSOSPLastRootDirectory'), isFalse);
    expect(data['flutter.reader_profiles'], isNull);
  });

  test('损坏的 XML 不抛，返回已读到的部分', () {
    expect(parsePlistDictionary(''), isEmpty);
    expect(parsePlistDictionary('<plist><dict><key>a</key>'), isEmpty);
  });

  test('JSON 偏好损坏时返回 null 而不是抛', () async {
    final temp = await Directory.systemTemp.createTemp('rossi-prefs-test-');
    addTearDown(() => temp.delete(recursive: true));
    final file = File(p.join(temp.path, 'shared_preferences.json'));
    await file.writeAsString('{"flutter.a": ');
    expect(await readJsonPreferences(file), isNull);
    // 原文件保留。
    expect(await file.exists(), isTrue);
  });

  test('二进制 plist（真实文件格式）也能读出来', () async {
    if (!Platform.isMacOS) {
      markTestSkipped('plutil 只在 macOS 上验证');
      return;
    }
    final temp = await Directory.systemTemp.createTemp('rossi-prefs-test-');
    addTearDown(() => temp.delete(recursive: true));
    final plist = File(p.join(temp.path, 'com.zephyr.breeze.plist'));
    await plist.writeAsString(_legacyPlist);
    final convert = await Process.run('/usr/bin/plutil', [
      '-convert',
      'binary1',
      plist.path,
    ]);
    expect(convert.exitCode, 0, reason: '${convert.stderr}');

    final data = await readMacPreferencesPlist(plist);
    expect(data, isNotNull);
    expect(data!['flutter.desktop_close_behavior'], 'exit');
    expect(data['flutter.image_denoise_model_revision'], 1791967860513228);
  });

  test('文件不存在时返回 null', () async {
    final temp = await Directory.systemTemp.createTemp('rossi-prefs-test-');
    addTearDown(() => temp.delete(recursive: true));
    expect(
      await readMacPreferencesPlist(File(p.join(temp.path, 'nope.plist'))),
      isNull,
    );
  });
}
