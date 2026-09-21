// 轮盘文档（核心 `RadialConfig`）的 **JSON 工具** —— 全部纯函数，不碰 FRB。
//
// 与 `binding_doc.dart` 同一分工：这一层只管「文档长什么样、字段丢没丢」，
// 真正问引擎（形状是否合法、落点在哪一格、怎么画）的部分在
// `operation_binding_store.dart`。判据要能在**没有原生库**的宿主里跑，
// 而轮盘最容易出错的两处正是：① 改形状时把用户没碰过的字段洗掉；
// ② 文档里的条目与绑定行对不上号。
//
// ## 为什么这里只当 Map 拿着
//
// 与绑定表同样的理由（ADR-0015）：schema 的唯一权威是 Rust。下面的 [RadialDoc] 是
// **视图**不是镜像 —— 读写自己认识的字段，其余原样留在 [RadialDoc.raw] 里，
// `encode()` 时一起写回去。核心将来加字段，这一层不改也不丢数据。
//
// ## 条目的动作不在这里
//
// 文档里的条目（[RadialItemDoc]）只有**身份与外观**：id、显示文字、第几格、可选的
// 「跳转轮盘」。它「干什么」是一条 `device: radial` 的绑定
// （`(menuId, itemId)` → 注册表里的动作 id），存在绑定表里。
// 这正是 neoview 自己的形状：它把条目上遗留的直连动作 `action` 从编辑器里剥掉
// （`stripLegacyActions`），改成物化绑定行；运行时先派发绑定、派发不到才回落。
// 于是轮盘与键盘、点击同权：同一个解析器、同一套冲突判定、`followUpActions` 自动可用。
//
// 形状与绑定表的接缝由核心的 `prune_bindings` 守住（这里只负责改形状，不剪绑定）。

import 'dart:convert';

import 'package:zephyr/service/operation_binding/binding_doc.dart';

/// 出厂轮盘的 id（核心 `DEFAULT_RADIAL_MENU_ID`）。
///
/// 只有这一个轮盘带出厂条目；用户新建的轮盘是空的，不该被塞别人的默认值。
const String kRadialDefaultMenuId = 'default';

/// 轮盘文档里条目 id 的形状（neoview 的校验：`^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$`）。
final RegExp _radialIdPattern = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$');

/// 一个槽位的身份：哪个轮盘的哪个条目。这就是绑定包里的 `(menuId, itemId)`。
typedef RadialSlotRef = ({String menuId, String itemId});

/// 解析轮盘文档。返回 `null` = 这份 JSON 根本读不出菜单列表（含空串）。
RadialDoc? parseRadialDoc(String configJson) {
  if (configJson.trim().isEmpty) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(configJson);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final menus = decoded['menus'];
  if (menus is! List) return null;
  return RadialDoc(Map<String, dynamic>.from(decoded));
}

/// 一份可编辑的轮盘文档视图。
class RadialDoc {
  RadialDoc(this.raw);

  /// 原始映射：本层不认识的字段都活在这里，`encode()` 时原样写回。
  final Map<String, dynamic> raw;

  bool get enabled => raw['enabled'] != false;

  /// 显示几层（同心环数）。缺省按 1 读，越界由核心校验报出来，这里不夹。
  int get layerCount => (raw['layerCount'] as num? ?? 1).toInt();

  String get activeMenuId => raw['activeMenuId'] as String? ?? '';

  double get radius => (raw['radius'] as num? ?? 120).toDouble();

  double get innerRadius => (raw['innerRadius'] as num? ?? 40).toDouble();

  /// `slice`（扇区）/ `bubble`（气泡）—— 照 neoview 的 `variant`。
  String get variant => raw['variant'] as String? ?? 'slice';

  double get startAngle => (raw['startAngle'] as num? ?? -90).toDouble();

  double get sweepAngle => (raw['sweepAngle'] as num? ?? 360).toDouble();

  List<RadialMenuDoc> get menus => [
    for (final entry in raw['menus'] as List? ?? const [])
      if (entry is Map) RadialMenuDoc(Map<String, dynamic>.from(entry)),
  ];

