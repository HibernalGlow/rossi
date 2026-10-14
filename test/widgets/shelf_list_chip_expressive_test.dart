import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/expressive/expressive_blob.dart';
import 'package:zephyr/widgets/spring_lens/jelly_hover.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_list_chip.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_list_rail.dart';

Widget _harness(Widget child, {bool reduced = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Scaffold(body: Center(child: child)),
  ),
);

/// 沿轮廓走一圈取样，压成一个可比较的指纹。
///
/// 不用 `Path.toString()`：那里只有 verb 列表，边上点的**坐标**差异（正是
/// 不规则性的来源）不一定进字符串，写死的形状与生成的形状可能读起来一样。
List<double> _fingerprint(Path path) {
  final samples = <double>[];
  for (final metric in path.computeMetrics()) {
    for (var t = 0.0; t < metric.length; t += metric.length / 48) {
      final p = metric.getTangentForOffset(t);
      if (p == null) continue;
      samples
        ..add(p.position.dx)
        ..add(p.position.dy);
    }
  }
  return samples;
}

bool _sameShape(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 0.05) return false;
  }
  return true;
}

Rect _labelBox(Rect rect) => Rect.fromLTRB(
  rect.left + 14,
  rect.top + 11,
  rect.right - 14,
  rect.bottom - 11,
);

/// 读 chip 当前的缩放（x/y）。
///
/// 形变只走 paint 层，所以必须从 `JellyHover` 那颗 `Transform` 的矩阵里读；
/// `getRect`/`getSize` 永远返回静止尺寸 —— 那正是我们要保住的性质（tooltip
/// 与相邻档的点击区不被形变挤走），不能拿它当「有没有放大」的尺。
Matrix4? _jellyTransform(WidgetTester tester) => tester
    .widget<Transform>(
      find
          .descendant(
            of: find.byType(JellyHover),
            matching: find.byType(Transform),
          )
          .first,
    )
    .transform;

double _scaleX(WidgetTester tester) => _jellyTransform(tester)!.storage[0];

double _scaleY(WidgetTester tester) => _jellyTransform(tester)!.storage[5];

double _progress(WidgetTester tester) =>
    (tester.widget<ChoiceChip>(find.byType(ChoiceChip)).shape
            as ExpressiveBlobBorder)
        .progress;

