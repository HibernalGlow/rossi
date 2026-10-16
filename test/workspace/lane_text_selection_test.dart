import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_interaction_settings.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/widgets/swimlane/swimlane_workspace.dart';

const _text = 'alpha beta gamma delta';
const _contentKey = Key('selection-content');

Future<ScrollPosition> _mount(WidgetTester tester, Widget content) async {
  tester.view.physicalSize = const Size(900, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final cubit = WorkspaceCubit()
    ..restore(
      const WorkspaceLayoutSnapshot(
        mode: WorkspaceMode.swimlane,
        layout: WorkspaceLayoutConfig(
          laneOrder: LaneId.defaultOrder,
          lanes: {
            LaneId.left: LaneConfig(width: 400, title: 'Left'),
            LaneId.reader: LaneConfig(
              width: 400,
              minWidth: 400,
              title: 'Reader',
            ),
            LaneId.right: LaneConfig(width: 400, title: 'Right'),
          },
        ),
        interaction: WorkspaceInteractionSettings(
          hoverFocusEnabled: false,
          panelHoverFocusEnabled: false,
        ),
      ),
    )
    ..activateLane(LaneId.left);
  addTearDown(cubit.close);
  await tester.pumpWidget(
    MaterialApp(
      // 复现应用的全局鼠标拖动配置；默认 Material 行为会掩盖冲突。
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
      ),
      home: BlocProvider.value(
        value: cubit,
        child: Scaffold(
          body: SwimlaneWorkspace(
            debugLaneContentBuilder: (id) => id == LaneId.left
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: content,
                    ),
                  )
                : const SizedBox.expand(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final position = tester
      .state<ScrollableState>(
        find
            .ancestor(
              of: find.byKey(_contentKey),
              matching: find.byType(Scrollable),
            )
            .last,
      )
      .position;
  expect(position.axis, Axis.horizontal);
  expect(position.maxScrollExtent, greaterThan(200));
  expect(position.pixels, 0);
  return position;
}

Future<void> _dragText(WidgetTester tester) async {
  final rect = tester.getRect(find.byKey(_contentKey));
  final gesture = await tester.startGesture(
    rect.topLeft + Offset(240, rect.height / 2),
    kind: PointerDeviceKind.mouse,
  );
  for (var i = 1; i <= 10; i++) {
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void _testOnDesktop(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  _testOnDesktop('鼠标拖选输入框文字不横移泳道', (tester) async {
    final controller = TextEditingController(text: _text);
    addTearDown(controller.dispose);
    final position = await _mount(
      tester,
      TextField(key: _contentKey, controller: controller),
    );
    await _dragText(tester);
    expect(controller.selection.isCollapsed, isFalse);
    expect(position.pixels, 0);
  });

  _testOnDesktop('鼠标拖选 SelectableText 不横移泳道', (tester) async {
    TextSelection? selection;
    final position = await _mount(
      tester,
      SelectableText(
        _text,
        key: _contentKey,
        onSelectionChanged: (value, _) => selection = value,
      ),
    );
    await _dragText(tester);
    expect(selection, isNotNull);
    expect(selection!.isCollapsed, isFalse);
    expect(position.pixels, 0);
  });

  _testOnDesktop('鼠标拖选 SelectionArea 不横移泳道', (tester) async {
    String? selected;
    final position = await _mount(
      tester,
      SelectionArea(
        onSelectionChanged: (value) => selected = value?.plainText,
        child: const Text(_text, key: _contentKey),
      ),
    );
    await _dragText(tester);
    expect(selected, isNotEmpty);
    expect(position.pixels, 0);
  });

  _testOnDesktop('鼠标从内容空白处拖动也不横移泳道', (tester) async {
    final position = await _mount(
      tester,
      const SizedBox(key: _contentKey, width: 300, height: 100),
    );
    await _dragText(tester);
    expect(position.pixels, 0);
  });

  _testOnDesktop('触屏拖动和横向滚轮信号仍可移动泳道', (tester) async {
    final position = await _mount(
      tester,
      const SizedBox(key: _contentKey, width: 300, height: 100),
    );
    final center = tester.getCenter(find.byKey(_contentKey));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(100, 0)),
    );
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    final before = position.pixels;
    await tester.dragFrom(center, const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(before));
  });
}
