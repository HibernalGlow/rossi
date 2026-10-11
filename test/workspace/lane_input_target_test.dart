import 'dart:ui' show ViewFocusEvent, ViewFocusState, ViewFocusDirection;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/util/input/reader_input_bridge.dart';
import 'package:zephyr/util/input/reader_input_context.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/input/workspace_lane_input_router.dart';
import 'package:zephyr/workspace/model/workspace_interaction_settings.dart';
import 'package:zephyr/workspace/model/workspace_lane_interaction.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/widgets/swimlane/swimlane_workspace.dart';

const _layout = WorkspaceLayoutConfig(
  laneOrder: LaneId.defaultOrder,
  lanes: {
    LaneId.left: LaneConfig(width: 400, minWidth: 300, title: '左'),
    LaneId.reader: LaneConfig(
      width: 300,
      widthRatio: .25,
      minWidth: 300,
      title: '阅读',
    ),
    LaneId.right: LaneConfig(width: 400, minWidth: 300, title: '右'),
  },
);

Future<WorkspaceCubit> _mount(
  WidgetTester tester, {
  required Widget Function(String) content,
  WorkspaceInteractionSettings interaction =
      const WorkspaceInteractionSettings(),
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final cubit = WorkspaceCubit()
    ..restore(
      WorkspaceLayoutSnapshot(
        mode: WorkspaceMode.swimlane,
        layout: _layout,
        interaction: interaction,
      ),
    );
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider.value(
        value: cubit,
        child: Scaffold(
          body: Focus(
            autofocus: true,
            onKeyEvent: (_, event) =>
                ReaderInputBridge.instance.dispatch(event),
            child: SwimlaneWorkspace(debugLaneContentBuilder: content),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(cubit.close);
  return cubit;
}

Widget _box(String laneId) => SizedBox.expand(key: ValueKey('content-$laneId'));
Finder _lane(String laneId) => find.byKey(ValueKey('content-$laneId'));

void main() {
  testWidgets('键盘目标在 dwell 前即时更新，空白保留目标，内容不重建', (tester) async {
    final bridge = ReaderInputBridge.instance;
    final received = <LogicalKeyboardKey>[];
    KeyEventResult handler(KeyEvent event) {
      if (event is KeyDownEvent) received.add(event.logicalKey);
      return KeyEventResult.handled;
    }

    bridge.attach(handler);
    addTearDown(() => bridge.detach(handler));
    var builds = 0;
    final cubit = await _mount(
      tester,
      content: (id) {
        builds++;
        return _box(id);
      },
    );
    final initialBuilds = builds;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(_lane(LaneId.left)));
    expect(cubit.state.activeLaneId, isNull);
    expect(bridge.activeContexts, {ReaderInputContext.panel});
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(received, isEmpty);
    await mouse.moveTo(tester.getCenter(_lane(LaneId.reader)));
    expect(bridge.activeContexts, {ReaderInputContext.reader});
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(received, [LogicalKeyboardKey.arrowRight]);
    await mouse.moveTo(Offset.zero);
    expect(bridge.activeContexts, {ReaderInputContext.reader});
    await tester.pump();
    expect(builds, initialBuilds);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('编辑和输入法组合保持焦点，跨泳道不触发 reader/global', (tester) async {
    final edit = TextEditingController();
    final native = ScrollController();
    addTearDown(edit.dispose);
    addTearDown(native.dispose);
    final bridge = ReaderInputBridge.instance;
    var readerKeys = 0;
    KeyEventResult handler(KeyEvent event) {
      readerKeys++;
      return KeyEventResult.handled;
    }

    bridge.attach(handler);
    addTearDown(() => bridge.detach(handler));
    final cubit = await _mount(
      tester,
      content: (id) => id == LaneId.left
          ? ListView(
              controller: native,
              children: [
                TextField(key: const ValueKey('editor'), controller: edit),
                const SizedBox(height: 3000),
              ],
            )
          : _box(id),
    );
    await tester.tap(find.byKey(const ValueKey('editor')));
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '拼音',
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    final focus = FocusManager.instance.primaryFocus;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byKey(const ValueKey('editor'))),
        scrollDelta: const Offset(0, 40),
      ),
    );
    await tester.pump();
    expect(native.offset, 40, reason: '打字期间仍可滚动输入框所在的面板');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(_lane(LaneId.reader)));
    expect(bridge.activeContexts, {ReaderInputContext.editor});
    expect(bridge.acceptsReaderKeyboard, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(readerKeys, 0);
    expect(FocusManager.instance.primaryFocus, same(focus));
    expect(edit.value.composing, const TextRange(start: 0, end: 2));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 330)),
    );
    await tester.pump(const Duration(milliseconds: 40));
    expect(cubit.state.activeLaneId, isNull);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('首次滚轮立即原生滚动，burst 跨泳道不执行第二份消费', (tester) async {
    final controllers = {
      for (final id in LaneId.defaultOrder) id: ScrollController(),
    };
    addTearDown(() {
      for (final c in controllers.values) {
        c.dispose();
      }
    });
    final cubit = await _mount(
      tester,
      content: (id) => ListView(
        key: ValueKey('content-$id'),
        controller: controllers[id],
        children: const [SizedBox(height: 3000)],
      ),
    );
    Future<void> wheel(String id) async {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(_lane(id)),
          scrollDelta: const Offset(0, 80),
        ),
      );
      await tester.pump();
    }

    await wheel(LaneId.left);
    expect(controllers[LaneId.left]!.offset, 80);
    expect(cubit.state.activeLaneId, isNull, reason: '视觉定位不抢滚轮序列');
    await wheel(LaneId.reader);
    expect(controllers[LaneId.reader]!.offset, 0);
    expect(ReaderInputBridge.instance.activeContexts, {
      ReaderInputContext.panel,
    });
    await tester.pump(const Duration(milliseconds: 220));
    await wheel(LaneId.reader);
    expect(controllers[LaneId.reader]!.offset, 80);
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('每泳道可选择点击确认键盘目标，定位开关独立', (tester) async {
    final cubit = await _mount(
      tester,
      interaction: const WorkspaceInteractionSettings(
        laneInteractions: {
          LaneId.left: WorkspaceLaneInteraction(
            inputTargetOnHover: false,
            autoReveal: true,
            hoverDelayMs: 80,
          ),
        },
      ),
      content: _box,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(_lane(LaneId.left)));
    expect(ReaderInputBridge.instance.activeContexts, {
      ReaderInputContext.reader,
    });
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 40));
    expect(cubit.state.activeLaneId, LaneId.left);
    expect(ReaderInputBridge.instance.activeContexts, {
      ReaderInputContext.reader,
    }, reason: '视觉驻留不能覆盖点击确认模式的键盘目标');
    await tester.tapAt(tester.getCenter(_lane(LaneId.left)));
    expect(ReaderInputBridge.instance.activeContexts, {
      ReaderInputContext.panel,
    });
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('真实对话框隔离 reader 按键，关闭后恢复目标', (tester) async {
    final bridge = ReaderInputBridge.instance;
    var readerKeys = 0;
    KeyEventResult handler(KeyEvent event) {
      readerKeys++;
      return KeyEventResult.handled;
    }

    bridge.attach(handler);
    addTearDown(() => bridge.detach(handler));
    await _mount(tester, content: _box);
    final context = tester.element(find.byType(Scaffold));
    final dialog = showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(content: Text('弹层拥有键盘')),
    );
    await tester.pumpAndSettle();
    expect(bridge.activeContexts, {ReaderInputContext.modal});
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(readerKeys, 0);
    Navigator.of(context).pop();
    await dialog;
    await tester.pumpAndSettle();
    expect(bridge.activeContexts, {ReaderInputContext.reader});
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(readerKeys, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('modal、拖动和窗口失焦锁住输入目标；多指释放不能提前解除', (tester) async {
    var overlay = false;
    final router = WorkspaceLaneInputRouter(
      hasLane: (id) => LaneId.defaultOrder.contains(id),
      interactionOwned: () => overlay,
      initialLaneId: LaneId.reader,
    );
    addTearDown(router.dispose);
    overlay = true;
    router.hover(LaneId.left, follows: true);
    expect(router.targetLaneId, LaneId.reader);
    expect(router.contexts(), {ReaderInputContext.modal});
    overlay = false;
    router.pointerDown(LaneId.reader, 1);
    router.pointerDown(LaneId.reader, 2);
    router.hover(LaneId.right, follows: true);
    router.pointerUp(1);
    expect(router.blocksAutomatic, isTrue);
    expect(router.targetLaneId, LaneId.reader);
    router.pointerUp(2);
    expect(router.targetLaneId, LaneId.right, reason: '释放后恢复鼠标目标');
    router.didChangeViewFocus(
      const ViewFocusEvent(
        viewId: 0,
        state: ViewFocusState.unfocused,
        direction: ViewFocusDirection.undefined,
      ),
    );
    router.hover(LaneId.left, follows: true);
    expect(ReaderInputBridge.instance.acceptsReaderKeyboard, isFalse);
    expect(router.targetLaneId, LaneId.right);
  });
}
