// 轮盘文档（`RadialConfig`）的 **JSON 工具** —— 全部纯函数，不碰 FRB。
//
// 与 `binding_doc.dart` 同一分工：这一层只管「文档长什么样、字段丢没丢」，
// 真正问引擎（形状是否合法、落点在哪一格、怎么画）的部分在
// `operation_binding_store.dart`。判据要能在**没有原生库**的宿主里跑，
// 而轮盘最容易出错的两处正是：① 改形状时把用户没碰过的字段洗掉；
// ② 槽位与绑定行对不上号。
//
// ## 为什么这里只当 Map 拿着
//
// 与绑定表同样的理由（ADR-0015）：schema 的唯一权威是 Rust。所以下面的 [RadialDoc]
// 是**视图**不是镜像 —— 它读写自己认识的字段，其余原样留在 [RadialDoc.raw] 里，
// `encode()` 时一起写回去。核心将来加字段（比如每层的起始角），这一层不改也不丢数据。
//
// ## 槽位的动作不在这里
//
// 轮盘文档只有**形状**。一个槽「干什么」是一条 `device: radial` 的绑定
// （`{menuId, itemId}` → 注册表里的动作 id），存在绑定表里。所以这里的
// [bindSlot] / [unbindSlot] 操作的都是绑定数组，而不是这份文档 ——
// 轮盘因此与键盘、点击同权：同一个解析器、同一套冲突判定。

import 'dart:convert';

import 'package:zephyr/service/operation_binding/binding_doc.dart';

/// 出厂轮盘的 id（核心 `DEFAULT_RADIAL_MENU_ID`）。
///
/// 只有这一个轮盘带出厂槽位；用户新建的轮盘是空的，不该被塞别人的默认值。
const String kRadialDefaultMenuId = 'default';

/// 槽位 `itemId` 的形状：`l{层}s{格}`（层 1 起、格 0 起且居中于正上方）。
///
/// 这个字符串**要落进用户绑定包**，所以只能追加不能重排（改了它，用户已有的
/// 轮盘绑定会指向不存在的槽）。真正的算术在 Rust `radial.rs`，这里只做形状检查。
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

  /// 原始映射：未知字段都活在这里。
  final Map<String, dynamic> raw;

  bool get enabled => raw['enabled'] != false;

  String get activeMenuId => raw['activeMenuId'] as String? ?? '';

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
    String? activeMenuId,
    List<RadialMenuDoc>? menus,
  }) {
    final next = Map<String, dynamic>.from(raw);
    if (enabled != null) next['enabled'] = enabled;
    if (activeMenuId != null) next['activeMenuId'] = activeMenuId;
    if (menus != null) {
      next['menus'] = [for (final menu in menus) menu.raw];
    }
    return RadialDoc(next);
  }

  String encode() => jsonEncode(raw);

  String prettyEncode() => const JsonEncoder.withIndent('  ').convert(raw);

  /// 加一个轮盘（名字与 id 由核心给，这里只负责放进列表）。
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
      activeMenuId: activeMenuId == id ? (kept.isEmpty ? '' : kept.first.id) : activeMenuId,
    );
  }

  /// 替换/插入一个轮盘（改层数、改名、改几何都走这里）。
  RadialDoc withMenuReplaced(RadialMenuDoc menu) {
    final all = menus;
    final index = all.indexWhere((entry) => entry.id == menu.id);
    if (index < 0) return withMenu(menu);
    return copyWith(menus: [
      for (var i = 0; i < all.length; i++) i == index ? menu : all[i],
    ]);
  }
}

/// 一个轮盘的形状视图（id / 名字 / 层数 / 半径 / 空洞 / 每层格数）。
class RadialMenuDoc {
  RadialMenuDoc(this.raw);

  final Map<String, dynamic> raw;

  String get id => raw['id'] as String? ?? '';
  String get name => raw['name'] as String? ?? '';

  /// 层数（1..3）。缺省按 1 层读，越界由核心校验报出来，这里不夹。
  int get layers => (raw['layers'] as num? ?? 1).toInt();

  Map<String, dynamic> get _geometry {
    final geometry = raw['geometry'];
    return geometry is Map
        ? Map<String, dynamic>.from(geometry)
        : <String, dynamic>{};
  }

  double get radius => (_geometry['radius'] as num? ?? 120).toDouble();
  double get innerRadius => (_geometry['innerRadius'] as num? ?? 40).toDouble();
  int get sectors => (_geometry['sectors'] as num? ?? 8).toInt();

  /// 这个轮盘上有多少个槽（层 × 格）。
  int get slotCount => layers * sectors;

  /// 某一格是否画得出来（层 1 起、格 0 起）。
  bool hasSlot(RadialSlotRef slot) {
    final parsed = parseSlotItemId(slot.itemId);
    if (parsed == null) return false;
    return parsed.$1 >= 1 && parsed.$1 <= layers && parsed.$2 < sectors;
  }

  RadialMenuDoc copyWith({
    String? name,
    int? layers,
    double? radius,
    double? innerRadius,
    int? sectors,
  }) {
    final next = Map<String, dynamic>.from(raw);
    if (name != null) next['name'] = name;
    if (layers != null) next['layers'] = layers;
    if (radius != null || innerRadius != null || sectors != null) {
      final geometry = Map<String, dynamic>.from(_geometry);
      if (radius != null) geometry['radius'] = radius;
      if (innerRadius != null) geometry['innerRadius'] = innerRadius;
      if (sectors != null) geometry['sectors'] = sectors;
      next['geometry'] = geometry;
    }
    return RadialMenuDoc(next);
  }
}

