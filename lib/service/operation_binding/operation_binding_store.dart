import 'dart:convert';

import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/service/operation_binding/radial_doc.dart';
import 'package:zephyr/src/rust/api/operation_binding.dart';

/// 操作绑定引擎（Rust / ADR-0015）在 Dart 侧的**唯一出入口**。
///
/// 这里只做三类事：播种出厂表、把绑定表喂给引擎问一句（解析 / 冲突 / 预设）、
/// 把注册表取回来给设置页渲染。**判定一律在 Rust** —— Dart 里不该出现
/// 「这条输入对应什么动作」的第二份实现。
///
/// 与 [binding_doc.dart] 的分工：那个文件是纯 JSON 文档操作（`flutter test` 直接跑），
/// 这一层要跨 FRB，所以判据只能靠真机 —— 也因此这层刻意薄到「只是转发」。
abstract final class OperationBindingStore {
  /// 引擎对外的 context 名：阅读页在场时活跃的是 `reader`。
  ///
  /// v0.1 只有阅读器接线（工作台/设置面板的输入仍走各自的路），所以活跃集合就一个。
  static const List<String> readerContexts = ['reader'];

  static String? areaAtPoint({
    required double x,
    required double y,
    required double width,
    required double height,
  }) => operationBindingAreaAtPoint(x: x, y: y, width: width, height: height);

  /// Neo 默认九宫格、滚轮、键盘、鼠标及默认轮盘槽位。
  /// 默认值由核心统一提供，与旧版左右手点击模式独立。
  static String factoryBindingsJson() =>
      encodeBindingsDoc(_decodeArray(operationBindingFactoryPreset()));

  /// 旧版左右手 / 全屏档对应的兼容预设名；Neo 默认表不按此设置改写。
  static String tapPresetOf(ReaderTapPageTurnMode mode) => switch (mode) {
    ReaderTapPageTurnMode.leftHand => 'left-hand',
    ReaderTapPageTurnMode.rightHand ||
    ReaderTapPageTurnMode.fullScreen => 'right-hand',
  };

  /// 首次启动播种；完整未修改的旧出厂输入表自动升级，自定义输入表保留。
  ///
  /// 在 `RustLib.init()` 之后调用（`GlobalSettingCubit.initBox`），因为出厂预设由
  /// Rust 侧生成 —— 「默认值是数据，不是 Dart 里的 if」（ADR-0015）。
  ///
  /// 轮盘文档单独判空：它和绑定表是两份东西，用户可能只有一份是坏的（比如手改了
  /// 绑定 JSON 把轮盘文档留了下来），一起重置等于顺手清掉另一份的用户数据。
  static void seedIfNeeded(GlobalSettingCubit cubit) {
    final setting = cubit.state.operationBindingSetting;
    final existing = parseBindings(setting.bindingsJson);
    final upgraded = existing == null
        ? null
        : operationBindingUpgradeDefaults(
            bindingsJson: encodeBindingsArray(existing),
          );
    final needsRadial = parseRadialDoc(setting.radialJson) == null;
    String? nextBindings;
    if (existing == null) {
      nextBindings = factoryBindingsJson();
    } else if (upgraded != null) {
      final rows = _decodeArray(upgraded);
      // 轮盘加入之前的旧默认表没有槽位；首次创建轮盘文档时补齐槽位绑定。
      // 已有合法轮盘文档时，即便用户删光了槽位绑定也保持原状。
      if (needsRadial &&
          !rows.any(
            (row) => (row['input'] as Map)['device'] == InputDevice.radial,
          )) {
        rows.addAll(radialPresetBindings(kRadialDefaultMenuId));
      }
      nextBindings = encodeBindingsDoc(rows);
    } else {
      // 用户已有自定义配置但历史表完全缺少滚轮绑定时，自动补全出厂滚轮行，
      // 避免老用户在滚轮引入后因未重置出厂而完全无法使用滚轮。
      final rows = List<Map<String, dynamic>>.from(existing);
      if (!rows.any(
        (row) => (row['input'] as Map)['device'] == InputDevice.wheel,
      )) {
        final factoryRows = _decodeArray(operationBindingFactoryPreset());
        final wheelRows = factoryRows.where(
          (row) => (row['input'] as Map)['device'] == InputDevice.wheel,
        );
        rows.addAll(wheelRows);
        nextBindings = encodeBindingsDoc(rows);
      }
    }
    if (nextBindings == null && !needsRadial) return;
    cubit.updateOperationBindingSetting(
      (current) => current.copyWith(
        bindingsJson: nextBindings ?? current.bindingsJson,
        radialJson: needsRadial ? radialFactoryJson() : current.radialJson,
      ),
    );
  }

