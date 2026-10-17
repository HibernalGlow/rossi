import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/workspace/model/library_presentation_preferences.dart';
import 'package:zephyr/workspace/service/library_presentation_store.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_fill.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_tile.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation_button.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry_list.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view_mode.dart';
import 'package:zephyr/i18n/strings.g.dart';

const _entry = LibraryEntry(key: 'book', title: '作品封面');

Future<void> _tapCover(WidgetTester tester) async {
  final wall = find.byType(LibraryEditorialTile);
  if (wall.evaluate().isNotEmpty) {
    await tester.tapAt(tester.getTopLeft(wall.first) + const Offset(12, 12));
  } else {
    await tester.tap(find.text(_entry.title));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('旧设置和未知点击行为保留宿主默认；新设置可单独同步、往返', () {
    for (final json in [
      <String, dynamic>{},
      {'coverTapAction': 'future'},
    ]) {
      final value = LibraryPresentation.fromJson(json);
      expect(value.expandsOnCoverTap(defaultValue: true), isTrue);
      expect(value.expandsOnCoverTap(defaultValue: false), isFalse);
    }
    expect(
      LibraryPresentationPreferences.parsePresentation({
        'coverTapAction': 'future',
      }),
      isNull,
    );
    for (final action in LibraryCoverTapAction.values) {
      final value = LibraryPresentationPreferences.parsePresentation({
        'coverTapAction': action.name,
      })!;
      expect(value.coverTapAction, action);
      expect(value.copyWith(cardWidth: 200).coverTapAction, action);
      expect(
        LibraryPresentation.fromJson(
          jsonDecode(jsonEncode(value.toJson())),
        ).coverTapAction,
        action,
      );
    }
  });

  for (final scope in ['bookmarks', 'reading-history']) {
    for (final editorial in [true, false]) {
      testWidgets('$scope ${editorial ? '展墙' : '普通视图'}：封面打开新视图，信息键独立展开', (
        tester,
      ) async {
        await LibraryPresentationStore.instance.save(
          scope,
          LibraryPresentation(
            hero: false,
            editorial: editorial,
            coverTapAction: LibraryCoverTapAction.openDetails,
          ),
        );
        var opened = 0;
        final key = GlobalKey<LibraryEditorialCanvasState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LibraryEntryList(
                editorialKey: key,
                editorialScope: scope,
                mode: LibraryViewMode.coverGrid,
                standalone: true,
                entries: const [_entry],
                onTap: (_) => opened++,
                detailBuilder: (_, entry, close) =>
                    SizedBox(height: 80, child: Text('详情 ${entry.key}')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _tapCover(tester);
        await tester.pumpAndSettle();
        expect(opened, 1);
        expect(find.text('详情 book'), findsNothing);
        await tester.tap(find.byTooltip('展开信息'));
        await tester.pumpAndSettle();
        expect(find.text('详情 book'), findsOneWidget);
        expect(opened, 1);
        expect(key.currentState!.expandedEntries.single.key, 'book');
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final (width, textScale) in [
    (220.0, 1.6),
    (480.0, 1.0),
    (1100.0, 1.0),
  ]) {
    testWidgets('$width 宽度：展墙设置修改、取消、恢复默认与重新加载封面行为', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var opened = 0;
      final key = GlobalKey<LibraryEditorialCanvasState>();
      Widget app() => MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: width == 220 ? Brightness.dark : Brightness.light,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: width == 220,
          ),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(actions: [LibraryPresentationButton(canvasKey: key)]),
          body: LibraryEditorialCanvas(
            key: key,
            scope: 'settings',
            standalone: true,
            tapOpensDetail: false,
            entries: const [_entry],
            initialPresentation: const LibraryPresentation(hero: false),
            onTap: (_) => opened++,
            legacyBuilder: (_) => const SizedBox(),
            detailBuilder: (_, entry, close) =>
                SizedBox(height: 80, child: Text('详情 ${entry.key}')),
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      Future<void> openCoverTab() async {
        final dock = find.byKey(const ValueKey('wall-settings-tabs'));
        await tester.ensureVisible(dock);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: dock,
            matching: find.text(t.workspace.wallTabCover),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> choose(String label) async {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pump();
      }

      await tester.tap(find.byTooltip(LibraryPresentationButton.tooltip));
      await tester.pumpAndSettle();
      // 封面向导已经收进「封面」页签，先切过去再断言。
      await openCoverTab();
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('library-cover-tap-openDetails')),
            )
            .selected,
        isTrue,
      );
      await choose('向下展开详情');
      await tester.tap(find.byKey(const ValueKey('wall-settings-apply')));
      await tester.pumpAndSettle();
      expect(
        (await LibraryPresentationStore.instance.read(
          'settings',
        ))!.coverTapAction,
        LibraryCoverTapAction.expandDetails,
      );
      await _tapCover(tester);
      await tester.pumpAndSettle();
      expect(find.text('详情 book'), findsOneWidget);
      expect(opened, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await _tapCover(tester);
      await tester.pumpAndSettle();
      expect(find.text('详情 book'), findsOneWidget);
      expect(opened, 0);
      await tester.tap(find.byTooltip(LibraryPresentationButton.tooltip));
      await tester.pumpAndSettle();
      await openCoverTab();
      await choose('打开详情页');
      await tester.tap(find.byKey(const ValueKey('wall-settings-cancel')));
      await tester.pumpAndSettle();
      expect(
        (await LibraryPresentationStore.instance.read(
          'settings',
        ))!.coverTapAction,
        LibraryCoverTapAction.expandDetails,
      );
      await tester.tap(find.byTooltip(LibraryPresentationButton.tooltip));
      await tester.pumpAndSettle();
      await openCoverTab();
      await tester.tap(find.byKey(const ValueKey('wall-settings-reset')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('wall-settings-apply')));
      await tester.pumpAndSettle();
      await _tapCover(tester);
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(find.text('详情 book'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('自定义封面的内层手势使用同一设置', (tester) async {
    await LibraryPresentationStore.instance.save(
      'custom',
      const LibraryPresentation(
        hero: false,
        coverTapAction: LibraryCoverTapAction.openDetails,
      ),
    );
    var opened = 0;
    final entry = LibraryEntry(
      key: 'nested',
      title: '内层封面',
      media:
          (
            context, {
            required width,
            required height,
            required radius,
            required fit,
          }) => GestureDetector(
            onTap: () =>
                LibraryInlineDetailScope.maybeOf(context)!.onCoverTap(),
            child: const ColoredBox(
              key: ValueKey('nested-cover'),
              color: Colors.teal,
            ),
          ),
    );
    final key = GlobalKey<LibraryEditorialCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryEditorialCanvas(
            key: key,
            scope: 'custom',
            standalone: true,
            entries: [entry],
            onTap: (_) => opened++,
            legacyBuilder: (_) => const SizedBox(),
            detailBuilder: (_, entry, close) => const Text('原位详情'),
            // 这条判据只关心「内层封面手势是不是同一套设置」；关掉空隙填充，
            // 免得拼贴小组件把那同一份封面素材铺满空隙、让 finder 命中 13 次。
            initialPresentation: const LibraryPresentation(
              hero: false,
              gapFill: LibraryGapFill.off,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 空隙小组件会拿同一份封面素材铺满空隙，同一把 key 会出现多次；
    // 这条判据要的是墙上那张卡里的内层手势，所以限定在卡片子树里找。
    Finder nestedCover() => find.descendant(
      of: find.byType(LibraryEditorialTile),
      matching: find.byKey(const ValueKey('nested-cover')),
    );
    await tester.tap(nestedCover());
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.text('原位详情'), findsNothing);
    await LibraryPresentationStore.instance.save(
      'custom',
      const LibraryPresentation(
        hero: false,
        gapFill: LibraryGapFill.off,
        coverTapAction: LibraryCoverTapAction.expandDetails,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(nestedCover());
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.text('原位详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('不支持原位详情的条目沿用导航，禁用态不响应两个入口', (tester) async {
    var opened = 0;
    Future<void> pump({required bool enabled, required bool hasDetail}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryEditorialCanvas(
              scope: 'guard',
              standalone: true,
              entries: const [_entry],
              enabled: enabled,
              canShowDetail: (_) => false,
              initialPresentation: const LibraryPresentation(
                hero: false,
                coverTapAction: LibraryCoverTapAction.expandDetails,
              ),
              onTap: (_) => opened++,
              legacyBuilder: (_) => const SizedBox(),
              detailBuilder: hasDetail
                  ? (_, entry, close) => const Text('原位详情')
                  : null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump(enabled: true, hasDetail: true);
    await _tapCover(tester);
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.byTooltip('展开信息'), findsNothing);
    expect(find.text('原位详情'), findsNothing);
    await pump(enabled: false, hasDetail: true);
    await _tapCover(tester);
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.byTooltip('展开信息'), findsNothing);
    await pump(enabled: true, hasDetail: false);
    await _tapCover(tester);
    await tester.pumpAndSettle();
    expect(opened, 2);
    expect(tester.takeException(), isNull);
  });
}
