import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/comic_read_preference_cubit.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_presentation_cubit.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/app_bar.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_download_button.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart';
import 'package:zephyr/type/enum.dart';

class _Settings extends GlobalSettingCubit {
  @override
  void updateReadSetting(
    ReadSettingState Function(ReadSettingState current) updates,
  ) => emit(state.copyWith(readSetting: updates(state.readSetting)));
}

Future<_Settings> _paintBar(
  WidgetTester tester,
  Size size, {
  String from = 'test-source',
  ComicEntryType type = ComicEntryType.normal,
  Future<void> Function()? onDownload,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = _Settings();
  final presentation = ReaderPresentationCubit(settings: settings);
  addTearDown(presentation.close);
  addTearDown(settings.close);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<GlobalSettingCubit>.value(value: settings),
        BlocProvider(create: (_) => ComicReadPreferenceCubit()),
        BlocProvider(create: (_) => ReaderCubit()),
        BlocProvider.value(value: presentation),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ComicReadAppBar(
                title: '第 3 话',
                from: from,
                comicId: 'test-comic',
                type: type,
                onDownload: onDownload,
                changePageIndex: (_) {},
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return settings;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [const Size(1280, 800), const Size(390, 800)]) {
    testWidgets('顶栏下载直接发起整本下载 $size', (tester) async {
      var downloadCount = 0;
      final settings = await _paintBar(
        tester,
        size,
        onDownload: () async => downloadCount++,
      );
      final download = find.byTooltip(t.comicInfo.download);
      ReaderToolbarIconButton button() => tester.widget(
        find.descendant(
          of: find.byType(ReaderDownloadButton),
          matching: find.byType(ReaderToolbarIconButton),
        ),
      );

      expect(download, findsOneWidget);
      expect(button().selected, isFalse);
      final before = settings.state.readSetting.readWhileDownloading;
      await tester.tap(download);
      await tester.pumpAndSettle();
      expect(downloadCount, 1);
      expect(settings.state.readSetting.readWhileDownloading, before);
      expect(button().selected, isFalse);
      expect(find.byType(ComicReadAppBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('窄屏更多菜单直接发起整本下载', (tester) async {
    var downloadCount = 0;
    await _paintBar(
      tester,
      const Size(700, 400),
      onDownload: () async => downloadCount++,
    );
    expect(find.byType(ReaderDownloadButton), findsNothing);
    final entry = find.text(t.comicInfo.download);
    await tester.tap(find.byTooltip(t.common.more));
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(downloadCount, 1);
    expect(find.byType(ComicReadAppBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final type in [
    ComicEntryType.download,
    ComicEntryType.historyAndDownload,
  ]) {
    testWidgets('离线阅读不显示下载入口 $type', (tester) async {
      await _paintBar(tester, const Size(1280, 800), type: type);
      expect(find.byType(ReaderDownloadButton), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
