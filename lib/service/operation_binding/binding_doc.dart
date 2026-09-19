// 绑定包（`InputBindingsConfig`）的 **JSON 文档工具** —— 全部纯函数，不碰 FRB。
//
// 分成这个文件和 `operation_binding_store.dart` 的理由：判据要在**没有加载原生库**的
// 宿主（`flutter test`）里跑，而「文档长什么样、字段丢没丢、冲突清单怎么读」正是
// 最需要钉死的那一层；真正问引擎（解析 / 冲突 / 预设）的部分在 store 里。
//
// ## 为什么 Dart 侧只当 Map 拿着
//
// schema 的唯一权威是 `rossi_local_core::operation_binding`（ADR-0015）。Dart 一旦建
// 一套强类型镜像，schema 每次演进都要两边同步改生成物 —— 而这里要的恰恰是
// 「换外壳时绑定表零改动」。所以下面每一个函数都只认**字段名**，不认类型。

import 'dart:convert';

import 'package:flutter/services.dart';

/// 引擎认识的输入设备名（`InputDescriptor` 的 serde tag 值，逐条照抄不许改）。
abstract final class InputDevice {
  static const keyboard = 'keyboard';
  static const mouse = 'mouse';
  static const mouseGesture = 'mouse-gesture';
  static const wheel = 'wheel';
  static const touch = 'touch';
  static const gamepad = 'gamepad';
  static const area = 'area';
  static const radial = 'radial';
  static const command = 'command';
}

/// 画面九宫格里**运行时真会产出的那三格**（中排）。
///
/// 点击分区在改造前就是「左半 / 正中 / 右半」三档（上下两排跟中排同动作），
/// 所以采集端把落点归一到中排三格 —— 上/下排那六格是 schema 里的合法值，
/// v0.1 的采集端不产出它们（导进来照样存得下，见 model.rs 的往返判据）。
abstract final class TapArea {
  static const middleLeft = 'middle-left';
  static const middleCenter = 'middle-center';
  static const middleRight = 'middle-right';

  static const all = [middleLeft, middleCenter, middleRight];
}

/// 动作 id（与 `vocabulary::action` 一一对应；这里是 Dart 侧**执行**要认的那几条）。
abstract final class BindingAction {
  static const nextPage = 'reader.next-page';
  static const previousPage = 'reader.previous-page';
  static const firstPage = 'reader.first-page';
  static const lastPage = 'reader.last-page';
  static const pageLeft = 'reader.page-left';
  static const pageRight = 'reader.page-right';
  static const fullscreen = 'reader.fullscreen';
  static const toggleReadingDirection = 'reader.toggle-reading-direction';
  static const toggleBookMode = 'reader.toggle-book-mode';
  static const resetView = 'reader.reset-view';
  static const toggleControls = 'reader.toggle-controls';
  static const openSettings = 'reader.open-settings';

  /// 缩放与旋转一族（注册表里早就有，本仓的执行体挂在顶栏那套呈现状态上）。
  static const zoomIn = 'reader.zoom-in';
  static const zoomOut = 'reader.zoom-out';
  static const fitWindow = 'reader.fit-window';
  static const actualSize = 'reader.actual-size';
  static const rotateClockwise = 'reader.rotate-clockwise';
  static const rotate180 = 'reader.rotate-180';

  /// 唤出轮盘（id 照抄 neoview 的注册表条目，见 `vocabulary.rs`）。
  ///
  /// 「轮盘怎么打开」与「轮盘里每一格干什么」走的是同一套：都是绑定表里的一条输入
  /// → 一个动作 id。差别只在前者的输入是键盘/鼠标，后者的输入是 `device: radial`。
  static const openRadialMenu = 'radial.open-default';

  /// 翻页语义的四条（其余翻页动作不算）。
  static const pageTurnFamily = [
    nextPage,
    previousPage,
    pageLeft,
    pageRight,
  ];
}

/// 预设行的 id 前缀（`preset.rs` 里生成的那批）。
///
/// 「改左右手预设」只重写 `preset-tap-` 那几条，用户自己加的绑定原样保留 ——
/// 否则一个开关会把用户的键盘/点击定制一起洗掉。
const String kTapPresetIdPrefix = 'preset-tap-';

