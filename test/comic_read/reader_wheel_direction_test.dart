import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_controller.dart';
import 'package:zephyr/page/comic_read/controller/reader_input_controller.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';
import 'package:zephyr/src/rust/frb_generated.dart';
import 'package:zephyr/util/input/reader_input_bridge.dart';
import 'package:zephyr/util/input/reader_input_context.dart';

/// 滚轮 × 阅读方向。真起 Rust 引擎，PageView 用和 `RowModeWidget` 同一种反转
/// （`reverse: isReverseRowReadMode(readMode)`），所以「下一页在左边」这件事是现场算出来的，
/// 不是测试里假设的。
class _Reader extends StatefulWidget {
  const _Reader({super.key, required this.readMode, required this.start});

  final int readMode;
  final int start;

  @override
  State<_Reader> createState() => _ReaderState();
}

class _ReaderState extends State<_Reader> {
  late final PageController pages = PageController(initialPage: widget.start);
  final ScrollController scroll = ScrollController(initialScrollOffset: 800);
  final TransformationController transform = TransformationController();
  late final ReaderInputController input;

  /// 当前落在第几页：以 `PageView` 自己的索引为准（左开时它对应画面左边那一页）。
  int get slot => context.read<ReaderCubit>().state.currentSlot;

  @override
  void initState() {
    super.initState();
    final reader = context.read<ReaderCubit>()
      ..updateTotalSlots(10)
      ..updateCurrentSlot(widget.start);
    input = ReaderInputController(
      context: context,
      readerCubit: reader,
      pageController: pages,
      transformationController: transform,
      onToggleMenu: () {},
      onToggleDesktopFullscreen: () async {},
      onRefreshState: () => setState(() {}),
      isScrollLockedByMultiTouch: () => false,
      onUpdateScrollLock: (_) {},
      buildColumnMode: (_) => const SizedBox.shrink(),
      buildRowMode: () => PageView.builder(
        controller: pages,
        reverse: isReverseRowReadMode(widget.readMode),
        itemCount: 10,
        onPageChanged: reader.updateCurrentSlot,
        itemBuilder: (_, i) => Text('$i'),
      ),
    );
    input.setActionController(
      ReaderActionController(
        context: context,
        scrollController: scroll,
        pageController: pages,
      ),
    );
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
  required int readMode,
  required bool noAnimation,
  required String bindingsDocJson,
}) async {
  final cubit = GlobalSettingCubit()
    ..emit(
      GlobalSettingState().copyWith(
        readSetting: ReadSettingState(
          readMode: readMode,
          noAnimation: noAnimation,
        ),
        operationBindingSetting: OperationBindingSettingState(
          bindingsRuntime: true,
          bindingsJson: bindingsDocJson,
        ),
      ),
    );
  ReaderInputBridge.instance.setActiveContexts({ReaderInputContext.reader});
  tester.view.physicalSize = const Size(1100, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final key = GlobalKey<_ReaderState>();
  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<GlobalSettingCubit>.value(value: cubit),
          BlocProvider(create: (_) => ReaderCubit()),
        ],
        child: _Reader(key: key, readMode: readMode, start: 3),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return key.currentState!;
}

Future<void> _wheel(WidgetTester tester, double dy) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      position: const Offset(300, 300),
      scrollDelta: Offset(0, dy),
    ),
  );
  await tester.pumpAndSettle();
}

/// 把出厂滚轮那两行的动作换掉，模拟「还留着旧口径」的表。
String _wheelRowsWith({required String down, required String up}) {
  final rows = parseBindings(OperationBindingStore.factoryBindingsJson())!;
  for (final row in rows) {
    final input = row['input'] as Map<String, dynamic>;
    if (input['device'] != InputDevice.wheel) continue;
    row['action'] = input['direction'] == 'down' ? down : up;
  }
  return encodeBindingsDoc(rows);
}

void main() {
  setUpAll(() async => RustLib.init());

  // 出厂表由 Rust 生成，只能在 `RustLib.init()` 之后现取（放 main() 顶层会抢在 setUpAll 前）。
  String factory() => OperationBindingStore.factoryBindingsJson();

  for (final readMode in [kReadModeRowLtr, kReadModeRowRtl]) {
    final open = readMode == kReadModeRowRtl ? '左开（下一页在左）' : '右开';
    for (final noAnimation in [true, false]) {
      testWidgets('$open · ${noAnimation ? '无动画' : '带动画'}：下滚=下一页、上滚=上一页', (
        tester,
      ) async {
        final reader = await _mount(
          tester,
          readMode: readMode,
          noAnimation: noAnimation,
          bindingsDocJson: factory(),
        );
        expect(reader.slot, 3);

        await _wheel(tester, 40);
        expect(reader.slot, 4, reason: '$open 下滚必须前进一页');

        await _wheel(tester, -40);
        expect(reader.slot, 3, reason: '$open 上滚必须退回一页');
      });
    }
  }

  testWidgets('旧口径的空间滚轮行仍随方向翻转（迁移前的行为可复现）', (tester) async {
    final spatial = _wheelRowsWith(
      down: BindingAction.pageLeft,
      up: BindingAction.pageRight,
    );

    for (final readMode in [kReadModeRowLtr, kReadModeRowRtl]) {
      final reader = await _mount(
        tester,
        readMode: readMode,
        noAnimation: true,
        bindingsDocJson: spatial,
      );
      await _wheel(tester, 40);
      // 右开：向左翻 = 退回。左开：向左翻 = 前进 —— 空间族就是为画面左右而生的。
      expect(
        reader.slot,
        readMode == kReadModeRowRtl ? 4 : 2,
        reason: '空间动作的方向解释必须留在引擎里',
      );
    }
  });

  test('出厂滚轮行绑的是语义族，不是空间族', () {
    final rows = parseBindings(factory())!;
    final wheel = rows
        .where((row) => (row['input'] as Map)['device'] == InputDevice.wheel)
        .toList();
    expect(wheel, hasLength(2));
    for (final row in wheel) {
      final direction = (row['input'] as Map)['direction'];
      expect(
        row['action'],
        direction == 'down' ? BindingAction.nextPage : BindingAction.previousPage,
        reason: '滚轮只有一根轴，出厂行不许随左右开翻转',
      );
    }
  });
}
