import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_controller.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_dispatcher.dart';
import 'package:zephyr/page/comic_read/widgets/radial/reader_radial_menu_overlay.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/util/input/reader_input_bridge.dart';
import 'package:zephyr/util/input/reader_input_context.dart';
import 'package:zephyr/src/rust/frb_generated.dart';
import 'package:flutter_ray_menu/flutter_ray_menu.dart';

class _Api implements RustLibApi {
  _Api({this.submenu = false});

  final bool submenu;
  final resolvedContexts = <List<String>>[];

  @override
  dynamic noSuchMethod(Invocation call) {
    if (call.memberName ==
        #crateApiOperationBindingOperationBindingRadialLayout) {
      final menuId = call.namedArguments[#menuId] as String;
      final isLink = submenu && menuId == 'default';
      return jsonEncode([
        {
          'menuId': menuId,
          'level': 1,
          'index': 0,
          'itemId': isLink ? 'link' : 'settings',
          'label': isLink ? '第二轮盘' : '设置',
          if (isLink) 'moveToMenuId': 'second',
          'innerRadius': 30,
          'outerRadius': 100,
          'startDeg': 0,
          'endDeg': 360,
          'midDeg': 180,
          'selectable': true,
        },
      ]);
    }
    if (call.memberName ==
        #crateApiOperationBindingOperationBindingResolveBinding) {
      resolvedContexts.add(
        List<String>.from(call.namedArguments[#contexts] as List),
      );
      final input =
          jsonDecode(call.namedArguments[#inputJson] as String) as Map;
      final action = input['device'] == 'radial'
          ? BindingAction.openSettings
          : input['code'] == 'KeyX'
          ? BindingAction.confirmRadialMenu
          : null;
      return action == null ? null : jsonEncode({'action': action});
    }
    throw UnsupportedError('${call.memberName}');
  }
}

void main() {
  for (final mode in ['drag', 'submenu', 'click', 'cancel', 'dismiss']) {
    final submenu = mode == 'submenu';
    testWidgets('右键轮盘完整指针链：$mode', (tester) async {
      RustLib.initMock(api: _Api(submenu: submenu));
      final scroll = ScrollController();
      final pages = PageController();
      addTearDown(() {
        ReaderRadialMenu.dismiss();
        scroll.dispose();
        pages.dispose();
        RustLib.dispose();
        // ignore: invalid_use_of_internal_member
        RustLib.instance.resetState();
      });
      var executed = 0;
      late ReaderActionDispatcher dispatcher;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              dispatcher = ReaderActionDispatcher(
                context: context,
                actions: ReaderActionController(
                  context: context,
                  scrollController: scroll,
                  pageController: pages,
                ),
                onToggleMenu: () {},
                onToggleFullscreen: () async {},
                onOpenSettings: () => executed++,
                onResetView: () {},
                onOpenRadialMenu: () {},
                onConfirmRadialMenu: ReaderRadialMenu.confirm,
              );
              return Listener(
                onPointerDown: (event) => ReaderRadialMenu.show(
                  context,
                  globalCenter: event.position,
                  openingPointer: event.pointer,
                  configJson:
                      '{"enabled":true,"activeMenuId":"default","menus":[{"id":"default","layers":[]},{"id":"second","layers":[]}]}',
                  bindingsArrayJson: '[]',
                  dispatcher: dispatcher,
                ),
                child: const Scaffold(),
              );
            },
          ),
        ),
      );
      final mouse = await tester.startGesture(
        const Offset(3, 3),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      if (mode == 'click') {
        await mouse.up();
        await tester.pumpAndSettle();
        expect(ReaderRadialMenu.isOpen, isTrue);
        expect(executed, 0);
        await tester.tapAt(
          tester.getCenter(find.byKey(const ValueKey('ray-item:settings'))),
        );
        await tester.pumpAndSettle();
        expect(executed, 1);
        expect(ReaderRadialMenu.isOpen, isFalse);
        expect(tester.takeException(), isNull);
        return;
      }
      if (mode == 'cancel') {
        await mouse.cancel();
        await tester.pumpAndSettle();
        expect(ReaderRadialMenu.isOpen, isFalse);
        expect(executed, 0);
        expect(tester.takeException(), isNull);
        return;
      }
      if (mode == 'dismiss') {
        // 按下就松（没动过）= 只是把轮盘开出来，不该关也不该执行。
        await mouse.up();
        await tester.pumpAndSettle();
        expect(ReaderRadialMenu.isOpen, isTrue);
        expect(executed, 0);
        // 再按一次右键 = 关掉；哪怕落在某一格上，也只关不执行。
        final again = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('ray-item:settings'))),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        await again.up();
        await tester.pumpAndSettle();
        expect(ReaderRadialMenu.isOpen, isFalse, reason: '再次右键应当退出轮盘');
        expect(executed, 0);
        expect(tester.takeException(), isNull);
        return;
      }
      // 键由组件给（`reader_ray_menu_adapter` 建的条目 id 原样进 `ray-item:`），
      // 不是核心的 `radial:<menuId>:<itemId>` 那种绑定标识符。
      final target = find.byKey(
        ValueKey(submenu ? 'ray-item:link' : 'ray-item:settings'),
      );
      await mouse.moveTo(tester.getCenter(target));
      await tester.pumpAndSettle();
      expect(tester.widget<Semantics>(target).properties.selected, isTrue);
      await mouse.up();
      await tester.pumpAndSettle();
      if (submenu) {
        expect(executed, 0);
        expect(ReaderRadialMenu.isOpen, isTrue);
        final next = find.byKey(const ValueKey('ray-item:settings'));
        expect(next, findsOneWidget);
        await tester.tapAt(tester.getCenter(next));
        await tester.pumpAndSettle();
      }
      expect(executed, 1);
      expect(ReaderRadialMenu.isOpen, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  // 上面那一圈用的是 `TestGesture`：一整条手势只有一个 pointer id。真实鼠标不是这样
  // —— hover 与每一次按下/抬起各有自己的 id，所以这里按真实 id 约定发裸事件，
  // 走的是用户实际那一条路：右键开出来 → 把鼠标移到某一格 → 左键单击。
  testWidgets('真实鼠标：右键开 → 移到某一格 → 左键单击执行', (tester) async {
    RustLib.initMock(api: _Api());
    final scroll = ScrollController();
    final pages = PageController();
    addTearDown(() {
      ReaderRadialMenu.dismiss();
      scroll.dispose();
      pages.dispose();
      RustLib.dispose();
      // ignore: invalid_use_of_internal_member
      RustLib.instance.resetState();
    });
    var executed = 0;
    late ReaderActionDispatcher dispatcher;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            dispatcher = ReaderActionDispatcher(
              context: context,
              actions: ReaderActionController(
                context: context,
                scrollController: scroll,
                pageController: pages,
              ),
              onToggleMenu: () {},
              onToggleFullscreen: () async {},
              onOpenSettings: () => executed++,
              onResetView: () {},
              onOpenRadialMenu: () {},
              onConfirmRadialMenu: ReaderRadialMenu.confirm,
            );
            return Listener(
              onPointerDown: (event) => ReaderRadialMenu.show(
                context,
                globalCenter: event.position,
                openingPointer: event.pointer,
                configJson:
                    '{"enabled":true,"activeMenuId":"default","menus":[{"id":"default","layers":[]}]}',
                bindingsArrayJson: '[]',
                dispatcher: dispatcher,
              ),
              child: const Scaffold(),
            );
          },
        ),
      ),
    );
    final viewId = tester.view.viewId;
    Future<void> send(PointerEvent event) => tester.sendEventToBinding(event);
    const at = Offset(400, 300);
    final item = find.byKey(const ValueKey('ray-item:settings'));

    await send(
      PointerHoverEvent(
        viewId: viewId,
        pointer: 1,
        position: at,
        kind: PointerDeviceKind.mouse,
      ),
    );
    await send(
      PointerDownEvent(
        viewId: viewId,
        pointer: 2,
        position: at,
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(ReaderRadialMenu.isOpen, isTrue);
    await send(
      PointerUpEvent(
        viewId: viewId,
        pointer: 2,
        position: at,
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(ReaderRadialMenu.isOpen, isTrue, reason: '按下即松只是把轮盘开出来');
    expect(executed, 0);

    final target = tester.getCenter(item);
    await send(
      PointerHoverEvent(
        viewId: viewId,
        pointer: 1,
        position: target,
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Semantics>(item).properties.selected,
      isTrue,
      reason: '没按住任何键、只是移过去就该高亮那一格',
    );
    await send(
      PointerDownEvent(
        viewId: viewId,
        pointer: 3,
        position: target,
        buttons: kPrimaryButton,
        kind: PointerDeviceKind.mouse,
      ),
    );
    await send(
      PointerUpEvent(
        viewId: viewId,
        pointer: 3,
        position: target,
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(executed, 1, reason: '左键单击应当执行指针下那一格');
    expect(ReaderRadialMenu.isOpen, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('确认轮盘走可编辑绑定，改绑后空格不会继续硬编码确认', (tester) async {
    final api = _Api();
    RustLib.initMock(api: api);
    addTearDown(
      () => ReaderInputBridge.instance.setActiveContexts(const {
        ReaderInputContext.reader,
      }),
    );
    final scroll = ScrollController();
    final pages = PageController();
    final readerFocus = FocusNode();
    addTearDown(() {
      ReaderRadialMenu.dismiss();
      scroll.dispose();
      pages.dispose();
      readerFocus.dispose();
      RustLib.dispose();
      // ignore: invalid_use_of_internal_member
      RustLib.instance.resetState();
    });
    late BuildContext host;
    var readerKeyEvents = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            host = context;
            return Focus(
              focusNode: readerFocus,
              autofocus: true,
              onKeyEvent: (_, _) {
                readerKeyEvents++;
                return KeyEventResult.handled;
              },
              child: const Scaffold(),
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(readerFocus.hasFocus, isTrue);
    var executed = 0;
    final dispatcher = ReaderActionDispatcher(
      context: host,
      actions: ReaderActionController(
        context: host,
        scrollController: scroll,
        pageController: pages,
      ),
      onToggleMenu: () {},
      onToggleFullscreen: () async {},
      onOpenSettings: () => executed++,
      onResetView: () {},
      onOpenRadialMenu: () {},
      onConfirmRadialMenu: ReaderRadialMenu.confirm,
    );
    ReaderRadialMenu.show(
      host,
      globalCenter: const Offset(250, 250),
      configJson:
          '{"enabled":true,"activeMenuId":"default","menus":[{"id":"default","name":"默认","layers":[]}]}',
      bindingsArrayJson: '[]',
      dispatcher: dispatcher,
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.byType(RayMenu), findsOneWidget);
    final selected = tester.widget<Semantics>(
      find.byKey(const ValueKey('ray-item:settings')),
    );
    expect(selected.properties.selected, isTrue);
    ReaderInputBridge.instance.setActiveContexts(const {
      ReaderInputContext.panel,
    });
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(ReaderRadialMenu.isOpen, true);
    expect(executed, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pumpAndSettle();
    expect(executed, 1);
    expect(ReaderRadialMenu.isOpen, false);
    expect(readerKeyEvents, 0);
    expect(api.resolvedContexts, isNotEmpty);
    expect(
      api.resolvedContexts.every(
        (contexts) => contexts.length == 1 && contexts.single == 'reader',
      ),
      isTrue,
      reason: '键盘确认和轮盘动作都保持唤出时的上下文',
    );
    expect(readerFocus.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });
}
