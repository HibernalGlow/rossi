import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/model/normal_comic_ep_info.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/registry/workspace_ids.dart';
import 'package:zephyr/workspace/widgets/cards/info_card_kit.dart';
import 'package:zephyr/workspace/widgets/cards/storage_information_card.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/grid/card_layout_scope.dart';
import 'package:zephyr/workspace/widgets/grid/card_resize_handle.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_menu_button.dart';
import 'package:zephyr/workspace/widgets/panels/lane_panel_host.dart';
import 'package:zephyr/workspace/widgets/panels/panel_card_list.dart';

import 'package:zephyr/widgets/spring_lens/spring_lens_bar.dart';
import 'package:zephyr/workspace/widgets/panels/panel_tab_strip.dart';
import 'package:zephyr/workspace/widgets/panels/retained_panel_switcher.dart';

import '../test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(TestObjectBoxHelper.setUpTestObjectBox);
  tearDownAll(TestObjectBoxHelper.tearDownTestObjectBox);

  Finder card(String id) =>
      find.byWidgetPredicate((w) => w is CollapsibleCard && w.cardId == id);

  for (final width in [320.0, 640.0, 960.0]) {
    testWidgets('信息视图 $width 宽度随卡片排布，展示无布局按钮，标题可折叠', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cubit = WorkspaceCubit();
      addTearDown(cubit.close);
      final reader = ReaderSessionCoordinator.instance;
      reader.attachSession(
        comicId: 'widget-book',
        from: 'test',
        title: '测试书籍',
        epInfo: NormalComicEpInfo(epName: '测试章节'),
        currentSlot: 1,
        totalSlots: 10,
        jumpToSlot: (_) async {},
      );
      addTearDown(() => reader.detachSession('widget-book'));
      cubit.setActivePanel('right', WorkspacePanelId.info);
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: cubit,
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: const LanePanelHost(side: WorkspacePanelSide.right),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CollapsibleCard), findsNWidgets(5));
      expect(find.byType(InfoFacts), findsWidgets);
      expect(find.byType(CardResizeHandle), findsNothing);
      expect(find.byType(ShelfMenuButton), findsNothing);
      expect(find.byTooltip('折叠书籍信息'), findsNothing);
      final book = card('book_information');
      final image = card('image_information');
      final storage = card('storage_information');
      if (width == 320) {
        expect(tester.getSize(image).width, tester.getSize(book).width);
        expect(
          tester.getTopLeft(storage).dy,
          greaterThan(tester.getTopLeft(image).dy),
        );
      } else {
        expect(
          tester.getSize(image).width,
          lessThan(tester.getSize(book).width),
        );
        expect(
          tester.getTopLeft(image).dy,
          closeTo(tester.getTopLeft(storage).dy, .1),
        );
      }
      await tester.tap(find.descendant(of: book, matching: find.text('书籍信息')));
      await tester.pumpAndSettle();
      expect(
        cubit.state.board.cardLayout('book_information')!.expanded,
        isFalse,
      );
      await tester.tap(find.descendant(of: book, matching: find.text('书籍信息')));
      await tester.pumpAndSettle();
      expect(
        cubit.state.board.cardLayout('book_information')!.expanded,
        isTrue,
      );

      final storageState = tester.state(find.byType(StorageInformationCard));
      await tester.tap(
        width < 420 ? find.byTooltip('自定义布局') : find.text('自定义布局'),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('折叠书籍信息'), findsOneWidget);
      final bookScope = tester.widget<CardLayoutScope>(
        find.ancestor(of: book, matching: find.byType(CardLayoutScope)).first,
      );
      expect(bookScope.onHide, isNull);
      final grip = find.descendant(
        of: image,
        matching: find.byType(CardResizeHandle),
      );
      await tester.ensureVisible(grip);
      final gesture = await tester.startGesture(tester.getCenter(grip));
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump();
      expect(cubit.state.board.cardLayout('image_information'), isNull);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        cubit.state.board.cardLayout('image_information')!.heightSpan,
        greaterThan(2),
      );
      expect(
        tester.state(find.byType(StorageInformationCard)),
        same(storageState),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('控制视图的画面调节也使用小组件外壳和拖拽尺寸', (tester) async {
    final cubit = WorkspaceCubit();
    final global = GlobalSettingCubit();
    addTearDown(cubit.close);
    addTearDown(global.close);
    final registry = WorkspaceCardRegistry.I;
    var board = const WorkspaceBoardLayout();
    for (final id in ['switch_toast', 'super_resolution', 'translate']) {
      board = board.withCard(
        id,
        registry
            .effectiveLayout(registry.find(id)!, board)
            .copyWith(visible: false),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: cubit),
            BlocProvider.value(value: global),
          ],
          child: Scaffold(
            body: SizedBox(
              width: 640,
              child: PanelCardList(
                panelId: WorkspacePanelId.control,
                board: board,
                isEditing: true,
                onSetExpanded: cubit.setCardExpanded,
                onMoveCard: (_, _) {},
                onHideCard: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tuning = card('image_tuning');
    expect(tuning, findsOneWidget);
    expect(tester.getSize(tuning).width, greaterThanOrEqualTo(320));
    final grip = find.descendant(
      of: tuning,
      matching: find.byType(CardResizeHandle),
    );
    await tester.ensureVisible(grip);
    final gesture = await tester.startGesture(tester.getCenter(grip));
    await gesture.moveBy(const Offset(70, 20));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(cubit.state.board.cardLayout('image_tuning'), isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('真实泳道页签点击仍有弹簧运动，内容过渡保留信息卡状态', (tester) async {
    final cubit = WorkspaceCubit();
    final global = GlobalSettingCubit();
    addTearDown(cubit.close);
    addTearDown(global.close);
    for (final id in ['switch_toast', 'super_resolution', 'translate']) {
      cubit.setCardVisible(id, false);
    }
    cubit.setActivePanel('right', WorkspacePanelId.info);
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: cubit),
            BlocProvider.value(value: global),
          ],
          child: const Scaffold(
            body: SizedBox(
              width: 640,
              child: Column(
                children: [
                  SizedBox(
                    height: 40,
                    child: PanelTabStrip(
                      side: WorkspacePanelSide.right,
                      maxWidth: 640,
                    ),
                  ),
                  Expanded(
                    child: LanePanelHost(side: WorkspacePanelSide.right),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final infoState = tester.state(find.byType(StorageInformationCard));
    final lensState = tester.state(find.byType(SpringLensBar));
    SpringLensPainter lens() => tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(SpringLensBar),
            matching: find.byType(CustomPaint),
          ),
        )
        .map((w) => w.painter)
        .whereType<SpringLensPainter>()
        .first;
    final start = lens().position;
    final control = find.byWidgetPredicate(
      (w) => w is Tooltip && w.message?.startsWith('控制') == true,
    );
    await tester.tap(control);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.state(find.byType(SpringLensBar)), same(lensState));
    expect(lens().position, greaterThan(start));
    final switcher = find.byType(RetainedPanelSwitcher);
    final opacity = tester
        .widgetList<FadeTransition>(
          find.descendant(of: switcher, matching: find.byType(FadeTransition)),
        )
        .where((w) => w.opacity.value > 0 && w.opacity.value < 1);
    expect(opacity.length, greaterThanOrEqualTo(2));
    await tester.pumpAndSettle();
    final destination = lens().position;
    expect(destination, greaterThan(start));
    expect(find.byType(StorageInformationCard), findsNothing);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is Tooltip && w.message?.startsWith('信息') == true,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(StorageInformationCard)), same(infoState));
    expect(lens().position, closeTo(start, .01));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
