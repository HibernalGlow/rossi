// 控制面板那三张「读改设置」卡的判据（超分 / 翻译 / 画面调节）。
//
// 要守住的三件事：
// 1. 卡片与阅读设置面板渲染的是**同一批** section，所以判据打在卡片上就等于
//    打在共用实现上 —— 这里不许出现「卡片自己另画一套」的漏网；
// 2. 「没有书」时「本书超分」那颗是**灰显 + 说明**，不是消失，而且点了不写状态；
// 3. 平台判不动的卡走「留壳 + tag + 不吃点击」，不是整张卡不上轨。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/model/normal_comic_ep_info.dart';
import 'package:zephyr/page/comic_read/widgets/settings/sections/super_resolution_section.dart';
import 'package:zephyr/page/comic_read/widgets/settings/sections/translate_section.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_book_scope.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';
import 'package:zephyr/src/rust/frb_generated.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/registry/workspace_ids.dart';
import 'package:zephyr/workspace/widgets/cards/image_tuning_card.dart';
import 'package:zephyr/workspace/widgets/cards/super_resolution_card.dart';
import 'package:zephyr/workspace/widgets/cards/translate_card.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/icons/icons.dart';

class _InMemoryGlobalSettingCubit extends GlobalSettingCubit {
  @override
  void updateReadSetting(
    ReadSettingState Function(ReadSettingState current) updates,
  ) {
    emit(state.copyWith(readSetting: updates(state.readSetting)));
  }
}