  RadialMenuDoc? menu(String id) {
    for (final menu in menus) {
      if (menu.id == id) return menu;
    }
    return null;
  }

  /// 当前生效的轮盘：`activeMenuId` 优先，指不到时退回第一个。
  ///
  /// 与核心 `RadialConfig::active_menu` 同一口径 —— 「刚删了生效项」这种瞬间窗口
  /// 不该让轮盘整个打不开。
  RadialMenuDoc? get activeMenu {
    final listed = menu(activeMenuId);
    if (listed != null) return listed;
    final all = menus;
    return all.isEmpty ? null : all.first;
  }

  RadialDoc copyWith({
    bool? enabled,
    int? layerCount,
    String? activeMenuId,
    List<RadialMenuDoc>? menus,
    double? radius,
    double? innerRadius,
    String? variant,
    double? startAngle,
    double? sweepAngle,
  }) {
    final next = Map<String, dynamic>.from(raw);
    if (enabled != null) next['enabled'] = enabled;
    if (layerCount != null) next['layerCount'] = layerCount;
    if (activeMenuId != null) next['activeMenuId'] = activeMenuId;
    if (menus != null) next['menus'] = [for (final menu in menus) menu.raw];
    if (radius != null) next['radius'] = radius;
    if (innerRadius != null) next['innerRadius'] = innerRadius;
    if (variant != null) next['variant'] = variant;
    if (startAngle != null) next['startAngle'] = startAngle;
    if (sweepAngle != null) next['sweepAngle'] = sweepAngle;
    return RadialDoc(next);
  }

  String encode() => jsonEncode(raw);

  String prettyEncode() => const JsonEncoder.withIndent('  ').convert(raw);

  RadialDoc withMenu(RadialMenuDoc menu) => copyWith(
    menus: [...menus, menu],
    activeMenuId: activeMenuId.isEmpty ? menu.id : activeMenuId,
  );

  /// 删一个轮盘。列表空了就不删（「至少一个轮盘」是核心的校验，不是这里的）。
  RadialDoc withoutMenu(String id) {
    final kept = menus.where((menu) => menu.id != id).toList();
    if (kept.length == menus.length) return this;
    return copyWith(
      menus: kept,
      activeMenuId: activeMenuId == id
          ? (kept.isEmpty ? '' : kept.first.id)
          : activeMenuId,
    );
  }

  /// 替换/插入一个轮盘（改条目、改名都走这里）。
  RadialDoc withMenuReplaced(RadialMenuDoc menu) {
    final all = menus;
    final index = all.indexWhere((entry) => entry.id == menu.id);
    if (index < 0) return withMenu(menu);
    return copyWith(
      menus: [for (var i = 0; i < all.length; i++) i == index ? menu : all[i]],
    );
  }

  /// 文档里已有多少个条目（新条目 id 的计数基准）。
  int get itemCount => menus.fold(0, (sum, menu) => sum + menu.itemCount);
}

/// 一个轮盘：id、名字、以及「每层一组条目」（下标 0 = 最里面那一圈）。
class RadialMenuDoc {
  RadialMenuDoc(this.raw);

  final Map<String, dynamic> raw;

  String get id => raw['id'] as String? ?? '';
  String get name => raw['name'] as String? ?? '';

  /// 每层的条目。缺省补到三层，省得调用方到处判空。
  List<List<RadialItemDoc>> get layers {
    final stored = raw['layers'] as List? ?? const [];
    final out = <List<RadialItemDoc>>[
      for (final layer in stored)
        [
          for (final entry in layer as List? ?? const [])
            if (entry is Map) RadialItemDoc(Map<String, dynamic>.from(entry)),
        ],
    ];
    while (out.length < 3) {
      out.add(const []);
    }
    return out;
  }

  /// 第 `level` 层（1 起）的条目。
  List<RadialItemDoc> layer(int level) {
    final all = layers;
    final index = level - 1;
    return index < 0 || index >= all.length ? const [] : all[index];
  }

  RadialItemDoc? item(String itemId) {
    for (final entries in layers) {
      for (final entry in entries) {
        if (entry.id == itemId) return entry;
      }
    }
    return null;
  }