/// `l2s5` → `(2, 5)`；形状不对返回 `null`。
(int, int)? parseSlotItemId(String itemId) {
  final matched = RegExp(r'^l(\d+)s(\d+)$').firstMatch(itemId);
  if (matched == null) return null;
  return (
    int.parse(matched.group(1)!),
    int.parse(matched.group(2)!),
  );
}

/// 一条轮盘输入 → descriptor 的 JSON（与核心 `radial_input` 同一形状）。
String radialInputJson({required String menuId, required String itemId}) => jsonEncode({
  'device': InputDevice.radial,
  'menuId': menuId,
  'itemId': itemId,
});

/// 一条绑定是不是轮盘输入；是则报出它指向哪个槽。
RadialSlotRef? slotOfBinding(Map<String, dynamic> binding) {
  final input = binding['input'];
  if (input is! Map) return null;
  if (input['device'] != InputDevice.radial) return null;
  final menuId = input['menuId'];
  final itemId = input['itemId'];
  if (menuId is! String || itemId is! String) return null;
  return (menuId: menuId, itemId: itemId);
}

/// 某个轮盘的全部槽位绑定（设置页的槽位列表靠它）。
List<Map<String, dynamic>> radialBindingsForMenu(
  List<Map<String, dynamic>> bindings,
  String menuId,
) => bindings.where((binding) => slotOfBinding(binding)?.menuId == menuId).toList();

/// 一个槽当前绑到的动作 id；没绑返回 `null`。
String? actionForSlot(
  List<Map<String, dynamic>> bindings,
  RadialSlotRef slot,
) {
  for (final binding in bindings) {
    if (slotOfBinding(binding) == slot) return binding['action'] as String?;
  }
  return null;
}

/// 预设轮盘绑定的 id 前缀（核心的 `RADIAL_PRESET_ID_PREFIX` + 轮盘 id）。
String radialPresetIdPrefix(String menuId) => 'preset-radial-$menuId-';

/// 把某个槽绑到 [actionId]（空串 = 解绑）。
///
/// 与 [bindArea] 同一条纪律：同一个输入只留一条绑定，原来就有就**改写**它 ——
/// 追加会立刻造出一个冲突，而用户的意图明明是「这一格改成干别的」。
/// 改写时保留原行的 id：预设那几条的 id 带着 `preset-radial-` 前缀，
/// 「重置轮盘」正是按前缀认出它们的。
List<Map<String, dynamic>> bindSlot(
  List<Map<String, dynamic>> bindings,
  RadialSlotRef slot,
  String actionId,
) {
  final index = bindings.indexWhere((binding) => slotOfBinding(binding) == slot);
  if (index < 0) {
    if (actionId.isEmpty) return bindings;
    return [
      ...bindings,
      buildBinding(
        id: newBindingId('radial-${slot.menuId}-${slot.itemId}'),
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

/// 解绑一个槽（等价于 `bindSlot(..., '')`，但读起来直白）。
List<Map<String, dynamic>> unbindSlot(
  List<Map<String, dynamic>> bindings,
  RadialSlotRef slot,
) => removeBindingById(bindings, _slotBindingId(bindings, slot) ?? '');

String? _slotBindingId(List<Map<String, dynamic>> bindings, RadialSlotRef slot) {
  for (final binding in bindings) {
    if (slotOfBinding(binding) == slot) return binding['id'] as String?;
  }
  return null;
}

/// 用 [rows] 替换某个轮盘的预设槽位，其余（含用户自绑的其它轮盘）原样保留。
List<Map<String, dynamic>> resetRadialPresetSlots(
  List<Map<String, dynamic>> bindings,
  String menuId,
  List<Map<String, dynamic>> rows,
) => replacePresetRows(bindings, radialPresetIdPrefix(menuId), rows);

/// 一个轮盘的槽位清单（**含空槽**）：设置页要点着空槽添加，运行时要高亮空格。
///
/// 空槽的动作是 `null`。顺序 = 层由内向外、每层由 12 点顺时针，与核心的布局同序。
List<({RadialSlotRef slot, String? actionId})> radialSlots(
  RadialMenuDoc menu,
  List<Map<String, dynamic>> bindings,
) {
  final out = <({RadialSlotRef slot, String? actionId})>[];
  for (var layer = 1; layer <= menu.layers; layer++) {
    for (var sector = 0; sector < menu.sectors; sector++) {
      final slot = (
        menuId: menu.id,
        itemId: 'l${layer}s$sector',
      );
      out.add((slot: slot, actionId: actionForSlot(bindings, slot)));
    }
  }
  return out;
}

/// 描述一个槽的输入（冲突清单与设置页都用它，口径要一致）。
String describeRadialSlot(RadialSlotRef slot) {
  final parsed = parseSlotItemId(slot.itemId);
  if (parsed == null) return 'radial:${slot.menuId}:${slot.itemId}';
  return 'radial:${slot.menuId}:第${parsed.$1}层第${parsed.$2 + 1}格';
}
