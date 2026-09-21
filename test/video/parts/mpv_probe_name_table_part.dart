part of '../mpv_property_probe_test.dart';
// 探针①：出厂


/// 出厂引擎的二进制：只在构建过 macOS 产物时存在。
File? _bundledMpv() {
  const relative = 'Contents/Frameworks/Mpv.framework/Versions/A/Mpv';
  final products = Directory('build/macos/Build/Products');
  if (!products.existsSync()) return null;
  for (final config in products.listSync().whereType<Directory>()) {
    for (final app in config.listSync().whereType<Directory>()) {
      if (!app.path.endsWith('.app')) continue;
      final binary = File('${app.path}/$relative');
      if (binary.existsSync()) return binary;
    }
  }
  return null;
}


/// 把 Mach-O 里的 C 字符串取出来（按 NUL 切，长度 ≥2 的都算）。
/// 不用 `strings`：那是外部工具，测试要能在任何开发机上自己跑。
Set<String> _cStrings(File binary) {
  final bytes = binary.readAsBytesSync();
  final out = <String>{};
  var start = 0;
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] != 0) continue;
    if (i - start >= 2) {
      var ascii = true;
      for (var j = start; j < i; j++) {
        final c = bytes[j];
        if (c < 0x20 || c > 0x7e) {
          ascii = false;
          break;
        }
      }
      if (ascii) out.add(String.fromCharCodes(bytes.sublist(start, i)));
    }
    start = i + 1;
  }
  return out;
}


/// 从传输层源码里把「我打算写给 mpv 的名字」抠出来。
///
/// 从源码取而不是在测试里抄一份名单：抄的那份会随时间失真，而失真成一个
/// **通过**的测试比失真成一个失败的测试糟得多。
List<String> _mpvNamesInUse() {
  final source = File('lib/video/controller/mpv_video_transport.dart');
  if (!source.existsSync()) return const [];
  final text = source.readAsStringSync();
  final names = <String>{};
  // `static const loopFile = 'loop-file';`
  for (final m in RegExp(
    r"static const \w+ = '([a-z][a-z0-9-]+)';",
  ).allMatches(text)) {
    names.add(m.group(1)!);
  }
  // `_get('chapter-list')`
  for (final m in RegExp(r"_get\('([a-z][a-z0-9-]+)'\)").allMatches(text)) {
    names.add(m.group(1)!);
  }
  // `_cmd(<String>['screenshot-to-file', path, 'video'])` —— 只有首位是命令名。
  for (final m in RegExp(
    r"_cmd\(<String>\[\s*'([a-z][a-z0-9-]+)'",
  ).allMatches(text)) {
    names.add(m.group(1)!);
  }
  return names.toList()..sort();
}
