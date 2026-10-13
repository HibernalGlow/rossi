import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/comic_read_preference_cubit.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_controller.dart';
import 'package:zephyr/page/comic_read/controller/reader_input_controller.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';
import 'package:zephyr/src/rust/frb_generated.dart';
import 'package:zephyr/src/rust/api/operation_binding.dart';

Map<String, dynamic> _binding(
  String id,
  String action, {
  String device = 'touch',
  String? area,
  String gesture = 'tap',
}) => {
  'id': id,
  'action': action,
  'context': 'reader',
  'enabled': true,
  'input': {
    'device': device,
    if (device == 'touch') ...{
      'gesture': gesture,
      'fingers': 1,
    } else ...{
      'action': 'click',
      'button': 0,
    },
    'area': ?area,
  },
};

class _Actions extends ReaderActionController {
  _Actions({
    required super.context,
    required super.scrollController,
    required super.pageController,
    required this.events,
  });
  final List<String> events;
  @override
  void onPageActionNext() => events.add('next');
  @override
  void onPageActionPrev() => events.add('previous');
}

class _Reader extends StatefulWidget {
  const _Reader({super.key});
  @override
  State<_Reader> createState() => _ReaderState();
}

class _ReaderState extends State<_Reader> {
  final pages = PageController();
  final scroll = ScrollController();
  final transform = TransformationController();
  final events = <String>[];
  late final ReaderInputController input;
  ReaderCubit get reader => context.read<ReaderCubit>();
  @override
  void initState() {
    super.initState();
    reader.updateMenuVisible(visible: false);
    input = ReaderInputController(
      context: context,
      readerCubit: reader,
      pageController: pages,
      transformationController: transform,
      onToggleMenu: () {
        events.add('menu');
        reader.updateMenuVisible();
      },
      onToggleDesktopFullscreen: () async {},
      onRefreshState: () {},
      isScrollLockedByMultiTouch: () => false,
      onUpdateScrollLock: (_) {},
      buildColumnMode: (_) => _surface(),
      buildRowMode: _surface,
    );
    input.setActionController(
      _Actions(
        context: context,
        scrollController: scroll,
        pageController: pages,
        events: events,
      ),
    );
  }

