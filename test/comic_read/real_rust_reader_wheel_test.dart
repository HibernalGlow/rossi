import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_controller.dart';
import 'package:zephyr/page/comic_read/controller/reader_input_controller.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';
import 'package:zephyr/src/rust/frb_generated.dart';
import 'package:zephyr/util/input/reader_input_bridge.dart';
import 'package:zephyr/util/input/reader_input_context.dart';

class _Reader extends StatefulWidget {
  const _Reader({super.key});
  @override
  State<_Reader> createState() => _ReaderState();
}

class _ReaderState extends State<_Reader> {
  final pages = PageController(initialPage: 3);
  final scroll = ScrollController(initialScrollOffset: 800);
  final transform = TransformationController();
  late final ReaderInputController input;
  bool locked = false;

  @override
  void initState() {
    super.initState();
    final reader = context.read<ReaderCubit>()
      ..updateTotalSlots(10)
      ..updateCurrentSlot(3);
    input = ReaderInputController(
      context: context,
      readerCubit: reader,
      pageController: pages,
      transformationController: transform,
      onToggleMenu: () {},
      onToggleDesktopFullscreen: () async {},
      onRefreshState: () => setState(() {}),
      isScrollLockedByMultiTouch: () => locked,
      onUpdateScrollLock: (value) => setState(() => locked = value),
      buildColumnMode: (_) => ListView.builder(
        controller: scroll,
        itemCount: 10,
        itemBuilder: (_, i) => SizedBox(
          height: 800,
          child: ColoredBox(color: Colors.blue, child: Text('$i')),
        ),
      ),
      buildRowMode: () => PageView.builder(
        controller: pages,
        itemCount: 10,
        onPageChanged: reader.updateCurrentSlot,
        itemBuilder: (_, i) =>
            ColoredBox(color: Colors.blue, child: Text('$i')),
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

void main() {
  setUpAll(() async {
    await RustLib.init();
  });

  testWidgets('真实 Rust 引擎下的滚轮绑定测试', (tester) async {
    final defaultBindings = OperationBindingStore.factoryBindingsJson();
    print('Factory bindings: ${defaultBindings.length} chars');
    final rows = parseBindings(defaultBindings)!;
    final wheelRows = rows.where((r) => (r['input'] as Map)['device'] == 'wheel').toList();
    print('Wheel bindings: $wheelRows');

    final cubit = GlobalSettingCubit()
      ..emit(
        const GlobalSettingState().copyWith(
          readSetting: const ReadSettingState(readMode: 1, noAnimation: true),
          operationBindingSetting: OperationBindingSettingState(
            bindingsRuntime: true,
            bindingsJson: defaultBindings,
          ),
        ),
      );

    ReaderInputBridge.instance.setActiveContexts({ReaderInputContext.reader});

    final key = GlobalKey<_ReaderState>();
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<GlobalSettingCubit>.value(value: cubit),
            BlocProvider(create: (_) => ReaderCubit()),
          ],
          child: _Reader(key: key),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final reader = key.currentState!;
    print('Initial page: ${reader.pages.page}');

    // 发送滚轮向下 (dy > 0)
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: Offset(300, 300),
        scrollDelta: Offset(0, 40),
      ),
    );
    await tester.pumpAndSettle();

    print('After wheel down dy=40 page: ${reader.pages.page}');

    // 发送滚轮向上 (dy < 0)
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: Offset(300, 300),
        scrollDelta: Offset(0, -40),
      ),
    );
    await tester.pumpAndSettle();

    print('After wheel up dy=-40 page: ${reader.pages.page}');
    expect(reader.pages.page, 3.0);
  });

  testWidgets('真实 Rust 引擎下的触控板双指滑动绑定测试', (tester) async {
    final defaultBindings = OperationBindingStore.factoryBindingsJson();
    final cubit = GlobalSettingCubit()
      ..emit(
        const GlobalSettingState().copyWith(
          readSetting: const ReadSettingState(readMode: 1, noAnimation: true),
          operationBindingSetting: OperationBindingSettingState(
            bindingsRuntime: true,
            bindingsJson: defaultBindings,
          ),
        ),
      );

    ReaderInputBridge.instance.setActiveContexts({ReaderInputContext.reader});

    final key = GlobalKey<_ReaderState>();
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<GlobalSettingCubit>.value(value: cubit),
            BlocProvider(create: (_) => ReaderCubit()),
          ],
          child: _Reader(key: key),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final reader = key.currentState!;
    expect(reader.pages.page, 3.0);

    // 触控板双指滑动向下 (panDelta.dy = 30 > 24 步进阈值)
    await tester.sendEventToBinding(
      const PointerPanZoomStartEvent(
        position: Offset(300, 300),
      ),
    );
    await tester.sendEventToBinding(
      const PointerPanZoomUpdateEvent(
        position: Offset(300, 300),
        panDelta: Offset(0, 30),
      ),
    );
    await tester.sendEventToBinding(
      const PointerPanZoomEndEvent(),
    );
    await tester.pumpAndSettle();

    expect(reader.pages.page, 2.0);

    // 触控板双指滑动向上 (panDelta.dy = -30)
    await tester.sendEventToBinding(
      const PointerPanZoomStartEvent(
        position: Offset(300, 300),
      ),
    );
    await tester.sendEventToBinding(
      const PointerPanZoomUpdateEvent(
        position: Offset(300, 300),
        panDelta: Offset(0, -30),
      ),
    );
    await tester.sendEventToBinding(
      const PointerPanZoomEndEvent(),
    );
    await tester.pumpAndSettle();

    expect(reader.pages.page, 3.0);
  });
}
