import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/plugin/source_visibility_policy.dart';

/// 「受限来源」判定的纯逻辑判据。
///
/// 这一层不碰 ObjectBox / 网络：来源列表那一页依赖前者，本机起不来
/// （`libobjectbox.dylib` 基线红），所以判定与过滤口径都收在 policy 里。
void main() {
  group('isRestricted · UUID 名单', () {
    test('内置源的两条 UUID 必须命中（与 rust/src/qjs/mod.rs 同步）', () {
      for (final uuid in SourceVisibilityPolicy.builtinUuids) {
        expect(SourceVisibilityPolicy.isRestricted(uuid: uuid), isTrue);
      }
    });

    test('内置名单是受限名单的子集', () {
      expect(
        SourceVisibilityPolicy.restrictedUuids.containsAll(
          SourceVisibilityPolicy.builtinUuids,
        ),
        isTrue,
      );
    });

    test('UUID 忽略大小写与首尾空白', () {
      expect(
        SourceVisibilityPolicy.isRestricted(
          uuid: '  0A0E5858-A467-4702-994A-79E608A4589D  ',
        ),
        isTrue,
      );
    });

    test('云端已知受限来源命中', () {
      const uuid = '416598d0-84d0-4de9-8ec5-e74816e768f2'; // nhentai
      expect(SourceVisibilityPolicy.isRestricted(uuid: uuid), isTrue);
    });

    test('UUID 优先于中性名称：名单里的源改名也挡得住', () {
      expect(
        SourceVisibilityPolicy.isRestricted(
          uuid: 'dba2a6cf-c495-4416-accf-c29263ab4016',
          name: 'A Very Clean Reader',
          describe: 'nothing to see here',
          repo: 'someone/clean-reader',
        ),
        isTrue,
      );
    });
  });

  group('isRestricted · 关键词兜底', () {
    test('中文站名命中', () {
      for (final name in ['禁漫天堂', '哔咔漫画', '绅士漫画']) {
        expect(
          SourceVisibilityPolicy.isRestricted(uuid: 'unknown', name: name),
          isTrue,
        );
      }
    });

    test('英文站名与仓库名命中', () {
      const cases = [
        ('nhentai', 'deretame/Breeze-plugin-nhentai'),
        ('e-hentai', 'deretame/Breeze-plugin-ehentai'),
        ('hitomi', 'deretame/Breeze-plugin-hitomi'),
        ('NoyAcg', 'deretame/Breeze-plugin-NoyAcg'),
        ('JmComic', 'deretame/Breeze-plugin-JmComic'),
        ('Bika', 'deretame/Breeze-plugin-bikaComic'),
      ];
      for (final (name, repo) in cases) {
        expect(
          SourceVisibilityPolicy.isRestricted(
            uuid: 'unknown',
            name: name,
            repo: repo,
          ),
          isTrue,
          reason: '$name / $repo',
        );
      }
    });

    test('描述命中也算', () {
      expect(
        SourceVisibilityPolicy.isRestricted(
          uuid: 'unknown',
          name: 'Reader',
          describe: 'alternative front-end for nhentai',
        ),
        isTrue,
      );
    });

    test('普通站点不误伤', () {
      const neutral = [
        ('WEBTOON', 'deretame/Breeze-plugin-webtoon'),
        ('Komiic', 'deretame/Breeze-plugin-komiic'),
        ('包子漫画 Plus', 'Enigma-Soul/Breeze-plugin-baozimh-plus'),
        ('漫画柜', 'deretame/Breeze-plugin-ManHuaGui'),
        ('JJ漫画', 'deretame/Breeze-plugin-jjmhw'),
        ('Toomics', 'wuuduf/Breeze-plugin-toomics'),
      ];
      for (final (name, repo) in neutral) {
        expect(
          SourceVisibilityPolicy.isRestricted(
            uuid: 'unknown',
            name: name,
            repo: repo,
          ),
          isFalse,
          reason: '$name / $repo',
        );
      }
    });

    test('「jm」两字母本身不作为关键词（避免误伤无关仓库名）', () {
      expect(
        SourceVisibilityPolicy.isRestricted(uuid: 'unknown', name: 'JM'),
        isFalse,
      );
    });
  });

  group('isRestricted · manifest 显式声明', () {
    test('声明为受限：即使名称中性也算', () {
      expect(
        SourceVisibilityPolicy.isRestricted(
          uuid: 'unknown',
          name: 'Clean Reader',
          declaredRestricted: true,
        ),
        isTrue,
      );
    });

    test('声明为否不覆盖名单：UUID 命中仍算受限', () {
      expect(
        SourceVisibilityPolicy.isRestricted(
          uuid: '0a0e5858-a467-4702-994a-79e608a4589d',
          declaredRestricted: false,
        ),
        isTrue,
      );
    });
  });

  test('空输入不命中', () {
    expect(SourceVisibilityPolicy.isRestricted(uuid: ''), isFalse);
  });
}
