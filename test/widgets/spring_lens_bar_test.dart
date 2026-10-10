// 按钮按压形变（`ElasticPress` / `ElasticButton`）与 tab 栏切换（`SpringLensBar`）
// 的 widget 判据。
//
// # 判据钉的是什么
//
// 钉**几何与结构**，不钉「动效好不好看」—— 弹簧的手感没有数值判据
// （同 `navigation_shell_test.dart` 头部那条口径）。具体钉四件事：
//
// 1. **lens 落在选中格上**（点击切换后，弹簧静止时那格正中）；
// 2. **形变只在 paint 层**：按下之后被测按钮的**布局矩形不动**，所以锚在它
//    上面的 tooltip / popup 不会跟着飘 —— 这是整套交互最容易写坏的一条；
// 3. **按钮跟手**：按住拖动时 `PressTransform` 的 pull 跟着指针走，松手归零；
// 4. **`draggable: false` 时不抢手势**（泳道面板页签条那一档的拖排序靠它保住）。

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_bar.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_value.dart';

/// 宿主页：一排按钮 + 一个被形变包着的方块。
Widget _host({
  required List<String> labels,
  required int selected,
  required ValueChanged<int> onSelected,
  bool draggable = true,
  List<double>? sizes,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SpringLensBar(
              tabs: [
                for (final label in labels)
                  SpringLensTab(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(label),
                    ),
                    semanticLabel: label,
                  ),
              ],
              tabSizes: sizes,
              selectedIndex: selected,
              onSelected: onSelected,
              draggable: draggable,
            ),
            const SizedBox(height: 40),
            // 一颗走 `ElasticButton` 的按钮，判据读它被形变包住之后的矩形。
            ElasticButton(
              child: IconButton(
                onPressed: () {},
                icon: const Icon(Icons.add),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 重放一遍 painter 内部做的事，算出 lens 真正画在哪。
///
/// **不能**直接读 `SpringLensPainter` 上的 `slots`：那是**解析之前**的原始值
/// （副轴为 0）。painter 在 `paint(canvas, size)` 里会用实到的 `size` 把副轴
/// 补出来（`resolvedTo`），外面看不见。所以这里照它那一步重放一遍 ——
/// 落点（主轴）本来就与副轴无关，补上是为了让宽度/高度也是真值。
Rect _lensRect(WidgetTester tester) {
  final painters = find.descendant(
    of: find.byType(SpringLensBar),
    matching: find.byType(CustomPaint),
  );
  // 转型失败说明组件改了画法（例如 lens 不再用 `SpringLensPainter`），
  // 那时这条判据会立刻报出来，而不是静默比错对象。
  final painter =
      tester.widget<CustomPaint>(painters.first).painter!
          as SpringLensPainter;
  final size = tester.getSize(painters.first);
  return lensRect(
    slots: painter.slots.resolvedTo(size)!,
    position: painter.position,
    velocity: painter.velocity,
    lift: painter.lift,
  );
}

/// 某一个 tab 文字在**bar 局部坐标系**里的矩形。
///
/// 必须换算：lens 是画在 bar 的 `CustomPaint` 上的，它的矩形天然是 bar 局部
/// 坐标；而 `tester.getRect(find.text(...))` 给的是**屏幕**坐标。两者差一个
/// bar 的起点 —— 直接比会差出好几十像素（实测 bar 起点 245、tab A 屏幕中心
/// 275，而它在 bar 局部是 30，正是 lens 的落点）。
Rect _tabRect(WidgetTester tester, String label) {
  final bar = tester.getRect(find.byType(SpringLensBar));
  return tester.getRect(find.text(label)).shift(-bar.topLeft);
}

/// 均分档下每一格的实际宽度 —— 拖动判据要按它换算位移，否则拖半天也跨不了格。
double _slotExtent(WidgetTester tester, String first, String second) =>
    _tabRect(tester, second).center.dx - _tabRect(tester, first).center.dx;

void main() {
  group('SpringLensBar：点击切换', () {
    testWidgets('lens 静止后正中落在选中格上', (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        _host(labels: const ['A', 'B', 'C'], selected: 0, onSelected: (i) => selected = i),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 点第二格。
      await tester.tap(find.text('B'));
      await tester.pump();
      // 弹簧正在飞 —— 此时不该断言落点（动画未结算会污染判据）。
      await tester.pumpAndSettle();

      expect(selected, 1, reason: '点第二格必须回调 1');
      // lens 中点应当与第二格的文字中心同 x。
      final lens = _lensRect(tester);
      expect(lens.center.dx, closeTo(_tabRect(tester, 'B').center.dx, 1.0));
    });

    testWidgets('切档后内容跟着换（阳性对照：确实切了，不只是 lens 动了）', (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        _host(labels: const ['A', 'B'], selected: 0, onSelected: (i) => selected = i),
      );
      await tester.pumpAndSettle();
      expect(selected, 0);
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      expect(selected, 1);
    });

    testWidgets('按内容取宽时 lens 仍落在选中格（不等宽那一档）', (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        _host(
          labels: const ['短', '长得多得多', '中'],
          // 三格不等宽：这是 Dock 那份等宽公式会算错的地方。
          sizes: const [60, 160, 90],
          selected: 0,
          onSelected: (i) => selected = i,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('长得多得多'));
      await tester.pumpAndSettle();
      expect(selected, 1);
      final lens = _lensRect(tester);
      // 用 bar 局部坐标比（`_tabRect` 已换算），见那条注释。
      final target = _tabRect(tester, '长得多得多');
      expect(lens.center.dx, closeTo(target.center.dx, 1.0));
    });
  });

  group('SpringLensBar：拖动跟手', () {
    testWidgets('按住横移跨格时逐格选中', (tester) async {
      final picked = <int>[];
      await tester.pumpWidget(
        _host(
          labels: const ['A', 'B', 'C', 'D'],
          selected: 0,
          onSelected: picked.add,
        ),
      );
      await tester.pumpAndSettle();

      // 位移要按**实际格宽**换算：均分档每格是屏宽/4（约 200px），
      // 按「bar 宽度的百分比」拖会一次跨掉好几格、落点又跳回来。
      final step = _slotExtent(tester, 'A', 'B');
      // `startGesture` 要**屏幕**坐标（与 `_tabRect` 的局部坐标差一个 bar 起点）。
      final barTopLeft = tester.getRect(find.byType(SpringLensBar)).topLeft;
      final gesture = await tester.startGesture(
        _tabRect(tester, 'A').center + barTopLeft,
      );
      await tester.pump();
      // 一格一格走过去，最后一步给足 1.0 格确保落进第四格。
      for (final frac in const [0.9, 0.9, 1.0]) {
        await gesture.moveBy(Offset(step * frac, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(picked, isNotEmpty, reason: '拖动必须真的换档');
      expect(picked.last, 3, reason: '拖到第四格就该选中第四格');
    });

    testWidgets('拖动全程不抛异常，且松手后 lens 落到最终落点', (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        _host(labels: const ['A', 'B', 'C'], selected: 0, onSelected: (i) => selected = i),
      );
      await tester.pumpAndSettle();
      final step = _slotExtent(tester, 'A', 'B');
      final barTopLeft = tester.getRect(find.byType(SpringLensBar)).topLeft;
      final gesture = await tester.startGesture(
        _tabRect(tester, 'A').center + barTopLeft,
      );
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(Offset(step * 0.12, 0));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final lens = _lensRect(tester);
      final target = _tabRect(tester, ['A', 'B', 'C'][selected]);
      expect(lens.center.dx, closeTo(target.center.dx, 1.0));
    });

    testWidgets('越过两端不崩，落点夹在合法档内（橡皮筋）', (tester) async {
      final picked = <int>[];
      await tester.pumpWidget(
        _host(labels: const ['A', 'B'], selected: 0, onSelected: picked.add),
      );
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byType(SpringLensBar));
      // 故意往左猛拖出轨道。
      final gesture = await tester.startGesture(
        Offset(bar.left + 4, bar.center.dy),
      );
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(-30, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(picked, everyElement(inInclusiveRange(0, 1)));
    });
  });

  group('手势归属：draggable: false 时不抢', () {
    testWidgets('关掉拖动跟手后，点击仍然能切档', (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        _host(
          labels: const ['A', 'B', 'C'],
          selected: 0,
          onSelected: (i) => selected = i,
          draggable: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('C'));
      await tester.pumpAndSettle();
      expect(selected, 2, reason: '关掉跟手不等于关掉点击');
    });

    testWidgets('关掉拖动跟手后，横移**不会**触发切档', (tester) async {
      final picked = <int>[];
      await tester.pumpWidget(
        _host(
          labels: const ['A', 'B', 'C'],
          selected: 0,
          onSelected: picked.add,
          draggable: false,
        ),
      );
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byType(SpringLensBar));
      final gesture = await tester.startGesture(
        Offset(bar.left + 6, bar.center.dy),
      );
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(picked, isEmpty, reason: '这一档留给宿主的拖排序，不能被切档抢走');
    });
  });

  group('形变只在 paint 层（锚在上面的东西不会飘）', () {
    testWidgets('按下按钮：布局矩形不动，只有 paint 层在变', (tester) async {
      await tester.pumpWidget(
        _host(labels: const ['A'], selected: 0, onSelected: (_) {}),
      );
      await tester.pumpAndSettle();

      final button = find.byIcon(Icons.add);
      final before = tester.getRect(button);

      // 按住那颗按钮并拖动 —— 它应当被拽。
      final gesture = await tester.startGesture(before.center);
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(4, 4));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);

      // 关键断言：布局矩形**纹丝不动**。
      final during = tester.getRect(button);
      expect(during.size, before.size);
      expect(during.topLeft, before.topLeft);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final after = tester.getRect(button);
      expect(after.topLeft, before.topLeft, reason: '松手弹回后要回到原位');
    });

    testWidgets('按下再松手：paint 变换确实发生过（阳性对照）', (tester) async {
      await tester.pumpWidget(
        _host(labels: const ['A'], selected: 0, onSelected: (_) {}),
      );
      await tester.pumpAndSettle();

      final transform = find.descendant(
        of: find.byType(ElasticButton),
        matching: find.byType(PressTransform),
      );
      expect(transform, findsOneWidget, reason: '按钮必须被 PressTransform 包住');

      final button = tester.getRect(find.byIcon(Icons.add));
      final gesture = await tester.startGesture(button.center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // 按下时那颗按钮的绘制变换非单位阵（确实在鼓）。
      // 要 pump 几十毫秒：`SpringLensValue` 的第一帧只启动 ticker，
      // 立刻读还是0。
      final pressed = tester.widget<PressTransform>(transform);
      expect(pressed.lift, greaterThan(0), reason: '按下要鼓');
      expect(tester.takeException(), isNull);

      // 拖动后 pull 跟着指针走。
      await gesture.moveBy(const Offset(5, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final dragged = tester.widget<PressTransform>(transform);
      expect(dragged.pull.dx, greaterThan(0), reason: '要跟手：往右拖就该被往右拽');

      await gesture.up();
      await tester.pumpAndSettle();
      final released = tester.widget<PressTransform>(transform);
      expect(released.lift, 0, reason: '松手弹回');
      expect(released.pull, Offset.zero);
    });

    testWidgets('禁用态按钮不形变（按一颗按不了的按钮不该鼓）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ElasticButton(
                enabled: false,
                child: IconButton(onPressed: null, icon: const Icon(Icons.add)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final transform = find.byType(PressTransform);
      final before = tester.widget<PressTransform>(transform);
      expect(before.lift, 0);

      final gesture = await tester.startGesture(
        tester.getRect(find.byIcon(Icons.add)).center,
      );
      await tester.pump();
      expect(tester.widget<PressTransform>(transform).lift, 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('阳性对照：这个判据本身不是空转的', () {
    testWidgets('三格都在树上，且都能点到', (tester) async {
      await tester.pumpWidget(
        _host(labels: const ['A', 'B', 'C'], selected: 0, onSelected: (_) {}),
      );
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      // 断言「没变」是空转，必须配一条「真发生」的：这里验 lens 真的挂上了
      // painter（lens 是画出来的，不是 `DecoratedBox` —— 换画法就会红）。
      expect(find.byType(CustomPaint), findsWidgets);
      expect(_lensRect(tester).width, greaterThan(0));
    });

    testWidgets('空 tab 列表不崩（阳性对照的边界）', (tester) async {
      await tester.pumpWidget(
        _host(labels: const [], selected: 0, onSelected: (_) {}),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('越界下标（宿主传错了）被夹住而不是崩', (tester) async {
      await tester.pumpWidget(
        _host(labels: const ['A', 'B'], selected: 99, onSelected: (_) {}),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  _regressions();
}

/// 三处「一眼看去就错」的回归判据 —— 都是 2026-10-11 用户截图报出来的。
///
/// 共同点是**都不能靠读 widget 属性发现**：要看几何、看绘制顺序、看谁收得到
/// 手势。所以每一条都钉在最直接的那一层上。
void _regressions() {
  group('lens 不会盖住选中那格的图标与文字', () {
    testWidgets('lens 层画在内容**之下**（Stack 里内容必须排最后）', (tester) async {
      await tester.pumpWidget(
        _host(labels: const ['收藏', '历史', '下载'], selected: 0, onSelected: (_) {}),
      );
      await tester.pumpAndSettle();

      final stack = tester.widget<Stack>(
        find
            .descendant(
              of: find.byType(SpringLensBar),
              matching: find.byType(Stack),
            )
            .first,
      );
      // Stack 里越靠前画得越早 = 越靠底。lens 是不透明的选中底色，
      // 一旦排在内容之后就会把选中那格的字整个盖住
      // （实测：只有选中那格的字看不见，没选中的正常 —— 这个「只有一格」
      // 的症状最容易误判成字体或颜色的问题）。
      expect(
        stack.children.last,
        isNot(isA<Positioned>()),
        reason: '内容必须是不定位的那一层，且排在最后（画在最上）',
      );
      // 定位层（lens / 悬停高亮）都必须是 `Positioned.fill`，且都在内容之前。
      final positioned = stack.children.whereType<Positioned>().length;
      expect(positioned, stack.children.length - 1);
      expect(positioned, greaterThanOrEqualTo(1), reason: 'lens 那一层得在');
    });
  });

  group('lens 不高于内容（副轴由实到的 size 决定）', () {
    testWidgets('外层给的高度比内容高时，lens 仍是内容那么高', (tester) async {
      // 这一条复现的是书架顶栏那种处境：AppBar 的标题区给的可用高度（48）
      // 比内容实际需要的高（32）。早先那版拿 `constraints.maxHeight` 当 lens
      // 的副轴，于是 lens 被画成 48 高、比胶囊还冒出一截。
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              // 用 `ConstrainedBox`（**松**约束）而不是 `SizedBox`（紧约束）：
              // AppBar 的标题区给的就是松约束（内容多高就多高），紧约束那档
              // 任何 widget 都会被拉满，lens 跟着满并不是这一条要钉的东西。
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: SpringLensBar(
                  tabs: const [
                    SpringLensTab(child: Padding(padding: EdgeInsets.all(8), child: Text('A'))),
                    SpringLensTab(child: Padding(padding: EdgeInsets.all(8), child: Text('B'))),
                  ],
                  selectedIndex: 0,
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lens = _lensRect(tester);
      final content = tester.getRect(find.text('A'));
      // 内容自己多高，lens 就多高 —— 与外面给了 120 无关。
      expect(lens.height, greaterThan(0));
      expect(
        lens.height,
        lessThanOrEqualTo(content.height + 16 + 0.5),
        reason: 'lens 不该高过内容那一条带（+8 上下内边距）',
      );
      expect(
        lens.height,
        isNot(closeTo(400, 1.0)),
        reason: '反面钉住：lens 绝不能是外层给的那 400',
      );
    });
  });

  group('观感参数由调用方给（书架那排要「浮起的一片」）', () {
    testWidgets('lens 的底色与投影原样传到 painter', (tester) async {
      // 书架那排 tab 改造前是 `surface` 底 + 一层很淡的投影。
      // 换成 lens 之后这两样必须由调用方给得进去，否则选中块会变成一块
      // `secondaryContainer` 的栗色实心块（2026-10-11 用户截图）。
      const lens = Color(0xFF123456);
      const shadow = Shadow(
        color: Color(0x0D000000),
        blurRadius: 4,
        offset: Offset(0, 1),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SpringLensBar(
                tabs: const [
                  SpringLensTab(child: Padding(padding: EdgeInsets.all(8), child: Text('A'))),
                  SpringLensTab(child: Padding(padding: EdgeInsets.all(8), child: Text('B'))),
                ],
                selectedIndex: 0,
                onSelected: (_) {},
                lensColor: lens,
                lensCorner: 16,
                lensShadow: shadow,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final painters = find.descendant(
        of: find.byType(SpringLensBar),
        matching: find.byType(CustomPaint),
      );
      final painter =
          tester.widget<CustomPaint>(painters.first).painter!
              as SpringLensPainter;
      expect(painter.color, lens);
      expect(painter.shadow, shadow);
      expect(painter.corner, 16);
      expect(tester.takeException(), isNull);
    });

    test('tintColor 默认关 —— 不指定就不动内容色', () {
      // 染色走 `BlendMode.srcIn`（**替换**内容原本的颜色）。默认必须关：
      // 书架那排的内容是文字，改造前选中的字是普通的 `textColor`；
      // 写死 `primary` 就会把字染成粉色（2026-10-11 用户截图报的就是这处）。
      final bar = SpringLensBar(
        tabs: const [],
        selectedIndex: 0,
        onSelected: (_) {},
      );
      expect(bar.tintColor, isNull);
      expect(bar.lensShadow, isNull);
    });
  });

  group('不抢外层滚动容器的拖动', () {
    testWidgets('在 bar 上横拖只切档，外层横向滚动一动不动', (tester) async {
      // 用户报的正是这个：在面板页签条上拖动切面板，整条泳道跟着横移。
      // 跟手走 `Listener`（不进手势 arena），祖先的滚动识别器于是也收到了
      // 同一次拖动 —— `_claimDrag` 那个只为抢手感存在的识别器就是治它的。
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var selected = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // 左右各垫一块宽内容，让外层**真的可以**滚
                    // （没余量的话「没滚」是空转，判不出东西）。
                    const SizedBox(width: 600, height: 60),
                    // 有界宽度 + `tabSizes`：横向滚动视图给子节点的是**无界**
                    // 主轴，而均分档要拿长度除以份数（见 `_slotsFor` 的断言）。
                    // 真实场景里这条 bar 也是被 `Flexible` / 定宽容器夹住的
                    // （面板页签条就那样），这里照实建。
                    SizedBox(
                      width: 240,
                      child: SpringLensBar(
                        tabSizes: const [80, 80, 80],
                        tabs: const [
                          SpringLensTab(child: Padding(padding: EdgeInsets.all(8), child: Text('A'))),
                          SpringLensTab(child: Padding(padding: EdgeInsets.all(8), child: Text('B'))),
                          SpringLensTab(child: Padding(padding: EdgeInsets.all(8), child: Text('C'))),
                        ],
                        selectedIndex: 0,
                        onSelected: (i) => selected = i,
                      ),
                    ),
                    const SizedBox(width: 600, height: 60),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 正面钉住「确实有可滚余量」—— 否则下面那条「没滚」毫无意义。
      expect(controller.position.maxScrollExtent, greaterThan(0));

      final barTopLeft = tester.getRect(find.byType(SpringLensBar)).topLeft;
      final step = _slotExtent(tester, 'A', 'B');
      final gesture = await tester.startGesture(
        _tabRect(tester, 'A').center + barTopLeft,
      );
      await tester.pump();
      for (final frac in const [0.6, 0.6]) {
        await gesture.moveBy(Offset(step * frac, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        controller.offset,
        closeTo(0, 0.5),
        reason: '外层泳道条不该被这一次拖动带走',
      );
      expect(selected, 1, reason: '该切的面板还是要切到');
    });

    testWidgets('draggable: false 时**不抢**，让宿主照旧滚', (tester) async {
      // 「不抢」是条件性的：那一档拖动本来就该留给宿主（例如排序模式下
      // 外层还要滚）。抢错了会把「在页签条上划一下滚列表」也挡掉。
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const SizedBox(width: 600, height: 60),
                    SizedBox(
                      width: 240,
                      child: SpringLensBar(
                        draggable: false,
                        tabSizes: const [80, 80],
                        tabs: const [
                          SpringLensTab(child: Padding(padding: EdgeInsets.all(8), child: Text('A'))),
                          SpringLensTab(child: Padding(padding: EdgeInsets.all(8), child: Text('B'))),
                        ],
                        selectedIndex: 0,
                        onSelected: (_) {},
                      ),
                    ),
                    const SizedBox(width: 600, height: 60),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final barTopLeft = tester.getRect(find.byType(SpringLensBar)).topLeft;
      final gesture = await tester.startGesture(
        _tabRect(tester, 'A').center + barTopLeft,
      );
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(-40, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        controller.offset,
        greaterThan(0),
        reason: '关掉跟手时，外层应当照旧收得到这次拖动',
      );
    });
  });
}
