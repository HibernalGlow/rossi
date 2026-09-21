import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/reader/ambient_palette.dart';
import 'package:zephyr/reader/reader_ambient_background.dart';

/// 一份形状与 Rust 侧 `ambient::AmbientPalette::to_probe_json` 一致的探针值。
Map<String, Object?> probeFixture({
  String average = '#804020',
  String topColor = '#ff0000',
  String rightColor = '#00ff00',
  String bottomColor = '#0000ff',
  String leftColor = '#ffff00',
}) {
  List<String> stops(String color) =>
      List<String>.filled(ReaderAmbientPalette.stops, color);
  return <String, Object?>{
    'average': average,
    'top': stops(topColor),
    'right': stops(rightColor),
    'bottom': stops(bottomColor),
    'left': stops(leftColor),
  };
}

void main() {
  group('ReaderAmbientPalette.fromProbe', () {
    test('正常形状解析出四条边与代表色', () {
      final palette = ReaderAmbientPalette.fromProbe(probeFixture());

      expect(palette, isNotNull);
      expect(palette!.average, const Color(0xFF804020));
      expect(palette.top, everyElement(const Color(0xFFFF0000)));
      expect(palette.right, everyElement(const Color(0xFF00FF00)));
      expect(palette.bottom, everyElement(const Color(0xFF0000FF)));
      expect(palette.left, everyElement(const Color(0xFFFFFF00)));
      expect(palette.top.length, ReaderAmbientPalette.stops);
    });

    test('Rust 侧报 null（这一页没采到）时返回 null', () {
      expect(ReaderAmbientPalette.fromProbe(null), isNull);
    });

    test('缺字段时整份丢掉，不做半份兜底', () {
      // 半份调色板会让背景出现「某一条边是黑的」这种莫名其妙的效果，
      // 而整份丢掉只是退回静态底色 —— 后者是用户能理解的结果。
      for (final broken in <Map<String, Object?>>[
        probeFixture()..remove('left'),
        probeFixture()..remove('average'),
        probeFixture()..['right'] = const <String>[],
        probeFixture()..['top'] = 'not-a-list',
      ]) {
        expect(
          ReaderAmbientPalette.fromProbe(broken),
          isNull,
          reason: '这一份本该被判为不可用: $broken',
        );
      }
    });

    test('颜色认不出时也整份丢掉（"认不出"不等于"就是黑"）', () {
      expect(
        ReaderAmbientPalette.fromProbe(probeFixture(average: 'nope')),
        isNull,
      );
      expect(
        ReaderAmbientPalette.fromProbe(probeFixture(topColor: '#12')),
        isNull,
      );
    });

    test('接受 8 位 #aarrggbb', () {
      final palette = ReaderAmbientPalette.fromProbe(
        probeFixture(average: '#ff112233'),
      );
      expect(palette?.average, const Color(0xFF112233));
    });
  });

  group('ReaderAmbientPalette.flat / lerpTo', () {
    test('flat 的四条边与代表色都是同一个颜色', () {
      final flat = ReaderAmbientPalette.flat(const Color(0xFF123456));

      expect(flat.average, const Color(0xFF123456));
      for (final edge in <List<Color>>[
        flat.top,
        flat.right,
        flat.bottom,
        flat.left,
      ]) {
        expect(edge.length, ReaderAmbientPalette.stops);
        expect(edge, everyElement(const Color(0xFF123456)));
      }
    });

    test('t=0 与 t=1 取到两端，t=0.5 真的变了', () {
      final from = ReaderAmbientPalette.flat(const Color(0xFF000000));
      final to = ReaderAmbientPalette.flat(const Color(0xFFFFFFFF));

      expect(from.lerpTo(to, 0).average, const Color(0xFF000000));
      expect(from.lerpTo(to, 1).average, const Color(0xFFFFFFFF));
      // 「变了」这条不能省：只断言两端的话，插值函数写成 `return t < 1 ? from : to`
      // 也能全绿 —— 而那正是过渡看起来"卡一下再跳"的成因。
      final mid = from.lerpTo(to, 0.5).average;
      expect(mid, isNot(const Color(0xFF000000)));
      expect(mid, isNot(const Color(0xFFFFFFFF)));
      expect(mid.r, closeTo(0.5, 0.01));
    });

    test('色标个数不一致时不抛异常（按下标记并夹紧）', () {
      final few = ReaderAmbientPalette.fromProbe(<String, Object?>{
        'average': '#000000',
        'top': <String>['#111111'],
        'right': <String>['#111111'],
        'bottom': <String>['#111111'],
        'left': <String>['#111111'],
      })!;
      final many = ReaderAmbientPalette.flat(const Color(0xFFFFFFFF));

      expect(() => few.lerpTo(many, 0.5), returnsNormally);
      expect(few.lerpTo(many, 0.5).top.length, ReaderAmbientPalette.stops);
    });
  });

  group('值相等语义（publish 的「同值不写」靠它）', () {
    test('内容相同的两份调色板相等，hashCode 一致', () {
      final ReaderAmbientPalette a = ReaderAmbientPalette.flat(
        const Color(0xFF334455),
      );
      final ReaderAmbientPalette b = ReaderAmbientPalette.flat(
        const Color(0xFF334455),
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('代表色或任一边不同都不相等', () {
      final ReaderAmbientPalette base = ReaderAmbientPalette.flat(
        const Color(0xFF808080),
      );

      // 只换代表色。
      expect(
        base,
        isNot(
          equals(
            ReaderAmbientPalette(
              average: const Color(0xFF707070),
              top: base.top,
              right: base.right,
              bottom: base.bottom,
              left: base.left,
            ),
          ),
        ),
      );

      // 只换一条边的一个色标 —— 翻页时最常见的差异就是这个量级。
      final List<Color> edge = List<Color>.of(base.top);
      edge[3] = const Color(0xFF101010);
      expect(
        base,
        isNot(
          equals(
            ReaderAmbientPalette(
              average: base.average,
              top: edge,
              right: base.right,
              bottom: base.bottom,
              left: base.left,
            ),
          ),
        ),
      );
    });

    test('publish 连发两份不同的调色板，第二份必须真的生效', () {
      // 这条判据钉死的是一个真 bug：publish 曾用 `toString()` 判「同值」，可默认
      // toString 不含字段值，两个不同的实例比出来永远相等 —— 第二份永远写不进去，
      // 背景色翻页后冻在第一页。
      final ReaderAmbientStore store = ReaderAmbientStore.forTest();
      int notifications = 0;
      store.palette.addListener(() => notifications++);

      store.publish(ReaderAmbientPalette.flat(const Color(0xFF111111)));
      expect(store.palette.value!.average, const Color(0xFF111111));

      store.publish(ReaderAmbientPalette.flat(const Color(0xFFEEEEEE)));
      expect(
        store.palette.value!.average,
        const Color(0xFFEEEEEE),
        reason: '第二份不同的调色板必须真的写入，而不是被错误的同值判断挡掉',
      );
      expect(notifications, 2);
    });

    test('publish 同值不重复通知（值相等语义挡住）', () {
      final ReaderAmbientStore store = ReaderAmbientStore.forTest();
      int notifications = 0;
      store.palette.addListener(() => notifications++);

      store.publish(ReaderAmbientPalette.flat(const Color(0xFF222222)));
      // 内容一致但对象不同 —— 也要被值相等挡住。
      store.publish(ReaderAmbientPalette.flat(const Color(0xFF222222)));
      store.publish(null);
      store.publish(null);

      expect(notifications, 2);
    });
  });

  group('ReaderAmbientPalette.dimmed', () {
    test('0 不压暗、100 全黑、50 真的暗了一半', () {
      final palette = ReaderAmbientPalette.flat(const Color(0xFF808080));
      final double original = palette.average.r; // 0x80 / 255 ≈ 0.502

      expect(palette.dimmed(0).average, const Color(0xFF808080));
      expect(palette.dimmed(100).average, const Color(0xFF000000));

      // 「真的暗了一半」：0x80 的一半是 0x40，也就是 0.25 附近。
      // 这条不能只写「变了」—— 写成 `* 0.99` 也算变了，而那样白纸边色
      // 在暗环境里依然是一块刺眼光斑，正是压暗这一档要防的事。
      final dimmed = palette.dimmed(50).average;
      expect(dimmed.r, closeTo(original * 0.5, 0.02));
      expect(dimmed.g, closeTo(original * 0.5, 0.02));
      expect(dimmed.b, closeTo(original * 0.5, 0.02));

      // 默认档位（45）也得真的暗掉一档，而不是差之毫厘。
      expect(palette.dimmed(45).average.r, lessThan(original * 0.6));
    });

    test('四条边一起压暗（不能只压代表色）', () {
      final palette = ReaderAmbientPalette.flat(const Color(0xFF808080));
      final dimmed = palette.dimmed(50);

      for (final edge in <List<Color>>[
        dimmed.top,
        dimmed.right,
        dimmed.bottom,
        dimmed.left,
      ]) {
        // 上界取 0.30 而不是「小于原值」：0x808080 压一半是 0.251，
        // 只写"小于原值"的话，只压了 1% 也能过。
        expect(edge.every((Color c) => c.r < 0.30), isTrue);
      }
    });
  });

  group('edgeGradient', () {
    test('色标数与位置数一致，且首个为 0、末个为 0.70、严格递增', () {
      final gradient = edgeGradient(
        stops: List<Color>.filled(
          ReaderAmbientPalette.stops,
          const Color(0xFF123456),
        ),
        fade: const Color(0xFF000000),
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );

      expect(gradient.colors.length, gradient.stops!.length);
      expect(gradient.stops!.first, 0);
      expect(gradient.stops!.last, closeTo(0.70, 1e-9));
      for (var i = 1; i < gradient.stops!.length; i++) {
        // 位置不递增的话，整条边会糊成一色 —— 而那种错在画面上
        // 看起来只是"渐变不好看"，不会有人去查。
        expect(
          gradient.stops![i],
          greaterThan(gradient.stops![i - 1]),
          reason: '第 $i 个 stop 没有比前一个大：${gradient.stops}',
        );
      }
      expect(gradient.begin, Alignment.topCenter);
      expect(gradient.end, Alignment.bottomCenter);
    });

    test('只有一个色标时仍然给出合法的渐变', () {
      final gradient = edgeGradient(
        stops: const <Color>[Color(0xFF123456)],
        fade: const Color(0xFF000000),
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      );
      expect(gradient.colors.length, 2);
      expect(gradient.stops, <double>[0, 0.70]);
    });
  });

  group('ReaderAmbientBackground', () {
    /// 收窄到**背景层自己**的 `ColoredBox`。
    ///
    /// 不能写全局 `find.byType(ColoredBox).first`：测试树里 `MaterialApp` /
    /// `Scaffold` 自身就带一个全透明的 `ColoredBox` 且排在前面，那样断言
    /// 变成在校验框架而不是在校验背景层（实测抓到 `alpha=0.0`，红过一次）。
    Finder ambientColoredBox() => find.descendant(
      of: find.byType(ReaderAmbientBackground),
      matching: find.byType(ColoredBox),
    );

    Finder ambientColoredBoxWith(Color color) => find.descendant(
      of: find.byType(ReaderAmbientBackground),
      matching: find.byWidgetPredicate(
        (Widget w) => w is ColoredBox && w.color == color,
      ),
    );

    Future<void> pump(
      WidgetTester tester, {
      required bool enabled,
      required bool edgeMode,
      required ReaderAmbientPalette? value,
      Color baseColor = const Color(0xFF000000),
      int dimPercent = 0,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderAmbientBackground(
              baseColor: baseColor,
              palette: ValueNotifier<ReaderAmbientPalette?>(value),
              enabled: enabled,
              edgeMode: edgeMode,
              dimPercent: dimPercent,
              // 关掉过渡：判据只关心"画出来是什么颜色"，
              // 不等 300 ms 动画，也就不会把它写成"等够时间就绿"的假判据。
              animate: false,
            ),
          ),
        ),
      );
    }

    testWidgets('没开自适应档位时画的是静态底色', (WidgetTester tester) async {
      await pump(
        tester,
        enabled: false,
        edgeMode: false,
        value: ReaderAmbientPalette.flat(const Color(0xFFFF0000)),
        baseColor: const Color(0xFF00FF00),
      );

      // 两条一起看：底色是绿的，**且**那一份红调色板没有被采纳。
      expect(ambientColoredBoxWith(const Color(0xFF00FF00)), findsOneWidget);
      expect(ambientColoredBox(), findsOneWidget);
    });

    testWidgets('开了自适应且有调色板时画的是压暗后的代表色', (WidgetTester tester) async {
      await pump(
        tester,
        enabled: true,
        edgeMode: false,
        value: ReaderAmbientPalette.flat(const Color(0xFF808080)),
        dimPercent: 50,
      );

      final Finder boxes = ambientColoredBox();
      expect(boxes, findsOneWidget);
      final ColoredBox box = tester.widget<ColoredBox>(boxes);
      // alpha 也得看：`Color.from` 忘了给 alpha 时三通道一样对，画出来却是全透明。
      expect(box.color.a, 1);
      expect(box.color.r, closeTo(0.25, 0.02));
      expect(box.color.g, closeTo(0.25, 0.02));
      expect(box.color.b, closeTo(0.25, 0.02));
    });

    testWidgets('开了自适应但还没有调色板时退回静态底色（不是黑屏）', (WidgetTester tester) async {
      await pump(
        tester,
        enabled: true,
        edgeMode: false,
        value: null,
        baseColor: const Color(0xFF00FF00),
      );

      expect(ambientColoredBoxWith(const Color(0xFF00FF00)), findsOneWidget);
      expect(ambientColoredBox(), findsOneWidget);
    });

    testWidgets('边缘渐变档位真的叠出四条边（不是只画了个底色）', (WidgetTester tester) async {
      await pump(
        tester,
        enabled: true,
        edgeMode: true,
        value: ReaderAmbientPalette.flat(const Color(0xFF404040)),
      );

      final Finder gradients = find.descendant(
        of: find.byType(ReaderAmbientBackground),
        matching: find.byWidgetPredicate(
          (Widget w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).gradient != null,
        ),
      );
      expect(gradients, findsNWidgets(4));
      // 四条边是**叠**在代表色上的，所以底色那一块依然得在。
      expect(ambientColoredBoxWith(const Color(0xFF404040)), findsOneWidget);
    });

    testWidgets('调色板变化时只重绘这一层，且不需要等动画', (WidgetTester tester) async {
      final ValueNotifier<ReaderAmbientPalette?> notifier =
          ValueNotifier<ReaderAmbientPalette?>(
            ReaderAmbientPalette.flat(const Color(0xFF000000)),
          );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderAmbientBackground(
              baseColor: const Color(0xFF000000),
              palette: notifier,
              enabled: true,
              edgeMode: false,
              dimPercent: 0,
              animate: false,
            ),
          ),
        ),
      );
      expect(ambientColoredBoxWith(const Color(0xFF000000)), findsOneWidget);

      notifier.value = ReaderAmbientPalette.flat(const Color(0xFFFFFFFF));
      await tester.pump();

      // 「换成了新色」与「旧色不在了」两条一起断言：只写前者的话，
      // 叠了一层新底色而旧的没走也能过 —— 那在画面上是"颜色不对"，
      // 但它看起来只是"取色不准"，不会有人去查。
      expect(
        ambientColoredBoxWith(const Color(0xFFFFFFFF)),
        findsOneWidget,
        reason: '调色板换了之后背景层必须真的跟着换',
      );
      expect(ambientColoredBoxWith(const Color(0xFF000000)), findsNothing);
    });
  });
}
