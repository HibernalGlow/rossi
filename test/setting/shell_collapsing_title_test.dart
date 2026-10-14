/// 折叠大标题本身的机制回读，用**合成页**而不是真设置页。
///
/// # 为什么要单独一份
/// 真设置页的夹具要经 `GlobalSettingCubit` → `main.dart` → 整个 app 的 import 图。
/// 2026-10-14 那次，别的会话在 `lib/page/comic_read/**` 留了编不过的在途代码
/// （`List.unmodifiable` 的 `growable`、`context.readEffectiveReadSetting`），
/// 于是**任何** pump 真页面的测试连编译都进不去，我的外壳改动就没尺可用了。
/// 这份只 import 外壳，坏在半路的那棵子树牵连不到它。
library;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/setting/common/setting_detail_scope.dart';
import 'package:zephyr/page/setting/common/setting_group.dart';
import 'package:zephyr/page/setting/common/setting_route.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';

Widget _page({String? description, String title = '墨水屏适配', int rows = 24}) =>
    SettingPageShell(
      title: title,
      description: description,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          SettingGroup(
            title: '运行行为',
            children: [
              for (var i = 0; i < rows; i++) ListTile(title: Text('第 $i 行')),
            ],
          ),
        ],
      ),
    );

Future<void> _open(
  WidgetTester tester,
  Widget page, {
  bool viaRoute = false,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // 同一条用例里二次 _open 时，上一轮的 Navigator 会被复用、设置页还压在按钮上面
  // （`find.text('打开设置页')` 于是命中 offstage，tap 直接失败）。先拆根再重建。
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                viaRoute
                    ? settingPageRoute<void>(
                        context: context,
                        builder: (_) => page,
                      )
                    : MaterialPageRoute(builder: (_) => page),
              ),
              child: const Text('打开设置页'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('打开设置页'));
  await tester.pumpAndSettle();
}

double _contentTop(WidgetTester tester) =>
    tester.getTopLeft(find.byType(SettingGroup).first).dy;