  Widget _surface() => ColoredBox(
    color: Colors.blue,
    child: Stack(
      children: [
        Positioned(
          left: 370,
          top: 370,
          width: 60,
          height: 60,
          child: GestureDetector(
            onTap: () => events.add('child'),
            onDoubleTap: () => events.add('child-double'),
            child: const ColoredBox(color: Colors.red),
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => input.buildInteractiveViewer();
  @override
  void dispose() {
    input.dispose();
    pages.dispose();
    scroll.dispose();
    transform.dispose();
    super.dispose();
  }
}

Future<_ReaderState> _mount(
  WidgetTester tester,
  List<Map<String, dynamic>> bindings,
) async {
  tester.view.physicalSize = const Size(800, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = GlobalSettingCubit()
    ..emit(
      GlobalSettingState(
        readSetting: const ReadSettingState(
          readMode: 1,
          hoverRevealEnabled: false,
          hoverRevealTop: false,
          hoverRevealBottom: false,
        ),
        operationBindingSetting: OperationBindingSettingState(
          bindingsJson: encodeBindingsDoc(bindings),
        ),
      ),
    );
  addTearDown(settings.close);
  final key = GlobalKey<_ReaderState>();
  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<GlobalSettingCubit>.value(value: settings),
          BlocProvider(create: (_) => ReaderCubit()),
          BlocProvider(create: (_) => ComicReadPreferenceCubit()),
        ],
        child: _Reader(key: key),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return key.currentState!;
}

Future<void> _tap(
  WidgetTester tester,
  Offset point, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) async {
  final pointer = await tester.startGesture(point, kind: kind);
  await tester.pump(const Duration(milliseconds: 40));
  await pointer.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  setUpAll(() async => RustLib.init());

  testWidgets('真实核心：触屏区域优先于通用单击，鼠标与触屏中央绑定独立', (tester) async {
    final reader = await _mount(tester, [
      _binding('generic', BindingAction.toggleControls),
      _binding('left', BindingAction.previousPage, area: 'middle-left'),
      _binding('right', BindingAction.nextPage, area: 'middle-right'),
      _binding(
        'touch-center',
        BindingAction.toggleControls,
        area: 'middle-center',
      ),
      _binding(
        'mouse-center',
        BindingAction.nextPage,
        device: 'mouse',
        area: 'middle-center',
      ),
    ]);
    await _tap(tester, const Offset(100, 400));
    await _tap(tester, const Offset(700, 400));
    await _tap(tester, const Offset(350, 400));
    await _tap(tester, const Offset(350, 400), kind: PointerDeviceKind.mouse);
    expect(reader.events, ['previous', 'next', 'menu', 'next']);
  });

  testWidgets('顶部与底部触屏确保显示控制栏，显示后不切回隐藏；鼠标仍执行绑定', (tester) async {
    final reader = await _mount(tester, [
      _binding('tap', BindingAction.nextPage),
      _binding('mouse', BindingAction.previousPage, device: 'mouse'),
    ]);
    await _tap(tester, const Offset(100, 10));
    expect(reader.reader.state.isMenuVisible, isTrue);
    // 已显示时边缘入口保持显示，不再切换控制栏。
    await _tap(tester, const Offset(100, 10));
    expect(reader.reader.state.isMenuVisible, isTrue);
    reader.reader.updateMenuVisible(visible: false);
    await _tap(tester, const Offset(700, 790));
    await _tap(tester, const Offset(100, 10), kind: PointerDeviceKind.mouse);
    expect(reader.events, ['menu', 'menu', 'previous']);
  });

  testWidgets('子控件点击只执行自身动作，未匹配触屏不会借用鼠标绑定', (tester) async {
    final reader = await _mount(tester, [
      _binding('touch', BindingAction.toggleControls),
      _binding('mouse', BindingAction.nextPage, device: 'mouse'),
    ]);
    await _tap(tester, const Offset(400, 400));
    expect(reader.events, ['child']);
    final mouseOnly = await _mount(tester, [
      _binding('mouse-only', BindingAction.nextPage, device: 'mouse'),
    ]);
    await _tap(tester, const Offset(100, 400));
    expect(mouseOnly.events, isEmpty);
  });

  testWidgets('真实触屏双击只执行双击动作，取消或移动后不补单击', (tester) async {
    final reader = await _mount(tester, [
      _binding('tap', BindingAction.toggleControls),
      _binding('double', BindingAction.nextPage, gesture: 'double-tap'),
    ]);
    final first = await tester.startGesture(const Offset(100, 400));
    await first.up();
    await tester.pump(const Duration(milliseconds: 80));
    final second = await tester.startGesture(const Offset(100, 400));
    await second.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(reader.events, ['next']);
    final canceled = await tester.startGesture(const Offset(700, 400));
    await canceled.cancel();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.dragFrom(const Offset(700, 400), const Offset(-80, 0));
    await tester.pump(const Duration(milliseconds: 350));
    expect(reader.events, ['next']);
  });

  testWidgets('鼠标主键双击也等待子控件手势竞争，胜出后只执行一次', (tester) async {
    final doubleClick = _binding(
      'double-click',
      BindingAction.nextPage,
      device: 'mouse',
    );
    (doubleClick['input'] as Map)['action'] = 'double-click';
    final reader = await _mount(tester, [doubleClick]);
    Future<void> doubleAt(Offset point) async {
      final first = await tester.startGesture(
        point,
        kind: PointerDeviceKind.mouse,
      );
      await first.up();
      await tester.pump(const Duration(milliseconds: 80));
      final second = await tester.startGesture(
        point,
        kind: PointerDeviceKind.mouse,
      );
      await second.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }

    await doubleAt(const Offset(100, 400));
    await doubleAt(const Offset(400, 400));
    expect(reader.events, ['next', 'child-double']);
  });

  test('FRB 的迁移报告与诊断来自同一核心，工厂文档可供独立宿主读取', () {
    final raw = OperationBindingStore.factoryBindingsJson();
    final document = jsonDecode(raw) as Map;
    expect(document['contexts'], isNotEmpty);
    final report =
        jsonDecode(operationBindingMigrationReport(documentJson: raw)) as Map;
    expect(report['report']['createdBindingIds'], isEmpty);
    final trace =
        jsonDecode(
              operationBindingDiagnose(
                bindingsJson: encodeBindingsArray(parseBindings(raw)!),
                inputJson:
                    '{"device":"touch","gesture":"tap","fingers":1,"area":"middle-center"}',
                contexts: ['reader'],
              ),
            )
            as Map;
    expect(trace['action'], BindingAction.toggleControls);
  });
}