/// 解析绑定文档，取出绑定数组。
///
/// 两种形状都吃：
/// - `{"bindings":[…]}` —— `InputBindingsConfig` 的序列化结果，也是**持久化用的形状**；
/// - `[…]` —— 引擎 FRB 对外的形状（预设导出即裸数组）。
///
/// 后者也要能吃，是因为「导入」的输入可能是用户从别处拿来的任何一份：
/// 认死一种形状 = 导入直接失败。写回时一律用第一种（见 [encodeBindingsDoc]）。
/// 返回 `null` = 这份 JSON 根本读不出绑定数组。
List<Map<String, dynamic>>? parseBindings(String docJson) {
  if (docJson.trim().isEmpty) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(docJson);
  } on FormatException {
    return null;
  }
  final raw = decoded is List
      ? decoded
      : (decoded is Map ? decoded['bindings'] : null);
  if (raw is! List) return null;
  final bindings = <Map<String, dynamic>>[];
  for (final entry in raw) {
    if (entry is! Map) return null;
    // 每条绑定必须有 `input`，且那个 input 得说自己是什么设备 —— 缺了就没法解析，
    // 与其让 Rust 侧 expect 掉进进程，不如在这里判死。
    final input = entry['input'];
    if (input is! Map || input['device'] is! String) return null;
    bindings.add(Map<String, dynamic>.from(entry));
  }
  return bindings;
}

/// 绑定数组 → 持久化形状（`InputBindingsConfig`）。
String encodeBindingsDoc(List<Map<String, dynamic>> bindings) =>
    jsonEncode({'bindings': bindings});

/// 绑定数组 → 引擎要的裸数组 JSON（`operation_binding_*` 的 `bindings_json` 参数）。
String encodeBindingsArray(List<Map<String, dynamic>> bindings) =>
    jsonEncode(bindings);

/// 人类可读的导出文本（缩进过，直接可以贴进文件 / 发给别人）。
String prettyBindingsDoc(List<Map<String, dynamic>> bindings) =>
    const JsonEncoder.withIndent('  ').convert({'bindings': bindings});

/// 一次键盘按下 → descriptor 的 JSON。
String keyboardInputJson({
  required String code,
  bool ctrl = false,
  bool alt = false,
  bool shift = false,
  bool meta = false,
}) => jsonEncode({
  'device': InputDevice.keyboard,
  'code': code,
  'trigger': 'down',
  'ctrl': ctrl,
  'alt': alt,
  'shift': shift,
  'meta': meta,
});

/// 一次鼠标/触控笔按下 → descriptor 的 JSON。
///
/// `button` 用 W3C `MouseEvent.button` 的口径（0 左 / 1 中 / 2 右），与 neoview 一致；
/// `Flutter` 的 `PointerDownEvent.buttons` 是位掩码，那层翻译在采集端
/// （`reader_input_controller.dart`）。`action` 默认 `press`：轮盘要在**按下**就出现。
String mouseInputJson({required int button, String action = 'press'}) => jsonEncode({
  'device': InputDevice.mouse,
  'button': button,
  'action': action,
});

/// 一次落在九宫格某一格的点击 → descriptor 的 JSON。
String areaInputJson({
  required String area,
  int button = 0,
  String action = 'click',
}) => jsonEncode({
  'device': InputDevice.area,
  'area': area,
  'button': button,
  'action': action,
});

/// 一条绑定（用于把解析结果写回表里）。
Map<String, dynamic> buildBinding({
  required String id,
  required String action,
  required String context,
  required String inputJson,
  bool enabled = true,
  bool ignoreRepeat = false,
  List<String> followUpActions = const [],
}) => {
  'id': id,
  'action': action,
  if (followUpActions.isNotEmpty) 'followUpActions': followUpActions,
  'context': context,
  'enabled': enabled,
  'ignoreRepeat': ignoreRepeat,
  'input': jsonDecode(inputJson),
};

/// 新绑定的 id：动作名 + 微秒，够让用户在冲突清单里认出「是哪一条」。
String newBindingId(String actionId) {
  final slug = actionId.split('.').last.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '-');
  return 'user-$slug-${DateTime.now().microsecondsSinceEpoch}';
}

/// 用 `rows` 替换掉所有 id 以 [prefix] 开头的行，其余原样保留（顺序：其余在前）。
List<Map<String, dynamic>> replacePresetRows(
  List<Map<String, dynamic>> bindings,
  String prefix,
  List<Map<String, dynamic>> rows,
) {
  final kept = bindings
      .where((binding) => !(binding['id'] as String? ?? '').startsWith(prefix))
      .toList();
  return [...kept, ...rows];
}

/// 某个动作当前的所有绑定（注册表顺序之外的「谁绑到了这个动作」）。
List<Map<String, dynamic>> bindingsForAction(
  List<Map<String, dynamic>> bindings,
  String actionId,
) => bindings
    .where((binding) => binding['action'] == actionId)
    .toList(growable: false);

/// 删掉一条绑定（按 id）。
List<Map<String, dynamic>> removeBindingById(
  List<Map<String, dynamic>> bindings,
  String id,
) => bindings.where((binding) => binding['id'] != id).toList();

