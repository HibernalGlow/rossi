import 'dart:convert';
import 'dart:ui' show ViewFocusEvent, ViewFocusState, ViewFocusDirection;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/comic_read_preference_cubit.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_controller.dart';
import 'package:zephyr/page/comic_read/controller/reader_input_controller.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';
import 'package:zephyr/src/rust/frb_generated.dart';
import 'package:zephyr/util/input/reader_input_bridge.dart';
import 'package:zephyr/util/input/reader_input_context.dart';
import 'package:zephyr/workspace/input/workspace_lane_input_router.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';

class _Reader extends StatefulWidget {
  const _Reader({super.key});

  @override
  State<_Reader> createState() => _ReaderState();
}

class _ReaderState extends State<_Reader> {
  final pages = PageController(initialPage: 30);
  final scroll = ScrollController();
  final transform = TransformationController();
  late final ReaderInputController input;
  late final ReaderActionController actions;
  int menuCalls = 0;
  int get slot => context.read<ReaderCubit>().state.currentSlot;

  @override
  void initState() {
    super.initState();
    final reader = context.read<ReaderCubit>()
      ..updateTotalSlots(80)
      ..updateCurrentSlot(30);
    input = ReaderInputController(
      context: context,
      readerCubit: reader,
      pageController: pages,
      transformationController: transform,
      onToggleMenu: () => menuCalls++,
      onToggleDesktopFullscreen: () async {},
      onRefreshState: () {},
      isScrollLockedByMultiTouch: () => false,
      onUpdateScrollLock: (_) {},
      buildColumnMode: (_) => ListView(
        controller: scroll,
        children: const [SizedBox(height: 5000)],
      ),
      buildRowMode: () => PageView.builder(
        controller: pages,
        itemCount: 80,
        reverse: context.readEffectiveReadMode() == 2,
        onPageChanged: reader.updateCurrentSlot,
        itemBuilder: (_, index) => Center(child: Text('page $index')),
      ),
    );
    actions = ReaderActionController(
      context: context,
      scrollController: scroll,
      pageController: pages,
    );
    input.setActionController(actions);
    input.init();
  }

  @override
  void dispose() {
    input.dispose();
    pages.dispose();
    scroll.dispose();
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => input.buildInteractiveViewer();
}

Future<_ReaderState> _mount(
  WidgetTester tester, {
  double speed = 4,
  int delay = 350,
  bool noAnimation = false,
  bool runtime = true,
  int readMode = 1,
  bool reverse = false,
  List<Map<String, dynamic>>? bindings,
  ComicReadPreferenceState? perComic,
}) async {
  final key = GlobalKey<_ReaderState>();
  final setting = GlobalSettingCubit()
    ..emit(
      GlobalSettingState(
        readSetting: ReadSettingState(
          readMode: readMode,
          noAnimation: noAnimation,
          keyboardPageTurnPagesPerSecond: speed,
          keyboardPageTurnHoldDelayMs: delay,
          reverseHorizontalPageTurn: reverse,
        ),
        operationBindingSetting: OperationBindingSettingState(
          bindingsRuntime: runtime,
          bindingsJson: encodeBindingsDoc(
            bindings ??
                parseBindings(OperationBindingStore.factoryBindingsJson())!,
          ),
        ),
      ),
    );
  addTearDown(setting.close);
  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<GlobalSettingCubit>.value(value: setting),
          BlocProvider(create: (_) => ReaderCubit()),
          BlocProvider(
            create: (_) =>
                ComicReadPreferenceCubit()
                  ..emit(perComic ?? const ComicReadPreferenceState()),
          ),
        ],
        child: _Reader(key: key),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return key.currentState!;
}

// 以真实动画帧推进时间，同时可注入任意密度的系统重复事件。
Future<void> _advance(
  WidgetTester tester,
  int milliseconds, {
  LogicalKeyboardKey? repeat,
}) async {
  var remaining = milliseconds;
  while (remaining > 0) {
    final step = remaining.clamp(1, 10);
    if (repeat != null) await tester.sendKeyRepeatEvent(repeat);
    await tester.pump(Duration(milliseconds: step));
    remaining -= step;
  }
}

List<Map<String, dynamic>> _rightBinding({
  bool ignoreRepeat = false,
  String trigger = 'down',
  String action = BindingAction.nextPage,
  List<String> followUps = const [],
}) => [
  {
    'id': 'test-key',
    'action': action,
    'enabled': true,
    'ignoreRepeat': ignoreRepeat,
    'followUpActions': followUps,
    'context': 'reader',
    'input': {
      'device': 'keyboard',
      'code': 'ArrowRight',
      'trigger': trigger,
      if (trigger == 'hold') 'durationMs': 450,
    },
  },
];

