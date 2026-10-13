import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/search/widget/search_input_dialog.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/search/search_history_field.dart';
import 'package:zephyr/widgets/search/search_history_panel.dart';
import 'package:zephyr/widgets/search/search_history_store.dart';

class _PopupObserver extends NavigatorObserver {
  final popups = <CommonPopupRoute<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is CommonPopupRoute) popups.add(route);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SearchHistoryStore> seed(String scope) async {
    final store = SearchHistoryStore.local(scope);
    await store.record('alpha');
    await store.record('beta');
    return store;
  }

  testWidgets(
    'both entrances share one expressive route without stealing focus',
    (tester) async {
      final store = await seed('expressive-entrances');
      final observer = _PopupObserver();
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: Scaffold(
            body: SearchHistoryField(
              history: store,
              focusNode: focus,
              autofocus: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SearchHistoryPanel), findsOneWidget);
      expect(find.byType(CommonPopupSurface), findsOneWidget);
      expect(find.byType(M3EList), findsOneWidget);
      expect(observer.popups.single.modal, isFalse);
      expect(focus.hasFocus, isTrue);
      await tester.enterText(find.byType(TextField), 'alp');
      await tester.pumpAndSettle();
      expect(find.text('beta'), findsNothing);
      await tester.tap(find.byTooltip(t.search.history));
      await tester.pumpAndSettle();
      expect(find.byType(SearchHistoryPanel), findsOneWidget);
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('beta'), findsOneWidget);
      expect(focus.hasFocus, isTrue);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selection retains the unified reverse animation then removes the panel',
    (tester) async {
      final store = await seed('expressive-exit');
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
      await tester.tap(find.text('alpha'));
      await tester.pump();
      expect(submissions, ['alpha']);
      expect(find.byType(SearchHistoryPanel), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SearchHistoryPanel), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(SearchHistoryPanel), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'escape dismisses; editing reopens; Tab moves to the next input',
    (tester) async {
      final store = await seed('expressive-keys');
      final first = FocusNode();
      final second = FocusNode();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SearchHistoryField(
                  history: store,
                  focusNode: first,
                  autofocus: true,
                ),
                TextField(key: const Key('next-input'), focusNode: second),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SearchHistoryPanel), findsNothing);
      expect(first.hasFocus, isTrue);
      await tester.enterText(find.byType(TextField).first, 'alp');
      await tester.pumpAndSettle();
      expect(find.byType(SearchHistoryPanel), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(second.hasFocus, isTrue);
      expect(find.byType(SearchHistoryPanel), findsNothing);
    },
  );

  testWidgets('empty history uses the same surface and reduced motion policy', (
    tester,
  ) async {
    final observer = _PopupObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        builder: (_, child) => MediaQuery(
          data: const MediaQueryData(
            size: Size(800, 600),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SearchHistoryField(
            history: SearchHistoryStore.local('empty-expressive'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(t.search.history));
    await tester.pumpAndSettle();
    expect(find.text(t.search.noHistory), findsOneWidget);
    expect(find.byType(CommonPopupSurface), findsOneWidget);
    expect(observer.popups.single.transitionDuration, Duration.zero);
    expect(observer.popups.single.reverseTransitionDuration, Duration.zero);
    await tester.tapAt(const Offset(790, 590));
    await tester.pumpAndSettle();
    expect(find.byType(SearchHistoryPanel), findsNothing);
  });

  testWidgets('narrow viewport and long terms scroll without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = SearchHistoryStore.local('narrow-expressive');
    for (var i = 0; i < 12; i++) {
      await store.record('history $i ${'long-term ' * 20}');
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SearchHistoryField(history: store)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(t.search.history));
    await tester.pumpAndSettle();
    expect(find.byType(SearchHistoryPanel), findsOneWidget);
    expect(
      tester.getSize(find.byType(CommonPopupSurface)).width,
      lessThanOrEqualTo(288),
    );
    final viewport = find.descendant(
      of: find.byType(SearchHistoryPanel),
      matching: find.byType(SingleChildScrollView),
    );
    await tester.drag(viewport, const Offset(0, -280));
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(
      find.descendant(of: viewport, matching: find.byType(Scrollable)).first,
    );
    expect(scroll.position.pixels, greaterThan(0));
    expect(find.text(t.search.clearHistory), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing a search while its popup is open leaves no route', (
    tester,
  ) async {
    final store = await seed('dispose-expressive');
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: visible,
            builder: (_, show, _) => show
                ? SearchHistoryField(history: store, autofocus: true)
                : const Text('removed'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    visible.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(SearchHistoryPanel), findsNothing);
    expect(find.text('removed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clicking an already focused field reopens dismissed history', (
    tester,
  ) async {
    final store = await seed('retap-expressive');
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchHistoryField(
            history: store,
            focusNode: focus,
            autofocus: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SearchHistoryPanel), findsNothing);
    expect(focus.hasFocus, isTrue);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.byType(SearchHistoryPanel), findsOneWidget);
  });

  testWidgets('keyboard highlight stays visible in a short viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = SearchHistoryStore.local('scroll-highlight-expressive');
    for (var i = 0; i < 8; i++) {
      await store.record('term $i');
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchHistoryField(history: store, autofocus: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    final highlighted = tester.widget<SearchHistoryPanel>(
      find.byType(SearchHistoryPanel),
    );
    expect(highlighted.highlighted, 7);
    expect(find.text('term 0').hitTestable(), findsOneWidget);
  });

  testWidgets('history opened without input focus is removed on navigation', (
    tester,
  ) async {
    final store = await seed('navigate-expressive');
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(body: SearchHistoryField(history: store)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(t.search.history));
    await tester.pumpAndSettle();
    expect(find.byType(SearchHistoryPanel), findsOneWidget);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('next page')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('next page'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(SearchHistoryPanel), findsNothing);
    expect(find.byType(SearchHistoryField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history button uses its own compact anchor on a narrow window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await seed('compact-anchor-expressive');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: 280,
              child: SearchHistoryField(history: store),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(t.search.history));
    await tester.pumpAndSettle();
    final surface = tester.getSize(find.byType(CommonPopupSurface));
    expect(surface.width, lessThanOrEqualTo(280));
    expect(surface.width, greaterThanOrEqualTo(240));
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded search stays single line when its pane is narrow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(240, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SearchQueryField(
            query: '',
            autoExpand: false,
            hintText: '搜索列表',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索列表'));
    await tester.pumpAndSettle();
    final field = tester.widget<SearchHistoryField>(
      find.byType(SearchHistoryField),
    );
    expect(field.maxLines, 1);
    expect(tester.takeException(), isNull);
  });
}
