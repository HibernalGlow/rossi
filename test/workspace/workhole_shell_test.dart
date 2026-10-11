import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_workhole.dart';
import 'package:zephyr/workspace/widgets/edges/controlled_edge_shell.dart';
import 'package:zephyr/workspace/widgets/edges/workhole_panel.dart';

Finder _handle(WorkspacePanelSide side) =>
    find.byKey(ValueKey('workhole-handle-${side.name}'));

Finder _panel(WorkspacePanelSide side) => find.byWidgetPredicate(
  (widget) => widget is WorkholePanel && widget.side == side,
);

Future<WorkspaceCubit> _mount(
  WidgetTester tester, {
  Size viewport = const Size(1200, 800),
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final cubit = WorkspaceCubit();
  addTearDown(cubit.close);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BlocProvider.value(
          value: cubit,
          child: ControlledEdgeShell(
            debugLaneContentBuilder: (id) => _ContentProbe(key: ValueKey(id)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return cubit;
}

// 先越过 Flutter 的手势识别距离，再用分帧移动验证浮层出现后同一手势仍在。
Future<TestGesture> _beginDrag(
  WidgetTester tester,
  WorkspacePanelSide side,
) async {
  final gesture = await tester.startGesture(tester.getCenter(_handle(side)));
  await gesture.moveBy(Offset(side == WorkspacePanelSide.left ? 24 : -24, 0));
  await tester.pump();
  return gesture;
}

void main() {
  for (final side in WorkspacePanelSide.values) {
    final direction = side == WorkspacePanelSide.left ? 1.0 : -1.0;
    testWidgets('${side.name}: tap opens workbench without moving reader', (
      tester,
    ) async {
      final cubit = await _mount(tester);
      final reader = find.byKey(const ValueKey(LaneId.reader));
      final readerState = tester.state(reader);
      final readerRect = tester.getRect(reader);
      final panelState = tester.state(find.byKey(ValueKey(side.laneId)));
      await tester.tap(_handle(side));
      await tester.pumpAndSettle();
      final layout = cubit.state.layout;
      expect(
        side == WorkspacePanelSide.left
            ? layout.edgeLeftSize
            : layout.edgeRightSize,
        WorkspaceWorkholeSize.workbench,
      );
      expect(tester.getSize(_panel(side)).width, 684);
      expect(tester.getRect(reader), readerRect);
      expect(tester.state(reader), same(readerState));
      expect(tester.state(find.byKey(ValueKey(side.laneId))), same(panelState));
      await tester.tap(_handle(side));
      await tester.pumpAndSettle();
      expect(tester.getRect(_panel(side)).overlaps(readerRect), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '${side.name}: continuous closed drag reaches peek and closes',
      (tester) async {
        final cubit = await _mount(tester);
        final drag = await _beginDrag(tester, side);
        await drag.moveBy(Offset(80 * direction, 0));
        await tester.pump();
        expect(
          tester.getRect(_panel(side)).left,
          side == WorkspacePanelSide.left ? 18 : 962,
        );
        await drag.moveBy(Offset(20 * direction, 0));
        await tester.pump();
        await drag.up();
        await tester.pumpAndSettle();
        expect(
          side == WorkspacePanelSide.left
              ? cubit.state.layout.edgeLeftSize
              : cubit.state.layout.edgeRightSize,
          WorkspaceWorkholeSize.peek,
        );
        expect(tester.getSize(_panel(side)).width, 408);
        final close = await _beginDrag(tester, side);
        await close.moveBy(Offset(-380 * direction, 0));
        await tester.pump();
        await close.up();
        await tester.pumpAndSettle();
        expect(
          side == WorkspacePanelSide.left
              ? cubit.state.layout.edgeLeftOpen
              : cubit.state.layout.edgeRightOpen,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('${side.name}: custom resize, preset snap and cancellation', (
      tester,
    ) async {
      final cubit = await _mount(tester);
      await tester.tap(_handle(side));
      await tester.pumpAndSettle();
      final drag = await _beginDrag(tester, side);
      await drag.moveBy(Offset(70 * direction, 0));
      await tester.pump();
      await drag.moveBy(Offset(76 * direction, 0));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(tester.getSize(_panel(side)).width, 830);
      expect(
        side == WorkspacePanelSide.left
            ? cubit.state.layout.edgeLeftWidth
            : cubit.state.layout.edgeRightWidth,
        830,
      );
      final cancel = await _beginDrag(tester, side);
      await cancel.moveBy(Offset(-180 * direction, 0));
      await tester.pump();
      await cancel.cancel();
      await tester.pumpAndSettle();
      expect(tester.getSize(_panel(side)).width, 830);
      final snap = await _beginDrag(tester, side);
      await snap.moveBy(Offset(-140 * direction, 0));
      await tester.pump();
      await snap.up();
      await tester.pumpAndSettle();
      expect(tester.getSize(_panel(side)).width, 684);
      expect(
        side == WorkspacePanelSide.left
            ? cubit.state.layout.edgeLeftWidth
            : cubit.state.layout.edgeRightWidth,
        isNull,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'takeover footer and reset change size without remounting reader',
    (tester) async {
      final cubit = await _mount(tester);
      final reader = find.byKey(const ValueKey(LaneId.reader));
      final readerState = tester.state(reader);
      await tester.tap(_handle(WorkspacePanelSide.left));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: _panel(WorkspacePanelSide.left),
          matching: find.text('takeover'),
        ),
      );
      await tester.pumpAndSettle();
      expect(cubit.state.layout.edgeLeftSize, WorkspaceWorkholeSize.takeover);
      expect(tester.getSize(_panel(WorkspacePanelSide.left)).width, 1032);
      await tester.tap(
        find.descendant(
          of: _panel(WorkspacePanelSide.left),
          matching: find.byTooltip('恢复默认尺寸'),
        ),
      );
      await tester.pumpAndSettle();
      expect(cubit.state.layout.edgeLeftSize, WorkspaceWorkholeSize.workbench);
      expect(tester.state(reader), same(readerState));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('narrow viewport contains panels and scrolls size controls', (
    tester,
  ) async {
    final cubit = await _mount(tester, viewport: const Size(240, 600));
    cubit.setEdgeWorkholeSize(
      WorkspacePanelSide.left,
      WorkspaceWorkholeSize.peek,
    );
    await tester.pumpAndSettle();
    final rect = tester.getRect(_panel(WorkspacePanelSide.left));
    expect(rect.left, 18);
    expect(rect.right, 222);
    expect(tester.takeException(), isNull);
  });
}

class _ContentProbe extends StatefulWidget {
  const _ContentProbe({super.key});

  @override
  State<_ContentProbe> createState() => _ContentProbeState();
}

class _ContentProbeState extends State<_ContentProbe> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