  /// 按当前左右手预设重置点击那几条，键盘与用户自加的绑定原样保留。
  static List<Map<String, dynamic>> resetTapRows(
    List<Map<String, dynamic>> bindings,
    ReaderTapPageTurnMode tapMode,
  ) => replacePresetRows(
    bindings,
    kTapPresetIdPrefix,
    _decodeArray(operationBindingTapPreset(preset: tapPresetOf(tapMode))),
  );

  /// 运行时可用的绑定表（引擎要的裸数组 JSON）。
  ///
  /// 返回 `null` = 这份表**不能用**（没播种、被用户导坏了）。调用方（按键/点击路径）
  /// 拿 null 时回退到改造前的硬编码分区，而不是「什么都不做」—— 后者等于阅读器打不开。
  static String? runtimeBindingsJson(OperationBindingSettingState setting) {
    if (!setting.bindingsRuntime) return null;
    final bindings = parseBindings(setting.bindingsJson);
    if (bindings == null) return null;
    return encodeBindingsArray(bindings);
  }

  /// 一次输入命中了哪个动作（没人认领返回 `null`，事件照常往下冒泡）。
  static String? resolveAction({
    required String bindingsArrayJson,
    required String inputJson,
    List<String> contexts = readerContexts,
  }) => operationBindingResolve(
    bindingsJson: bindingsArrayJson,
    inputJson: inputJson,
    contexts: contexts,
  );

  /// 仍由核心决定命中哪一行，外壳只读取执行与采集所需的字段。
  static Map<String, dynamic>? resolveBinding({
    required String bindingsArrayJson,
    required String inputJson,
    List<String> contexts = readerContexts,
  }) {
    final json = operationBindingResolveBinding(
      bindingsJson: bindingsArrayJson,
      inputJson: inputJson,
      contexts: contexts,
    );
    if (json == null) return null;
    return Map<String, dynamic>.from(jsonDecode(json) as Map);
  }

  /// 把一条翻页动作按阅读方向解释成 `"next"` / `"previous"`（不是翻页动作返回 null）。
  ///
  /// **阅读方向只有这一个生效处**：UI 层任何地方都不许出现「左开时向右是上一页」这种判断。
  static String? resolvePageTurn({
    required String actionId,
    required int readMode,
  }) => operationBindingResolvePageTurn(actionId: actionId, readMode: readMode);

  /// 冲突清单（保存前必须问一次；非空即拒绝保存）。返回 `null` = 这份表引擎读不懂，
  /// 同样要拒绝保存 —— 「校验没过」和「没有冲突」是两件事，混成后者会让坏表静默通过。
  ///
  /// 为什么要先 validate 再问：`operationBindingConflicts` 对不合法的输入直接 panic
  /// （那是「调用方已校验过」的前提）。panic 跨桥会变成 Dart 侧异常，用户在设置页点了
  /// 「保存」看到红屏，比一句「这份表读不懂」差得远。
  static List<BindingConflict>? conflictsOf(
    List<Map<String, dynamic>> bindings,
  ) {
    final json = encodeBindingsArray(bindings);
    if (!operationBindingValidate(bindingsJson: json)) return null;
    return parseConflicts(operationBindingConflicts(bindingsJson: json));
  }

  /// 这份表能不能用（导入的第一道关）。
  static bool isValid(List<Map<String, dynamic>> bindings) =>
      operationBindingValidate(bindingsJson: encodeBindingsArray(bindings));

  /// 动作注册表（设置页的选项清单，schema 与显示名都取自 Rust）。
  ///
  /// 走 [_decodeList] 而不是 [_decodeArray]：注册表的行是 `{id,label,category,…}`，
  /// **没有** `input` 字段，而绑定表那条校验恰恰要求每条都有 `input.device`。
  /// 用错那个函数等于「清单永远读不出来」，而且抛的是 Bad state —— 设置页一进来就红屏。
  static List<BindingActionInfo> actionCatalog() => [
    for (final entry in _decodeList(operationBindingActionCatalog()))
      BindingActionInfo(
        id: entry['id'] as String? ?? '',
        label: entry['label'] as String? ?? '',
        category: entry['category'] as String? ?? '',
        categoryLabel: entry['categoryLabel'] as String? ?? '',
        implemented: entry['implemented'] == true,
      ),
  ];

