import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';

/// 绑定表文档层的判据（纯 Dart，不加载原生库）。
///
/// 盯的是三件「坏了没人会发现」的事：
/// 1. **往返丢字段** —— 导入一份带手柄/轮盘绑定的包，存回去不能把它洗掉；
/// 2. **冲突清单读不出来** —— 读成空就等于「冲突阻止保存」这条规则静默失效；
/// 3. **键名归一化跑偏** —— `code` 写错了那条绑定永远匹配不上，而设置页看起来一切正常。
void main() {
  // `keyboardInputJsonOf` 会读 `HardwareKeyboard.instance`，而它要等 binding 初始化
  // 之后才拿得到按键状态（bare `test()` 不会自动初始化）。不开这个，采集那两条判据
  // 会以「Binding has not yet been initialized」的形态失败，看着像代码错了。
  TestWidgetsFlutterBinding.ensureInitialized();

  group('绑定包 JSON 往返', () {
    // 一份「别处带来的」绑定包：含 v0.1 运行时**不产出**的四类 descriptor。
    const imported = '''
{
  "bindings": [
    {"id":"k1","action":"reader.page-right","context":"reader","enabled":true,
     "input":{"device":"keyboard","code":"ArrowRight","ctrl":true}},
    {"id":"g1","action":"reader.zoom-in","context":"reader","enabled":true,
     "input":{"device":"gamepad","button":3}},
    {"id":"r1","action":"reader.last-page","context":"reader","enabled":true,
     "input":{"device":"radial","menuId":"default","itemId":"radial-next-page"}},
    {"id":"m1","action":"reader.reset-view","context":"reader","enabled":true,
     "input":{"device":"mouse-gesture","button":2,"directions":["left","up"],"trigger":"hold"}},
    {"id":"c1","action":"reader.open-settings","context":"shell","enabled":true,
     "input":{"device":"command","command":"file-card.trash-current"}},
    {"id":"t1","action":"reader.next-page","context":"global","enabled":false,
     "ignoreRepeat":true,"followUpActions":["reader.toggle-controls"],
     "input":{"device":"wheel","direction":"down","shift":true}}
  ]
}''';

    test('解析 → 编码 → 再解析，逐字段等价', () {
      final bindings = parseBindings(imported);
      expect(bindings, isNotNull);
      expect(bindings!.length, 6);

      final again = parseBindings(encodeBindingsDoc(bindings));
      expect(again, bindings, reason: '一次导出/导入不许丢任何字段');
    });

    test('手柄/轮盘/轨迹/命令这四类原样存回（运行时不产出，但必须留得住）', () {
      final bindings = parseBindings(imported)!;
      final byId = {for (final b in bindings) b['id'] as String: b};

      expect(byId['g1']!['input']['device'], 'gamepad');
      expect(byId['g1']!['input']['button'], 3);
      expect(byId['r1']!['input']['itemId'], 'radial-next-page');
      expect(byId['m1']!['input']['directions'], ['left', 'up']);
      expect(byId['c1']!['input']['command'], 'file-card.trash-current');
    });

    test('禁用标记、追加动作、ignoreRepeat 都跟着走', () {
      final row = parseBindings(imported)!.firstWhere((b) => b['id'] == 't1');
      expect(row['enabled'], isFalse);
      expect(row['ignoreRepeat'], isTrue);
      expect(row['followUpActions'], ['reader.toggle-controls']);
    });

    test('裸数组也吃得下（引擎预设导出的就是这个形状）', () {
      const bare =
          '[{"id":"p1","action":"reader.page-left","context":"reader",'
          '"enabled":true,"input":{"device":"area","area":"middle-left",'
          '"button":0,"action":"click"}}]';
      final bindings = parseBindings(bare);
      expect(bindings, hasLength(1));
      // 写回一律成 `InputBindingsConfig` 的形状（持久化权威形状）。
      expect(parseBindings(encodeBindingsDoc(bindings!)), bindings);
      expect(
        jsonDecodeArray(encodeBindingsArray(bindings)).length,
        1,
        reason: '喂给引擎的那一份是裸数组',
      );
    });

    test('读不出绑定数组时返回 null，而不是抛', () {
      expect(parseBindings(''), isNull);
      expect(parseBindings('not json'), isNull);
      expect(parseBindings('{"bindings":{}}'), isNull);
      // input 缺 device 的行：宁可整份判非法，也不要把一条永远匹配不上的绑定留下。
      expect(
        parseBindings('[{"id":"x","action":"a","input":{"code":"A"}}]'),
        isNull,
      );
    });
  });

  group('预设行替换', () {
    final bindings = <Map<String, dynamic>>[
      {'id': 'preset-tap-advance', 'action': 'reader.page-right'},
      {'id': 'user-key-1', 'action': 'reader.next-page'},
      {'id': 'preset-key-0-ArrowRight', 'action': 'reader.page-right'},
    ];

    test('只换 preset-tap- 那几条，用户加的与键盘预设原样保留', () {
      final result = replacePresetRows(bindings, kTapPresetIdPrefix, [
        {'id': 'preset-tap-advance', 'action': 'reader.page-left'},
      ]);
      expect(result, hasLength(3));
      expect(
        result.firstWhere((b) => b['id'] == 'preset-tap-advance')['action'],
        'reader.page-left',
      );
      expect(
        result.firstWhere((b) => b['id'] == 'user-key-1')['action'],
        'reader.next-page',
        reason: '改左右手预设不该洗掉用户的定制',
      );
      expect(
        result.where((b) => (b['id'] as String).startsWith('preset-key-')),
        hasLength(1),
      );
    });

    test('删一条 / 改启用状态都是纯函数（不动入参）', () {
      final removed = removeBindingById(bindings, 'user-key-1');
      expect(bindings, hasLength(3), reason: '原表不许被改到');
      expect(removed, hasLength(2));

      final disabled = setBindingEnabled(bindings, 'preset-tap-advance', false);
      expect(
        disabled.firstWhere((b) => b['id'] == 'preset-tap-advance')['enabled'],
        isFalse,
      );
      expect(bindings.first['enabled'], isNull, reason: '入参仍是原样');
    });
  });

  group('冲突清单（冲突阻止保存）', () {
    test('读引擎返回的形状', () {
      const engineJson =
          '[{"key":"reader:area:middle-right:0:click",'
          '"bindingIds":["preset-tap-advance","user-key-1"]}]';
      final conflicts = parseConflicts(engineJson);
      expect(conflicts, hasLength(1));
      expect(conflicts.first.key, 'reader:area:middle-right:0:click');
      expect(conflicts.first.bindingIds, ['preset-tap-advance', 'user-key-1']);
    });

    test('没有冲突时是空表（保存放行）', () {
      expect(parseConflicts('[]'), isEmpty);
    });

    test('descriptor 组装：修饰键与九宫格', () {
      expect(jsonDecodeMap(keyboardInputJson(code: 'ArrowLeft', ctrl: true)), {
        'device': 'keyboard',
        'code': 'ArrowLeft',
        'trigger': 'down',
        'ctrl': true,
        'alt': false,
        'shift': false,
        'meta': false,
      });
      expect(jsonDecodeMap(areaInputJson(area: TapArea.middleCenter)), {
        'device': 'area',
        'area': 'middle-center',
        'button': 0,
        'action': 'click',
      });
      expect(
        describeInput(
          jsonDecodeMap(
            keyboardInputJson(code: 'Space', shift: true, meta: true),
          ),
        ),
        'Shift+Meta+Space',
      );
    });
  });

  group('LogicalKeyboardKey → code（映射归外壳，ADR-0015 §6）', () {
    test('W3C 口径：首字母大写，覆盖方向键/字母/小键盘/功能键', () {
      // `LogicalKeyboardKey` 没有原样相等（`const` 表的键要求这个），所以用 `final`。
      final cases = <LogicalKeyboardKey, String>{
        LogicalKeyboardKey.arrowLeft: 'ArrowLeft',
        LogicalKeyboardKey.arrowRight: 'ArrowRight',
        LogicalKeyboardKey.arrowUp: 'ArrowUp',
        LogicalKeyboardKey.keyA: 'KeyA',
        LogicalKeyboardKey.keyS: 'KeyS',
        LogicalKeyboardKey.numpad2: 'Numpad2',
        LogicalKeyboardKey.numpad4: 'Numpad4',
        LogicalKeyboardKey.numpad6: 'Numpad6',
        LogicalKeyboardKey.numpad8: 'Numpad8',
        LogicalKeyboardKey.space: 'Space',
        LogicalKeyboardKey.pageDown: 'PageDown',
        LogicalKeyboardKey.pageUp: 'PageUp',
        LogicalKeyboardKey.home: 'Home',
        LogicalKeyboardKey.end: 'End',
        LogicalKeyboardKey.enter: 'Enter',
        LogicalKeyboardKey.tab: 'Tab',
        LogicalKeyboardKey.backspace: 'Backspace',
        LogicalKeyboardKey.escape: 'Escape',
        LogicalKeyboardKey.comma: 'Comma',
        LogicalKeyboardKey.period: 'Period',
        LogicalKeyboardKey.slash: 'Slash',
        LogicalKeyboardKey.backslash: 'Backslash',
        LogicalKeyboardKey.minus: 'Minus',
        LogicalKeyboardKey.equal: 'Equal',
        LogicalKeyboardKey.semicolon: 'Semicolon',
        LogicalKeyboardKey.quote: 'Quote',
        LogicalKeyboardKey.bracketLeft: 'BracketLeft',
        LogicalKeyboardKey.bracketRight: 'BracketRight',
        LogicalKeyboardKey.backquote: 'Backquote',
        LogicalKeyboardKey.keyD: 'KeyD',
        LogicalKeyboardKey.keyW: 'KeyW',
        LogicalKeyboardKey.arrowDown: 'ArrowDown',
        LogicalKeyboardKey.f11: 'F11',
        LogicalKeyboardKey.digit1: 'Digit1',
        LogicalKeyboardKey.shiftLeft: 'ShiftLeft',
        LogicalKeyboardKey.controlRight: 'ControlRight',
      };
      for (final entry in cases.entries) {
        expect(
          keyCodeOf(entry.key),
          entry.value,
          reason: '${entry.key} 的 code 必须是 ${entry.value}',
        );
      }
    });

    test('出厂预设里的每个 code 都能被采集端产出（两边不许分叉）', () {
      // preset.rs 的 DEFAULT_KEY_BINDINGS 用的是 W3C 名；这里反向核对：
      // Flutter 侧对同一批键算出的名字必须一模一样，否则预设永远匹配不上。
      const presetCodes = [
        'ArrowRight',
        'ArrowLeft',
        'Space',
        'PageDown',
        'PageUp',
        'Home',
      ];
      final produced = <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.home,
      ].map(keyCodeOf).nonNulls.toSet();
      expect(produced, containsAll(presetCodes));
    });

    test('认不出名字的键返回 null（不猜一个永远匹配不上的 code）', () {
      expect(keyCodeOf(LogicalKeyboardKey(0x0000FF00FF00FF)), isNull);
      // 重音字母：逻辑键记录的是「这个布局下这个键产出什么字符」，W3C 的 code
      // 是物理键名，从逻辑键推不出来 —— 宁可录不进去，也不要留一条永不生效的绑定。
      expect(keyCodeOf(LogicalKeyboardKey(0x000000000e9)), isNull);
    });
  });

  group('点击分区的读写（设置页那一侧的表操作）', () {
    final table = parseBindings(
      '[{"id":"preset-tap-advance","action":"reader.page-right","context":"reader",'
      '"enabled":true,"input":{"device":"area","area":"middle-right","button":0,"action":"click"}}]',
    )!;

    test('同一格只留一条：改写而不是追加（追加会立刻造出冲突）', () {
      var bindings = bindArea(table, TapArea.middleRight, 'reader.fullscreen');
      expect(bindings, hasLength(1));
      expect(actionForArea(bindings, TapArea.middleRight), 'reader.fullscreen');
    });

    test('换到没绑过的格子是新增；空动作是解绑', () {
      var bindings = bindArea(table, TapArea.middleLeft, 'reader.page-left');
      expect(bindings, hasLength(2));
      expect(actionForArea(bindings, TapArea.middleLeft), 'reader.page-left');

      bindings = bindArea(bindings, TapArea.middleLeft, '');
      expect(actionForArea(bindings, TapArea.middleLeft), isNull);
      expect(actionForArea(bindings, TapArea.middleRight), 'reader.page-right');
    });

    test('解绑/改写不许动到别的设备类型的行', () {
      final withKeyboard = parseBindings(
        '[{"id":"k1","action":"reader.page-right","context":"reader","enabled":true,'
        '"input":{"device":"keyboard","code":"ArrowRight"}},'
        '{"id":"g1","action":"reader.zoom-in","context":"reader","enabled":true,'
        '"input":{"device":"gamepad","button":3}}]',
      )!;
      final bindings = bindArea(
        withKeyboard,
        TapArea.middleRight,
        'reader.last-page',
      );
      expect(bindings, hasLength(3), reason: '两个 area 格之外，键盘与手柄那两条原样在');
      expect(
        bindings.firstWhere((b) => b['id'] == 'g1')['input']['device'],
        'gamepad',
      );
    });
  });

  group('按键采集（运行时与录入框共用同一个采集口）', () {
    test('没按修饰键时四个 flag 都是 false，code 是 W3C 名', () {
      final json = keyboardInputJsonOf(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: LogicalKeyboardKey.keyA,
          timeStamp: Duration.zero,
        ),
      );
      expect(json, isNotNull);
      final input = jsonDecodeMap(json!);
      expect(input['code'], 'KeyA');
      expect(input['device'], 'keyboard');
      expect(
        [input['ctrl'], input['alt'], input['shift'], input['meta']],
        [false, false, false, false],
      );
    });

    test('认不出键名的键返回 null（录入框要据此提示，而不是静默失败）', () {
      expect(
        keyboardInputJsonOf(
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey(0),
            logicalKey: LogicalKeyboardKey(0x0000FF00FF00FF),
            timeStamp: Duration.zero,
          ),
        ),
        isNull,
      );
    });
  });
}

Object? jsonDecodeValue(String source) => jsonDecode(source);

List<dynamic> jsonDecodeArray(String source) =>
    (jsonDecodeValue(source) as List<dynamic>);

Map<String, dynamic> jsonDecodeMap(String source) =>
    Map<String, dynamic>.from(jsonDecodeValue(source) as Map);
