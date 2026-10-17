import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/model/normal_comic_ep_info.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/workspace/widgets/cards/page_list_card.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation_button.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'rossi.library.presentation.reader-pages': jsonEncode(
        const LibraryPresentation(
          editorial: true,
          hero: false,
          sections: false,
          weight: LibraryWeight.imageShape,
        ).toJson(),
      ),
    });
  });
  tearDown(() => ReaderSessionCoordinator.instance.detachSession('wall-test'));

  testWidgets('原图展墙保留页序，初次打开和翻到远页均跟随居中', (tester) async {
    await _pumpPages(tester, currentSlot: 150);
    _expectCentered(tester);
    final canvas = tester.widget<LibraryEditorialCanvas>(
      find.byType(LibraryEditorialCanvas),
    );
    expect(
      canvas.entries.map((entry) => entry.source),
      orderedEquals(List.generate(300, (index) => index)),
    );
    expect(find.byTooltip(LibraryPresentationButton.tooltip), findsOneWidget);
    expect(find.text('不对称'), findsNothing);

    ReaderSessionCoordinator.instance.updateProgress(
      currentSlot: 247,
      totalSlots: 300,
    );
    await tester.pumpAndSettle();
    _expectCentered(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('展墙搜索按原页码过滤，点击缩略图仍跳到对应原页', (tester) async {
    int? jumped;
    await _pumpPages(tester, currentSlot: 0, onJump: (slot) => jumped = slot);
    final search = find.byType(TextField).first;
    await tester.enterText(search, 'page153.jpg');
    await tester.pumpAndSettle();
    final canvas = tester.widget<LibraryEditorialCanvas>(
      find.byType(LibraryEditorialCanvas),
    );
    expect(canvas.entries.map((entry) => entry.source), orderedEquals([152]));
    await tester.tap(find.descendant(
      of: find.byType(LibraryEditorialCanvas),
      matching: find.text('#153'),
    ).first);
    await tester.pumpAndSettle();
    expect(jumped, 152);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPages(
  WidgetTester tester, {
  required int currentSlot,
  ValueChanged<int>? onJump,
}) async {
  ReaderSessionCoordinator.instance.attachSession(
    comicId: 'wall-test',
    from: 'test',
    title: '页面展墙',
    epInfo: NormalComicEpInfo(
      epName: '第一章',
      docs: List.generate(
        300,
        (index) => Doc(
          originalName: 'page${index + 1}.jpg',
          path: 'p$index',
          fileServer: 's1',
          id: '$index',
        ),
      ),
    ),
    currentSlot: currentSlot,
    totalSlots: 300,
    jumpToSlot: (slot) async => onJump?.call(slot),
  );
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 600,
          child: PageListCard(
            isExpanded: true,
            onToggle: _noop,
            isStandalone: true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _noop() {}

void _expectCentered(WidgetTester tester) {
  final view = tester.getRect(
    find
        .descendant(
          of: find.byType(LibraryEditorialCanvas),
          matching: find.byType(ListView),
        )
        .first,
  );
  final row = tester.getRect(
    find.ancestor(of: find.text('当前'), matching: find.byType(InkWell)).first,
  );
  expect((row.center.dy - view.center.dy).abs(), lessThan(10));
}