  // ── 轮盘（radial）──────────────────────────────────────────────────────────
  //
  // 这里**没有**「这个槽是什么动作」的那一问：槽位就是一条 `device: radial` 的绑定，
  // 由 [resolveAction] 与键盘、点击同一个解析器回答。这一层只转发形状相关的三件事：
  // 出厂文档、合法性、画法与命中。

  /// 轮盘的出厂文档（默认轮盘：3 层 · r120 · 内 40 · 每层 8 格）。
  static String radialFactoryJson() => operationBindingRadialDefaultConfig();

  /// 这份轮盘文档合不合法（保存前的闸门；读不出也算不合法）。
  static bool radialIsValid(String configJson) =>
      operationBindingRadialValidate(configJson: configJson);

  /// 不合法的具体原因（人话清单）。
  ///
  /// 与 [radialIsValid] 分开是「不许保存」和「为什么不许」两件事，设置页两件都要说。
  static List<String> radialProblems(String configJson) {
    final Object? decoded;
    try {
      decoded = jsonDecode(
        operationBindingRadialProblems(configJson: configJson),
      );
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    return [for (final item in decoded) item.toString()];
  }

  /// 运行时可用的轮盘文档 JSON；`null` = 轮盘这条通道不走绑定表（总开关关着、
  /// 轮盘自己被关掉、或者文档读不出）。
  static String? runtimeRadialJson(OperationBindingSettingState setting) {
    if (!setting.bindingsRuntime) return null;
    final doc = parseRadialDoc(setting.radialJson);
    if (doc == null || !doc.enabled) return null;
    return setting.radialJson;
  }

  /// 一个轮盘显示出来的全部槽位（**含空格**）。外壳照着这份数字画，
  /// 命中判定也读同一份数字（[radialSlotHit]）。
  static List<RadialSlotPaint> radialLayout({
    required String configJson,
    required String menuId,
  }) => [
    for (final entry in _decodeList(
      operationBindingRadialLayout(configJson: configJson, menuId: menuId),
    ))
      RadialSlotPaint.fromMap(map: entry),
  ];

  /// 落点（相对圆心的偏移）→ 选中的槽；落在空洞、空格、被禁用的条目或扫过角之外
  /// 都返回 `null`。
  ///
  /// 返回里带着 `itemId`，外壳拼出那条 `radial` 输入喂给 [resolveAction] ——
  /// 轮盘不经过任何专用的动作判断。
  static RadialSlotHit? radialSlotHit({
    required String configJson,
    required String menuId,
    required double dx,
    required double dy,
  }) {
    final raw = operationBindingRadialSlot(
      configJson: configJson,
      menuId: menuId,
      dx: dx,
      dy: dy,
    );
    if (raw == null) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    return RadialSlotHit.fromMap(Map<String, dynamic>.from(decoded));
  }

  /// 新建一个轮盘（只有默认轮盘有出厂槽位；新轮盘是空的）。
  static List<Map<String, dynamic>> radialPresetBindings(String menuId) =>
      _decodeList(operationBindingRadialPreset(menuId: menuId));

  /// 新建一个轮盘：id 与名字的**生成规则**归核心（与 `default_config` 同一处），
  /// 外壳自己拼一套 `menu-7` 迟早和核心认的 id 分叉。
  static RadialMenuDoc? radialNewMenu(int count) {
    final Object? decoded;
    try {
      decoded = jsonDecode(operationBindingRadialNewMenu(count: count));
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    return RadialMenuDoc(Map<String, dynamic>.from(decoded));
  }

  /// 新建一个条目的 id（`item-N`）。同上一条理由：id 的生成规则只有一处。
  static String radialNewItemId(int count) =>
      operationBindingRadialNewItemId(count: count);

  /// 形状变了（减层、改格数、删轮盘）之后，剪掉指向已不存在的槽的绑定。
  static List<Map<String, dynamic>> radialPrune({
    required String configJson,
    required List<Map<String, dynamic>> bindings,
  }) => _decodeList(
    operationBindingRadialPrune(
      configJson: configJson,
      bindingsJson: encodeBindingsArray(bindings),
    ),
  );

  static List<Map<String, dynamic>> _decodeList(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    return [
      for (final entry in decoded)
        if (entry is Map) Map<String, dynamic>.from(entry),
    ];
  }

  static List<Map<String, dynamic>> _decodeArray(String json) {
    final bindings = parseBindings(json);
    if (bindings == null) {
      throw StateError('引擎返回的绑定表读不出来：$json');
    }
    return bindings;
  }
}

/// 注册表的一条动作（[OperationBindingStore.actionCatalog] 的元素）。
class BindingActionInfo {
  const BindingActionInfo({
    required this.id,
    required this.label,
    required this.category,
    required this.categoryLabel,
    required this.implemented,
  });

  final String id;
  final String label;
  final String category;
  final String categoryLabel;

  /// 本仓运行时**是否已能执行**。`false` 的在设置页置灰：能不能用写在数据里，
  /// 而不是在 UI 里维护第二份「哪些动作能用」的名单。
  final bool implemented;
}

/// 一个槽的**画法与命中区**（核心算出来的那一份数字，含条目的显示文字）。
///
/// 外壳不许自己再算一遍角度与环带：两处各算一次迟早差半个扇区，而屏幕上看着没错 ——
/// 表现就是「高亮的格子与松手执行的格子不是同一个」。
class RadialSlotPaint {
  const RadialSlotPaint({
    required this.menuId,
    required this.level,
    required this.index,
    required this.innerRadius,
    required this.outerRadius,
    required this.startDeg,
    required this.endDeg,
    required this.midDeg,
    this.itemId,
    this.label,
    this.legacyAction,
    this.moveToMenuId,
    this.disabled = false,
    this.selectable = false,
  });

  factory RadialSlotPaint.fromMap({required Map<String, dynamic> map}) =>
      RadialSlotPaint(
        menuId: map['menuId'] as String? ?? '',
        level: (map['level'] as num? ?? 0).toInt(),
        index: (map['index'] as num? ?? 0).toInt(),
        innerRadius: (map['innerRadius'] as num? ?? 0).toDouble(),
        outerRadius: (map['outerRadius'] as num? ?? 0).toDouble(),
        startDeg: (map['startDeg'] as num? ?? 0).toDouble(),
        endDeg: (map['endDeg'] as num? ?? 0).toDouble(),
        midDeg: (map['midDeg'] as num? ?? 0).toDouble(),
        itemId: map['itemId'] as String?,
        label: map['label'] as String?,
        legacyAction: map['legacyAction'] as String?,
        moveToMenuId: map['moveToMenuId'] as String?,
        disabled: map['disabled'] == true,
        selectable: map['selectable'] == true,
      );

  final String menuId;

  /// 第几环（1 起）与这一环里的第几格（0 起）。
  final int level;
  final int index;

  /// 这一格上的条目；`null` = 空格（画成 `+`）。
  final String? itemId;

  /// 条目的显示文字（住在文档里，绑动作时由编辑器自动跟随动作名）。
  final String? label;
  final String? legacyAction;
  final String? moveToMenuId;
  final bool disabled;
  final bool selectable;

  final double innerRadius;
  final double outerRadius;
  final double startDeg;
  final double endDeg;
  final double midDeg;

  bool get isEmpty => itemId == null;

  /// 这一格的身份 —— 拿去拼那条 `radial` 输入。
  RadialSlotRef? get slot {
    final id = itemId;
    return id == null ? null : (menuId: menuId, itemId: id);
  }
}

/// 一次落点的命中结果（核心算的）。
class RadialSlotHit {
  const RadialSlotHit({
    required this.menuId,
    required this.level,
    required this.index,
    required this.itemId,
    this.legacyAction,
    this.moveToMenuId,
  });

  factory RadialSlotHit.fromMap(Map<String, dynamic> map) => RadialSlotHit(
    menuId: map['menuId'] as String? ?? '',
    level: (map['level'] as num? ?? 0).toInt(),
    index: (map['index'] as num? ?? 0).toInt(),
    itemId: map['itemId'] as String? ?? '',
    legacyAction: map['legacyAction'] as String?,
    moveToMenuId: map['moveToMenuId'] as String?,
  );

  final String menuId;
  final int level;
  final int index;
  final String itemId;

  /// 老包里的直连动作：绑定派发不到时回落（neoview 同一顺序）。
  final String? legacyAction;

  /// 非空 = 这一格是「跳转轮盘」，松手换轮盘而不是执行动作。
  final String? moveToMenuId;

  RadialSlotRef get slot => (menuId: menuId, itemId: itemId);
}
