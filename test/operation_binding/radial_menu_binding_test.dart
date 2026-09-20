import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_controller.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_dispatcher.dart';
import 'package:zephyr/page/comic_read/widgets/radial/reader_radial_menu_overlay.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/src/rust/frb_generated.dart';
import 'package:flutter_ray_menu/flutter_ray_menu.dart';

class _Api implements RustLibApi {
  _Api({this.submenu = false});

  final bool submenu;

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
  for (final mode in ['drag', 'submenu', 'click', 'cancel']) {
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
          tester.getCenter(find.byKey(const ValueKey('radial:settings'))),
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
      final target = find.byKey(
        ValueKey(submenu ? 'radial:link' : 'radial:settings'),
      );
      await mouse.moveTo(tester.getCenter(target));
      await tester.pumpAndSettle();
      expect(tester.widget<Semantics>(target).properties.selected, isTrue);
      await mouse.up();
      await tester.pumpAndSettle();
      if (submenu) {
        expect(executed, 0);
        expect(ReaderRadialMenu.isOpen, isTrue);
        final next = find.byKey(const ValueKey('radial:settings'));
        expect(next, findsOneWidget);
        await tester.tapAt(tester.getCenter(next));
        await tester.pumpAndSettle();
      }
      expect(executed, 1);
      expect(ReaderRadialMenu.isOpen, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('确认轮盘走可编辑绑定，改绑后空格不会继续硬编码确认', (tester) async {
    RustLib.initMock(api: _Api());
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
      find.byKey(const ValueKey('radial:settings')),
    );
    expect(selected.properties.selected, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(ReaderRadialMenu.isOpen, true);
    expect(executed, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pumpAndSettle();
    expect(executed, 1);
    expect(ReaderRadialMenu.isOpen, false);
    expect(readerKeyEvents, 0);
    expect(readerFocus.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });
}