void main() {
  setUpAll(() async => RustLib.init());
  setUp(() {
    ReaderInputBridge.instance.windowFocused = true;
    ReaderInputBridge.instance.setActiveContexts({ReaderInputContext.reader});
  });
  tearDown(() {
    ReaderInputBridge.instance.windowFocused = true;
    ReaderInputBridge.instance.setActiveContexts({ReaderInputContext.reader});
  });

  for (final runtime in [false, true]) {
    for (final noAnimation in [false, true]) {
      for (final speed in [2, 4, 10, 15]) {
        testWidgets(
          '速度 $speed 页/秒，动画 ${!noAnimation}，绑定 $runtime：密集系统重复不改变节奏',
          (tester) async {
            final reader = await _mount(
              tester,
              speed: speed.toDouble(),
              runtime: runtime,
              noAnimation: noAnimation,
            );
            await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
            await _advance(tester, 300, repeat: LogicalKeyboardKey.arrowRight);
            expect(reader.slot, 31, reason: '长按启动前只翻一次');
            await _advance(tester, 1049, repeat: LogicalKeyboardKey.arrowRight);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
            await tester.pumpAndSettle();
            expect(reader.slot, 31 + speed);
            await _advance(tester, 2500);
            expect(reader.slot, 31 + speed, reason: '松手后没有积压翻页');
          },
        );
      }
    }
  }

  testWidgets('0.5 页/秒与 100ms 延迟均生效，不需要系统重复事件', (tester) async {
    final reader = await _mount(tester, speed: 0.5, delay: 100);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await _advance(tester, 450);
    expect(reader.slot, 32);
    await _advance(tester, 1640);
    expect(reader.slot, 32);
    await _advance(tester, 350);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(reader.slot, 33);
  });

  testWidgets('同时按反方向立即反转，松开新方向不会恢复旧方向', (tester) async {
    final reader = await _mount(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await _advance(tester, 450);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await _advance(tester, 300, repeat: LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await _advance(tester, 1000, repeat: LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(reader.slot, 31);
  });

  for (final mode in [1, 2]) {
    for (final reverse in [false, true]) {
      testWidgets('阅读方向 $mode，反转键 $reverse：长按与单次方向一致', (tester) async {
        final reader = await _mount(
          tester,
          readMode: mode,
          reverse: reverse,
          noAnimation: true,
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
        await _advance(tester, 850);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        final forward = (mode == 1) != reverse;
        expect(reader.slot, forward ? 34 : 26);
      });
    }
  }

  for (final interruption in [
    'window',
    'context',
    'focus',
    'lifecycle',
    'view',
  ]) {
    testWidgets('$interruption 中断：重新激活不会继续旧长按', (tester) async {
      final reader = await _mount(tester, speed: 0.5);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await _advance(tester, 450);
      switch (interruption) {
        case 'window':
          ReaderInputBridge.instance.windowFocused = false;
          ReaderInputBridge.instance.windowFocused = true;
        case 'context':
          ReaderInputBridge.instance.setActiveContexts({
            ReaderInputContext.panel,
          });
          ReaderInputBridge.instance.setActiveContexts({
            ReaderInputContext.reader,
          });
        case 'focus':
          reader.input.focusNode.unfocus();
          await tester.pump();
          reader.input.focusNode.requestFocus();
          await tester.pump();
        case 'lifecycle':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        case 'view':
          tester.binding.handleViewFocusChanged(
            ViewFocusEvent(
              viewId: tester.view.viewId,
              state: ViewFocusState.unfocused,
              direction: ViewFocusDirection.undefined,
            ),
          );
      }
      await _advance(tester, 2500, repeat: LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(reader.slot, 32);
    });
  }

  testWidgets('工作台即时目标 source 切到另一泳道后停止旧长按', (tester) async {
    final router = WorkspaceLaneInputRouter(
      hasLane: (_) => true,
      interactionOwned: () => false,
      initialLaneId: LaneId.reader,
    );
    final reader = await _mount(tester, speed: 0.5);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await _advance(tester, 450);
    router.selectExplicitly(LaneId.left);
    router.selectExplicitly(LaneId.reader);
    await _advance(tester, 2500);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(reader.slot, 32);
    router.dispose();
  });

  testWidgets('ignoreRepeat 不连续翻，显式 hold 仍优先且只触发一次', (tester) async {
    var reader = await _mount(
      tester,
      bindings: _rightBinding(ignoreRepeat: true),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await _advance(tester, 1200, repeat: LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(reader.slot, 31);
    reader = await _mount(
      tester,
      bindings: _rightBinding(
        trigger: 'hold',
        action: BindingAction.toggleControls,
      ),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await _advance(tester, 1200, repeat: LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect(reader.menuCalls, 1);
    expect(reader.slot, 30);
  });

  testWidgets('连续翻页保留绑定后续动作，非翻页动作不使用翻页计时器', (tester) async {
    var reader = await _mount(
      tester,
      noAnimation: true,
      bindings: _rightBinding(followUps: [BindingAction.toggleControls]),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await _advance(tester, 850);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect(reader.menuCalls, 4);
    reader = await _mount(
      tester,
      bindings: _rightBinding(action: BindingAction.toggleControls),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await _advance(tester, 1200);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect(reader.menuCalls, 2);
  });

  testWidgets('快速点按明确累加目标，动画中途不会重复翻向同一页', (tester) async {
    final reader = await _mount(tester);
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await _advance(tester, 40);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    }
    await tester.pumpAndSettle();
    expect(reader.slot, 36);
  });

  testWidgets('条漫保持系统重复的小步滚动，不启动横翻计时器', (tester) async {
    final reader = await _mount(
      tester,
      readMode: 0,
      speed: 15,
      noAnimation: true,
      // Neo 出厂表把向下键绑定为下一本；这里明确绑定条漫滚动动作。
      bindings: [
        {
          'id': 'webtoon-next',
          'action': BindingAction.nextPage,
          'context': 'reader',
          'enabled': true,
          'input': {'device': 'keyboard', 'code': 'ArrowDown'},
        },
      ],
    );
    reader.input.focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await _advance(tester, 1500);
    expect(reader.scroll.offset, 200);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(reader.scroll.offset, 400);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
  });

  testWidgets('卸载时取消长按计时器', (tester) async {
    await _mount(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await _advance(tester, 400);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await _advance(tester, 1000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('单本稀疏覆盖同时控制速度与延迟', (tester) async {
    final reader = await _mount(
      tester,
      speed: 15,
      delay: 350,
      perComic: const ComicReadPreferenceState(
        override: (
          setting: ReadSettingState(
            keyboardPageTurnPagesPerSecond: 2,
            keyboardPageTurnHoldDelayMs: 500,
          ),
          keys: {
            'keyboardPageTurnPagesPerSecond',
            'keyboardPageTurnHoldDelayMs',
          },
        ),
      ),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await _advance(tester, 400);
    expect(reader.slot, 31);
    await _advance(tester, 1099);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(reader.slot, 33);
  });

  test('旧设置默认值、同步 JSON 与单本 patch 往返不丢失', () {
    final old = ReadSettingState.fromJson({'readMode': 2});
    expect(old.keyboardPageTurnPagesPerSecond, 4);
    expect(old.keyboardPageTurnHoldDelayMs, 350);
    final edited = old.copyWith(
      keyboardPageTurnPagesPerSecond: 7.5,
      keyboardPageTurnHoldDelayMs: 600,
    );
    expect(ReadSettingState.fromJson(edited.toJson()), edited);
    final preference = ComicReadPreference(
      uniqueKey: 'test:book',
      source: 'test',
      comicId: 'book',
      updatedAt: DateTime.utc(2026, 10, 13),
      deleted: false,
    );
    expect(preference.applyChanges(old, edited), {
      'keyboardPageTurnPagesPerSecond',
      'keyboardPageTurnHoldDelayMs',
    });
    expect(jsonDecode(preference.overridesJson), {
      'keyboardPageTurnPagesPerSecond': 7.5,
      'keyboardPageTurnHoldDelayMs': 600,
    });
    expect(
      ComicReadPreferenceService.resolveEffective(
        old,
        preference.overrideSetting,
      ),
      edited,
    );
    expect(
      sanitizeReadSettingPatch({
        'keyboardPageTurnPagesPerSecond': double.infinity,
      }),
      isEmpty,
    );
    expect(sanitizeReadSettingPatch({'keyboardPageTurnPagesPerSecond': 7}), {
      'keyboardPageTurnPagesPerSecond': 7.0,
    });
  });
}
