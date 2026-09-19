import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_controller.dart';
import 'package:zephyr/page/comic_read/controller/reader_input_controller.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/method/reader_gesture_logic.dart';

// ── 这一组判据盯的是什么 ────────────────────────────────────────────────────
//
// 「阅读器泳道里点击只翻下一页、上下栏再也唤不出来、左边点不出上一页」
// ——三个症状其实是**同一个** bug：点击分区拿到的落点是**窗口**坐标，
// 而参照的面是**泳道**尺寸。工作台里阅读器泳道左边还压着一条面板泳道，
// 于是窗口坐标里几乎每个点都落在「右半」与「后两栏」：
//
//   1. 右边那一档恒真 ⇒ 点哪儿都是下一页（翻页又会把上下栏收起，
//      `RowModeWidget` / `ColumnModeWidget` 翻页即 `updateMenuVisible(false)`）；
//   2. 中间那一格 `dx ∈ [w/3, 2w/3)` 在窗口坐标下够不着 ⇒ 上下栏唤不出来；
//   3. 左边那一档 `dx < w/2` 同样够不着 ⇒ 上一页点不出来。
//
// 所以判据必须**在泳道几何下**跑（泳道比窗口窄、且不贴窗口左上角）：
// 泳道与窗口重合时（独立阅读器）这个 bug 根本不显形，用那种几何写的判据
// 会给出假绿。三种几何都跑一遍正是为了钉死这一点。

/// 「这一次点击被分区判成了哪一档」——三个出口都记进同一条流水。
class _ZoneRecorder {
  final List<String> events = <String>[];

  void menu() => events.add('menu');
}

class _SpyActionController extends ReaderActionController {
  _SpyActionController({
    required super.context,
    required super.scrollController,
    required super.pageController,
    required this.recorder,
  });

  final _ZoneRecorder recorder;

  @override
  void onPageActionNext() => recorder.events.add('next');

  @override
  void onPageActionPrev() => recorder.events.add('prev');
}

/// 只改阅读设置，不落盘（`GlobalSettingCubit.updateState` 会写 ObjectBox）。
class _TestSettingCubit extends GlobalSettingCubit {
  _TestSettingCubit({required ReadSettingState read}) : super() {
    emit(state.copyWith(readSetting: read));
  }
}

/// 真 [ReaderInputController]（不是替身）——被测的就是它手里那对落点/尺码。
class _LaneHarness extends StatefulWidget {
  const _LaneHarness({super.key, required this.recorder});

  final _ZoneRecorder recorder;

  @override
  State<_LaneHarness> createState() => _LaneHarnessState();
}

class _LaneHarnessState extends State<_LaneHarness> {
  final _pageController = PageController();
  final _scrollController = ScrollController();
  final _transformationController = TransformationController();
  late final ReaderInputController _input;

  @override
  void initState() {
    super.initState();
    final recorder = widget.recorder;
    _input = ReaderInputController(
      context: context,
      readerCubit: context.read<ReaderCubit>(),
      pageController: _pageController,
      transformationController: _transformationController,
      onToggleMenu: recorder.menu,
      onToggleDesktopFullscreen: () async {},
      onRefreshState: () {},
      isScrollLockedByMultiTouch: () => false,
      onUpdateScrollLock: (_) {},
      buildColumnMode: (_) => const ColoredBox(color: Colors.red),
      buildRowMode: () => const ColoredBox(color: Colors.blue),
    );
    _input.setActionController(
      _SpyActionController(
        context: context,
        scrollController: _scrollController,
        pageController: _pageController,
        recorder: recorder,
      ),
    );
  }

