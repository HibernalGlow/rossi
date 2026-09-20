import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/cubit/image_size_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/page/comic_read/model/reader_presentation.dart';
import 'package:zephyr/page/comic_read/widgets/image/read_image_widget.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';
import 'package:zephyr/page/comic_read/widgets/modes/read_mode_slot_builder.dart';
import 'package:zephyr/page/comic_read/widgets/modes/read_mode_transition_style.dart';
import 'package:zephyr/page/comic_read/widgets/modes/read_mode_utils.dart';

void main() {
  testWidgets('本地图片按真实比例最大化显示，未知尺寸不套占位框', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = GlobalSettingCubit();
    final reader = ReaderCubit();
    final sizes = ImageSizeCubit(
      count: 1,
      defaultWidth: 800,
      defaultHeight: 960,
      sourceTag: 'local-fit-test',
      pageKeys: const ['page'],
      chapterOrder: 0,
      hydrateOnInit: false,
      initialCache: {},
      initialResolved: {},
    );
    addTearDown(() async {
      await LocalReadSession.instance.dispose();
      await settings.close();
      await reader.close();
      await sizes.close();
    });
    final cacheIndex = resolveStableSizeCacheIndex(
      chapterOrder: 0,
      localPageIndex: 0,
    );
    final item = ReadModeSlotItem(
      entryIndex: 0,
      entry: ReadModeEntry.image(
        doc: const Doc(
          originalName: 'page.jpg',
          path: '0',
          fileServer: '/local/book.zip',
          id: '0',
          extern: {'isLocalGpu': true, 'localIndex': 0},
        ),
        chapterId: 'chapter',
        chapterOrder: 0,
        chapterTitle: '',
        chapterPageIndex: 0,
      ),
    );

    Future<void> show([
      ReaderPresentation presentation = const ReaderPresentation(),
    ]) => tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<GlobalSettingCubit>.value(value: settings),
          BlocProvider<ReaderCubit>.value(value: reader),
          BlocProvider<ImageSizeCubit>.value(value: sizes),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => buildReadModeSlot(
              context: context,
              slotIndex: 0,
              singleItem: item,
              doublePageSlot: null,
              axis: ReadModeAxis.row,
              containerWidth: 800,
              contentWidth: 800,
              viewportHeight: 1000,
              presentation: presentation,
              backgroundColor: Colors.white,
              isRtl: false,
              comicId: 'book',
              from: 'local',
              onTransitionAction: null,
              transitionStyle: ReadModeTransitionStyle.row,
            ),
          ),
        ),
      ),
    );

    final image = find.byType(ReadImageWidget);
    await show();
    expect(tester.getSize(image), const Size(800, 1000));

    // 竖图顶到上下边界，横图顶到左右边界，另一维等比缩放。
    sizes.updateIntrinsicSize(cacheIndex, const Size(600, 1200));
    await tester.pumpAndSettle();
    expect(tester.getSize(image), const Size(500, 1000));
    expect(tester.getTopLeft(image), const Offset(150, 0));

    sizes.updateIntrinsicSize(cacheIndex, const Size(1200, 600));
    await tester.pumpAndSettle();
    expect(tester.getSize(image), const Size(800, 400));
    expect(tester.getTopLeft(image), const Offset(0, 300));

    await show(const ReaderPresentation(fitMode: ReaderFitMode.fitHeight));
    expect(tester.getSize(image), const Size(2000, 1000));

    await show(const ReaderPresentation(rotation: 90));
    expect(
      tester.widget<ReadImageWidget>(image).paintSize,
      const Size(1000, 500),
    );
    expect(find.byType(RotatedBox), findsOneWidget);

    await show(const ReaderPresentation());
    expect(tester.getSize(image), const Size(800, 400));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await LocalReadSession.instance.dispose();
  });
}
