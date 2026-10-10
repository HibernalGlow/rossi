// 工具条分组槽（`ActionGroup`）与其按钮的度量判据。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/widgets/action_group_test.dart
//
// 纯 widget，不碰 ObjectBox / 工作台 / 原生库。钉住四件事：
//
//   1. **横排锁高、竖排锁宽**：两条都是「与排布垂直的那一条 = 图标钮见方」。
//      这一条是竖排那一档的回归判据 —— 早先两档共用一个写死的 `height`，
//      竖排的内容比 40 高，直接被挤爆（`RenderFlex overflowed`）。
//   2. 槽壁 = `wellPadding`：槽正好箍住两端的键，不多不少。
//   3. 图标钮 40 见方、图标 20、`tapTargetSize` 收缩（一行要塞十几颗）；
//      禁用就是 `onPressed: null`，不是把键藏起来。
//   4. 开关键选中走 `secondaryContainer`；`fill` 缺省 `surfaceContainer`，
//      显式传就听调用方的（书架页右上角压在同色栏上时用得上）。
//
// 另外留一条**阳性对照**：同一把尺子必须量得出「裸 `IconButton` 的 48」，
// 否则上面那两条 40 的断言可能只是量不到东西而空过。
//
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/action_group.dart';

/// 夹具：给足空间，免得量到的几何被挤压。
Widget _harness(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

/// 两颗图标键 + 组内间距的**标准一组**。
List<Widget> _twoIcons() => [
  ActionIconButton(
    glyph: AppGlyphs.search,
    tooltip: '第一颗',
    onPressed: () {},
  ),
  const SizedBox(width: ActionGroupMetrics.gapWithinGroup),
  ActionIconButton(glyph: AppGlyphs.sliders, tooltip: '第二颗', onPressed: () {}),
];

void main() {
  testWidgets('横排：高锁 40，宽 = 两片槽壁 + 两颗键 + 一个组内间距', (tester) async {
    await tester.pumpWidget(_harness(ActionGroup(children: _twoIcons())));
    await tester.pumpAndSettle();

    final well = tester.getRect(find.byType(ActionGroup));
    expect(well.height, ActionGroupMetrics.buttonSize, reason: '横排锁的该是高度');
    expect(
      well.width,
      ActionGroupMetrics.buttonSize * 2 +
          ActionGroupMetrics.gapWithinGroup +
          ActionGroupMetrics.wellPadding * 2,
    );

    // 槽正好箍住两端：左壁与右壁各一片。
    final first = tester.getRect(find.byTooltip('第一颗'));
    final last = tester.getRect(find.byTooltip('第二颗'));
    expect(well.left, first.left - ActionGroupMetrics.wellPadding);
    expect(well.right, last.right + ActionGroupMetrics.wellPadding);
    // 组内间距是**调用方**给的（`ActionGroup` 自己不加分隔）：两颗键之间就是它。
    expect(last.left - first.right, ActionGroupMetrics.gapWithinGroup);
  });

  testWidgets('竖排：宽锁 40，高按内容长（侧栏那一档）', (tester) async {
    await tester.pumpWidget(
      _harness(
        ActionGroup(
          axis: Axis.vertical,
          children: [
            ActionIconButton(
              glyph: AppGlyphs.search,
              tooltip: '第一颗',
              onPressed: () {},
            ),
            const SizedBox(height: ActionGroupMetrics.gapWithinGroup),
            ActionIconButton(
              glyph: AppGlyphs.sliders,
              tooltip: '第二颗',
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final well = tester.getRect(find.byType(ActionGroup));
    expect(well.width, ActionGroupMetrics.buttonSize, reason: '竖排锁的该是宽度');
    expect(
      well.height,
      ActionGroupMetrics.buttonSize * 2 +
          ActionGroupMetrics.gapWithinGroup +
          ActionGroupMetrics.wellPadding * 2,
      reason: '竖排的高被锁成 40 时，内容会被挤爆 —— 这里是那条回归判据',
    );

    final first = tester.getRect(find.byTooltip('第一颗'));
    final last = tester.getRect(find.byTooltip('第二颗'));
    expect(well.top, first.top - ActionGroupMetrics.wellPadding);
    expect(well.bottom, last.bottom + ActionGroupMetrics.wellPadding);
    expect(last.top - first.bottom, ActionGroupMetrics.gapWithinGroup);
  });

  testWidgets('图标钮 40 见方、图标 20；禁用就是 onPressed: null', (tester) async {
    await tester.pumpWidget(
      _harness(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ActionIconButton(
              glyph: AppGlyphs.search,
              tooltip: '可用',
              onPressed: () {},
            ),
            const SizedBox(width: ActionGroupMetrics.gapWithinGroup),
            ActionIconButton(
              glyph: AppGlyphs.search,
              tooltip: '不可用',
              enabled: false,
              onPressed: () {},
            ),
            const SizedBox(width: ActionGroupMetrics.gapWithinGroup),
            // 「在这儿了，点了也没去处」：画成禁用色但仍然可点。
            ActionIconButton(
              glyph: AppGlyphs.search,
              tooltip: '暗着但可点',
              muted: true,
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final tooltip in ['可用', '不可用', '暗着但可点']) {
      final trigger = find.byTooltip(tooltip);
      expect(
        tester.getSize(trigger),
        const Size.square(ActionGroupMetrics.buttonSize),
        reason: '$tooltip 不是 40 见方',
      );
      expect(
        tester.getSize(
          find.descendant(of: trigger, matching: find.byType(GlyphIcon)),
        ),
        const Size.square(ActionGroupMetrics.iconSize),
        reason: '$tooltip 的图标不是 20 —— 缺省是 24，那会把整条顶高',
      );
    }

    IconButton buttonOf(String tooltip) => tester.widget<IconButton>(
      find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(IconButton)),
    );
    expect(buttonOf('可用').onPressed, isNotNull);
    expect(buttonOf('不可用').onPressed, isNull, reason: '禁用没生效');
    expect(
      buttonOf('暗着但可点').onPressed,
      isNotNull,
      reason: 'muted 只是画成暗的，不该顺手把动作也拿走',
    );

    // 阳性对照：同一把尺子得看得见「裸 IconButton 的 48 触摸区」。
    await tester.pumpWidget(
      _harness(IconButton(icon: const Icon(Icons.search_rounded), onPressed: () {})),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(IconButton)),
      const Size.square(48),
      reason: '对照不成立 —— 这把尺子量不出 40 与 48 的差别',
    );
  });

  testWidgets('开关键：选中走 secondaryContainer，未选中无底', (tester) async {
    late ColorScheme scheme;
    Widget bar({required bool on}) => _harness(
      Builder(
        builder: (context) {
          scheme = Theme.of(context).colorScheme;
          return ActionToggleButton(
            glyph: AppGlyphs.clock,
            tooltip: '开关',
            on: on,
            onPressed: () {},
          );
        },
      ),
    );

    await tester.pumpWidget(bar(on: false));
    await tester.pumpAndSettle();
    ButtonStyle style() => tester
        .widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('开关'),
            matching: find.byType(IconButton),
          ),
        )
        .style!;
    expect(style().backgroundColor!.resolve({}), Colors.transparent);

    await tester.pumpWidget(bar(on: true));
    await tester.pumpAndSettle();
    expect(style().backgroundColor!.resolve({}), scheme.secondaryContainer);
  });

  testWidgets('开关键（glyph）：选中即填充，且填充是动画过去的', (tester) async {
    // 选中态不是「换个颜色」：glyph 走 `AnimatedGlyph`，fill 0→1 涨成实心。
    // 这条是那条回归判据 —— 早先选中只换底色与前景色，图标本身纹丝不动。
    Widget bar({required bool on}) => _harness(
      ActionToggleButton(
        glyph: AppGlyphs.search,
        tooltip: '开关',
        on: on,
        onPressed: () {},
      ),
    );

    double fillOf() =>
        tester.widget<GlyphIcon>(find.byType(GlyphIcon)).fill!;

    await tester.pumpWidget(bar(on: false));
    await tester.pumpAndSettle();
    expect(find.byType(AnimatedGlyph), findsOneWidget);
    expect(fillOf(), 0, reason: '未选中该是描边（fill 0）');

    await tester.pumpWidget(bar(on: true));
    await tester.pump(const Duration(milliseconds: 100));
    final mid = fillOf();
    expect(mid, greaterThan(0), reason: '选中该开始填充');
    expect(mid, lessThan(1), reason: '填充该是动画过去的，不是瞬跳到实心');

    await tester.pumpAndSettle();
    expect(fillOf(), 1, reason: '动画结束后该是完全实心');
  });

  testWidgets('槽的底色：缺省 surfaceContainer，显式传就听调用方的', (tester) async {
    late ColorScheme scheme;
    await tester.pumpWidget(
      _harness(
        Builder(
          builder: (context) {
            scheme = Theme.of(context).colorScheme;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ActionGroup(children: _twoIcons()),
                const SizedBox(height: 8),
                ActionGroup(fill: scheme.primaryContainer, children: _twoIcons()),
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    Color fillOf(int index) {
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(ActionGroup).at(index),
          matching: find.byType(Container),
        ),
      );
      return (container.decoration! as BoxDecoration).color!;
    }

    expect(fillOf(0), scheme.surfaceContainer, reason: '缺省档该是「比卡片低一档」');
    expect(fillOf(1), scheme.primaryContainer, reason: '显式传的 fill 被丢了');
  });
}
