import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/operation_binding/operation_binding_setting_page.dart';
import 'package:zephyr/page/setting/operation_binding/input_bindings_editor.dart';
import 'package:zephyr/page/setting/operation_binding/binding_input_editor.dart';
import 'package:zephyr/page/setting/operation_binding/radial_binding_editor.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/src/rust/frb_generated.dart';

class _MemorySettings extends GlobalSettingCubit {
  _MemorySettings() {
    emit(
      state.copyWith(
        operationBindingSetting: state.operationBindingSetting.copyWith(
          bindingsJson: encodeBindingsDoc([
            {
              'id': 'test-key',
              'action': BindingAction.previousPage,
              'context': 'reader',
              'enabled': true,
              'input': {'device': 'keyboard', 'code': 'KeyP'},
            },
          ]),
          radialJson: '{"enabled":true,"activeMenuId":"default","menus":[]}',
        ),
      ),
    );
  }
  int saves = 0;
  @override
  void updateOperationBindingSetting(
    OperationBindingSettingState Function(OperationBindingSettingState) updates,
  ) {
    saves++;
    emit(
      state.copyWith(
        operationBindingSetting: updates(state.operationBindingSetting),
      ),
    );
  }
}

class _Api implements RustLibApi {
  bool conflict = false;
  @override
  dynamic noSuchMethod(Invocation call) => switch (call.memberName) {
    #crateApiOperationBindingOperationBindingActionCatalog => jsonEncode([
      {
        'id': BindingAction.previousPage,
        'label': '上一页',
        'category': 'navigation',
        'categoryLabel': '导航',
        'implemented': true,
      },
      {
        'id': BindingAction.nextPage,
        'label': '下一页',
        'category': 'navigation',
        'categoryLabel': '导航',
        'implemented': true,
      },
    ]),
    #crateApiOperationBindingOperationBindingValidate ||
    #crateApiOperationBindingOperationBindingRadialValidate => true,
    #crateApiOperationBindingOperationBindingConflicts =>
      conflict ? '[{"key":"test","bindingIds":["test-key"]}]' : '[]',
    #crateApiOperationBindingOperationBindingFactoryPreset => jsonEncode([
      {
        'id': 'factory-key',
        'action': BindingAction.nextPage,
        'context': 'reader',
        'enabled': true,
        'input': {'device': 'keyboard', 'code': 'KeyD'},
      },
    ]),
    #crateApiOperationBindingOperationBindingRadialDefaultConfig =>
      '{"enabled":true,"activeMenuId":"default","menus":[]}',
    #crateApiOperationBindingOperationBindingRadialLayout => '[]',
    _ => throw UnsupportedError('${call.memberName}'),
  };
}

void main() {
  testWidgets('窄屏添加绑定出现冲突后仍停在当前动作，恢复默认回到列表', (tester) async {
    final api = _Api();
    RustLib.initMock(api: api);
    final settings = _MemorySettings();
    addTearDown(() {
      RustLib.dispose();
      // ignore: invalid_use_of_internal_member
      RustLib.instance.resetState();
      settings.close();
    });
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<GlobalSettingCubit>.value(
          value: settings,
          child: const OperationBindingSettingPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('action:reader.next-page')));
    await tester.pumpAndSettle();
    final pageScroll = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    pageScroll.jumpTo(80);
    await tester.pumpAndSettle();
    final add = find.byTooltip(t.bindingEditor.addBinding);
    await tester.ensureVisible(add);
    final scrollBefore = pageScroll.pixels;
    expect(scrollBefore, greaterThan(0));
    await tester.tap(add);
    await tester.pumpAndSettle();
    api.conflict = true;
    await tester.tap(
      find.widgetWithText(PopupMenuItem<String>, t.bindingEditor.keyboard),
    );
    await tester.pumpAndSettle();
    expect(find.text(t.bindingEditor.conflictHint), findsWidgets);
    expect(find.byType(BindingInputEditor), findsOneWidget);
    final editor = tester.widget<InputBindingsEditor>(
      find.byType(InputBindingsEditor),
    );
    expect(editor.bindings.last['action'], BindingAction.nextPage);
    expect(
      tester
          .widget<BindingInputEditor>(find.byType(BindingInputEditor))
          .input['code'],
      'KeyN',
    );
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
    expect(pageScroll.pixels, closeTo(scrollBefore, 1));

    api.conflict = false;
    final restore = find.widgetWithText(
      OutlinedButton,
      t.bindingEditor.restore,
    );
    await tester.ensureVisible(restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, t.common.confirm));
    await tester.pumpAndSettle();
    expect(find.byType(BindingInputEditor), findsNothing);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);
    expect(
      parseBindings(
        settings.state.operationBindingSetting.bindingsJson,
      )!.single['id'],
      'factory-key',
    );
    final radialTab = find.text(t.settings.operationBindingTabRadial);
    await tester.ensureVisible(radialTab);
    await tester.tap(radialTab);
    await tester.pumpAndSettle();
    expect(find.byType(RadialBindingEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('修改自动保存；冲突保留草稿，解除后保存', (tester) async {
    final api = _Api();
    RustLib.initMock(api: api);
    final settings = _MemorySettings();
    addTearDown(() {
      RustLib.dispose();
      // ignore: invalid_use_of_internal_member
      RustLib.instance.resetState();
      settings.close();
    });
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<GlobalSettingCubit>.value(
          value: settings,
          child: const OperationBindingSettingPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-binding:test-key')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Ctrl'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(settings.saves, 0);
    await tester.pump(const Duration(milliseconds: 150));
    expect(settings.saves, 1);
    expect(
      parseBindings(
        settings.state.operationBindingSetting.bindingsJson,
      )!.single['input']['ctrl'],
      true,
    );
    api.conflict = true;
    await tester.tap(find.widgetWithText(FilterChip, 'Alt'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(settings.saves, 1);
    expect(find.text(t.bindingEditor.conflictHint), findsWidgets);
    api.conflict = false;
    await tester.tap(find.widgetWithText(FilterChip, 'Shift'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(settings.saves, 2);
    expect(
      parseBindings(
        settings.state.operationBindingSetting.bindingsJson,
      )!.single['input']['alt'],
      true,
    );
    expect(tester.takeException(), isNull);
  });
}
