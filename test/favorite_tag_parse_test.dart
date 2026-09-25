import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/setting/global/favorite_tag_setting_page.dart';
import 'package:zephyr/util/text/tag_text.dart';

/// 收藏 tag 的输入语法（`本名 | 别名 | 别名`）是用户能写错的地方，
/// 手动添加、批量导入、文件导入三处共用 `parseFavoriteTagLine` / `parseFavoriteTags`，
/// 所以判据打在解析上，而不是打在需要 objectbox 的 cubit 上。
void main() {
  group('一行文本', () {
    test('本名与别名都按 | 切，并各自去掉首尾空白', () {
      final tag = parseFavoriteTagLine(
        '  school_lolita | 学校萝莉 | School Lolita ',
      );
      expect(tag!.name, 'school_lolita');
      expect(tag.aliases, ['学校萝莉', 'School Lolita']);
    });

    test('只有一个名字时没有别名', () {
      expect(parseFavoriteTagLine('loli')!.aliases, isEmpty);
    });

    test('空行、只有分隔符、本名归一化后为空 ⇒ 不产出条目', () {
      expect(parseFavoriteTagLine(''), isNull);
      expect(parseFavoriteTagLine('   '), isNull);
      expect(parseFavoriteTagLine('| |'), isNull);
      expect(parseFavoriteTagLine('[] | 学校萝莉')!.name, '[]');
    });

    test('别名里的重复项由设置层去重，本处只负责解析', () {
      final tag = parseFavoriteTagLine('a | b | b');
      expect(
        TagText.normalize(tag!.aliases[0]),
        TagText.normalize(tag.aliases[1]),
      );
    });
  });

  group('文件与批量文本', () {
    test('纯文本按行解析，忽略空行', () {
      final tags = parseFavoriteTags('chinese\n\nloli | 萝莉\n');
      expect(tags.map((t) => t.name), ['chinese', 'loli']);
      expect(tags.last.aliases, ['萝莉']);
    });

    test('JSON 数组：字符串走 | 语法，对象读 {name, aliases}', () {
      final decoded = jsonDecode(
        '["school_lolita | 学校萝莉", {"name":"loli","aliases":["萝莉","Loli"]}]',
      );
      final tags = parseFavoriteTags(decoded);
      expect(tags.map((t) => t.name), ['school_lolita', 'loli']);
      expect(tags.first.aliases, ['学校萝莉']);
      expect(tags.last.aliases, ['萝莉', 'Loli']);
    });

    test('JSON 对象：{"tags": [...]} 与单条 {"name","aliases"} 都吃', () {
      final wrapped = parseFavoriteTags(jsonDecode('{"tags":["a","b | c"]}'));
      expect(wrapped.map((t) => t.name), ['a', 'b']);
      expect(wrapped.last.aliases, ['c']);

      final single = parseFavoriteTags(
        jsonDecode('{"name":"a","aliases":["b"]}'),
      );
      expect(single.single.aliases, ['b']);
    });

    test('EMM setting.json：取 collectTag 的 tag 字段，cat 不参与', () {
      final decoded = jsonDecode('''
      {
        "library": "D:/emm",
        "collectTag": [
          {"id": "female:footjob", "letter": "f", "cat": "female",
           "tag": "footjob", "color": "rgb(38, 166, 154)"},
          {"id": "other:full color", "cat": "other", "tag": "full color"},
          {"cat": "misc", "tag": "  "}
        ]
      }
      ''');
      final tags = parseFavoriteTags(decoded);
      expect(tags.map((t) => t.name), ['footjob', 'full color']);
      expect(tags.every((t) => t.aliases.isEmpty), isTrue);
    });
  });
}