  /// 这个轮盘能不能容纳某个绑定行指向的条目（核心的剪枝同一条判据，Dart 侧用来过滤列表）。
  bool hasItem(String itemId) => item(itemId) != null;

  int get itemCount => layers.fold(0, (sum, entries) => sum + entries.length);

  RadialMenuDoc copyWith({String? name, List<List<RadialItemDoc>>? layers}) {
    final next = Map<String, dynamic>.from(raw);
    if (name != null) next['name'] = name;
    if (layers != null) {
      next['layers'] = [
        for (final layer in layers) [for (final entry in layer) entry.raw],
      ];
    }
    return RadialMenuDoc(next);
  }

  /// 往第 `level` 层（1 起）加一个条目。写回一律按槽位排序：
  /// 层的显示顺序就是槽位顺序，插一个不排序的条目会让「前移/后移」下一步找不到邻居。
  RadialMenuDoc withItem(RadialItemDoc item, {int? level}) {
    final all = [for (final layer in layers) List<RadialItemDoc>.from(layer)];
    final index = ((level ?? 1) - 1).clamp(0, all.length - 1);
    all[index] = [...all[index], item]
      ..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));
    return copyWith(layers: all);
  }

  RadialMenuDoc withItemReplaced(RadialItemDoc item) {
    final all = [for (final layer in layers) List<RadialItemDoc>.from(layer)];
    for (var level = 0; level < all.length; level++) {
      final index = all[level].indexWhere((entry) => entry.id == item.id);
      if (index < 0) continue;
      all[level] = [...all[level]..removeAt(index), item]
        ..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));
      return copyWith(layers: all);
    }
    return this;
  }

  RadialMenuDoc withoutItem(String itemId) {
    final all = [
      for (final layer in layers)
        layer.where((entry) => entry.id != itemId).toList(),
    ];
    return copyWith(layers: all);
  }
}

/// 轮盘里的一个条目（身份 + 外观；动作在绑定表里）。
class RadialItemDoc {
  RadialItemDoc(this.raw);

  final Map<String, dynamic> raw;

  /// = 绑定包里的 `itemId`。用户数据会引用它，**只能追加不能重排**。
  String get id => raw['id'] as String? ?? '';
  String get label => raw['label'] as String? ?? '';
  int get slotIndex => (raw['slotIndex'] as num? ?? 0).toInt();

  /// 遗留的直连动作：新条目一律走绑定，这里只为读得懂老包而保留。
  String? get legacyAction => raw['action'] as String?;

  /// 非空 = 这一格是「跳转轮盘」，松手换轮盘而不是执行动作。
  String? get moveToMenuId {
    final value = raw['moveToMenuId'] as String?;
    return value == null || value.isEmpty ? null : value;
  }

  bool get disabled => raw['disabled'] == true;

  bool get isMoveTo => moveToMenuId != null;

  RadialItemDoc copyWith({
    String? label,
    int? slotIndex,
    String? moveToMenuId,
    bool? disabled,
  }) {
    final next = Map<String, dynamic>.from(raw);
    if (label != null) next['label'] = label;
    if (slotIndex != null) next['slotIndex'] = slotIndex;
    if (moveToMenuId != null) next['moveToMenuId'] = moveToMenuId;
    if (disabled != null) {
      if (disabled) {
        next['disabled'] = true;
      } else {
        next.remove('disabled');
      }
    }
    return RadialItemDoc(next);
  }

  /// 造一个新条目。id 必须过 neoview 的形状校验，否则导入出去的老版本读不懂。
  static RadialItemDoc create({
    required String id,
    required String label,
    required int slotIndex,
    String? moveToMenuId,
  }) {
    assert(isRadialItemIdShape(id), '条目 id 形状不合法：$id');
    return RadialItemDoc({
      'id': id,
      'label': label,
      'slotIndex': slotIndex,
      'moveToMenuId': ?moveToMenuId,
    });
  }
}

