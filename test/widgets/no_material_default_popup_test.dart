// 门禁：`lib/` 里不许再出现 SDK 默认的弹出菜单构造点。
//
// # 为什么要有这一道
//
// 2026-10-14 把最后一批 `DropdownMenu` / `PopupMenuButton` / `showMenu` 换成
// `common_popup.dart` 那套托盘弹出器（理由有两条：动画要与全仓同源；
// 而这个 SDK 的 `PopupMenuItem` **没有 leading 槽**，图标只能往 `child` 里手塞 `Row`）。
// 这类缺口是「换个页面就悄悄长回来」的：静态扫一遍就能挡住，不必等用户看图发现。
//
// # 尺子怎么读
//
// - 只算**构造点**：`DropdownMenu<…>(` / `DropdownButton<…>(` /
//   `DropdownButtonFormField<…>(` / `PopupMenuButton<…>(` / `showMenu(`。
// - 先剥注释再判：`//` 与 `///` 整行丢掉。否则会误报 —— 实测
//   `discover_plat_view.dart` 的文档注释里引用过 SDK 原文 `showMenu(constraints:)`。
// - 白名单**必须打印理由**，不许静默 skip（同 `script/check_setting_group_style.py` 的口径）。
// - 正控：同一条尺喂一段明知违规的合成源码，必须报出来。尺不响就是死尺。

// ignore_for_file: avoid_print  // 豁免理由要每次运行都打印，别变成静默 skip

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 按用户口径排除的文件（超分那页「没有特定风格」，见
/// `script/check_setting_group_style.py` 的 `EXCLUDED` 与每次运行打印的理由）。
const Map<String, String> _allowed = {
  'lib/page/setting/real_sr/widgets/super_resolution_engine_settings.dart':
      '超分设置不做统一风格（用户口径）；这 4 处是引擎选择与预取页数',
  'lib/page/setting/real_sr/widgets/mimage_model_settings.dart':
      '同上：模型选择器，随超分那一组一起豁免',
};

/// 组件本体：它就是那份 Fluent 弹出实现，不是「用错了 Material 默认弹出」。
const List<String> _componentFiles = ['lib/widgets/fluent_dropdown.dart'];

final RegExp _constructors = RegExp(
  r'(?:^|[^.\w])(?:DropdownMenu<[^>]*>\(|DropdownMenu\(|'
  r'DropdownButtonFormField<[^>]*>\(|DropdownButton<[^>]*>\(|'
  r'PopupMenuButton<[^>]*>\(|showMenu\()',
);

/// 返回 [source] 里的构造点行号（1 基）。纯函数，正控直接喂它。
List<int> defaultPopupConstructors(String source) {
  final hits = <int>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('//')) continue; // 整行注释（含 /// 文档注释）
    final code = trimmed.contains('//')
        ? trimmed.substring(0, trimmed.indexOf('//'))
        : trimmed;
    if (_constructors.hasMatch(code)) hits.add(i + 1);
  }
  return hits;
}

void main() {
  test('正控：这把尺看得见违规（不响就是死尺）', () {
    final sample = '''
class X extends StatelessWidget {
  Widget build(BuildContext context) => PopupMenuButton<String>(
    itemBuilder: (_) => [],
  );
  // DropdownButton<int>( 这行是注释，不该被算进去
}
''';
    expect(defaultPopupConstructors(sample), [2]);
  });

  test('lib/ 里只剩白名单那几处 SDK 默认弹出', () {
    final offenders = <String>[];
    final whitelisted = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (_componentFiles.contains(path)) continue;
      final hits = defaultPopupConstructors(entity.readAsStringSync());
      if (hits.isEmpty) continue;
      final reason = _allowed[path];
      if (reason != null) {
        whitelisted.add('$path:${hits.join(',')} — 豁免理由：$reason');
      } else {
        offenders.add('$path:${hits.join(',')}');
      }
    }
    for (final line in whitelisted) {
      // 每次运行都打印，别让它变成静默 skip。
      print('[豁免] $line');
    }
    expect(whitelisted, isNotEmpty, reason: '白名单一条都没命中 ⇒ 豁免名单已经过期，该删掉对应条目');
    expect(
      offenders,
      isEmpty,
      reason:
          '这些点还在用 SDK 默认的弹出动画，且 `PopupMenuItem` 没有 leading 槽挂不进'
          '本仓 Glyph。换成 `CommonPopupBox` + `CommonPopupMenu`（字段形态用'
          '`PopupSelectField`）。',
    );
  });
}
