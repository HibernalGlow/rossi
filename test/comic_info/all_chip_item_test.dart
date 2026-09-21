import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_info/widgets/all_chip.dart';
import 'package:zephyr/util/layout/layout_overflow_guard.dart';
import 'package:zephyr/util/layout/quiet_flex.dart';

/// 截图里那条溢出 294px 的种子标题（`AllChipWidget.processText` 会把空格全去掉，
/// 所以它是一个「没有断点的长词」—— 这正是原来能撑破 Row 的原因）。
const String _longSeedLabel =
    '#1-[Velvet_ovo]Aisha&Sylphiette|MushokuTensei(Patreon)[AIGenerated]18.0.1';

/// 只给 300 逻辑像素的宽：远小于上面那条文案的自然宽度。
const double _hostWidth = 300;

/// 快照用的宿主边界。**必须按 key 取**：`MaterialApp`/`Scaffold`/`Overlay`
/// 自己会插若干 `RepaintBoundary`，`find.byType(RepaintBoundary).first` 命中的是它们，
/// 取到的图里根本没有被测的那个 Row。
final GlobalKey _hostBoundaryKey = GlobalKey();

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      // 必须是 `maxWidth` 的**松**约束，不能用 `SizedBox(width:)`：
      // 后者给的紧约束会把整棵子树强行撑到 300，于是「胶囊按内容宽」这类
      // 断言无论实现对不对都永远量到 300（2026-09-20 实测踩到）。
      // `Align` 会把约束 loosen 成 0..300 —— 这也更贴近真实场景：
      // chip 住在 `Wrap` / `Expanded` 里，拿到的是「最多这么宽」，不是「就得这么宽」。
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _hostWidth),
        child: RepaintBoundary(key: _hostBoundaryKey, child: child),
      ),
    ),
  ),
);

/// 在渲染结果里找「黄黑斜纹」的黄色。
///
/// 条纹是 `DebugOverflowIndicatorMixin` 用 `0xBFFFFF00`（75% 不透明）画的，
/// 叠在近白底上仍然是亮黄 ⇒ 用「红绿都高、蓝明显低」认它。
/// `AllChipItem` 的胶囊本身是白底 + 主题色描边（蓝紫系），不会落进这个区间。
Future<bool> _paintsYellowStripe(WidgetTester tester) async {
  final boundary =
      _hostBoundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;

  // 光靠开关切换**不会**让这棵子树变脏（widget 树没变、布局也没变），
  // 于是 `toImage()` 会把上一帧那张带条纹的图原样交回来 —— 假绿/假红都出过。
  // 要读「现在的开关下画的是什么」，就得显式重绘一次。
  boundary.markNeedsPaint();
  await tester.pump();

  // `toImage()` / `toByteData()` 是靠**引擎的真实事件循环**兑现 Future 的，
  // 而 `testWidgets` 默认跑在 FakeAsync 里 ⇒ 不包 `runAsync` 就永远挂着
  // （2026-09-20 实测：整条用例卡到整体超时被 SIGKILL，不是断言失败）。
  final painted = await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final bytes = data!.buffer.asUint8List();
      for (var i = 0; i + 3 < bytes.length; i += 4) {
        final r = bytes[i];
        final g = bytes[i + 1];
        final b = bytes[i + 2];
        if (r > 200 && g > 200 && b < 140) {
          return true;
        }
      }
      return false;
    } finally {
      image.dispose();
    }
  });
  return painted ?? false;
}

void main() {
  tearDown(() => setLayoutOverflowStripesEnabled(enabled: true));

  testWidgets('超长 chip 文案：一行 + 省略号，且不再溢出（无黄黑条）', (tester) async {
    await tester.pumpWidget(
      _host(
        AllChipItem(label: _longSeedLabel, onTap: () {}, onLongPress: () {}),
      ),
    );

    // 旧实现（裸 Text 塞进 Row）在这里会抛
    // `A RenderFlex overflowed by N pixels on the right.`：
    // 先断言「没有异常」，再断言那条黄黑条真的没画出来（只断言前者的话，
    // 「不建 widget 但留占位」也能过）。
    expect(tester.takeException(), isNull);
    expect(
      await _paintsYellowStripe(tester),
      isFalse,
      reason: '胶囊自己溢出时才会出现黄黑斜纹',
    );

    final text = tester.widget<Text>(find.text(_longSeedLabel));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);

    // 真的被夹在宿主宽度里（不是「文案被截断了但胶囊还是撑到屏幕外」）。
    expect(
      tester.getSize(find.byType(AllChipItem)).width,
      lessThanOrEqualTo(_hostWidth),
    );
  });

  testWidgets('短文案不受影响：胶囊按内容宽，不是被拉满', (tester) async {
    await tester.pumpWidget(
      _host(AllChipItem(label: 'AI生成', onTap: () {}, onLongPress: () {})),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(AllChipItem)).width, lessThan(120));
  });

  testWidgets('开关关掉后，自绘布局溢出也不再画条纹（仍然溢出，但不上报）', (tester) async {
    Widget overflowingRow({required bool quiet}) => _host(
      // 600 > 300：必溢出。
      quiet
          ? const QuietRow(children: [SizedBox(width: 600, height: 24)])
          : const Row(children: [SizedBox(width: 600, height: 24)]),
    );

    // 基线一：框架的 Row 的确会溢出、也的确画条纹（否则下面两条断言没意义）。
    await tester.pumpWidget(overflowingRow(quiet: false));
    expect(tester.takeException(), isA<FlutterError>());
    expect(await _paintsYellowStripe(tester), isTrue);

    // 基线二：开关开着时，QuietRow 与框架行为一致。
    setLayoutOverflowStripesEnabled(enabled: true);
    await tester.pumpWidget(overflowingRow(quiet: true));
    expect(tester.takeException(), isA<FlutterError>());
    expect(await _paintsYellowStripe(tester), isTrue);

    // 开关关掉：同样溢出，条纹与错误上报一起消失。
    setLayoutOverflowStripesEnabled(enabled: false);
    await tester.pumpWidget(overflowingRow(quiet: true));
    expect(tester.takeException(), isNull);
    expect(await _paintsYellowStripe(tester), isFalse);
  });
}
