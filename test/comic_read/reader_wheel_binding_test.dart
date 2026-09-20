import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_controller.dart';
import 'package:zephyr/page/comic_read/controller/reader_input_controller.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/src/rust/frb_generated.dart';
import 'package:zephyr/util/input/reader_input_bridge.dart';
import 'package:zephyr/util/input/reader_input_context.dart';

Map<String, dynamic> _wheel(
  String direction,
  String action, {
  bool ctrl = false,
}) => {
  'id': 'wheel-$direction',
  'action': action,
  'enabled': true,
  'context': 'reader',
  'input': {'device': 'wheel', 'direction': direction, 'ctrl': ctrl},
};

class _Settings extends GlobalSettingCubit {
  _Settings({required int mode, required List<Map<String, dynamic>> bindings}) {
    emit(
      state.copyWith(
        readSetting: state.readSetting.copyWith(
          readMode: mode,
          noAnimation: true,
        ),
        operationBindingSetting: state.operationBindingSetting.copyWith(
          bindingsRuntime: true,
          bindingsJson: encodeBindingsDoc(bindings),
        ),
      ),
    );
  }
}

/// 核心替身仅认 reader 上下文的精确滚轮描述符，用真实控件验证事件采集与派发。
class _Api implements RustLibApi {
  final inputs = <Map<String, dynamic>>[];
  final contexts = <List<String>>[];

  @override
  dynamic noSuchMethod(Invocation call) {
    if (call.memberName == #crateApiOperationBindingOperationBindingValidate) {
      return true;
    }
    if (call.memberName ==
        #crateApiOperationBindingOperationBindingResolveBinding) {
      final input = Map<String, dynamic>.from(
        jsonDecode(call.namedArguments[#inputJson] as String) as Map,
      );
      final active = List<String>.from(call.namedArguments[#contexts] as List);
      inputs.add(input);
      contexts.add(active);
      if (!active.contains('reader')) return null;
      final rows =
          jsonDecode(call.namedArguments[#bindingsJson] as String) as List;
      for (final row in rows) {
        final expected = row['input'] as Map;
        if (row['enabled'] != true || input['device'] != expected['device']) {
          continue;
        }
        if (input['direction'] == expected['direction'] &&
            ['ctrl', 'alt', 'shift', 'meta'].every(
              (key) => (input[key] ?? false) == (expected[key] ?? false),
            )) {
          return jsonEncode(row);
        }
      }
      return null;
    }
    throw UnsupportedError('${call.memberName}');
  }
}

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
  late _Api api;
  setUp(() {
    api = _Api();
    RustLib.initMock(api: api);
    ReaderInputBridge.instance.setActiveContexts({ReaderInputContext.reader});
  });
  tearDown(() {
    ReaderInputBridge.instance.setActiveContexts({ReaderInputContext.reader});
    RustLib.dispose();
    // ignore: invalid_use_of_internal_member
    RustLib.instance.resetState();
  });

  Future<_ReaderState> pump(
    WidgetTester tester, {
    int mode = 1,
    List<Map<String, dynamic>>? bindings,
  }) async {
    final key = GlobalKey<_ReaderState>();
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<GlobalSettingCubit>(
              create: (_) => _Settings(
                mode: mode,
                bindings:
                    bindings ??
                    [
                      _wheel('down', BindingAction.nextPage),
                      _wheel('up', BindingAction.previousPage),
                    ],
              ),
            ),
            BlocProvider(create: (_) => ReaderCubit()),
          ],
          child: Row(
            children: [
              SizedBox(width: 700, child: _Reader(key: key)),
              Expanded(
                child: ListView(children: const [SizedBox(height: 2000)]),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return key.currentState!;
  }

  Future<void> wheel(
    WidgetTester tester,
    double dy, {
    Offset at = const Offset(300, 300),
  }) async {
    await tester.sendEventToBinding(
      PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: at,
        scrollDelta: Offset(0, dy),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('真实阅读器的滚轮上下绑定各翻一页，右侧面板滚动不翻页', (tester) async {
    final reader = await pump(tester);
    await wheel(tester, 40);
    expect(reader.pages.page, 4);
    await wheel(tester, -40);
    expect(reader.pages.page, 3);
    final inputCount = api.inputs.length;
    await wheel(tester, 40, at: const Offset(900, 300));
    expect(reader.pages.page, 3);
    expect(api.inputs.length, inputCount);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置面板留下 panel 上下文后，阅读区滚轮仍执行自定义方向', (tester) async {
    final reader = await pump(
      tester,
      bindings: [_wheel('down', BindingAction.previousPage)],
    );
    ReaderInputBridge.instance.setActiveContexts({ReaderInputContext.panel});
    await wheel(tester, 40);
    expect(reader.pages.page, 2, reason: '向下已改绑上一页，不能失配后回退为下一页');
    expect(api.contexts.last, contains('reader'));
    expect(ReaderInputBridge.instance.activeContexts, {
      ReaderInputContext.panel,
    }, reason: '滚轮使用自己的事件上下文，不改写键盘焦点上下文');
  });

  testWidgets('条漫中 reader 滚轮绑定优先于 ListView 的默认小步滚动', (tester) async {
    final reader = await pump(tester, mode: 0);
    ReaderInputBridge.instance.setActiveContexts({ReaderInputContext.panel});
    await wheel(tester, 40);
    expect(reader.scroll.offset, closeTo(800 + 800 * .7, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ctrl 滚轮只执行绑定，不同时缩放图片', (tester) async {
    final reader = await pump(
      tester,
      bindings: [_wheel('up', BindingAction.nextPage, ctrl: true)],
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    // 模拟已经放大的图片，确保 InteractiveViewer 自身会处理缩放。
    reader.transform.value = Matrix4.diagonal3Values(2, 2, 1);
    await tester.pumpAndSettle();
    await wheel(tester, -40);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(reader.pages.page, 4);
    expect(
      reader.transform.value.getMaxScaleOnAxis(),
      1,
      reason: '翻页归位，滚轮不能再叠加缩放',
    );
    expect(api.inputs.last['ctrl'], isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('停用滚轮绑定后不回退到旧翻页', (tester) async {
    final reader = await pump(
      tester,
      bindings: [
        {..._wheel('down', BindingAction.nextPage), 'enabled': false},
      ],
    );
    await wheel(tester, 40);
    expect(reader.pages.page, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未绑定的条漫滚轮仍交给 ListView', (tester) async {
    final reader = await pump(tester, mode: 0, bindings: []);
    await wheel(tester, 40);
    expect(reader.scroll.offset, 840);
    expect(tester.takeException(), isNull);
  });
}
