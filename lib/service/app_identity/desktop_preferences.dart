import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 读旧版 macOS 偏好文件（`~/Library/Preferences/<bundle id>.plist`）。
///
/// **不要用 `plutil -convert json`**：plist 里除了 Flutter 的 `flutter.*` 标量，
/// 还混着 AppKit 自己写进去的 `<data>`（保存面板记的上次目录、窗口几何等）。
/// `plutil` 一遇到 `<data>` 就以 `Invalid object in plist for JSON format` 退出，
/// 于是整个文件都读不出来 —— 老用户反而最容易踩到（用得越久，原生键越多）。
/// 这里先转成 XML，再只挑顶层 dict 里的标量。
Future<Map<String, dynamic>?> readMacPreferencesPlist(File plist) async {
  if (!await plist.exists()) return null;
  final result = await Process.run('/usr/bin/plutil', [
    '-convert',
    'xml1',
    '-o',
    '-',
    plist.path,
  ]);
  if (result.exitCode != 0) {
    debugPrint(
      '旧版偏好 plutil 转换失败（原文件保留）：'
      '${result.stderr.toString().trim()}',
    );
    return null;
  }
  return parsePlistDictionary(result.stdout as String);
}

/// 把 plist 的 XML 表示解析成顶层 dict。
///
/// 只认 `bool` / `int` / `double` / `String` 这几种标量 —— 与
/// `SharedPreferences` 能存的类型一致；`<data>` / `<date>` / 嵌套容器整项跳过
/// （迁移关心的是 Flutter 的偏好，不是原生状态）。
Map<String, dynamic> parsePlistDictionary(String xml) {
  final result = <String, dynamic>{};
  final tags = RegExp(r'<([^<>]*)>');
  // dict / array 的嵌套深度：只有深度 1（顶层 dict）的成员才是偏好。
  var depth = 0;
  String? pendingKey;
  var cursor = 0;

  for (final match in tags.allMatches(xml)) {
    if (match.start < cursor) continue;
    final raw = match.group(1)!.trim();
    if (raw.isEmpty || raw.startsWith('?') || raw.startsWith('!')) continue;
    final rtrim = raw.replaceAll(RegExp(r'/+$'), '').trim();
    final closing = rtrim.startsWith('/');
    final selfClosing = raw.endsWith('/');
    final name = closing ? rtrim.substring(1).trim() : rtrim;

    if (!closing && name == 'array' && depth == 1 && pendingKey != null) {
      // List<String> 的偏好（例如搜索历史）在 plist 里是顶层 `<array>`，
      // SharedPreferences 也只支持字符串列表这一种集合，按它解析。
      final end = _endOfContainer(xml, match.end, 'array');
      if (end < 0) break;
      final items = <String>[];
      for (final item in RegExp(
        r'<string>([\s\S]*?)</string>',
      ).allMatches(xml.substring(match.end, end))) {
        items.add(_decodeXmlText(item.group(1)!));
      }
      result[pendingKey] = items;
      pendingKey = null;
      cursor = end + '</array>'.length;
      continue;
    }
    if (!closing && (name == 'dict' || name == 'array')) {
      depth++;
      cursor = match.end;
      continue;
    }
    if (closing && (name == 'dict' || name == 'array')) {
      depth--;
      pendingKey = null;
      cursor = match.end;
      continue;
    }
    if (depth != 1) continue;

    if (name == 'key' && !closing && !selfClosing) {
      final end = xml.indexOf('</key>', match.end);
      if (end < 0) break;
      pendingKey = _decodeXmlText(xml.substring(match.end, end));
      cursor = end + '</key>'.length;
      continue;
    }
    if (pendingKey == null) continue;

    if (name == 'true' && selfClosing) {
      result[pendingKey] = true;
      pendingKey = null;
      cursor = match.end;
      continue;
    }
    if (name == 'false' && selfClosing) {
      result[pendingKey] = false;
      pendingKey = null;
      cursor = match.end;
      continue;
    }
    // 容器值已经在上面按 depth 处理过了，这里只剩带文本内容的标量。
    if (closing || selfClosing) continue;
    final endTag = '</$name>';
    final end = xml.indexOf(endTag, match.end);
    if (end < 0) break;
    final text = xml.substring(match.end, end);
    cursor = end + endTag.length;

    switch (name) {
      case 'string':
        result[pendingKey] = _decodeXmlText(text);
      case 'integer':
        final value = int.tryParse(text.trim());
        if (value != null) result[pendingKey] = value;
      case 'real':
        final value = double.tryParse(text.trim());
        if (value != null) result[pendingKey] = value;
      default:
        // <data> / <date> / 其它原生类型：不迁移。
        break;
    }
    pendingKey = null;
  }
  return result;
}

/// 找到 `open` 之后与之配对的 `</name>`（跳过同名的嵌套容器）。
int _endOfContainer(String xml, int open, String name) {
  final pattern = RegExp('<$name[\\s>/]|</$name>');
  var depth = 1;
  for (final match in pattern.allMatches(xml)) {
    if (match.start < open) continue;
    final text = match.group(0)!;
    if (text.startsWith('</')) {
      depth--;
      if (depth == 0) return match.start;
    } else if (!text.endsWith('/')) {
      depth++;
    }
  }
  return -1;
}

String _decodeXmlText(String text) {
  if (!text.contains('&')) return text;
  return text.replaceAllMapped(
    RegExp(r'&(amp|lt|gt|quot|apos|#\d+|#[xX][0-9a-fA-F]+);'),
    (match) {
      switch (match.group(1)!) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
      }
      final body = match.group(1)!;
      final code = body.startsWith('#x') || body.startsWith('#X')
          ? int.parse(body.substring(2), radix: 16)
          : int.parse(body.substring(1));
      return String.fromCharCode(code);
    },
  );
}

/// 平台无关的旧偏好读取（Windows / Linux 的 `shared_preferences.json`）。
///
/// 文件损坏时返回 null 而不是抛：偏好是「锦上添花」，不该挡住启动。
Future<Map<String, dynamic>?> readJsonPreferences(File file) async {
  if (!await file.exists()) return null;
  try {
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException catch (error) {
    debugPrint('旧版偏好 JSON 解析失败（原文件保留）：$error');
    return null;
  }
}