/// 真实 IO 与测试帧之间推进，而不是干等动画停。
///
/// 不用 `pumpAndSettle`：加载中的 `CircularProgressIndicator` 是**永动**的，
/// 那条调用只会以「timed out」收场 —— 那是尺子看不见东西，不是卡坏了。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (!tester.binding.hasScheduledFrame) return;
  }
  fail('卡片没停下来');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 只有「超分卡与翻译卡」那一组要问 native 侧，所以 RustLib 与 path_provider
  // 的接线收在那一组里面。挂在 main 层上，别的会话把 FRB codegen 改到半同步
  // 状态时（实测 `Content hash … is different`），会把注册表、灰显外壳、
  // 本书身份这些**根本不碰 native** 的判据一起拖红 —— 那是把别人的红灯
  // 复制成自己的。
  SharedPreferences.setMockInitialValues(<String, Object>{});

  group('注册表', () {
    test('控制面板四张卡按 defaultOrder 排好，新三张都住在控制面板', () {
      final registry = WorkspaceCardRegistry.I;
      final ids = [
        for (final card in registry.cards)
          if (card.defaultPanelId == WorkspacePanelId.control) card.id,
      ];
      expect(ids, [
        WorkspaceCardRegistry.switchToast,
        WorkspaceCardRegistry.superResolution,
        WorkspaceCardRegistry.translate,
        WorkspaceCardRegistry.imageTuning,
      ]);
    });

    test('翻译卡带平台门禁，另两张没有', () {
      final registry = WorkspaceCardRegistry.I;
      expect(
        registry.find(WorkspaceCardRegistry.translate)!.supportedHere,
        isNotNull,
      );
      expect(
        registry.find(WorkspaceCardRegistry.translate)!.unsupportedHint,
        '仅桌面',
      );
      expect(
        registry.find(WorkspaceCardRegistry.superResolution)!.supportedHere,
        isNull,
      );
      expect(
        registry.find(WorkspaceCardRegistry.imageTuning)!.supportedHere,
        isNull,
      );
    });
  });

  group('灰显外壳（CollapsibleCard.disabledHint）', () {
    const probeKey = Key('probe');

    Widget host({required String? disabledHint}) {
      return MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CollapsibleCard(
              cardId: 'probe',
              title: '探针卡',
              icon: AppGlyphs.wrench,
              isExpanded: true,
              onToggle: () {},
              disabledHint: disabledHint,
              child: Column(
                children: [
                  const Text('内容正文'),
                  TextButton(
                    key: probeKey,
                    onPressed: () {},
                    child: const Text('按我'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('带 hint 时标题行出现说明 tag', (tester) async {
      await tester.pumpWidget(host(disabledHint: '仅桌面'));
      await tester.pumpAndSettle();
      expect(find.text('仅桌面'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('灰显只吃点击，不藏内容', (tester) async {
      await tester.pumpWidget(host(disabledHint: '仅桌面'));
      await tester.pumpAndSettle();
      // 内容还在：藏起来会被读成「这个功能不存在」。
      expect(find.text('内容正文'), findsOneWidget);

      // 判据只能看「有没有正在吃点击的那一层」：`TextButton` / `Material`
      // 自己就带 IgnorePointer 祖先（实测 5 层），按存在与否判会在两种状态下都成立。
      int blockingAncestors() => tester
          .widgetList<IgnorePointer>(
            find.ancestor(
              of: find.byKey(probeKey),
              matching: find.byType(IgnorePointer),
            ),
          )
          .where((w) => w.ignoring)
          .length;

      expect(blockingAncestors(), greaterThan(0));

      // 阳性对照：没有 hint 时必须一颗都不挡，否则上面那条
      // 在「外壳永远灰着」这种坏状态下也会变绿。
      await tester.pumpWidget(host(disabledHint: null));
      await tester.pumpAndSettle();
      expect(find.text('仅桌面'), findsNothing);
      expect(blockingAncestors(), 0);
    });
  });

  testWidgets('独占面板（没有折叠外壳）时闸门照样生效', (tester) async {
    const gateKey = Key('gate-probe');
    // `applyCardGate` 是两条落点共用的那一份：折叠外壳的内容区，
    // 以及 standalone —— 那条路上根本没有 CollapsibleCard，标题行的 tag 画不出来。
    Widget wrap(String? hint) => MaterialApp(
      home: Scaffold(
        body: applyCardGate(
          TextButton(key: gateKey, onPressed: () {}, child: const Text('按我')),
          disabledHint: hint,
        ),
      ),
    );

    int blocking() => tester
        .widgetList<IgnorePointer>(
          find.ancestor(
            of: find.byKey(gateKey),
            matching: find.byType(IgnorePointer),
          ),
        )
        .where((w) => w.ignoring)
        .length;

    await tester.pumpWidget(wrap('仅桌面'));
    await tester.pumpAndSettle();
    expect(blocking(), greaterThan(0));

    await tester.pumpWidget(wrap(null));
    await tester.pumpAndSettle();
    expect(blocking(), 0);
  });

  group('画面调节卡', () {
    late _InMemoryGlobalSettingCubit cubit;

    Widget host(Widget child) {
      return BlocProvider<GlobalSettingCubit>.value(
        value: cubit,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 380,
              height: 700,
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      );
    }

    setUp(() {
      cubit = _InMemoryGlobalSettingCubit();
    });

    testWidgets('渲染三颗开关，拨动写回 cubit（不是局部 State）', (tester) async {
      await tester.pumpWidget(
        host(const ImageTuningCard(isExpanded: true, onToggle: _noop)),
      );
      await tester.pumpAndSettle();

      expect(find.text('画面调节'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 行本体是 ListTile + 末尾 Switch.adaptive，不是 SwitchListTile。
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      final afterFirst = cubit.state.readSetting;
      expect(
        afterFirst.noAnimation ||
            afterFirst.readFilterEnabled ||
            afterFirst.einkOptimization,
        isTrue,
      );
    });
  });

  // 「本书」那颗到底写给谁 —— 串书回归。纯 Dart，不碰 native。
  //
  // 坏掉的那一格：本地书 A 开着，再从书架 push 一本在线书 B。
  // `RealSrBookScope.activeLocalBook` 是全局静态，而在线书那条路不会清它
  // （`LocalReadSession.dispose` 的清理卡在路径比对与 `isLocalComicSource` 之后），
  // 于是旧写法 `activeLocalBook ?? keyFor(…)` 短路返回 A 的路径 ——
  // 界面读的是 B，覆盖却写到 A 上。
  group('本书身份（activeReaderBookKey）', () {
    void attachOnline() {
      ReaderSessionCoordinator.instance.attachSession(
        comicId: 'b2',
        from: 'jm',
        title: '在线书 B',
        epInfo: NormalComicEpInfo(
          epName: '第 1 话',
          docs: [
            Doc(originalName: '001.jpg', path: 'p1', fileServer: 's', id: '1'),
          ],
        ),
        currentSlot: 0,
        totalSlots: 1,
        jumpToSlot: (_) async {},
      );
    }

    tearDown(() {
      ReaderSessionCoordinator.instance.detachSession('b2');
      ReaderSessionCoordinator.instance.detachSession('a1');
      RealSrBookScope.setActiveLocalBook(null);
    });

    test('没有会话：null（跟随全局），不是任何一本书的键', () {
      expect(activeReaderBookKey(), isNull);
    });

    test('在线书 B 压在本地书 A 上：键是 B，不是残留的 A', () {
      RealSrBookScope.setActiveLocalBook('/tmp/rossi_book_a');
      attachOnline();

      final key = activeReaderBookKey();
      expect(key, isNotNull);
      expect(key, isNot('/tmp/rossi_book_a'));
      expect(key, contains('b2'));
      // 阳性对照：残留值本身还在（说明这条判据真的在防它，而不是它已经没了）。
      expect(RealSrBookScope.activeLocalBook, '/tmp/rossi_book_a');
      expect(ReaderSessionCoordinator.instance.hasActiveSession, isTrue);
    });

    test('本地书：键就是会话登记的那条路径', () {
      RealSrBookScope.setActiveLocalBook('/tmp/rossi_book_a');
      ReaderSessionCoordinator.instance.attachSession(
        comicId: 'a1',
        from: 'local',
        title: '本地书 A',
        epInfo: NormalComicEpInfo(
          epName: 'A',
          docs: [
            Doc(originalName: '001.jpg', path: 'p1', fileServer: 's', id: '1'),
          ],
        ),
        localSource: _FakeSource('/tmp/rossi_book_a'),
        currentSlot: 0,
        totalSlots: 1,
        jumpToSlot: (_) async {},
      );

      expect(activeReaderBookKey(), '/tmp/rossi_book_a');
    });
  });

  group('超分卡与翻译卡', () {
    // 视口按**真实控制面板宽度**取（截图里那条右泳道是 620）。
    // 刻意不用窄宽度：实测 `UpscaleConditionsCard(isReaderCompact: true)` 在
    // 内容宽 <346 时右侧溢出 5.7 px，而那是它自己的既有形状 ——
    // 阅读设置面板在手机上正文只有 310 px（窗口 -24 再 -32），今天就已经越过去了。
    // 那条归 `lib/page/setting/real_sr/widgets/`（另一会话正在改），不归这张卡。
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    late Directory root;

    setUpAll(() async {
      // 写在 setUpAll 而不是某条 testWidgets 体里：后者会把那条测试挂到超时。
      await RustLib.init();
    });

    setUp(() async {
      root = await Directory.systemTemp.createTemp('rossi_control_cards_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, (_) async => root.path);
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, null);
      if (await root.exists()) await root.delete(recursive: true);
    });

    Widget host(Widget child) {
      return BlocProvider<GlobalSettingCubit>.value(
        value: _InMemoryGlobalSettingCubit(),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 620,
              height: 1200,
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      );
    }

    testWidgets('没开书时「本书」那颗灰显并说明，而不是消失', (tester) async {
      await tester.pumpWidget(
        host(const SuperResolutionCard(isExpanded: true, onToggle: _noop)),
      );
      await _settle(tester);

      expect(find.text('本书：启用 AI 超分辨率'), findsOneWidget);
      expect(find.textContaining('现在没有打开的书'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches.length, greaterThanOrEqualTo(2));
      expect(switches[0].onChanged, isNull);
      // 阳性对照：同一张卡里的「全局」那颗必须点得动，否则「灰显」这条判据
      // 在「整张卡都点不动」这种坏状态下也会变绿。
      expect(switches[1].onChanged, isNotNull);
    });

    testWidgets('翻译卡渲染出与面板共用的那份正文', (tester) async {
      await tester.pumpWidget(
        host(const TranslateCard(isExpanded: true, onToggle: _noop)),
      );
      await _settle(tester);
      expect(tester.takeException(), isNull);

      if (!ocrSupportedHere) {
        // 判不动的那一端：留壳 + tag，正文整块灰着不吃点击。
        expect(find.text('仅桌面'), findsOneWidget);
        return;
      }
      expect(find.byType(TranslateSettingsSection), findsOneWidget);
      expect(find.byType(Switch), findsWidgets);
    });
  });
}

/// 只要 `path` 那一个成员真的被读到，其余走 `noSuchMethod`。
class _FakeSource implements PageSource {
  _FakeSource(this.path);

  @override
  final String path;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void _noop() {}
