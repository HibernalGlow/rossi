import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/operation_binding/binding_input_editor.dart';
import 'package:zephyr/page/setting/operation_binding/binding_input_recorder.dart';
import 'package:zephyr/page/setting/operation_binding/input_bindings_editor.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';

const catalog = [
  BindingActionInfo(
    id: BindingAction.previousPage,
    label: '上一页',
    category: 'navigation',
    categoryLabel: '导航',
    implemented: true,
  ),
  BindingActionInfo(
    id: BindingAction.nextPage,
    label: '下一页',
    category: 'navigation',
    categoryLabel: '导航',
    implemented: true,
  ),
  BindingActionInfo(
    id: BindingAction.zoomIn,
    label: '放大',
    category: 'zoom',
    categoryLabel: '缩放',
    implemented: true,
  ),
];
Map<String, dynamic> row(
  String id,
  String action,
  Map<String, dynamic> input,
) => {
  'id': id,
  'action': action,
  'context': 'reader',
  'enabled': true,
  'input': input,
};

void main() {
  late List<Map<String, dynamic>> bindings;
  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1440, 1000),
    List<BindingConflict> conflicts = const [],
    List<BindingActionInfo> actions = catalog,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: InputBindingsEditor(
                  bindings: bindings,
                  catalog: actions,
                  conflicts: conflicts,
                  onChanged: (next) => setState(() => bindings = next),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    bindings = [
      row('wheel', BindingAction.previousPage, {
        'device': 'wheel',
        'direction': 'up',
      }),
      row('key', BindingAction.nextPage, {
        'device': 'keyboard',
        'code': 'KeyN',
      }),
    ];
  });

  testWidgets('分类缩短列表，视频独立分组且搜索跨分类', (tester) async {
    final actions = [
      ...catalog,
      for (final entry in const {
        'video.play-pause': '视频：播放/暂停',
        'video.volume-up': '视频：增大音量',
        'video.toggle-subtitle': '视频：字幕',
      }.entries)
        BindingActionInfo(
          id: entry.key,
          label: entry.value,
          category: 'view',
          categoryLabel: '视图',
          implemented: true,
        ),
    ];
    await pump(tester, actions: actions);
    expect(find.byKey(const ValueKey('action:reader.zoom-in')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('action-group:view')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('action:reader.zoom-in')), findsOneWidget);
    expect(find.byKey(const ValueKey('action:video.play-pause')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('action-group:video')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('action:video.play-pause')),
      findsOneWidget,
    );
    expect(find.text('视频：播放/暂停'), findsNothing);
    expect(find.byIcon(Icons.play_circle_outline), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('video-group:audio')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('action:video.volume-up')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('action:video.play-pause')), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'KeyN');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('action:reader.next-page')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('action-group:all')));
    await tester.pumpAndSettle();
    for (final action in actions) {
      expect(find.byKey(ValueKey('action:${action.id}')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('多绑定先显示摘要，只展开一条，编辑和启停不丢数据', (tester) async {
    bindings = [
      for (var i = 0; i < 6; i++)
        row('key-$i', BindingAction.previousPage, {
          'device': 'keyboard',
          'code': 'Digit$i',
        }),
    ];
    await pump(tester);
    expect(find.byType(BindingInputEditor), findsNothing);
    expect(find.text('+4'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('edit-binding:key-5')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('edit-binding:key-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Ctrl'));
    await tester.pumpAndSettle();
    final second = find.byKey(const ValueKey('edit-binding:key-1'));
    await tester.ensureVisible(second);
    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(find.byType(BindingInputEditor), findsOneWidget);
    expect(
      tester
          .widget<BindingInputEditor>(find.byType(BindingInputEditor))
          .input['code'],
      'Digit1',
    );
    expect(bindings.first['input']['ctrl'], isTrue);
    final toggle = find.descendant(of: second, matching: find.byType(Switch));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(bindings[1]['enabled'], isFalse);
    expect(bindings.length, 6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜索输入和上下文，空结果可以清除', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField).first, 'KeyN');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('action:reader.next-page')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('action:reader.previous-page')),
      findsNothing,
    );
    await tester.enterText(find.byType(TextField).first, '不存在');
    await tester.pumpAndSettle();
    expect(find.text(t.bindingEditor.noResults), findsOneWidget);
    await tester.tap(find.text(t.bindingEditor.resetFilters));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('action:reader.previous-page')),
      findsOneWidget,
    );
  });

  testWidgets('修改滚轮修饰键、重复开关、后续动作并复制到全局', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('edit-binding:wheel')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Ctrl'));
    await tester.pumpAndSettle();
    expect(bindings.first['input']['ctrl'], isTrue);
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();
    expect(bindings.first['ignoreRepeat'], isTrue);
    await tester.ensureVisible(
      find.widgetWithText(TextButton, t.bindingEditor.add),
    );
    await tester.tap(find.widgetWithText(TextButton, t.bindingEditor.add));
    await tester.pumpAndSettle();
    expect(bindings.first['followUpActions'], [BindingAction.nextPage]);
    final copy = find.byTooltip(t.bindingEditor.copyTo);
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(PopupMenuItem<String>, t.bindingEditor.global),
    );
    await tester.pumpAndSettle();
    final duplicate = bindings.last;
    expect(duplicate['id'], isNot('wheel'));
    expect(duplicate['context'], 'global');
    expect(duplicate['ignoreRepeat'], isTrue);
    expect(duplicate['input'], bindings.first['input']);
    expect(duplicate['followUpActions'], [BindingAction.nextPage]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏的完整表单与后续动作不溢出', (tester) async {
    bindings.first['followUpActions'] = [
      BindingAction.nextPage,
      BindingAction.zoomIn,
    ];
    await pump(
      tester,
      size: const Size(360, 800),
      conflicts: [
        (key: 'test', bindingIds: ['wheel']),
      ],
    );
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.byType(BindingInputEditor), findsNothing);
    await tester.tap(find.byKey(const ValueKey('action:reader.previous-page')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-binding:wheel')));
    await tester.pumpAndSettle();
    expect(find.text(t.bindingEditor.conflictHint), findsOneWidget);
    expect(find.byType(BindingInputEditor), findsOneWidget);
    await tester.drag(
      find.byKey(const PageStorageKey('binding-action-details')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏先看翻页分类，页签切换和拉宽保留编辑结果', (tester) async {
    await pump(tester, size: const Size(600, 1000));
    for (final action in catalog.where((a) => a.category == 'navigation')) {
      expect(find.byKey(ValueKey('action:${action.id}')), findsOneWidget);
    }
    expect(find.byType(BindingInputEditor), findsNothing);
    await tester.tap(find.byKey(const ValueKey('action:reader.next-page')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-binding:key')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Ctrl'));
    await tester.pumpAndSettle();
    expect(bindings.last['input']['ctrl'], isTrue);
    await tester.tap(find.text(t.bindingEditor.actionList));
    await tester.pumpAndSettle();
    expect(find.byType(BindingInputEditor), findsNothing);
    await tester.tap(find.text(t.bindingEditor.bindingDetails));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BindingInputEditor>(find.byType(BindingInputEditor))
          .input['code'],
      'KeyN',
    );
    tester.view.physicalSize = const Size(1440, 1000);
    await tester.pumpAndSettle();
    expect(find.byType(TabBar), findsNothing);
    expect(
      tester
          .widget<BindingInputEditor>(find.byType(BindingInputEditor))
          .input['ctrl'],
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换设备后显示对应字段，输入按键名保持焦点', (tester) async {
    bindings = [
      row('key', BindingAction.previousPage, {
        'device': 'keyboard',
        'code': 'KeyN',
      }),
    ];
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('edit-binding:key')));
    await tester.pumpAndSettle();
    final code = find.descendant(
      of: find.byKey(const ValueKey('code')),
      matching: find.byType(TextField),
    );
    await tester.enterText(code, 'ArrowLeft');
    await tester.pumpAndSettle();
    expect(bindings.single['input']['code'], 'ArrowLeft');
    expect(tester.widget<TextField>(code).focusNode?.hasFocus ?? true, isTrue);
    final device = find.byWidgetPredicate(
      (w) => w is BindingSelect<String> && w.label == t.bindingEditor.device,
    );
    await tester.tap(
      find.descendant(of: device, matching: find.byType(DropdownMenu<String>)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.bindingEditor.touch).last);
    await tester.pumpAndSettle();
    expect(bindings.single['input'], defaultBindingInput('touch'));
    expect(find.text(t.bindingEditor.fingers), findsWidgets);
  });

  testWidgets('键盘录制等待主键，修饰键不会抢先结束录制', (tester) async {
    Map<String, dynamic>? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                captured = await BindingInputRecorder.show(context, {
                  'device': 'keyboard',
                  'code': 'KeyN',
                });
              },
              child: const Text('record'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('record'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text(t.bindingEditor.recordWaiting), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.common.confirm));
    await tester.pumpAndSettle();
    expect(captured?['code'], 'KeyK');
    expect(captured?['ctrl'], isTrue);
  });

  test('重复事件被消费，序列不因主动作未实现而截断', () {
    final events = <String>[];
    final binding = {
      ...bindings.first,
      'ignoreRepeat': true,
      'followUpActions': [BindingAction.zoomIn, BindingAction.nextPage],
    };
    expect(
      dispatchBindingActions(
        binding,
        isRepeat: true,
        execute: (action) {
          events.add(action);
          return true;
        },
      ),
      isTrue,
    );
    expect(events, isEmpty);
    expect(
      dispatchBindingActions(
        binding,
        execute: (action) {
          events.add(action);
          return action != BindingAction.previousPage;
        },
      ),
      isTrue,
    );
    expect(events, [
      BindingAction.previousPage,
      BindingAction.zoomIn,
      BindingAction.nextPage,
    ]);
  });
}
