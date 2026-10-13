import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/bookshelf/widgets/shelf_search_field.dart';
import 'package:zephyr/page/search/widget/search_input_dialog.dart';
import 'package:zephyr/widgets/search/search_history_field.dart';
import 'package:zephyr/widgets/search/search_history_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SearchHistoryStore> seed(String scope) async {
    final store = SearchHistoryStore.local(scope);
    await store.record('alpha');
    await store.record('alpine');
    return store;
  }

  testWidgets(
    'official autocomplete filters history; typed Enter is preserved',
    (tester) async {
      final store = await seed('typed');
      final submissions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchHistoryField(
              history: store,
              autofocus: true,
              onSubmitted: submissions.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Autocomplete<String>), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'al');
      await tester.pumpAndSettle();
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('alpine'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(submissions, ['al']);
      expect((await store.load()).first, 'al');
    },
  );

  testWidgets(
    'keyboard history selection updates controller, filter and submission once',
    (tester) async {
      final store = await seed('keyboard');
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final changes = <String>[];
      final submissions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchHistoryField(
              history: store,
              controller: controller,
              autofocus: true,
              onChanged: changes.add,
              onSubmitted: submissions.add,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'al');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(submissions, ['alpha']);
      expect(changes.last, 'alpha');
      expect(controller.text, 'alpha');
    },
  );

  testWidgets('live filtering saves only the finished term on blur', (
    tester,
  ) async {
    final store = SearchHistoryStore.local('blur');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SearchHistoryField(history: store, autofocus: true),
              const TextField(key: Key('other')),
            ],
          ),
        ),
      ),
    );
    final field = find.byType(TextField).first;
    await tester.enterText(field, 'p');
    await tester.enterText(field, 'pa');
    await tester.enterText(field, 'parody:"full term"');
    expect(await store.load(), isEmpty);
    await tester.tap(find.byKey(const Key('other')));
    await tester.pumpAndSettle();
    expect(await store.load(), ['parody:"full term"']);
  });

  testWidgets('history menu replays and clears only its own scope', (
    tester,
  ) async {
    final store = await seed('menu');
    final other = SearchHistoryStore.local('other-menu');
    await other.record('keep');
    final submissions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchHistoryField(
            history: store,
            onSubmitted: submissions.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(t.search.history));
    await tester.pumpAndSettle();
    await tester.tap(find.text('alpha'));
    await tester.pumpAndSettle();
    expect(submissions, ['alpha']);
    await tester.tap(find.byTooltip(t.search.history));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.search.clearHistory));
    await tester.pumpAndSettle();
    expect(await store.load(), isEmpty);
    expect(await other.load(), ['keep']);
  });

  testWidgets(
    'expanded online search accepts history without dismissing before selection',
    (tester) async {
      final store = await seed('expanded');
      final submissions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchQueryField(
              query: '',
              autoExpand: true,
              history: store,
              onSubmitted: submissions.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'al');
      await tester.pumpAndSettle();
      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();
      expect(submissions, ['alpha']);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mobile shelf replays history and keeps focus for continued filtering',
    (tester) async {
      final store = await seed('mobile-shelf');
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final submissions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShelfSearchField(
              query: '',
              focusNode: focus,
              hintText: '搜索书架',
              historyScope: 'mobile-shelf',
              onChanged: (_) {},
              onSubmitted: submissions.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'al');
      await tester.pumpAndSettle();
      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();
      expect(submissions, ['alpha']);
      expect(focus.hasFocus, isTrue);
      expect((await store.load()).first, 'alpha');
    },
  );

  testWidgets(
    'expanded search history menu keeps the input alive until replay',
    (tester) async {
      final store = await seed('expanded-menu');
      final submissions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchQueryField(
              query: '',
              autoExpand: true,
              history: store,
              onSubmitted: submissions.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(t.search.history));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.tap(find.text('alpha').last);
      await tester.pumpAndSettle();
      expect(submissions, ['alpha']);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'history appears on focus with an empty query and follows scope changes',
    (tester) async {
      final first = await seed('scope-first');
      final second = SearchHistoryStore.local('scope-second');
      await second.record('second-only');
      Widget field(SearchHistoryStore history) => MaterialApp(
        home: Scaffold(
          body: SearchHistoryField(history: history, autofocus: true),
        ),
      );
      await tester.pumpWidget(field(first));
      await tester.pumpAndSettle();
      expect(find.text('alpha'), findsOneWidget);
      await tester.pumpWidget(field(second));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(t.search.history));
      await tester.pumpAndSettle();
      expect(find.text('alpha'), findsNothing);
      expect(find.text('second-only'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('store errors never block regular searching', (tester) async {
    final store = CallbackSearchHistoryStore(
      scope: 'broken',
      read: () => throw StateError('offline'),
      write: (_) => throw StateError('offline'),
      reset: () => throw StateError('offline'),
    );
    final submissions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchHistoryField(
            history: store,
            onSubmitted: submissions.add,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'search anyway');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(submissions, ['search anyway']);
    expect(tester.takeException(), isNull);
  });
}