void main() {
  const rect = Rect.fromLTRB(0, 0, 120, 42);

  group('形状来自种子，不来自写死的表', () {
    test('同一个 identity 永远同一个轮廓', () {
      Path build() => ExpressiveBlobBorder(
        seed: expressiveBlobSeed('/阅读计划'),
      ).getOuterPath(rect);
      expect(_sameShape(_fingerprint(build()), _fingerprint(build())), isTrue);
    });

    test('十二档列表拿到十二个不同轮廓（不是几档轮换）', () {
      final names = [
        '全部',
        '未分类',
        '/阅读计划',
        '/深夜',
        '/月光旅行者',
        '/海边的夏日',
        '/夜航日记',
        '/森林里的信',
        '/漫长的告别',
        '/星河之间',
        '/山谷与风',
        '/漂流书店',
      ];
      final shapes = [
        for (final name in names)
          _fingerprint(
            ExpressiveBlobBorder(
              seed: expressiveBlobSeed(name),
            ).getOuterPath(rect),
          ),
      ];
      for (var i = 0; i < shapes.length; i++) {
        for (var j = i + 1; j < shapes.length; j++) {
          expect(
            _sameShape(shapes[i], shapes[j]),
            isFalse,
            reason: '${names[i]} 与 ${names[j]} 拿到了同一颗形状',
          );
        }
      }
    });

    test('四十档 × 三档进度 × 两种高度：标签框全部保住，静止态又真的不规则', () {
      var cutCorner = 0;
      for (var i = 0; i < 40; i++) {
        final seed = expressiveBlobSeed('/列表 $i');
        for (final height in [42.0, 56.0]) {
          final boxRect = Rect.fromLTRB(0, 0, 120, height);
          final box = _labelBox(boxRect);
          for (final progress in [0.0, 0.5, 1.0]) {
            final path = ExpressiveBlobBorder(
              seed: seed,
              progress: progress,
              safeInset: 11,
            ).getOuterPath(boxRect);
            // 文字安全区：标签框四个角都必须在轮廓内（字号放大那档也要）。
            for (final corner in [
              box.topLeft,
              box.topRight,
              box.bottomLeft,
              box.bottomRight,
            ]) {
              expect(
                path.contains(corner),
                isTrue,
                reason:
                    '第 $i 档在 progress=$progress、高 $height 时把标签框的 '
                    '$corner 切到了轮廓外',
              );
            }
          }
          // 这把尺也要看得见「不规则」：静止态必须真的啃角。
          if (!ExpressiveBlobBorder(
            seed: seed,
          ).getOuterPath(boxRect).contains(const Offset(0.75, 0.75))) {
            cutCorner++;
          }
        }
      }
      // 实测值先量再钉，不拍脑袋：阈值取「全部样本的一半」，既容得下换 seed 的
      // 波动，也足以在形状退化回圆角矩形时报红。
      // ignore: avoid_print
      print('measured cutCorner(40 seeds x 2 heights) = $cutCorner / 80');
      expect(cutCorner, greaterThanOrEqualTo(40));
    });

    test('阳性对照：越界的框必须被判为不安全', () {
      // 同一段包含关系判据，喂一个必然越界的框 —— 全绿不等于尺有效。
      final path = ExpressiveBlobBorder(
        seed: expressiveBlobSeed('/越界对照'),
      ).getOuterPath(rect);
      final tooWide = Rect.fromLTRB(-4, 0, rect.right, rect.bottom);
      expect(path.contains(const Offset(-4, 21)), isFalse);
      expect(path.contains(tooWide.topLeft), isFalse);
    });

    test('progress=1 收成 stadium，且与不规则那一档明显不同', () {
      final rest = ExpressiveBlobBorder(
        seed: expressiveBlobSeed('/阅读计划'),
      ).getOuterPath(rect);
      final taut = ExpressiveBlobBorder(
        seed: expressiveBlobSeed('/阅读计划'),
        progress: 1,
      ).getOuterPath(rect);
      // 规范：导航的选中态用 pill/stadium。判据用端头几何 —— 胶囊的左端帽
      // 最左点应落在 x=0 且竖直中线上，而左上角 (0,0) 必须在轮廓外。
      expect(taut.contains(const Offset(0.2, 21)), isTrue, reason: '左端帽没贴住盒子');
      expect(
        taut.contains(const Offset(0.75, 0.75)),
        isFalse,
        reason: '选中态还是个方角',
      );
      expect(taut.getBounds().width, closeTo(rect.width, 1.0));
      expect(
        _sameShape(_fingerprint(rest), _fingerprint(taut)),
        isFalse,
        reason: 'progress 0 与 1 形状相同 ⇒ 状态没有写进形状',
      );
    });
  });

  group('悬停果冻', () {
    testWidgets('鼠标移上去鼓起来并过冲，移开回弹到原尺寸', (tester) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(-200, -200));
      addTearDown(gesture.removePointer);

      await tester.pumpWidget(
        _harness(ShelfListChip(label: '阅读计划', selected: false, onTap: () {})),
      );
      await tester.pumpAndSettle();
      expect(_scaleX(tester), closeTo(1, 0.001), reason: '静止时不该有形变');

      await gesture.moveTo(tester.getCenter(find.byType(ChoiceChip)));
      await tester.pump();

      // 逐帧采样：过冲必须真的出现（值越过稳态），否则「回弹」只是补间淡入。
      var maxX = 1.0;
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (_scaleX(tester) > maxX) maxX = _scaleX(tester);
      }
      final steady = 1 + JellyHover.hoverScale;
      expect(maxX, greaterThan(steady), reason: '横轴没有过冲 ⇒ 不是弹簧，是补间');
      await tester.pumpAndSettle();
      expect(_scaleX(tester), closeTo(steady, 0.02));
      expect(_scaleY(tester), closeTo(steady, 0.02));

      // 移开：回弹同样要往下过冲
      await gesture.moveTo(const Offset(-200, -200));
      await tester.pump();
      var minOnExit = 9.9;
      for (var frame = 0; frame < 45; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (_scaleX(tester) < minOnExit) minOnExit = _scaleX(tester);
      }
      expect(minOnExit, lessThan(steady), reason: '回弹没有过冲 ⇒ 读起来像淡出而不是果冻');
      await tester.pumpAndSettle();
      expect(_scaleX(tester), closeTo(1, 0.01));
    });

    testWidgets('悬停把轮廓收成一半，选中收成胶囊，静止回到不规则', (tester) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(-200, -200));
      addTearDown(gesture.removePointer);

      await tester.pumpWidget(
        _harness(ShelfListChip(label: '深夜', selected: false, onTap: () {})),
      );
      await tester.pumpAndSettle();
      expect(_progress(tester), 0);

      await gesture.moveTo(tester.getCenter(find.byType(ChoiceChip)));
      await tester.pump();
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_progress(tester), greaterThan(0.2), reason: '悬停没有改轮廓 ⇒ 形状与状态脱钩');
      expect(_progress(tester), lessThan(1.0), reason: '悬停一步到位 ⇒ 三态读不出连续形变');

      await gesture.moveTo(const Offset(-200, -200));
      await tester.pumpAndSettle();
      expect(_progress(tester), 0);

      await tester.pumpWidget(
        _harness(ShelfListChip(label: '深夜', selected: true, onTap: () {})),
      );
      await tester.pumpAndSettle();
      expect(_progress(tester), 1);
    });

    testWidgets('关掉动画时不做形变，但形状照旧不规则', (tester) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(-200, -200));
      addTearDown(gesture.removePointer);

      await tester.pumpWidget(
        _harness(
          ShelfListChip(label: '未分类', selected: false, onTap: () {}),
          reduced: true,
        ),
      );
      await tester.pumpAndSettle();
      await gesture.moveTo(tester.getCenter(find.byType(ChoiceChip)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_scaleX(tester), closeTo(1, 0.001), reason: '减少动画还被放大 ⇒ 开关没接');
      // 形状与动画无关：关掉动效不等于把这档能力藏起来。
      expect(_progress(tester), 0);
      final border =
          tester.widget<ChoiceChip>(find.byType(ChoiceChip)).shape
              as ExpressiveBlobBorder;
      expect(
        border.getOuterPath(rect).contains(const Offset(0.75, 0.75)),
        isFalse,
        reason: '减少动画时轮廓退化成了圆角矩形',
      );
    });

    testWidgets('点一下只触发一次动作，点击区按静止矩形算', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _harness(
          ShelfListChip(label: '星河之间', selected: false, onTap: () => taps++),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ChoiceChip));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('未选中档的底色必须与那条轨不同色，否则轮廓等于没画', (tester) async {
      // 渲染台实测到的真问题：chip 与轨（下沉槽）同用 `surfaceContainer` 时，
      // 静止态只剩文字，「不规则形状 → 收一半 → 胶囊」这条状态语言整个看不见。
      await tester.pumpWidget(
        _harness(
          ShelfListRail(
            onCreate: () {},
            children: [
              ShelfListChip(label: '未分类', selected: false, onTap: () {}),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scheme = Theme.of(
        tester.element(find.byType(ChoiceChip)),
      ).colorScheme;
      final chip = tester.widget<ChoiceChip>(find.byType(ChoiceChip));
      final railColor = tester
          .widget<Material>(
            find
                .ancestor(
                  of: find.byType(ChoiceChip),
                  matching: find.byType(Material),
                )
                .last,
          )
          .color;
      expect(chip.backgroundColor, scheme.surfaceContainerHigh);
      expect(
        chip.backgroundColor,
        isNot(railColor),
        reason: 'chip 与轨同色 ⇒ 轮廓读不出来，形状承载的状态全部丢失',
      );
    });
  });
}
