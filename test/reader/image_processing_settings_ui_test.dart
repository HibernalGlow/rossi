import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/comic_read_preference_cubit.dart';
import 'package:zephyr/page/comic_read/widgets/settings/sections/auto_trim_section.dart';
import 'package:zephyr/page/comic_read/widgets/settings/sections/image_denoise_section.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/setting/real_sr/service/denoise_model_download.dart';
import 'package:zephyr/page/setting/real_sr/widgets/image_processing/denoise_model_card.dart';
import 'package:zephyr/page/setting/real_sr/widgets/image_processing/processing_settings_card.dart';

class _PreviewPreferenceCubit extends ComicReadPreferenceCubit {
  void setOverride(ReadSettingState setting, Set<String> keys) =>
      emit(ComicReadPreferenceState(override: (setting: setting, keys: keys)));
}

class _PreviewGlobalCubit extends GlobalSettingCubit {
  @override
  void updateReadSetting(ReadSettingState Function(ReadSettingState) updates) {
    emit(state.copyWith(readSetting: updates(state.readSetting)));
  }
}

void main() {
  testWidgets(
    'production sections expose independent advanced settings at narrow widths',
    (tester) async {
      SharedPreferences.setMockInitialValues({'image_denoise_enabled': true});
      await tester.binding.setSurfaceSize(const Size(420, 2800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const previewPath = String.fromEnvironment('IMAGE_PROCESSING_PREVIEW');
      if (previewPath.isNotEmpty) {
        await tester.runAsync(() async {
          final data = await File(
            'asset/fonts/LXGWWenKaiLite-Regular.ttf',
          ).readAsBytes();
          final loader = FontLoader('ProcessingPreview');
          loader.addFont(Future.value(data.buffer.asByteData()));
          await loader.load();
          final icons = await File(
            'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
          ).readAsBytes();
          final iconLoader = FontLoader('MaterialIcons');
          iconLoader.addFont(Future.value(icons.buffer.asByteData()));
          await iconLoader.load();
        });
      }
      final cubit = _PreviewGlobalCubit();
      addTearDown(cubit.close);
      cubit.updateReadSetting(
        (setting) => setting.copyWith(autoTrimPageMargins: true),
      );
      final model = DenoiseModelDownload(
        inspect: () async => 29620809,
        transfer: (_, _) async {},
        remove: () async {},
      );
      addTearDown(model.dispose);
      await model.refresh();
      await tester.pumpWidget(
        BlocProvider<GlobalSettingCubit>.value(
          value: cubit,
          child: MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              fontFamily: previewPath.isEmpty ? null : 'ProcessingPreview',
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff526b56),
              ),
            ),
            home: Scaffold(
              body: RepaintBoundary(
                key: const ValueKey('processing-preview'),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const AutoTrimSection(),
                      const SizedBox(height: 16),
                      ImageDenoiseSection(
                        globalOnly: true,
                        modelDownload: model,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 预览默认收起，不加载任何图片。
      expect(find.text('裁边预览'), findsOneWidget);
      expect(find.text('降噪预览'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await tester.tap(find.text('裁边高级设置'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('降噪高级设置'));
      await tester.tap(find.text('降噪高级设置'));
      await tester.pumpAndSettle();
      expect(find.text('安全留边'), findsOneWidget);
      expect(find.text('降噪分块大小'), findsOneWidget);
      expect(find.text('仅处理 JPEG 页面'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('模型已安装'), findsOneWidget);

      // 没有正在阅读的页面时，展开后才显示内置示例。
      await tester.ensureVisible(find.text('裁边预览'));
      await tester.tap(find.text('裁边预览'));
      await tester.runAsync(() async {
        final context = tester.element(find.byType(AutoTrimSection));
        await Future.wait([
          for (final name in ['trim_before', 'trim_after'])
            precacheImage(
              AssetImage('asset/image/processing_examples/$name.png'),
              context,
            ),
        ]);
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('没有正在阅读的页面'), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(2));
      await tester.ensureVisible(find.text('降噪预览'));
      await tester.tap(find.text('降噪预览'));
      await tester.runAsync(() async {
        final context = tester.element(find.byType(AutoTrimSection));
        await Future.wait([
          for (final name in ['denoise_before', 'denoise_after'])
            precacheImage(
              AssetImage('asset/image/processing_examples/$name.png'),
              context,
            ),
        ]);
      });
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNWidgets(4));

      // 收起后立即释放。
      await tester.ensureVisible(find.text('裁边预览'));
      await tester.tap(find.text('裁边预览'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNWidgets(2));
      await tester.ensureVisible(find.text('降噪预览'));
      await tester.tap(find.text('降噪预览'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
      if (previewPath.isNotEmpty) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('processing-preview')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(previewPath).parent.create(recursive: true);
          await File(previewPath).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );
  testWidgets('auto trim status follows the per-book override, not just global', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final global = _PreviewGlobalCubit();
    addTearDown(global.close);
    global.updateReadSetting(
      (setting) => setting.copyWith(autoTrimPageMargins: true),
    );
    final preference = _PreviewPreferenceCubit();
    addTearDown(preference.close);
    Future<void> pump() async {
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<GlobalSettingCubit>.value(value: global),
            BlocProvider<ComicReadPreferenceCubit>.value(value: preference),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: AutoTrimSection())),
          ),
        ),
      );
      await tester.pump();
    }

    await pump();
    expect(find.textContaining('已开启 · 白边和黑边自动检测'), findsOneWidget);

    preference.setOverride(
      global.state.readSetting.copyWith(autoTrimPageMargins: false),
      {'autoTrimPageMargins'},
    );
    // bloc 的 stream 事件要走一次异步调度才送达 BlocBuilder。
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(find.textContaining('本书已单独关闭裁边'), findsOneWidget);
    expect(find.textContaining('已开启 · 白边和黑边自动检测'), findsNothing);
  });

  testWidgets(
    'download card shows progress and retry without overflow on narrow large text layout',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final release = Completer<void>();
      final model = DenoiseModelDownload(
        inspect: () async => 0,
        transfer: (progress, _) async {
          progress(10, 100);
          await release.future;
          throw StateError('网络中断');
        },
        remove: () async {},
      );
      addTearDown(model.dispose);
      await model.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 900),
              textScaler: TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: DenoiseModelCard(download: model),
              ),
            ),
          ),
        ),
      );
      expect(find.text('模型未安装'), findsOneWidget);
      final work = model.download();
      await tester.pump();
      expect(find.text('正在下载模型'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .1,
      );
      final button = tester.widget<FilledButton>(
        find.byWidgetPredicate((widget) => widget is FilledButton),
      );
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
      release.complete();
      await work;
      await tester.pump();
      expect(find.text('重试下载'), findsOneWidget);
      expect(find.textContaining('网络中断'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'advanced disclosure respects reduced motion and has accessible touch targets',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: ProcessingAdvancedDisclosure(
                title: '裁边高级设置',
                child: const Text('安全留边'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('安全留边'), findsNothing);
      await tester.tap(find.text('裁边高级设置'));
      await tester.pump();
      expect(find.text('安全留边'), findsOneWidget);
      expect(
        tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).duration,
        Duration.zero,
      );
      expect(
        tester.getSize(find.byType(ListTile)).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.text('裁边高级设置'));
      await tester.pump();
      expect(find.text('安全留边'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('advanced sliders save only when dragging finishes', (
    tester,
  ) async {
    final values = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProcessingSlider(
            title: '背景检测容差',
            value: 24,
            min: 0,
            max: 64,
            labelOf: (v) => '$v',
            onChanged: values.add,
          ),
        ),
      ),
    );
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(40);
    await tester.pump();
    expect(values, isEmpty);
    slider.onChangeEnd!(40);
    expect(values, [40]);
  });
}
