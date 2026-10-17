import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/workspace/model/library_presentation_preferences.dart';
import 'package:zephyr/workspace/service/library_presentation_store.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view_mode.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation_button.dart';
import 'package:zephyr/i18n/strings.g.dart';

Future<T> finish<T>(WidgetTester tester, Future<T> operation) async {
  await tester.pump();
  return operation;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final scope in ['bookmarks', 'reading-history', 'reader-pages']) {
    testWidgets('$scope 恢复底层样式不关闭已保存展墙，回收重建仍开启', (tester) async {
      final store = LibraryPresentationStore.instance;
      await finish(
        tester,
        store.save(
          scope,
          const LibraryPresentation(
            editorial: true,
            hero: false,
            weight: LibraryWeight.imageShape,
            cardWidth: 210,
          ),
        ),
      );
      final key = GlobalKey<LibraryEditorialCanvasState>();
      Widget page(LibraryViewMode mode) => MaterialApp(
        home: Scaffold(
          body: LibraryEditorialCanvas(
            key: key,
            scope: scope,
            viewToken: mode,
            initialPresentation: const LibraryPresentation(
              editorial: false,
              hero: false,
            ),
            entries: const [LibraryEntry(key: 'book', title: '展墙内容')],
            onTap: (_) {},
            legacyBuilder: (_) => const Text('传统视图'),
          ),
        ),
      );
      await tester.pumpWidget(page(LibraryViewMode.coverList));
      await tester.pumpAndSettle();
      expect(find.text('传统视图'), findsNothing);
      // 宿主异步恢复列表样式，模拟书签和历史的 _restoreViewState。
      await tester.pumpWidget(page(LibraryViewMode.details));
      await tester.pumpAndSettle();
      expect(find.text('传统视图'), findsNothing);
      final saved = await finish(tester, store.readAll());
      expect(saved[scope]!.presentation.editorial, isTrue);
      expect(saved[scope]!.presentation.cardWidth, 210);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page(LibraryViewMode.coverList));
      await tester.pumpAndSettle();
      expect(find.text('传统视图'), findsNothing);
      // 手动选择普通样式仍然关闭展墙，并把明确的选择持久化。
      key.currentState!.showLegacyView();
      await tester.pumpAndSettle();
      expect(find.text('传统视图'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page(LibraryViewMode.details));
      await tester.pumpAndSettle();
      expect(find.text('传统视图'), findsOneWidget);
      final disabled = await finish(tester, store.read(scope));
      expect(disabled!.editorial, isFalse);
      expect(disabled.cardWidth, 210);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('手动启用并应用后销毁面板，重新打开仍保留启用与尺寸设置', (tester) async {
    final key = GlobalKey<LibraryEditorialCanvasState>();
    Widget page() => MaterialApp(
      home: Scaffold(
        appBar: AppBar(actions: [LibraryPresentationButton(canvasKey: key)]),
        body: LibraryEditorialCanvas(
          key: key,
          scope: 'reader-pages',
          initialPresentation: const LibraryPresentation(
            editorial: false,
            hero: false,
          ),
          entries: const [LibraryEntry(key: 'page', title: '页面')],
          onTap: (_) {},
          legacyBuilder: (_) => const Text('传统视图'),
        ),
      ),
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('传统视图'), findsOneWidget);
    await tester.tap(find.byTooltip(LibraryPresentationButton.tooltip));
    await tester.pumpAndSettle();
    // 「展墙」开关在「布局」页签里（底部导航条）。
    final dock = find.byKey(const ValueKey('wall-settings-tabs'));
    await tester.ensureVisible(dock);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: dock, matching: find.text(t.workspace.wallTabLayout)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('展墙'));
    await tester.tap(find.text('展墙'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wall-settings-apply')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('传统视图'), findsNothing);
    expect(
      (await finish(
        tester,
        LibraryPresentationStore.instance.read('reader-pages'),
      ))!.editorial,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('同步更新已打开的对应面板，其他位置保持自己的设置', (tester) async {
    final seen = <String, LibraryPresentation>{};
    Widget canvas(String scope) => Expanded(
      child: LibraryEditorialCanvas(
        scope: scope,
        initialPresentation: const LibraryPresentation(hero: false),
        entries: [LibraryEntry(key: scope, title: scope)],
        onTap: (_) {},
        onPresentationChanged: (value) => seen[scope] = value,
        legacyBuilder: (_) => Text('$scope 传统视图'),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(children: [canvas('bookmarks'), canvas('reading-history')]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('bookmarks 传统视图'), findsNothing);
    await finish(
      tester,
      LibraryPresentationStore.instance.apply({
        'bookmarks': const LibraryPresentationPreference(
          LibraryPresentation(
            editorial: false,
            weight: LibraryWeight.imageShape,
          ),
          100,
        ),
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('bookmarks 传统视图'), findsOneWidget);
    expect(find.text('reading-history 传统视图'), findsNothing);
    expect(seen['bookmarks']!.weight, LibraryWeight.imageShape);
    expect(seen.containsKey('reading-history'), isFalse);
    final snapshot = await finish(
      tester,
      LibraryPresentationStore.instance.readAll(),
    );
    expect(snapshot['bookmarks']!.updatedAt, 100);
    expect(snapshot.containsKey('reading-history'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('同一宿主换分类读取对应偏好，返回原分类保持独立；卸载后同步无异常', (tester) async {
    final store = LibraryPresentationStore.instance;
    await finish(
      tester,
      store.save('home:favorite', const LibraryPresentation(editorial: false)),
    );
    await finish(
      tester,
      store.save('home:history', const LibraryPresentation(hero: false)),
    );
    final key = GlobalKey<LibraryEditorialCanvasState>();
    Widget page(String scope) => MaterialApp(
      home: Scaffold(
        body: LibraryEditorialCanvas(
          key: key,
          scope: scope,
          entries: const [LibraryEntry(key: 'book', title: '作品')],
          onTap: (_) {},
          legacyBuilder: (_) => const Text('传统视图'),
        ),
      ),
    );
    await tester.pumpWidget(page('home:favorite'));
    await tester.pumpAndSettle();
    expect(find.text('传统视图'), findsOneWidget);
    await tester.pumpWidget(page('home:history'));
    await tester.pumpAndSettle();
    expect(find.text('传统视图'), findsNothing);
    await tester.pumpWidget(page('home:favorite'));
    await tester.pumpAndSettle();
    expect(find.text('传统视图'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await finish(
      tester,
      store.apply({
        'home:favorite': LibraryPresentationPreference(
          const LibraryPresentation(),
          DateTime.now().millisecondsSinceEpoch + 1000,
        ),
      }),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