/// 启用/停用一条绑定（按 id）。
///
/// 冲突判定只看**启用**的行（引擎 `conflicts` 同语义），所以「禁用其一」
/// 是用户解开冲突的那条路 —— 这里给它一个入口，而不是逼用户删掉一条。
List<Map<String, dynamic>> setBindingEnabled(
  List<Map<String, dynamic>> bindings,
  String id,
  bool enabled,
) => bindings.map((binding) {
  if (binding['id'] != id) return binding;
  return {...binding, 'enabled': enabled};
}).toList();

/// 引擎 `conflicts()` 的一项。
typedef BindingConflict = ({String key, List<String> bindingIds});

/// 读引擎返回的冲突清单（`[{"key":…,"bindingIds":[…]}]`）。
List<BindingConflict> parseConflicts(String conflictsJson) {
  final Object? decoded;
  try {
    decoded = jsonDecode(conflictsJson);
  } on FormatException {
    // 读不懂就当「有冲突」？不行 —— 那会让用户永远存不了。
    // 但也不能当没冲突：调用方（保存路径）在此之前已经 validate 过绑定表，
    // 走到这里说明引擎本身出了问题，交给上层按异常处理。
    return const [];
  }
  if (decoded is! List) return const [];
  return [
    for (final entry in decoded)
      if (entry is Map)
        (
          key: entry['key'] as String? ?? '',
          bindingIds: [
            for (final id in entry['bindingIds'] as List? ?? const [])
              id.toString(),
          ],
        ),
  ];
}

/// 一条输入的展示名（`Ctrl+Alt+ArrowLeft` 这种）。
///
/// 只覆盖 v0.1 采集端会产出的两类（键盘 / 九宫格）；其余类别原样显示 descriptor，
/// 好过把它们误标成某个具体手势。
String describeInput(Map<String, dynamic> input) {
  final device = input['device'] as String? ?? '';
  switch (device) {
    case InputDevice.keyboard:
      final modifiers = [
        if (input['ctrl'] == true) 'Ctrl',
        if (input['alt'] == true) 'Alt',
        if (input['shift'] == true) 'Shift',
        if (input['meta'] == true) 'Meta',
      ];
      final code = input['code'] as String? ?? '?';
      return modifiers.isEmpty ? code : '${modifiers.join('+')}+$code';
    case InputDevice.area:
      return 'area:${input['area'] ?? '?'}:${input['action'] ?? 'click'}';
    case InputDevice.mouse:
      return 'mouse:${input['button'] ?? '?'}:${input['action'] ?? 'click'}';
    case InputDevice.radial:
      return 'radial:${input['menuId'] ?? '?'}:${input['itemId'] ?? '?'}';
    default:
      return jsonEncode(input);
  }
}

/// `LogicalKeyboardKey` → descriptor 的 `code`（平台无关键名）。
///
/// **这一层就是 ADR-0015 §6 说的「`KeySlot ⇄ 平台键码` 的映射归外壳」**：核心只认
/// `ArrowLeft` / `KeyA` / `Numpad4` 这类字符串，Flutter 的键对象到它的翻译住在 Dart。
/// 名字口径 = W3C `KeyboardEvent.code`（neoview 也是这个）。
///
/// 为什么用 [LogicalKeyboardKey.keyLabel] 而不是 `debugName`／`toString()`：
/// `debugName` 里层是 `assert(() { … }())`，**release 构建恒为 null**（Flutter 故意把
/// 那张名字表剔出 release 以省体积）。拿它当持久化的键名，Debug 下录的绑定会在
/// Release 包里静默失效 —— 那是最难查的一类 bug。`keyLabel` 用的是普通 const 表，
/// release 也在。
///
/// 认不出名字的键返回 `null`（重音字母、未命名键码）：**不猜一个名字写进绑定表**，
/// 否则那条绑定永远匹配不上，而设置页看起来一切正常。
String? keyCodeOf(LogicalKeyboardKey key) {
  // 控制字符类：`keyLabel` 给出的是那个不可打印字符本身，只能按 keyId 认。
  final byId = _keyIdCodes[key.keyId];
  if (byId != null) return byId;

  final label = key.keyLabel;
  if (label.isEmpty) return null;

  // 可打印的标点：keyLabel 就是那个字符，W3C 给它一个词（`Comma` 而不是 `,`）。
  final punctuated = _punctuationCodes[label];
  if (punctuated != null) return punctuated;

  if (label.length == 1) {
    final unit = label.toUpperCase();
    final code = unit.codeUnitAt(0);
    // A–Z / 0–9 → `KeyA` / `Digit1`（W3C 口径）。其余单字符（重音字母等）没有
    // 平台无关名 —— 逻辑键本身承载的是「这个布局上这个键产出什么字符」。
    if (code >= 0x41 && code <= 0x5A) return 'Key$unit';
    if (code >= 0x30 && code <= 0x39) return 'Digit$unit';
    return null;
  }

  // 非打印键：`Arrow Left` → `ArrowLeft`、`Numpad 4` → `Numpad4`、`F11` → `F11`。
  final collapsed = label.replaceAll(' ', '');
  if (collapsed.isEmpty) return null;
  return collapsed[0].toUpperCase() + collapsed.substring(1);
}

