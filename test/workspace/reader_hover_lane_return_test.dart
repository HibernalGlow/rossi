import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/cubit/comic_read_preference_cubit.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_presentation_cubit.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/app_bar.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/reader_chrome_transition.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/reader_hover_reveal_layer.dart';
import 'package:zephyr/util/input/binding_input_capture.dart';
import 'package:zephyr/util/input/reader_input_bridge.dart';
import 'package:zephyr/util/input/reader_input_context.dart';
import 'package:zephyr/util/input/reader_input_guard.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_interaction_settings.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/widgets/swimlane/swimlane_workspace.dart';
import 'package:zephyr/workspace/widgets/reader/reader_viewport.dart';

class _Settings extends GlobalSettingCubit {
  _Settings() {
    emit(
      state.copyWith(
        readSetting: const ReadSettingState(hoverHideDelayMs: 100),
      ),
    );
  }
}

class _ReaderProbe extends StatefulWidget {
  const _ReaderProbe();

  @override
  State<_ReaderProbe> createState() => _ReaderProbeState();
}

class _ReaderBar extends StatelessWidget {
  const _ReaderBar({required this.top, required this.hover});

  final bool top;
  final ReaderHoverController hover;

  @override
  Widget build(BuildContext context) {
    // 与真实栏体一致：通过 provider 的 select 订阅，验证实际动画与状态。
    final visible = context.select(
      (ReaderCubit cubit) => top
          ? cubit.state.showTopAppBar(pinned: false)
          : cubit.state.showBottomBar(pinned: false),
    );
    return ReaderChromeTransition(
      visible: visible,
      top: top,
      child: MouseRegion(
        onEnter: (_) => top ? hover.onEnterTopBar() : hover.onEnterBottomBar(),
        onExit: (_) => top ? hover.onExitTopBar() : hover.onExitBottomBar(),
        child: ColoredBox(
          key: ValueKey(top ? 'reader-top-bar' : 'reader-bottom-bar'),
          color: Colors.white,
          child: const SizedBox(height: 60),
        ),
      ),
    );
  }
}

class _ReaderHostProbe extends StatelessWidget {
  const _ReaderHostProbe();

  @override
  Widget build(BuildContext context) => ReaderViewport(
    child: Navigator(
      onGenerateRoute: (_) =>
          MaterialPageRoute<void>(builder: (_) => const _ReaderProbe()),
    ),
  );
}

class _ReaderProbeState extends State<_ReaderProbe> {
  late final _hover = ReaderHoverController(context);

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final setting = context.read<GlobalSettingCubit>().state.readSetting;
    _hover.updateContext(context, readSetting: setting);
    Widget bar(bool top) => Positioned(
      top: top ? 8 : null,
      bottom: top ? null : 8,
      left: 8,
      right: 8,
      child: _ReaderBar(top: top, hover: _hover),
    );
    return ReaderHoverScope(
      controller: _hover,
      child: ReaderHoverStack(
        key: const ValueKey('reader-viewport'),
        controller: _hover,
        readSetting: setting,
        children: [
          Positioned.fill(
            child: BindingPointerSignalRegion(
              onPointerSignal: (_) {},
              child: const ColoredBox(color: Colors.grey),
            ),
          ),
          ComicReadAppBar(title: '悬停回归', changePageIndex: (_) {}),
          bar(false),
        ],
      ),
    );
  }
}

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

Future<void> _dwell(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 250)),
  );
  await tester.pump(const Duration(milliseconds: 40));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => SharedPreferences.setMockInitialValues({}));
  for (final width in [1200.0, 800.0]) {
    testWidgets('离开阅读泳道再回来，上下栏仍可悬停唤出（width=$width）', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final workspace = WorkspaceCubit()
        ..restore(
          const WorkspaceLayoutSnapshot(
            mode: WorkspaceMode.swimlane,
            layout: _layout,
            interaction: WorkspaceInteractionSettings(hoverFocusDelayMs: 80),
          ),
        )
        ..activateLane(LaneId.reader);
      final reader = ReaderCubit()..updateMenuVisible(visible: false);
      final settings = _Settings();
      final presentation = ReaderPresentationCubit(settings: settings);
      final preference = ComicReadPreferenceCubit();
      addTearDown(workspace.close);
      addTearDown(reader.close);
      addTearDown(settings.close);
      addTearDown(presentation.close);
      addTearDown(preference.close);
      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<WorkspaceCubit>.value(value: workspace),
              BlocProvider<ReaderCubit>.value(value: reader),
              BlocProvider<GlobalSettingCubit>.value(value: settings),
              BlocProvider<ReaderPresentationCubit>.value(value: presentation),
              BlocProvider<ComicReadPreferenceCubit>.value(value: preference),
            ],
            child: Scaffold(
              body: SwimlaneWorkspace(
                debugLaneContentBuilder: (id) => id == LaneId.reader
                    ? const _ReaderHostProbe()
                    : ColoredBox(
                        key: ValueKey('panel-$id'),
                        color: Colors.blue,
                        child: const Align(
                          alignment: Alignment.center,
                          child: TextField(),
                        ),
                      ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      final viewport = find.byKey(const ValueKey('reader-viewport'));
      for (var i = 0; i < 3; i++) {
        await mouse.moveTo(tester.getCenter(viewport));
        await _dwell(tester);
        for (final top in [true, false]) {
          final rect = tester.getRect(viewport);
          await mouse.moveTo(
            Offset(rect.center.dx, top ? rect.top + 20 : rect.bottom - 20),
          );
          await tester.pumpAndSettle();
          expect(
            top ? reader.state.isTopHovered : reader.state.isBottomHovered,
            isTrue,
            reason: 'cycle=$i top=$top',
          );
          final opacity = tester.widget<Opacity>(
            find
                .descendant(
                  of: find.byType(ReaderChromeTransition).at(top ? 0 : 1),
                  matching: find.byType(Opacity),
                )
                .first,
          );
          expect(opacity.opacity, 1, reason: '栏体实际显示 cycle=$i top=$top');
        }
        // 左泳道有一部分在视口内，先移过去让绑定目标与视觉定位真正切换。
        final panelRect = tester.getRect(
          find.byKey(const ValueKey('panel-left')),
        );
        final panelX = panelRect.center.dx.clamp(20.0, width - 20);
        await mouse.moveTo(Offset(panelX, panelRect.center.dy));
        await _dwell(tester);
        expect(ReaderInputBridge.instance.activeContexts, {
          ReaderInputContext.panel,
        });
        expect(workspace.state.activeLaneId, LaneId.left);
        expect(reader.state.isTopHovered, isFalse);
        expect(reader.state.isBottomHovered, isFalse);
      }
      // 面板输入框持有键盘焦点时，阅读器的鼠标悬停仍应独立工作。
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      expect(ReaderInputGuard.isEditing, isTrue);
      for (final top in [true, false]) {
        final rect = tester.getRect(viewport);
        final x = rect.center.dx.clamp(20.0, width - 20);
        await mouse.moveTo(Offset(x, top ? rect.top + 20 : rect.bottom - 20));
        await tester.pumpAndSettle();
        expect(
          top ? reader.state.isTopHovered : reader.state.isBottomHovered,
          isTrue,
        );
        expect(ReaderInputGuard.isEditing, isTrue);
      }
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
    });
  }
}
