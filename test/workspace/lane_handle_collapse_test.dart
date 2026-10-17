// 泳道标题栏图标点击折叠泳道的判据。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/workspace/lane_handle_collapse_test.dart
//
// 契约：
// 1. 常规展开状态下，栏头最左侧的泳道图标是可点击的，点击即可触发折叠（onToggleCollapse）。
// 2. 常规展开状态下，栏头最左侧图标悬停提示为「$title (点击折叠泳道)」。
// 3. 折叠为紧凑轨后，紧凑轨顶部的泳道图标点击可触发展开（onToggleCollapse）。
// 4. 编辑排序模式下，点击图标同样能折叠泳道，长按则保持可拖动重排能力。

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/widgets/swimlane/swimlane_column.dart';
import 'package:zephyr/workspace/widgets/swimlane/swimlane_workspace.dart';

const String _leftTitle = '泳道-左';
const String _readerTitle = '泳道-中';
const String _rightTitle = '泳道-右';

const WorkspaceLayoutConfig _testLayout = WorkspaceLayoutConfig(
  laneOrder: LaneId.defaultOrder,
  lanes: <String, LaneConfig>{
    LaneId.left: LaneConfig(
      width: 400,
      minWidth: 300,
      maxWidth: 600,
      title: _leftTitle,
    ),
    LaneId.reader: LaneConfig(
      width: 300,
      widthRatio: 0.25,
      minWidth: 300,
      maxWidth: 900,
      title: _readerTitle,
    ),
    LaneId.right: LaneConfig(
      width: 400,
      minWidth: 300,
      maxWidth: 600,
      title: _rightTitle,
    ),
  },
);

final WorkspaceLayoutSnapshot _testSnapshot = WorkspaceLayoutSnapshot(
  mode: WorkspaceMode.swimlane,
  layout: _testLayout,
);

const Size _windowSize = Size(1200, 900);

Widget _probeContent(String laneId) => const SizedBox.expand();

Finder _laneScope(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(SwimlaneColumn));

Finder _laneHandleIcon(String title, Glyph glyph) => find.descendant(
      of: _laneScope(title),
      matching: find.byWidgetPredicate((w) => w is GlyphIcon && w.glyph == glyph),
    );

Future<WorkspaceCubit> _pumpWorkspace(WidgetTester tester) async {
  tester.view.physicalSize = _windowSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final cubit = WorkspaceCubit();
  addTearDown(cubit.close);
  cubit.restore(_testSnapshot);

  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<WorkspaceCubit>.value(
        value: cubit,
        child: const Scaffold(
          body: SwimlaneWorkspace(debugLaneContentBuilder: _probeContent),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cubit;
}

void main() {
  testWidgets('点击展开泳道标题栏的图标折叠泳道，点击紧凑轨图标恢复展开', (tester) async {
    final cubit = await _pumpWorkspace(tester);

    // 初始状态：左泳道展开
    expect(cubit.state.layout.lanes[LaneId.left]!.collapsed, isFalse);

    // 找到左泳道栏头左侧的身份图标（AppGlyphs.book，取栏头左侧第一个）
    final handleIcons = _laneHandleIcon(_leftTitle, AppGlyphs.book);
    expect(handleIcons, findsAtLeastNWidgets(1));
    final handleIcon = handleIcons.first;

    // 验证 Tooltip 包含折叠提示
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: handleIcon, matching: find.byType(Tooltip)).first,
    );
    expect(tooltip.message, contains('点击折叠泳道'));

    // 点击栏头图标
    await tester.tap(handleIcon);
    await tester.pumpAndSettle();

    // 左泳道状态变为已折叠
    expect(cubit.state.layout.lanes[LaneId.left]!.collapsed, isTrue);

    // 折叠成紧凑轨后，顶部依然是左泳道图标（AppGlyphs.book）
    final railIcons = _laneHandleIcon(_leftTitle, AppGlyphs.book);
    expect(railIcons, findsAtLeastNWidgets(1));
    final railIcon = railIcons.first;

    // 验证紧凑轨图标的 Tooltip 包含展开提示
    final railTooltip = tester.widget<Tooltip>(
      find.ancestor(of: railIcon, matching: find.byType(Tooltip)).first,
    );
    expect(railTooltip.message, contains('点击展开泳道'));

    // 点击紧凑轨顶部的图标
    await tester.tap(railIcon);
    await tester.pumpAndSettle();

    // 左泳道重新展开
    expect(cubit.state.layout.lanes[LaneId.left]!.collapsed, isFalse);
  });

  testWidgets('编辑排序模式下点击标题栏图标同样能折叠泳道', (tester) async {
    final cubit = await _pumpWorkspace(tester);

    // 通过更多菜单进入编辑布局模式
    await tester.tap(_laneHandleIcon(_leftTitle, AppGlyphs.more));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑布局'));
    await tester.pumpAndSettle();

    expect(cubit.state.interaction.panelTabSortMode, isTrue);

    // 找到左泳道栏头左侧图标
    final handleIcons = _laneHandleIcon(_leftTitle, AppGlyphs.book);
    expect(handleIcons, findsAtLeastNWidgets(1));
    final handleIcon = handleIcons.first;

    // 点击栏头图标
    await tester.tap(handleIcon);
    await tester.pumpAndSettle();

    // 验证泳道被折叠
    expect(cubit.state.layout.lanes[LaneId.left]!.collapsed, isTrue);
  });
}
