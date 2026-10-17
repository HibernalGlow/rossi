import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_shape.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_widgets.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';

/// 展墙端到端：原图比例造成的不规则空隙，三档口径各画什么。
///
/// 六份条目按 mediaAspectRatio 排成三行，每行「竖封面 + 横图宽卡」，
/// 于是第 1、3 行的横图下方各留一块余量 —— 与截图里那种空白同一种成因。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpWall(
    WidgetTester tester,
    LibraryGapFill mode, {
    bool shapes = true,
    Map<String, bool> widgetToggles = const {},
  }) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.noScaling),
          child: child!,
        ),
        home: Scaffold(
          body: LibraryEditorialCanvas(
            // 每个档位一份 scope：展墙只在 scope 变化时采纳
            // initialPresentation，于是这里走的是与「换到另一个位置」
            // 完全相同的那条恢复路径。
            scope: 'gap-${mode.name}-$shapes-${widgetToggles.keys.join(",")}',
            standalone: true,
            entries: const [
              LibraryEntry(key: 'a', title: 'A', mediaAspectRatio: .5),
              LibraryEntry(key: 'b', title: 'B', mediaAspectRatio: 2.2),
              LibraryEntry(key: 'c', title: 'C', mediaAspectRatio: .6),
              LibraryEntry(key: 'd', title: 'D', mediaAspectRatio: 1.4),
              LibraryEntry(key: 'e', title: 'E', mediaAspectRatio: .5),
              LibraryEntry(key: 'f', title: 'F', mediaAspectRatio: 2.5),
            ],
            initialPresentation: LibraryPresentation(
              hero: false,
              weight: LibraryWeight.imageShape,
              gapFill: mode,
              gapShapes: shapes,
              gapWidgets: widgetToggles,
            ),
            // 这一份判据只关心「某一档怎么画」；套件锁定成唯一一款
            // 无数据门槛的组件，新增组件不会把这里的期望数改来改去。
            gapWidgets: defaultLibraryGapWidgets()
                .where((spec) => spec.id == 'gap_count')
                .toList(),
            onTap: (_) {},
            legacyBuilder: (_) => const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('并存档：一块小组件 + 一块随机图形，组件不重复', (tester) async {
    await pumpWall(tester, LibraryGapFill.both);
    expect(find.text('这一墙'), findsOneWidget);
    expect(find.byType(LibraryGapShape), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('随机图形档：两块空隙都画图形', (tester) async {
    await pumpWall(tester, LibraryGapFill.shapes);
    expect(find.byType(LibraryGapShape), findsNWidgets(2));
    expect(find.text('这一墙'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('不填充档：一块都不画（与上面两档同一份布局当阳性对照）', (tester) async {
    await pumpWall(tester, LibraryGapFill.off);
    expect(find.byType(LibraryGapShape), findsNothing);
    expect(find.text('这一墙'), findsNothing);
  });

  testWidgets('单项开关关掉唯一那款组件后，真画布里只剩随机图形', (tester) async {
    // 这一墙只有「条目数」一款装得下（没有封面/时间/进度/体积），
    // 所以把它单独关掉之后，both 档应该整体退化成两块图形 —— 证明开关
    // 一路走到了渲染，而不是只在纯函数里生效。
    await pumpWall(
      tester,
      LibraryGapFill.both,
      widgetToggles: const {'gap_count': false},
    );
    expect(find.text('这一墙'), findsNothing);
    expect(find.byType(LibraryGapShape), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('随机图形单独关掉后，both 档退化成只放组件', (tester) async {
    await pumpWall(tester, LibraryGapFill.both, shapes: false);
    // 退化后的口径是 widgets 档 —— 那一档允许重复，所以两块空隙都由
    // 唯一装得下的「条目数」认领，图形一块不画。
    expect(find.text('这一墙'), findsNWidgets(2));
    expect(find.byType(LibraryGapShape), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