/// 条目 id 的形状（neoview `^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$`）。
///
/// 为什么是个函数而不是一句 `assert`：`assert` 在 release 构建里会被整个剥掉，
/// 「非法 id 静默进用户绑定包」正是最难查的那类 bug（老版本读不懂、而且看不出来）。
/// 判定的权威在核心（`radial::validate`），这里给外壳一个**能测**的预检。
bool isRadialItemIdShape(String id) => _radialIdPattern.hasMatch(id);

/// 一条轮盘输入 → descriptor 的 JSON（与核心 `radial_input` 同一形状）。
String radialInputJson({required String menuId, required String itemId}) =>
    jsonEncode({
      'device': InputDevice.radial,
      'menuId': menuId,
      'itemId': itemId,
    });

/// 一条绑定是不是轮盘输入；是则报出它指向哪个条目。
RadialSlotRef? slotOfBinding(Map<String, dynamic> binding) {
  final input = binding['input'];
  if (input is! Map) return null;
  if (input['device'] != InputDevice.radial) return null;
  final menuId = input['menuId'];
  final itemId = input['itemId'];
  if (menuId is! String || itemId is! String) return null;
  return (menuId: menuId, itemId: itemId);
}

/// 某个轮盘的全部条目绑定（设置页的槽位列表靠它）。
List<Map<String, dynamic>> radialBindingsForMenu(
  List<Map<String, dynamic>> bindings,
  String menuId,
) => bindings
    .where((binding) => slotOfBinding(binding)?.menuId == menuId)
    .toList();

/// 一个条目当前绑到的动作 id；没绑返回 `null`。
String? actionForSlot(List<Map<String, dynamic>> bindings, RadialSlotRef slot) {
  for (final binding in bindings) {
    if (slotOfBinding(binding) == slot) return binding['action'] as String?;
  }
  return null;
}

/// 预设轮盘条目的 id 前缀（核心的 `RADIAL_PRESET_ID_PREFIX` + 轮盘 id）。
String radialPresetIdPrefix(String menuId) => 'preset-radial-$menuId-';

/// 把某个条目绑到 [actionId]（空串 = 解绑）。
///
/// 与 [bindArea] 同一条纪律：同一个输入只留一条绑定，原来就有就**改写**它 ——
/// 追加会立刻造出一个冲突，而用户的意图明明是「这一格改成干别的」。
/// 改写时保留原行的 id：预设那几条靠 `preset-radial-` 前缀被认出来。
List<Map<String, dynamic>> bindSlot(
  List<Map<String, dynamic>> bindings,
  RadialSlotRef slot,
  String actionId,
) {
  final index = bindings.indexWhere(
    (binding) => slotOfBinding(binding) == slot,
  );
  if (index < 0) {
    if (actionId.isEmpty) return bindings;
    return [
      ...bindings,
      buildBinding(
        id: newBindingId('radial-${slot.itemId}'),
        action: actionId,
        context: 'reader',
        inputJson: radialInputJson(menuId: slot.menuId, itemId: slot.itemId),
      ),
    ];
  }
  final row = bindings[index];
  if (actionId.isEmpty) return removeBindingById(bindings, row['id'] as String);
  if (row['action'] == actionId) return bindings;
  return [
    for (var i = 0; i < bindings.length; i++)
      i == index ? {...row, 'action': actionId} : bindings[i],
  ];
}

/// 解绑一个条目（等价于 `bindSlot(..., '')`，读起来直白）。
List<Map<String, dynamic>> unbindSlot(
  List<Map<String, dynamic>> bindings,
  RadialSlotRef slot,
) => bindings
    .where((binding) => slotOfBinding(binding) != slot)
    .toList(growable: false);

/// 用 [rows] 替换某个轮盘的预设条目绑定，其余（含用户自绑的）原样保留。
List<Map<String, dynamic>> resetRadialPresetSlots(
  List<Map<String, dynamic>> bindings,
  String menuId,
  List<Map<String, dynamic>> rows,
) => replacePresetRows(bindings, radialPresetIdPrefix(menuId), rows);

/// 描述一个槽位（冲突清单与设置页共用，口径要一致）。
String describeRadialSlot(RadialSlotRef slot) =>
    'radial:${slot.menuId}:${slot.itemId}';
