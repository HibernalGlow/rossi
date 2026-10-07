// 只用 material_ui：它自带一套 MaterialApp / Scaffold / Icons（与主应用同一套），
// 再 import flutter/material 会得到一堆二义名。
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/discover/widgets/plugin_function_chips.dart';

/// 功能胶囊那一排。
///
/// 判的是「辨识度」这件事本身：不同语义的胶囊必须画出不同的图标、不同档位必须
/// 有不同的容器形态，否则这轮改动等于没做。外加两条布局护栏 ——
/// 标题是插件作者随手写的，长名字和窄卡片都不能把它撑爆。
Map<String, dynamic> _listFunction(String id, String title) => {
  'id': id,
  'title': title,
  'action': {
    'type': 'openComicList',
    'payload': {
      'scene': {'title': title},
    },
  },
};

/// 顺序即档位：browse browse browse browse / library / tool / tool。
List<Map<String, dynamic>> _fixture() => [
  _listFunction('ranking', '排行'),
  _listFunction('recent', '最新'),
  _listFunction('popular', '热门'),
  _listFunction('recommend', '推荐'),
  _listFunction('cloudFavorite', '云端收藏'),
  _listFunction('nav', '分类'),
  _listFunction('zzz', '啵哩啵哩'),
];

Future<void> _pump(
  WidgetTester tester,
  List<Map<String, dynamic>> functions, {
  double width = 320,
  void Function(Map<String, dynamic> action)? onAction,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: PluginFunctionChips(
              functions: functions,
              onAction: onAction == null
                  ? (_) async {}
                  : (a) async => onAction(a),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<ActionChip> _chips(WidgetTester tester) =>
    tester.widgetList<ActionChip>(find.byType(ActionChip)).toList();

ActionChip _chipAt(WidgetTester tester, int index) {
  final chips = _chips(tester);
  expect(chips.length, greaterThan(index), reason: '第 $index 颗胶囊没画出来');
  return chips[index];
}

void main() {
  testWidgets('每颗胶囊都带图标，且不同语义的图标两两不同', (tester) async {
    await _pump(tester, _fixture());

    expect(tester.takeException(), isNull);

    final chips = _chips(tester);
    expect(chips.length, 7);

    final icons = <IconData>[];
    for (final chip in chips) {
      expect(chip.avatar, isA<Icon>(), reason: '有胶囊没拿到图标');
      icons.add((chip.avatar! as Icon).icon!);
    }
    // 「排行」和「最新」以前是两颗一模一样的描边药丸 —— 这轮改动要的就是它们不再同形。
    expect(
      icons.toSet().length,
      icons.length,
      reason: '有语义不同的胶囊共用了同一个图标：$icons',
    );
  });

  testWidgets('浏览档与用户档是两种实心色，工具档退成描边', (tester) async {
    await _pump(tester, _fixture());

    final browse = _chipAt(tester, 0);
    final library = _chipAt(tester, 4);
    final tool = _chipAt(tester, 5);
    final unknown = _chipAt(tester, 6);

    // 两档实心都得靠容器色自己说话，谁都不该再描一圈边。
    expect(browse.side, BorderSide.none);
    expect(library.side, BorderSide.none);
    expect(
      browse.backgroundColor,
      isNot(library.backgroundColor),
      reason: '「看内容」和「我自己的」必须一眼分得开',
    );
    expect(
      browse.backgroundColor,
      isNot(Colors.transparent),
      reason: '实心档得有底色，透明就等于没档位',
    );

    for (final chip in [tool, unknown]) {
      expect(
        chip.side?.style,
        BorderStyle.solid,
        reason: '工具档该是描边 assist chip',
      );
      expect(chip.backgroundColor, Colors.transparent);
    }
  });

  testWidgets('长标题与窄卡片都不撑爆这一排', (tester) async {
    await _pump(
      tester,
      [
        _listFunction('ranking', '一个长得足以单独占满一行的插件自定义功能名字'),
        _listFunction('recent', '最新'),
        _listFunction('cloudFavorite', '云端收藏'),
      ],
      // 220 ≈ 最窄手机上卡片的内容区（320 − 32 卡边距 − 40 内边距 = 248 再留点余量）。
      width: 220,
    );

    // 溢出在测试里表现为一次异常 + 黄黑条纹；条纹看不见，异常跑不掉。
    expect(tester.takeException(), isNull);
    expect(find.byType(ActionChip), findsNWidgets(3));
  });

  testWidgets('只给 id 不给 action 的胶囊，宿主补一个打开功能页的动作', (tester) async {
    Map<String, dynamic>? dispatched;
    await _pump(tester, [
      {'id': 'seriesIndex', 'title': '系列'},
    ], onAction: (action) => dispatched = action);

    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();

    expect(dispatched, isNotNull);
    expect(dispatched!['type'], 'openPluginFunction');
    expect((dispatched!['payload'] as Map)['id'], 'seriesIndex');
  });

  testWidgets('既没 action 也没 id 的那颗点不动', (tester) async {
    await _pump(tester, [
      {
        'title': '云端收藏',
        'action': {'type': 'openCloudFavorite'},
      },
      {'title': '未命名'},
    ]);

    expect(_chipAt(tester, 0).onPressed, isNotNull);
    final dead = _chipAt(tester, 1);
    expect(dead.onPressed, isNull);
    // 点不动的那颗统一摊成一层灰底，不再分档位 —— 档位是给「能点的东西」分优先级的。
    expect(dead.side, BorderSide.none);
  });
}