void main() {
  testWidgets('进入时是大标题，滚一段后顶栏跟着收、标题常驻', (tester) async {
    await _open(tester, _page(description: '减少动画并定期整屏刷新'));
    expect(
      find.descendant(of: find.byType(M3EAppBar), matching: find.text('墨水屏适配')),
      findsOneWidget,
    );
    expect(find.byType(BackButton), findsOneWidget, reason: '顶栏丢了返回键就出不去');

    final expanded = _contentTop(tester);
    expect(expanded, greaterThanOrEqualTo(110), reason: '没先看到大标题');

    await tester.drag(find.byType(ListView).first, const Offset(0, -320));
    await tester.pumpAndSettle();
    final collapsed = _contentTop(tester);
    expect(
      collapsed,
      lessThan(expanded - 30),
      reason: '滚了 320 只上移 ${expanded - collapsed}，顶栏没跟着收',
    );
    expect(
      find.descendant(of: find.byType(M3EAppBar), matching: find.text('墨水屏适配')),
      findsOneWidget,
      reason: '收起后标题该缩着留下，不是消失',
    );
  });

  testWidgets('应用真实的全屏弹层路由里同样折叠', (tester) async {
    await _open(tester, _page(description: '减少动画并定期整屏刷新'), viaRoute: true);
    final expanded = _contentTop(tester);
    expect(find.byType(M3EAppBar), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -320));
    await tester.pumpAndSettle();
    expect(_contentTop(tester), lessThan(expanded - 30));
  });

  testWidgets('介绍为空也照样是大标题（不靠副标题撑）', (tester) async {
    await _open(tester, _page());
    expect(
      _contentTop(tester),
      greaterThanOrEqualTo(110),
      reason: '缺介绍的页不该退回小标题栏',
    );
  });

  testWidgets('长介绍换行而不是被截断，并且卷得走（大标题留着）', (tester) async {
    // 顶栏那条带子是定高的（实测单行标题＋单行介绍＝164，标题再换一行就 overflowed
    // by 28），所以上游实现里放不下「长句子自然换行」。介绍挪到壳里第二条
    // header sliver 之后，它按内容定高：这一条量的就是「真的换行了、而且还能卷走」。
    const intro = '为电子墨水屏优化显示行为，减少动画，并通过定期整屏刷新改善使用体验。';
    await _open(tester, _page(description: intro));

    final introBox = tester.getSize(find.text(intro));
    expect(
      introBox.height,
      greaterThan(30),
      reason: '介绍只有 ${introBox.height} 高＝还是一行＋省略号，没换成第二行',
    );

    final expanded = _contentTop(tester);
    await tester.drag(find.byType(ListView).first, const Offset(0, -320));
    await tester.pumpAndSettle();
    // 前面已经按文本正控过一次（拿得到尺寸），这里换成「找不到」＝它是真的被视口
    // 请出去了，而不是夹具没加载出来。
    expect(find.text(intro), findsNothing, reason: '介绍还留在树上＝常驻了两层标题');
    expect(
      find.descendant(of: find.byType(M3EAppBar), matching: find.text('墨水屏适配')),
      findsOneWidget,
      reason: '卷走介绍时大标题得留下',
    );
    expect(_contentTop(tester), lessThan(expanded - 30));
  });

  testWidgets('短页不为了能折叠而造内容：顶栏不占满一屏', (tester) async {
    await _open(tester, _page(rows: 1));
    expect(_contentTop(tester), lessThan(220));
    expect(find.byType(SettingGroup), findsOneWidget);
  });

  for (final scale in [2.0, 3.0]) {
    testWidgets('textScale $scale 的窄面板不顶穿顶栏', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: _page(description: '为电子墨水屏优化显示行为，减少动画，并通过定期整屏刷新改善体验。'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$scale 倍字号下顶栏被顶穿');
    });
  }

  testWidgets('一行标题够放真实最长的页名（截断有阳性对照）', (tester) async {
    // 折叠带子是定高的，标题只能一行＋省略号（实测数字见 setting_ui.dart 那段注释）。
    // 这条断言管的是「一行够不够」：22 个走外壳的设置页里最长的页名 9 字
    // （`漫画翻译（成品页）`，按 lib/page/** 的 `SettingPageShell(title:` 扫出来的）。
    // 判据不是「画得下」，而是「没被省略号吃掉」：整句的单行宽 <= 段落实际宽度。
    Future<(double, double)> paintVsIntrinsic(String text) async {
      final box = tester.renderObject<RenderParagraph>(find.text(text))!;
      final painter = TextPainter(
        text: TextSpan(text: text, style: box.text.style),
        textDirection: TextDirection.ltr,
      )..layout();
      return (box.size.width, painter.width);
    }

    await _open(tester, _page(title: '漫画翻译（成品页）'));
    final (painted, needed) = await paintVsIntrinsic('漫画翻译（成品页）');
    expect(
      needed,
      lessThanOrEqualTo(painted + 0.5),
      reason: '整句要 $needed px，只给了 $painted px ＝ 标题被省略号截了',
    );

    // 正控：同一条尺必须在真放不下的标题上报红，否则上面那条是假绿。
    const tooLong = '阅读器与工作台联动偏好与滚动展开到全屏行为设置';
    await _open(tester, _page(title: tooLong));
    final (longPainted, longNeeded) = await paintVsIntrinsic(tooLong);
    expect(
      longNeeded,
      greaterThan(longPainted + 0.5),
      reason: '360 宽连 22 字的标题都放得下，这条尺就是空的',
    );
  });

  testWidgets('介绍卷到常驻小栏底下时被压住，不是盖在它上面', (tester) async {
    // 介绍换成外层 header 的第二条 sliver 之后，唯一的视觉风险是：pinned 小栏没有
    // 向后面的 sliver 报「我这里被占住了」，于是介绍画在标题栏上（两层字叠一起）。
    // 这不用等真机：本 SDK 里这条通道是 `SliverConstraints.overlap`（旧名 overlapOffset，
    // 由 pinned header 的 maxScrollObstructionExtent 供），收拢后介绍那条 sliver 必须拿到 >0。
    const intro = '为电子墨水屏优化显示行为，减少动画，并通过定期整屏刷新改善使用体验。';
    await _open(tester, _page(description: intro));

    // 100 > 展开到收起的幅度（实测 132→约 72），所以此刻小栏已经常驻、还在往下卷。
    final introSliver = tester
        .element(find.text(intro))
        .findAncestorRenderObjectOfType<RenderSliver>();
    expect(introSliver, isNotNull, reason: '介绍不在任何 sliver 里，这条尺量错了对象');
    // 正控：还没滚的时候同一条 sliver 必须是 0 —— 否则「>0」这条是恒真的空尺。
    expect(
      introSliver!.constraints.overlap,
      isZero,
      reason: '进页面就 overlap>0，说明这把尺读的不是「谁被压住」',
    );

    await tester.drag(find.byType(ListView).first, const Offset(0, -100));
    await tester.pumpAndSettle();

    expect(
      introSliver.constraints.overlap,
      greaterThan(0),
      reason: 'overlap=0 ＝ 介绍正画在常驻小栏上，两层字叠在一起',
    );
  });

  testWidgets('双栏右栏不挂大标题', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingDetailScope(child: _page(description: '减少动画并定期整屏刷新')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NestedScrollView), findsNothing);
    expect(find.byType(M3EAppBar), findsNothing);
    expect(find.text('墨水屏适配'), findsOneWidget, reason: '只有小标题栏那一份');
  });

  testWidgets('阳性对照：没有外壳就没有折叠（这条尺量的是壳）', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('墨水屏适配')),
          body: ListView(children: const [ListTile(title: Text('第 0 行'))]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(M3EAppBar), findsNothing);
    expect(find.byType(SettingPageShell), findsNothing);
  });
}