/// 某格（九宫格里的那一格）当前绑到的动作 id；没绑返回 `null`。
String? actionForArea(List<Map<String, dynamic>> bindings, String area) {
  for (final binding in bindings) {
    if (_areaOf(binding) == area) {
      return binding['action'] as String?;
    }
  }
  return null;
}

/// 把某一格绑到 [actionId]（空串 = 解绑这一格）。
///
/// 同一格只留一条：这一格原来就有绑定时**改写**它，而不是再追加一条 —— 追加会立刻
/// 造出一个冲突，而用户的意图明明是「这一格改成干别的」。
List<Map<String, dynamic>> bindArea(
  List<Map<String, dynamic>> bindings,
  String area,
  String actionId,
) {
  final index = bindings.indexWhere((binding) => _areaOf(binding) == area);
  if (index < 0) {
    if (actionId.isEmpty) return bindings;
    return [
      ...bindings,
      buildBinding(
        id: newBindingId(actionId),
        action: actionId,
        context: 'reader',
        inputJson: areaInputJson(area: area),
      ),
    ];
  }
  final row = bindings[index];
  if (actionId.isEmpty) return removeBindingById(bindings, row['id'] as String);
  if (row['action'] == actionId) return bindings;
  return [
    for (final binding in bindings)
      if (binding == row) {...binding, 'action': actionId} else binding,
  ];
}

String? _areaOf(Map<String, dynamic> binding) {
  final input = binding['input'];
  if (input is! Map) return null;
  if (input['device'] != InputDevice.area) return null;
  return input['area'] as String?;
}

/// 一次按键 → 键盘 descriptor 的 JSON（认不出键名时 `null`，不猜）。
///
/// 采集端（运行时的按键处理、设置页的录入框）都用它，两边才可能产出同一个 `code`：
/// 录进去的与运行时算出来的只要差一个字符，那条绑定就永远不生效，而两边都看着正常。
///
/// 修饰键有个坑：按下 `ControlLeft` 本身时 `isControlPressed` 已经是 `true`，于是
/// 采集结果会是 `Ctrl+ControlLeft` —— 用户录进去的是这个，而**单独按 Ctrl 永远
/// 不满足它**（那条绑定形同废掉）。所以「键自己不算自己的修饰键」。
String? keyboardInputJsonOf(KeyEvent event) {
  final code = keyCodeOf(event.logicalKey);
  if (code == null) return null;
  final keyboard = HardwareKeyboard.instance;
  return keyboardInputJson(
    code: code,
    ctrl: keyboard.isControlPressed && !code.startsWith('Control'),
    alt: keyboard.isAltPressed && !code.startsWith('Alt'),
    shift: keyboard.isShiftPressed && !code.startsWith('Shift'),
    meta: keyboard.isMetaPressed && !code.startsWith('Meta'),
  );
}

/// 不可打印但 keyId 就是 Unicode 码点的那几个键（W3C 名字）。
const Map<int, String> _keyIdCodes = {
  0x08: 'Backspace',
  0x09: 'Tab',
  0x0d: 'Enter',
  0x1b: 'Escape',
  0x20: 'Space',
};

/// 可打印标点的 W3C 名字（keyLabel 给的是字符本身）。
const Map<String, String> _punctuationCodes = {
  ' ': 'Space',
  ',': 'Comma',
  '.': 'Period',
  '/': 'Slash',
  '\\': 'Backslash',
  '-': 'Minus',
  '=': 'Equal',
  ';': 'Semicolon',
  // Flutter 的 `LogicalKeyboardKey.quote` 是 `"`（0x22，即按住 Shift 的那一档），
  // 而 W3C 的 `Quote` 说的是**同一个物理键**（不偏 shift 时产出 `'`）。
  // 两个字符都收敛到 `Quote` 才对：绑定按物理键记，不按有没有按 Shift 记。
  "'": 'Quote',
  '"': 'Quote',
  '[': 'BracketLeft',
  ']': 'BracketRight',
  '`': 'Backquote',
};

