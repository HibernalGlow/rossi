import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry_list.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view_mode.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_timeline_view.dart';

class _StatefulDetail extends StatefulWidget {
  const _StatefulDetail({
    required this.id,
    required this.loaded,
    required this.close,
  });
  final String id;
  final VoidCallback loaded;
  final VoidCallback close;
  @override
  State<_StatefulDetail> createState() => _StatefulDetailState();
}

class _StatefulDetailState extends State<_StatefulDetail> {
  var value = 0;
  @override
  void initState() {
    super.initState();
    widget.loaded();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 140,
    child: Column(
      children: [
        Text('详情 ${widget.id} · $value'),
        TextButton(
          onPressed: () => setState(() => value++),
          child: Text('选择 ${widget.id}'),
        ),
        TextButton(onPressed: widget.close, child: Text('收起 ${widget.id}')),
      ],
    ),
  );
}

void main() {
  for (final legacy in [false, true]) {
    testWidgets('${legacy ? '传统' : '展墙'}：首帧加载，多项保持独立状态，重新展开不重复加载', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final canvas = GlobalKey<LibraryEditorialCanvasState>();
      final data = List.generate(
        3,
        (i) => LibraryEntry(key: '$i', title: '作品 $i'),
      );
      final loads = <String, int>{};
      Widget detail(BuildContext _, LibraryEntry entry, VoidCallback close) =>
          _StatefulDetail(
            id: entry.key,
            close: close,
            loaded: () =>
                loads.update(entry.key, (v) => v + 1, ifAbsent: () => 1),
          );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: legacy
                ? LibraryEntryList(
                    editorialKey: canvas,
                    editorialScope: 'multi-legacy',
                    fileStats: true,
                    mode: LibraryViewMode.coverGrid,
                    standalone: true,
                    entries: data,
                    onTap: (_) {},
                    detailBuilder: detail,
                  )
                : LibraryEditorialCanvas(
                    key: canvas,
                    scope: 'multi-wall',
                    entries: data,
                    initialPresentation: const LibraryPresentation(
                      hero: false,
                      asymmetric: false,
                    ),
                    standalone: true,
                    legacyBuilder: (_) => const SizedBox(),
                    onTap: (_) {},
                    detailBuilder: detail,
                  ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      canvas.currentState!.toggleDetails(data[0]);
      await tester.pump();
      // 不等展开动画完成，业务宿主已经挂载并开始加载。
      expect(loads['0'], 1);
      expect(
        tester.getSize(find.text('详情 0 · 0', skipOffstage: false)).height,
        greaterThan(0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择 0'));
      await tester.pump();
      canvas.currentState!.toggleDetails(data[1]);
      canvas.currentState!.toggleDetails(data[2]);
      await tester.pumpAndSettle();
      expect(find.text('详情 0 · 1'), findsOneWidget);
      expect(find.text('详情 1 · 0'), findsOneWidget);
      expect(find.text('详情 2 · 0'), findsOneWidget);
      await tester.tap(find.text('收起 1'));
      await tester.pumpAndSettle();
      expect(find.text('详情 1 · 0'), findsNothing);
      expect(find.text('详情 0 · 1'), findsOneWidget);
      expect(find.text('详情 2 · 0'), findsOneWidget);
      canvas.currentState!.toggleDetails(data[1]);
      await tester.pumpAndSettle();
      expect(loads, {'0': 1, '1': 1, '2': 1});
      expect(canvas.currentState!.closeDetails(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('详情 1 · 0'), findsNothing);
      expect(find.text('详情 0 · 1'), findsOneWidget);
      expect(find.text('详情 2 · 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('书签与历史时间线也支持独立展开，并保留收起前的状态', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final expanded = <String>{};
    final loads = <String, int>{};
    final data = List.generate(
      3,
      (i) => LibraryEntry(key: '$i', title: '时间线作品 $i'),
    );
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return ShelfTimelineView(
                entries: data,
                standalone: true,
                expandedKeys: expanded,
                timeOf: (_) => DateTime(2026, 10, 13),
                onTap: (entry) => setState(() {
                  if (!expanded.remove(entry.key)) expanded.add(entry.key);
                }),
                onCloseDetail: (key) => setState(() => expanded.remove(key)),
                detailBuilder: (_, entry, close) => _StatefulDetail(
                  id: entry.key,
                  close: close,
                  loaded: () =>
                      loads.update(entry.key, (n) => n + 1, ifAbsent: () => 1),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    update(() => expanded.addAll(['0', '1', '2']));
    await tester.pump();
    expect(loads, {'0': 1, '1': 1, '2': 1});
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择 1'));
    await tester.pump();
    await tester.tap(find.text('收起 1'));
    await tester.pumpAndSettle();
    expect(find.text('详情 1 · 1'), findsNothing);
    expect(find.text('详情 0 · 0'), findsOneWidget);
    expect(find.text('详情 2 · 0'), findsOneWidget);
    update(() => expanded.add('1'));
    await tester.pumpAndSettle();
    expect(find.text('详情 1 · 1'), findsOneWidget);
    expect(loads, {'0': 1, '1': 1, '2': 1});
    expect(tester.takeException(), isNull);
  });
}
