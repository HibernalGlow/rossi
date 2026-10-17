import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/workspace/service/library_presentation_store.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation_button.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';

Future<T> finish<T>(WidgetTester tester, Future<T> operation) async {
  await tester.pump();
  return operation;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpPage(
    WidgetTester tester,
    GlobalKey<LibraryEditorialCanvasState> key, {
    bool enabled = true,
    bool canvasEnabled = true,
    String scope = 'home:favorite',
    LibraryPresentation initial = const LibraryPresentation(
      editorial: false,
      hero: false,
    ),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              LibraryPresentationButton(canvasKey: key, enabled: enabled),
            ],
          ),
          body: LibraryEditorialCanvas(
            key: key,
            scope: scope,
            standalone: true,
            enabled: canvasEnabled,
            initialPresentation: initial,
            entries: const [LibraryEntry(key: 'book', title: '展墙内容')],
            onTap: (_) {},
            legacyBuilder: (_) => const Text('普通视图'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('长按开关：只翻转展墙，其余偏好与落盘保持不变', (tester) async {
    final key = GlobalKey<LibraryEditorialCanvasState>();
    await finish(
      tester,
      LibraryPresentationStore.instance.save(
        'home:favorite',
        const LibraryPresentation(
          editorial: false,
          hero: false,
          cardWidth: 210,
          gap: 14,
        ),
      ),
    );
    await pumpPage(tester, key);
    expect(find.text('普通视图'), findsOneWidget);

    await tester.longPress(find.byTooltip(LibraryPresentationButton.tooltip));
    await tester.pumpAndSettle();
    expect(find.text('普通视图'), findsNothing);
    expect(
      (await finish(
        tester,
        LibraryPresentationStore.instance.read('home:favorite'),
      ))!.editorial,
      isTrue,
    );

    // 再长按回到普通视图，尺寸偏好没有被这次快开关改写。
    await tester.longPress(find.byTooltip(LibraryPresentationButton.tooltip));
    await tester.pumpAndSettle();
    expect(find.text('普通视图'), findsOneWidget);
    final saved = await finish(
      tester,
      LibraryPresentationStore.instance.read('home:favorite'),
    );
    expect(saved!.editorial, isFalse);
    expect(saved.cardWidth, 210);
    expect(saved.gap, 14);
    expect(tester.takeException(), isNull);
  });

  testWidgets('单击仍然只打开设置面板，不误开关', (tester) async {
    final key = GlobalKey<LibraryEditorialCanvasState>();
    await pumpPage(tester, key);
    await tester.tap(find.byTooltip(LibraryPresentationButton.tooltip));
    await tester.pumpAndSettle();
    expect(find.text('展墙自定义'), findsOneWidget);
    expect(find.text('普通视图'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('宿主禁用时长按与单击都没有动作', (tester) async {
    final key = GlobalKey<LibraryEditorialCanvasState>();
    await pumpPage(tester, key, enabled: false);
    final button = find.byTooltip(LibraryPresentationButton.tooltip);
    await tester.longPress(button);
    await tester.tapAt(tester.getCenter(button));
    await tester.pumpAndSettle();
    expect(find.text('普通视图'), findsOneWidget);
    expect(find.text('展墙自定义'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('画布自己禁用（加载中）时长按不动', (tester) async {
    final key = GlobalKey<LibraryEditorialCanvasState>();
    await pumpPage(tester, key, canvasEnabled: false, scope: 'home:disabled');
    await tester.longPress(find.byTooltip(LibraryPresentationButton.tooltip));
    await tester.pumpAndSettle();
    expect(find.text('普通视图'), findsOneWidget);
    expect(
      await finish(
        tester,
        LibraryPresentationStore.instance.read('home:disabled'),
      ),
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
