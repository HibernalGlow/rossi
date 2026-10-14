import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_info/view/comic_info.dart';
import 'package:zephyr/page/comic_list/view/discover_library_view.dart';
import 'package:zephyr/page/discover/service/discover_tab_scope.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_info.dart';
import 'package:zephyr/workspace/service/library_presentation_store.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_book_details.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_tile.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/type/enum.dart';

class _Tabs implements DiscoverTabActions {
  final opened = <Map<String, String?>>[];

  @override
  void openComicInfo({
    required String comicId,
    required String from,
    required String title,
    String? collectionTargetId,
    String? collectionTargetName,
  }) {
    opened.add({
      'id': comicId,
      'from': from,
      'title': title,
      'target': collectionTargetId,
      'targetName': collectionTargetName,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _info = ComicSimplifyEntryInfo(
  title: '发现作品',
  id: 'comic',
  from: 'fallback',
  source: ' actual-plugin ',
  fileServer: '',
  path: '',
  pictureType: PictureType.cover,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('发现默认封面打开新页签，信息键独立展开真实详情并保留合集目标', (tester) async {
    final key = GlobalKey<LibraryEditorialCanvasState>();
    final tabs = _Tabs();
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider(
          create: (_) => GlobalSettingCubit(),
          child: DiscoverTabScope(
            actions: tabs,
            child: Scaffold(
              body: DiscoverLibraryView(
                canvasKey: key,
                scope: 'discover:test',
                entries: const [
                  LibraryEntry(key: 'comic', title: '发现作品', source: _info),
                ],
                collectionTargetId: 'target-id',
                collectionTargetName: '我的合集',
                legacyBuilder: (_) => const SizedBox(),
                footerBuilder: (_) => const SizedBox(),
                onReachEnd: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('展开信息'), findsOneWidget);
    await tester.tapAt(
      tester.getTopLeft(find.byType(LibraryEditorialTile)) +
          const Offset(12, 12),
    );
    await tester.pumpAndSettle();
    expect(tabs.opened.single, {
      'id': 'comic',
      'from': 'actual-plugin',
      'title': '发现作品',
      'target': 'target-id',
      'targetName': '我的合集',
    });
    expect(find.byType(LibraryBookDetails), findsNothing);
    await tester.tap(find.byTooltip('展开信息'));
    await tester.pumpAndSettle();
    expect(tabs.opened, hasLength(1));
    final detail = tester.widget<EmbeddedComicInfo>(
      find.byType(EmbeddedComicInfo),
    );
    expect(detail.comicId, 'comic');
    expect(detail.from, 'actual-plugin');
    expect(detail.collectionTargetId, 'target-id');
    expect(detail.collectionTargetName, '我的合集');
    expect(key.currentState!.expandedEntries.single.key, 'comic');
    await tester.tap(find.byTooltip('收起信息'));
    await tester.pumpAndSettle();
    expect(key.currentState!.expandedEntries, isEmpty);

    await LibraryPresentationStore.instance.save(
      'discover:test',
      const LibraryPresentation(
        hero: false,
        coverTapAction: LibraryCoverTapAction.expandDetails,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getTopLeft(find.byType(LibraryEditorialTile)) +
          const Offset(12, 12),
    );
    await tester.pumpAndSettle();
    expect(key.currentState!.expandedEntries.single.key, 'comic');
    expect(tabs.opened, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