  @override
  void dispose() {
    _input.dispose();
    _pageController.dispose();
    _scrollController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _input.buildInteractiveViewer();
}

/// 一块几何：窗口多大、阅读区（泳道）多大、它在窗口里的左上角在哪。
typedef _Geometry = ({String label, Size window, Size lane, Offset laneOrigin});

const _workbench = (
  label: '工作台几何（左面板把阅读器泳道挤到右边）',
  window: Size(1600, 1000),
  lane: Size(800, 800),
  laneOrigin: Offset(400, 60),
);

const _workbenchNarrow = (
  label: '工作台几何（另一个窗口尺寸）',
  window: Size(1000, 900),
  lane: Size(800, 800),
  laneOrigin: Offset(180, 40),
);

const _standalone = (
  label: '独立阅读器几何（阅读区就是整个窗口）',
  window: Size(800, 800),
  lane: Size(800, 800),
  laneOrigin: Offset.zero,
);

/// 把阅读器放进 [geometry] 那块阅读区里，并把 `MediaQuery.size` 改写成它 ——
/// 泳道宿主（`WorkspaceReaderHost`）就是这么干的。
Future<_ZoneRecorder> _pumpReader(
  WidgetTester tester,
  _Geometry geometry, {
  required ReadSettingState read,
}) async {
  tester.view.physicalSize = geometry.window;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final recorder = _ZoneRecorder();
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<GlobalSettingCubit>(
        create: (_) => _TestSettingCubit(read: read),
        child: BlocProvider<ReaderCubit>(
          create: (_) => ReaderCubit(),
          child: Builder(
            builder: (context) => Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: EdgeInsets.only(
                  left: geometry.laneOrigin.dx,
                  top: geometry.laneOrigin.dy,
                ),
                child: SizedBox(
                  width: geometry.lane.width,
                  height: geometry.lane.height,
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(size: geometry.lane),
                    // 每条几何一个 key：不然 `pumpWidget` 会复用 Element、
                    // `initState` 不再执行，控制器还连着上一块几何。
                    child: _LaneHarness(
                      key: ValueKey<String>(geometry.label),
                      recorder: recorder,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return recorder;
}

/// 点阅读区里 [laneLocal] 那个点（**窗口**落点由几何换算出来，走真实命中测试）。
Future<void> _tapLane(
  WidgetTester tester,
  _Geometry geometry,
  Offset laneLocal,
) async {
  await tester.tapAt(geometry.laneOrigin + laneLocal);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// 右手模式的常用坐标：左半 / 正中 / 右半。
const _left = Offset(100, 400);
const _center = Offset(400, 400);
const _right = Offset(700, 400);

void main() {
  const rightHandRow = ReadSettingState(
    readMode: 1,
    tapPageTurnMode: ReaderTapPageTurnMode.rightHand,
  );

  group('泳道里的点击分区（真 ReaderInputController + 真实命中测试）', () {
    for (final geometry in <_Geometry>[
      _workbench,
      _workbenchNarrow,
      _standalone,
    ]) {
      testWidgets('${geometry.label}：分区只跟「手指底下这块面」走', (tester) async {
        final recorder = await _pumpReader(
          tester,
          geometry,
          read: rightHandRow,
        );

        await _tapLane(tester, geometry, _center);
        await _tapLane(tester, geometry, _left);
        await _tapLane(tester, geometry, _right);

        expect(recorder.events, [
          'menu',
          'prev',
          'next',
        ], reason: '正中=唤出上下栏、左半=上一页、右半=下一页；实际 ${recorder.events}');
      });
    }

    testWidgets('中间那一档只是正中那一格（横向居中但纵向顶上 ⇒ 仍是翻页）', (tester) async {
      final recorder = await _pumpReader(
        tester,
        _workbench,
        read: rightHandRow,
      );

      // 泳道正中偏上 60px：横向落在中间三分之一里，纵向落在上三分之一里。
      await _tapLane(tester, _workbench, const Offset(400, 60));

      expect(
        recorder.events,
        ['next'],
        reason:
            '中心控制区是正中那一格（横竖都在中间那三分之一），不是整条中轴；'
            '否则「点上部想唤出顶栏」会变成翻页',
      );
    });

    testWidgets('条漫默认（竖向 + 未开「条漫点击翻页」）⇒ 点哪儿都只唤出上下栏', (tester) async {
      final recorder = await _pumpReader(
        tester,
        _workbench,
        read: const ReadSettingState(),
      );

      await _tapLane(tester, _workbench, _left);
      await _tapLane(tester, _workbench, _center);
      await _tapLane(tester, _workbench, _right);

      expect(recorder.events, ['menu', 'menu', 'menu']);
    });

    testWidgets('全屏点击翻页档：正中仍是唤出上下栏，其余两半按这一档的定义翻页', (tester) async {
      final recorder = await _pumpReader(
        tester,
        _workbench,
        read: const ReadSettingState(
          readMode: 1,
          tapPageTurnMode: ReaderTapPageTurnMode.fullScreen,
        ),
      );

      await _tapLane(tester, _workbench, _center);
      await _tapLane(tester, _workbench, _left);
      await _tapLane(tester, _workbench, _right);

      expect(
        recorder.events,
        ['menu', 'next', 'next'],
        reason:
            'fullScreen 档下左右两侧都是下一页是**契约**（不是 bug）；'
            '但正中那一格必须留给上下栏，否则这一档下用户没有任何唤出 chrome 的出口',
      );
    });

    // ── 「点击唤出/收起上下栏」是可以关的（设置 → 手势） ──────────────────────
    //
    // 关掉的是**这一档动作**，不是整个分区：左右两半照旧翻页，正中只是什么都不做。
    testWidgets('关掉「点击唤出上下栏」后：正中不再唤出，左右两半照旧翻页', (tester) async {
      final recorder = await _pumpReader(
        tester,
        _workbench,
        read: const ReadSettingState(
          readMode: 1,
          tapPageTurnMode: ReaderTapPageTurnMode.rightHand,
          centerTapToggleBars: false,
        ),
      );

      await _tapLane(tester, _workbench, _center);
      await _tapLane(tester, _workbench, _left);
      await _tapLane(tester, _workbench, _right);

      expect(recorder.events, [
        'prev',
        'next',
      ], reason: '正中那一档被关掉后什么都不做；分区本身没变');
    });

    // 条漫默认档下「点哪儿都算中间」（`isWebtoon && !tapPageTurnInWebtoon` 那条早退），
    // 而默认阅读模式就是条漫 —— 这一档要是不跟着关，这个开关在默认设置下等于没做。
    testWidgets('关掉后条漫「点哪儿都算中间」也一并关掉', (tester) async {
      final recorder = await _pumpReader(
        tester,
        _workbench,
        read: const ReadSettingState(centerTapToggleBars: false),
      );

      await _tapLane(tester, _workbench, _left);
      await _tapLane(tester, _workbench, _center);
      await _tapLane(tester, _workbench, _right);

      expect(
        recorder.events,
        isEmpty,
        reason:
            '默认（条漫）模式下用户能按到的每一处都是「中间那一档」，'
            '只关正中那一格等于这个开关没生效',
      );
    });
  });

  group('分区函数的退化输入', () {
    const normal = Size(800, 800);

    ReaderTapZone zone({
      required Offset at,
      required Size viewport,
      bool isWebtoon = false,
      bool tapPageTurnInWebtoon = false,
      ReaderTapPageTurnMode mode = ReaderTapPageTurnMode.rightHand,
    }) => ReaderGestureLogic.resolveTapZone(
      sample: ReaderTapSample(localPosition: at, viewportSize: viewport),
      isWebtoon: isWebtoon,
      tapPageTurnInWebtoon: tapPageTurnInWebtoon,
      mode: mode,
    );

    // 对照：正常尺寸下这一档就是「正中唤出 / 左半上一页」，守卫不吃正常路径。
    test('正常尺寸：正中唤出上下栏、左半上一页', () {
      expect(zone(at: _center, viewport: normal), ReaderTapZone.toggleMenu);
      expect(zone(at: _left, viewport: normal), ReaderTapZone.previousPage);
      expect(zone(at: _right, viewport: normal), ReaderTapZone.nextPage);
    });

    // 尺寸拿不到时不许落到翻页分支：0 ⇒ 「右半」恒真（点哪儿都下一页），
    // 无穷 ⇒ 「右半」恒假（点哪儿都上一页）。两者都是静默的、用户没法自救。
    test('视口尺寸为 0 ⇒ 唤出上下栏（不是下一页）', () {
      expect(zone(at: _center, viewport: Size.zero), ReaderTapZone.toggleMenu);
      expect(zone(at: _left, viewport: Size.zero), ReaderTapZone.toggleMenu);
      expect(zone(at: _right, viewport: Size.zero), ReaderTapZone.toggleMenu);
    });

    test('视口尺寸非有限 ⇒ 唤出上下栏', () {
      const infinite = Size(double.infinity, double.infinity);
      expect(zone(at: _center, viewport: infinite), ReaderTapZone.toggleMenu);
      expect(zone(at: _left, viewport: infinite), ReaderTapZone.toggleMenu);
    });

    test('条漫 + 开了「条漫点击翻页」：上下半按这一档翻页，正中仍是上下栏', () {
      expect(
        zone(
          at: const Offset(100, 700),
          viewport: normal,
          isWebtoon: true,
          tapPageTurnInWebtoon: true,
        ),
        ReaderTapZone.nextPage,
      );
      expect(
        zone(
          at: const Offset(100, 100),
          viewport: normal,
          isWebtoon: true,
          tapPageTurnInWebtoon: true,
        ),
        ReaderTapZone.previousPage,
      );
      expect(
        zone(
          at: _center,
          viewport: normal,
          isWebtoon: true,
          tapPageTurnInWebtoon: true,
        ),
        ReaderTapZone.toggleMenu,
      );
    });
  });
}
