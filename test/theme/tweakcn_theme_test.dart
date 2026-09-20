// tweakcn 主题导入的判据。
//
// 分三截：CSS 颜色值转换（OKLCH → sRGB，含色域外收缩）、粘贴文本的归属判定
// （哪一段算 light、哪一段算 dark、哪些是要跳过的转发）、以及覆盖到 ColorScheme
// 之后的角色映射。视觉对不对最终靠肉眼，但**这些数值与归属**在这里钉死。

import 'dart:ui' show Brightness, Color;

import 'package:flutter_test/flutter_test.dart';
// 与 `main.dart` 同一套主题栈：这里要覆盖的是 material_ui 的 ColorScheme。
import 'package:material_ui/material_ui.dart' show ColorScheme;

import 'package:zephyr/util/theme/tweakcn_color.dart';
import 'package:zephyr/util/theme/tweakcn_theme.dart';

void main() {
  group('parseCssColor', () {
    test('hex 的 3/4/6/8 位写法', () {
      expect(parseCssColor('#fff'), const Color(0xFFFFFFFF));
      expect(parseCssColor('#ffffff'), const Color(0xFFFFFFFF));
      expect(parseCssColor('#ff000080')!.a, closeTo(0.502, 0.01));
      expect(parseCssColor('#f00f')!.a, closeTo(1.0, 0.01));
      expect(parseCssColor('#f00')!.r, 1);
      expect(parseCssColor('#f00')!.g, 0);
    });

    test('rgb / 百分比 / 逗号老写法 / 透明度', () {
      expect(parseCssColor('rgb(255, 0, 0)'), const Color(0xFFFF0000));
      expect(parseCssColor('rgb(0 128 0)'), const Color(0xFF008000));
      expect(parseCssColor('rgb(50% 50% 50%)')!.g, closeTo(0.5, 0.004));
      // 透明度也落在 8bit 上（128/255），所以按 1/255 的容差断言。
      expect(parseCssColor('rgba(0, 0, 0, 0.5)')!.a, closeTo(0.5, 0.004));
      expect(parseCssColor('rgb(0 0 0 / 25%)')!.a, closeTo(0.25, 0.004));
    });

    test('hsl / hwb', () {
      expect(parseCssColor('hsl(0, 100%, 50%)'), const Color(0xFFFF0000));
      expect(parseCssColor('hsl(120 100% 50%)')!.g, 1);
      expect(parseCssColor('hsl(240deg 100% 50%)')!.b, 1);
      expect(parseCssColor('hwb(0 0% 100%)'), const Color(0xFF000000));
      expect(parseCssColor('hwb(0 50% 0%)')!.r, closeTo(1, 1e-6));
    });

    test('oklch 的灰轴与黑白（shadcn 默认值就是这么写的）', () {
      expect(parseCssColor('oklch(1 0 0)'), const Color(0xFFFFFFFF));
      expect(parseCssColor('oklch(0 0 0)'), const Color(0xFF000000));
      // 已知值对账：Tailwind neutral-950 = oklch(0.145 0 0) = #0a0a0a，
      // 也是 shadcn 默认深色的 background。矩阵算错一定过不了这条。
      expect(parseCssColor('oklch(0.145 0 0)'), const Color(0xFF0A0A0A));
    });

    test('oklch 色相落点正确', () {
      // 已知值对账：浏览器把 CSS `red`（#ff0000）算成 oklch(0.628 0.2577 29.234)。
      // 色相丢了单位（`29.23` 而不是 `29.23deg`）也会在这条上暴露出来。
      expect(
        parseCssColor('oklch(0.628 0.2577 29.23)'),
        const Color(0xFFFF0000),
      );
      expect(
        parseCssColor('oklch(0.628 0.2577 29.23deg)'),
        const Color(0xFFFF0000),
      );
      // hue 290° 一带必须是蓝紫，不能偏成青
      final purple = parseCssColor('oklch(0.55 0.2 290)')!;
      expect(purple.b, greaterThan(purple.g));
      expect(purple.r, greaterThan(purple.g));
    });

    test('色域外先收缩彩度：通道都落在 0~1，且色相不翻转', () {
      // L .7 / C .4 / 300° 远超 sRGB 色域
      final c = parseCssColor('oklch(0.7 0.4 300)')!;
      for (final v in [c.r, c.g, c.b]) {
        expect(v, inInclusiveRange(0.0, 1.0));
      }
      // 收缩后仍是蓝紫（b 最高、g 最低），而不是被截断成一块灰
      expect(c.b, greaterThan(c.g));
      expect(c.r, greaterThan(c.g));
      // 彩度 0 的灰轴不该触发收缩，亮度要对得上 L
      final gray = parseCssColor('oklch(0.5 0 300)')!;
      expect(gray.r, closeTo(gray.g, 1e-6));
      expect(gray.r, closeTo(gray.b, 1e-6));
    });

    test('透明度与 oklch / alpha 语法', () {
      expect(parseCssColor('oklch(0.5 0.1 120 / 0.4)')!.a, closeTo(0.4, 1e-6));
      expect(parseCssColor('oklab(0.5 0.1 -0.1)')!.a, 1);
    });

    test('间接值与垃圾输入一律 null', () {
      expect(parseCssColor('var(--background)'), isNull);
      expect(parseCssColor('color-mix(in oklch, red 50%, blue)'), isNull);
      expect(parseCssColor(''), isNull);
      expect(parseCssColor('not-a-color'), isNull);
      expect(parseCssColor('hsl(1 2)'), isNull);
    });

    test('关键字与 !important', () {
      expect(parseCssColor('transparent'), const Color(0x00000000));
      expect(parseCssColor('#fff !important'), const Color(0xFFFFFFFF));
    });
  });

  group('mixClamped / contrastOn', () {
    test('t 允许越界外推，并按通道截断', () {
      final white = const Color(0xFFFFFFFF);
      final black = const Color(0xFF000000);
      expect(mixClamped(white, black, 0.5), const Color(0xFF808080));
      // 负方向外推不会翻成负数，而是截到白
      expect(mixClamped(white, black, -0.5), white);
      expect(mixClamped(white, black, 1.5), const Color(0xFF000000));
    });

    test('深底配白字、浅底配黑字，交叉点是 WCAG 的 0.179', () {
      expect(contrastOn(const Color(0xFF0A0A0A)), const Color(0xFFFFFFFF));
      expect(contrastOn(const Color(0xFFFFFFFF)), const Color(0xFF0A0A0A));
      // 中灰 #808080 亮度约 .216，黑字对比度更高；按保守的 .45 阈值会错配白字。
      expect(contrastOn(const Color(0xFF808080)), const Color(0xFF0A0A0A));
      // 再暗一档（#606060 亮度约 .114）就该翻成白字
      expect(contrastOn(const Color(0xFF606060)), const Color(0xFFFFFFFF));
    });
  });

  group('parseLengthToPx / normalizeTokenName', () {
    test('rem / px / 无单位', () {
      expect(parseLengthToPx('0.625rem'), closeTo(10, 1e-9));
      expect(parseLengthToPx('12px'), 12);
      expect(parseLengthToPx('8'), 8);
      expect(parseLengthToPx(''), isNull);
      expect(parseLengthToPx('abc'), isNull);
    });

    test('CSS 数字语法的边角：前导 + / 省略整数位 / 指数 / 大写单位', () {
      expect(parseLengthToPx('+0.5rem'), closeTo(8, 1e-9));
      expect(parseLengthToPx('.5rem'), closeTo(8, 1e-9));
      expect(parseLengthToPx('1e1px'), 10);
      expect(parseLengthToPx('0.625REM'), closeTo(10, 1e-9));
      expect(parseLengthToPx('10px !important'), isNull);
      expect(parseLengthToPx('50%'), isNull);
    });

    test('剥掉 -- 与 Tailwind v4 的 color- 前缀', () {
      expect(normalizeTokenName('--background'), 'background');
      expect(normalizeTokenName('--color-background'), 'background');
      expect(normalizeTokenName('--Color-Primary'), 'primary');
    });
  });

  group('parseTweakcnTheme（CSS 文本）', () {
    const css = '''
:root {
  --radius: 0.625rem;
  --background: oklch(1 0 0);
  --foreground: oklch(0.145 0 0);
  --primary: oklch(0.205 0 0);
  --primary-foreground: oklch(0.922 0 0);
  --muted: oklch(0.97 0 0);
  --muted-foreground: oklch(0.556 0 0);
  --border: oklch(0.922 0 0);
  --destructive: oklch(0.577 0.245 27.325);
}
.dark {
  --background: oklch(0.145 0 0);
  --foreground: oklch(0.985 0 0);
  --primary: oklch(0.922 0 0);
  --muted: oklch(0.269 0 0);
}
''';

    test('light / dark 分开收，radius 换算成 px', () {
      final result = parseTweakcnTheme(css);
      expect(result.isSuccess, isTrue);
      final theme = result.theme!;
      expect(theme.radius, closeTo(10, 1e-9));
      expect(theme.light['background'], const Color(0xFFFFFFFF));
      expect(theme.dark['background'], isNot(theme.light['background']));
      expect(theme.light['foreground'], isNotNull);
      expect(theme.light['primary'], isNotNull);
    });

    test('包在 @layer base 里、或嵌在 @media 的 dark 里，归属不变', () {
      final wrapped = parseTweakcnTheme('''
@layer base {
  :root { --background: #ffffff; --primary: #111111; }
  .dark { --background: #000000; --primary: #eeeeee; }
}
@media (prefers-color-scheme: dark) {
  :root { --muted: #27272a; }
}
''').theme!;
      expect(wrapped.light['background'], const Color(0xFFFFFFFF));
      expect(wrapped.dark['background'], const Color(0xFF000000));
      // @media 里的 :root 由祖先链判暗色，不能被算成 light
      expect(wrapped.dark['muted'], const Color(0xFF27272A));
      expect(wrapped.light.containsKey('muted'), isFalse);
    });

    test('Tailwind v4 的 @theme 转发块整块剪掉，不产生 skipped 噪音', () {
      final result = parseTweakcnTheme('''
@theme inline {
  --color-background: var(--background);
  --color-foreground: var(--foreground);
  --radius-sm: calc(var(--radius) - 4px);
}
:root { --background: #ffffff; }
''');
      expect(result.theme!.light['background'], const Color(0xFFFFFFFF));
      expect(result.theme!.light.containsKey('foreground'), isFalse);
      // 转发的东西根本不进解析，所以回执里不该冒出「foreground 读不出颜色」这种噪音。
      expect(result.skipped, isEmpty);
    });

    test('@theme 嵌套 braces 也要整块剪干净（不能只剪到第一个 }）', () {
      final result = parseTweakcnTheme('''
@theme inline {
  --color-background: var(--background);
  @media (width >= 40rem) { --breakpoint-md: 40rem; }
}
.dark { --background: #000000; }
''');
      expect(result.theme!.dark['background'], const Color(0xFF000000));
      expect(result.theme!.light, isEmpty);
    });

    test('只给半套时，另一套亮度沿用这一套', () {
      final theme = parseTweakcnTheme(
        ':root { --background: #ffffff; }',
      ).theme!;
      expect(theme.dark, isEmpty);
      expect(
        theme.tokensOrFallback(Brightness.dark)['background'],
        const Color(0xFFFFFFFF),
      );
    });

    test('裸片段（没有选择器）按 light 读', () {
      final theme = parseTweakcnTheme(
        '--background: #ffffff;\n--primary: #ff0000;',
      ).theme!;
      expect(theme.light['background'], const Color(0xFFFFFFFF));
      expect(theme.light['primary'], const Color(0xFFFF0000));
    });
  });

  group('parseTweakcnTheme（registry JSON / 失败判据）', () {
    test(r'$cssVars 形态，name 带出来', () {
      final result = parseTweakcnTheme(r'''
{"name":"zen","type":"registry:theme","$cssVars":{
  "theme":{"--background":"oklch(1 0 0)","--primary":"oklch(0.5 0.2 270)"},
  "dark":{"--background":"oklch(0.15 0 0)"}
}}
''');
      expect(result.isSuccess, isTrue);
      expect(result.theme!.name, 'zen');
      expect(result.theme!.light['primary'], isNotNull);
      expect(result.theme!.dark['background'], isNotNull);
    });

    test('扁平 --key JSON 也能读', () {
      final theme = parseTweakcnTheme('{"--background":"#0a0a0a"}').theme!;
      expect(theme.light['background'], const Color(0xFF0A0A0A));
    });

    test('失败判据：空 / 坏 JSON / 一个颜色都没有', () {
      expect(parseTweakcnTheme('   ').failure, TweakcnImportFailure.empty);
      expect(
        parseTweakcnTheme('{"name":').failure,
        TweakcnImportFailure.unrecognized,
      );
      expect(
        parseTweakcnTheme(':root { --font-sans: Inter; }').failure,
        TweakcnImportFailure.noColors,
      );
    });
  });

  group('TweakcnTheme.encode / decode', () {
    test('绕一圈存储值不变', () {
      final theme = parseTweakcnTheme(
        ':root { --background: #ffffff; --primary: oklch(0.5 0.2 270); }\n'
        '.dark { --background: #000000; }',
      ).theme!;
      final restored = TweakcnTheme.decode(theme.encode())!;
      expect(restored.light, theme.light);
      expect(restored.dark, theme.dark);
      expect(restored, theme);
    });

    test('空串与坏串返回 null（调用方按未导入处理）', () {
      expect(TweakcnTheme.decode(''), isNull);
      expect(TweakcnTheme.decode('not json'), isNull);
      expect(TweakcnTheme.decode('{"light":{}}'), isNull);
    });
  });

  group('apply（覆盖到 ColorScheme 上）', () {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7C3AED),
      brightness: Brightness.light,
    );
    final theme = parseTweakcnTheme('''
:root {
  --background: #ffffff;
  --foreground: #0a0a0a;
  --muted: #f4f4f5;
  --muted-foreground: #71717a;
  --primary: #16a34a;
  --secondary: #f4f4f5;
  --secondary-foreground: #18181b;
  --accent: #e4e4e7;
  --accent-foreground: #18181b;
  --destructive: #dc2626;
  --border: #e4e4e7;
  --input: #e4e4e7;
}
''').theme!;
    final scheme = theme.apply(base, Brightness.light);

    test('导入的 token 说了算', () {
      expect(scheme.surface, const Color(0xFFFFFFFF));
      expect(scheme.onSurface, const Color(0xFF0A0A0A));
      expect(scheme.primary, const Color(0xFF16A34A));
      expect(scheme.error, const Color(0xFFDC2626));
      expect(scheme.outlineVariant, const Color(0xFFE4E4E7));
      expect(scheme.onSurfaceVariant, const Color(0xFF71717A));
    });

    test('种子色的 tertiary 不残留：跟着 secondary 走', () {
      expect(scheme.tertiary, scheme.secondary);
      expect(scheme.tertiaryContainer, const Color(0xFFE4E4E7));
    });

    test('缺 --secondary 时不退回种子色，顺到中性灰 / primary', () {
      // shadcn 的 secondary 本来就是灰，主题没给时用 fromSeed 那套按出厂红派生的
      // 次级色，等于在导入主题里塞进一坨无关的颜色。
      final noSecondary = parseTweakcnTheme(
        ':root { --background: #ffffff; --primary: #16a34a; --muted: #f4f4f5; }',
      ).theme!;
      final viaMuted = noSecondary.apply(base, Brightness.light);
      expect(viaMuted.secondary, const Color(0xFFF4F4F5));
      expect(viaMuted.secondary, isNot(base.secondary));

      final bare = parseTweakcnTheme(
        ':root { --background: #ffffff; --primary: #16a34a; }',
      ).theme!;
      expect(
        bare.apply(base, Brightness.light).secondary,
        const Color(0xFF16A34A),
      );
    });

    test('主题没给的必需角色要列出来（补值是静默的）', () {
      final bare = parseTweakcnTheme(
        ':root { --background: #ffffff; --primary: #16a34a; }',
      ).theme!;
      expect(bare.missingRequiredTokens(Brightness.light), [
        'foreground',
        'secondary',
        'muted',
        'border',
        'destructive',
      ]);
      expect(theme.missingRequiredTokens(Brightness.light), isEmpty);
    });

    test('surface 色阶由中性向量外推，浅→深单调且不掺种子色', () {
      final ladder = surfaceLadder(
        const Color(0xFFFFFFFF),
        const Color(0xFFF4F4F5),
        Brightness.light,
      );
      final order = [
        ladder.lowest,
        ladder.low,
        ladder.container,
        ladder.high,
        ladder.highest,
      ];
      for (var i = 1; i < order.length; i++) {
        expect(
          order[i].computeLuminance() <= order[i - 1].computeLuminance() + 1e-6,
          isTrue,
          reason: '第 $i 档应该比前一档暗',
        );
      }
      // 中性：三通道彼此在 1/255 量级内（shadcn 的灰本身带一点点蓝），
      // 关键是没把种子色的紫混进卡片底。
      for (final c in order) {
        expect((c.r - c.g).abs(), lessThan(0.01));
        expect((c.g - c.b).abs(), lessThan(0.01));
      }
      // 卡片底走的是色阶里的档位，不是白底本身
      expect(scheme.surfaceContainerHigh, isNot(scheme.surface));
    });

    test('深色色阶 lowest 比 surface 更暗（M3 的那一档方向）', () {
      final darkLadder = surfaceLadder(
        const Color(0xFF09090B),
        const Color(0xFF27272A),
        Brightness.dark,
      );
      expect(
        darkLadder.lowest.computeLuminance(),
        lessThan(darkLadder.highest.computeLuminance()),
      );
      expect(
        darkLadder.lowest.computeLuminance(),
        lessThan(darkLadder.container.computeLuminance()),
      );
    });

    test('缺 foreground 的底色自己配对比色，不留种子色前景', () {
      final half = parseTweakcnTheme(
        ':root { --background: #111111; --primary: #222222; }',
      ).theme!;
      final applied = half.apply(base, Brightness.light);
      expect(applied.onPrimary, const Color(0xFFFFFFFF));
      expect(applied.onSurface, isNot(base.onSurface));
    });

    test('空 token 集原样返回（不影响 fromSeed 结果）', () {
      expect(const TweakcnTheme().apply(base, Brightness.light), base);
    });
  });

  group('TweakcnThemeLibrary（多主题库）', () {
    TweakcnTheme themeOf(String hex) =>
        parseTweakcnTheme(':root { --background: $hex; }').theme!;

    test('空串 / 坏串 / 没有项的库都读成空库', () {
      expect(TweakcnThemeLibrary.decode('').isEmpty, isTrue);
      expect(TweakcnThemeLibrary.decode('not json').isEmpty, isTrue);
      expect(TweakcnThemeLibrary.decode('{"entries":[]}').isEmpty, isTrue);
    });

    test('旧的单槽格式读成库里一项，并且就是生效项', () {
      final legacy = themeOf('#16a34a').encode();
      final library = TweakcnThemeLibrary.decode(legacy);
      expect(library.entries.length, 1);
      expect(library.activeId, TweakcnThemeLibrary.legacyEntryId);
      expect(library.activeTheme!.light['background'], const Color(0xFF16A34A));
    });

    test('追加即生效，绕一圈存储名字 / 圆角 / 颜色都不丢', () {
      final library = const TweakcnThemeLibrary()
          .withTheme(themeOf('#ffffff'), name: '白', id: 'a')
          .withTheme(themeOf('#000000'), name: '黑', id: 'b');
      expect(library.activeId, 'b');
      expect(library.entries.map((e) => e.name), ['白', '黑']);

      final restored = TweakcnThemeLibrary.decode(library.encode());
      expect(restored.activeId, 'b');
      expect(restored.entries.length, 2);
      expect(
        restored.activeTheme!.light['background'],
        const Color(0xFF000000),
      );
    });

    test('挑没听过的 id 不改库；删掉生效项清空选中而不是自动换一个', () {
      final library = const TweakcnThemeLibrary()
          .withTheme(themeOf('#ffffff'), id: 'a')
          .withTheme(themeOf('#000000'), id: 'b');

      expect(library.activated('nope').activeId, 'b');
      expect(library.activated('a').activeId, 'a');
      // 名字留空时退到 registry 的 name（这里没有）→ 再退到 id，不会是空串。
      expect(library.entries.first.name, 'a');

      final removedActive = library.removed('b');
      expect(removedActive.activeId, isEmpty);
      expect(removedActive.activeTheme, isNull);
      expect(removedActive.entries.map((e) => e.id), ['a']);
      expect(library.removed('a').activeId, 'b');
    });

    test('activeId 指向不存在的项时，读回来回落到第一项', () {
      const broken =
          '{"entries":[{"id":"x","light":{"background":"#ffffffff"}}],"activeId":"gone"}';
      final library = TweakcnThemeLibrary.decode(broken);
      expect(library.activeId, 'x');
      expect(library.activeTheme!.light['background'], const Color(0xFFFFFFFF));
    });

    test('默认名带时间，列表里能排出导入顺序', () {
      final name = defaultTweakcnThemeName(DateTime(2026, 9, 20, 7, 5, 0));
      expect(name, contains('2026-09-20'));
      expect(name, contains('07:05'));
    });

    test('tokenCount 取两套的并集', () {
      final half = parseTweakcnTheme(
        ':root { --background: #ffffff; --primary: #000000; }\n'
        '.dark { --background: #000000; --muted: #111111; }',
      ).theme!;
      // background 两套都有，只算一次。
      expect(half.tokenCount, 3);
    });
  });
}
