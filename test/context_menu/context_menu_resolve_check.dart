// 上下文菜单解析器的**纯 Dart** 判据。
//
//   dart run test/context_menu/context_menu_resolve_check.dart
//
// 这些断言守的是「用户改过偏好之后菜单长什么样」：次序、折叠、隐藏、pin、
// 顶部图标条上限，以及坏数据 / 新增项 / 已删除项这几种静默出错的方式。
// 它们错了界面上都不报错，只是菜单少了项、顺序乱了、或者怎么点都不出来。
//
// ignore_for_file: avoid_print

import 'package:zephyr/model/context_menu/context_menu.dart';

int _passed = 0;

void check(String label, bool condition, [String? detail]) {
  if (!condition) {
    throw StateError('FAIL: $label${detail == null ? '' : ' — $detail'}');
  }
  _passed++;
}

void checkEq(String label, List<String> actual, List<String> expected) {
  final ok =
      actual.length == expected.length &&
      <int>[
        for (var i = 0; i < actual.length; i++) i,
      ].every((i) => actual[i] == expected[i]);
  check(label, ok, '实际 $actual，期望 $expected');
}

ContextMenuEntryDefinition _entry(
  String id, {
  int group = 0,
  bool persistent = true,
  bool available = true,
  bool dangerous = false,
  bool destructive = false,
  ContextMenuEntryCapabilities capabilities =
      const ContextMenuEntryCapabilities(),
}) => ContextMenuEntryDefinition(
  id: id,
  group: group,
  persistent: persistent,
  available: available,
  dangerous: dangerous,
  destructive: destructive,
  capabilities: capabilities,
);

ContextMenuDefinition _definition({
  List<ContextMenuEntryDefinition>? entries,
  bool supportsTopStrip = true,
}) => ContextMenuDefinition(
  scope: 'demo',
  supportsTopStrip: supportsTopStrip,
  entries:
      entries ??
      <ContextMenuEntryDefinition>[
        _entry('demo.a'),
        _entry('demo.b'),
        _entry('demo.c'),
        _entry('demo.d'),
      ],
);

List<String> _ids(List<ContextMenuPlannedEntry> entries) => <String>[
  for (final entry in entries) entry.entry.id,
];

List<String> _topIds(ContextMenuPlan plan) => <String>[
  ..._ids(plan.topStrip),
  ..._ids(plan.topRows),
];

void main() {
  _factoryOrder();
  _pinTop();
  _iconStrip();
  _hidden();
  _collapsed();
  _badOrder();
  _newAndDeletedEntries();
  _unavailable();
  _ephemeral();
  _reorder();
  _json();
  print('✅ context_menu_resolve_check: $_passed 条断言通过');
}

void _factoryOrder() {
  final plan = resolveContextMenu(definition: _definition(), layout: null);
  checkEq('没设置过时按出厂次序', _ids(plan.list), [
    'demo.a',
    'demo.b',
    'demo.c',
    'demo.d',
  ]);
  check('没设置过时没有顶部图标', plan.topStrip.isEmpty && plan.topRows.isEmpty);
  check('没设置过时没有底部固定', plan.bottomRows.isEmpty);
}

void _pinTop() {
  final definition = _definition();
  final layout = setContextMenuPin(
    definition,
    null,
    'demo.c',
    ContextMenuPin.top,
  );
  final plan = resolveContextMenu(definition: definition, layout: layout);
  checkEq('pin 顶部后顶部区段只有它', _topIds(plan), ['demo.c']);
  checkEq('pin 顶部后列表里不再有它', _ids(plan.list), ['demo.a', 'demo.b', 'demo.d']);

  final bottom = setContextMenuPin(
    definition,
    null,
    'demo.a',
    ContextMenuPin.bottom,
  );
  final bottomPlan = resolveContextMenu(definition: definition, layout: bottom);
  checkEq('pin 底部后在底部区段', _ids(bottomPlan.bottomRows), ['demo.a']);
  checkEq('pin 底部后列表里不再有它', _ids(bottomPlan.list), [
    'demo.b',
    'demo.c',
    'demo.d',
  ]);
}

void _iconStrip() {
  final definition = _definition();
  var layout = setContextMenuPin(
    definition,
    null,
    'demo.a',
    ContextMenuPin.top,
  );
  layout = setContextMenuIconOnly(definition, layout, 'demo.a', true);
  final plan = resolveContextMenu(definition: definition, layout: layout);
  checkEq('pin 顶部 + 只显示图标进图标条', _ids(plan.topStrip), ['demo.a']);
  check('图标条里的项不再出现在普通顶部行', plan.topRows.isEmpty);

  // 上限：6 格之后降级成普通行。
  final many = _definition(
    entries: <ContextMenuEntryDefinition>[
      for (var i = 0; i < 8; i++) _entry('demo.e$i'),
    ],
  );
  var wide = const ContextMenuScopeLayout();
  for (var i = 0; i < 8; i++) {
    final id = 'demo.e$i';
    wide = setContextMenuPin(many, wide, id, ContextMenuPin.top);
    wide = setContextMenuIconOnly(many, wide, id, true);
  }
  final widePlan = resolveContextMenu(
    definition: many,
    layout: wide,
    maxStripItems: kMaxContextMenuStripItems,
  );
  checkEq('图标条最多 6 格', _ids(widePlan.topStrip), [
    'demo.e0',
    'demo.e1',
    'demo.e2',
    'demo.e3',
    'demo.e4',
    'demo.e5',
  ]);
  checkEq('第 7、8 个降级为普通顶部行', _ids(widePlan.topRows), ['demo.e6', 'demo.e7']);

  final noStrip = _definition(supportsTopStrip: false);
  var disabled = setContextMenuPin(noStrip, null, 'demo.a', ContextMenuPin.top);
  disabled = setContextMenuIconOnly(noStrip, disabled, 'demo.a', true);
  final disabledPlan = resolveContextMenu(
    definition: noStrip,
    layout: disabled,
  );
  check('菜单不支持图标条时降级为普通行', disabledPlan.topStrip.isEmpty);
  checkEq('降级后仍在顶部区段', _topIds(disabledPlan), ['demo.a']);
}

void _hidden() {
  final definition = _definition();
  final layout = setContextMenuVisibility(
    definition,
    null,
    'demo.b',
    ContextMenuVisibility.hidden,
  );
  final plan = resolveContextMenu(definition: definition, layout: layout);
  checkEq('隐藏的项从列表消失', _ids(plan.list), ['demo.a', 'demo.c', 'demo.d']);
  check(
    '隐藏时 pin 值仍保留（取消隐藏后位置恢复）',
    layout.overrides['demo.b']?.visibility == ContextMenuVisibility.hidden,
  );

  final pinned = setContextMenuPin(
    definition,
    layout,
    'demo.b',
    ContextMenuPin.top,
  );
  final pinnedPlan = resolveContextMenu(definition: definition, layout: pinned);
  check(
    '隐藏优先于 pin：pin 了也不出现',
    !_topIds(pinnedPlan).contains('demo.b') &&
        !_ids(pinnedPlan.list).contains('demo.b'),
  );
}

void _collapsed() {
  final definition = _definition();
  final layout = setContextMenuVisibility(
    definition,
    null,
    'demo.c',
    ContextMenuVisibility.collapsed,
  );
  final plan = resolveContextMenu(definition: definition, layout: layout);
  checkEq('折叠的项进「更多」', _ids(plan.collapsed), ['demo.c']);
  checkEq('折叠的项不在主列表', _ids(plan.list), ['demo.a', 'demo.b', 'demo.d']);

  final pinned = setContextMenuPin(
    definition,
    layout,
    'demo.c',
    ContextMenuPin.top,
  );
  final pinnedPlan = resolveContextMenu(definition: definition, layout: pinned);
  check('折叠 + pin 顶部：pin 胜', _topIds(pinnedPlan).contains('demo.c'));
  check('折叠 + pin 顶部：不在「更多」', pinnedPlan.collapsed.isEmpty);
}

void _badOrder() {
  final definition = _definition();
  final plan = resolveContextMenu(
    definition: definition,
    layout: const ContextMenuScopeLayout(
      order: <String>['demo.zzz', 'demo.b', 'demo.b', '', 'demo.a'],
    ),
  );
  checkEq('认不出的 id 丢掉、重复的保留第一次、缺失的补到末尾', _ids(plan.list), [
    'demo.b',
    'demo.a',
    'demo.c',
    'demo.d',
  ]);

  final allGarbage = resolveContextMenu(
    definition: definition,
    layout: const ContextMenuScopeLayout(order: <String>['x', 'y']),
  );
  checkEq('order 全是垃圾时回出厂', _ids(allGarbage.list), [
    'demo.a',
    'demo.b',
    'demo.c',
    'demo.d',
  ]);

  final overrideOnly = resolveContextMenu(
    definition: definition,
    layout: const ContextMenuScopeLayout(
      overrides: <String, ContextMenuItemOverride>{
        'demo.d': ContextMenuItemOverride(pin: ContextMenuPin.top),
      },
    ),
  );
  checkEq('只有 override 时次序仍是出厂', _ids(overrideOnly.list), [
    'demo.a',
    'demo.b',
    'demo.c',
  ]);
  checkEq('只有 override 时 pin 生效', _topIds(overrideOnly), ['demo.d']);
}

void _newAndDeletedEntries() {
  final definition = _definition();
  final stored = ContextMenuScopeLayout(
    order: const <String>['demo.c', 'demo.a'],
    overrides: <String, ContextMenuItemOverride>{
      'demo.removed': const ContextMenuItemOverride(pin: ContextMenuPin.top),
    },
  );
  final materialized = materializeContextMenuLayout(definition, stored);
  checkEq('已删除项的 order 丢弃', materialized.order, [
    'demo.c',
    'demo.a',
    'demo.b',
    'demo.d',
  ]);
  check(
    '已删除项的 override 丢弃',
    !materialized.overrides.containsKey('demo.removed'),
  );

  final plan = resolveContextMenu(definition: definition, layout: stored);
  checkEq('未知 override 不影响渲染', _ids(plan.list), [
    'demo.c',
    'demo.a',
    'demo.b',
    'demo.d',
  ]);
}

void _unavailable() {
  final definition = _definition(
    entries: <ContextMenuEntryDefinition>[
      _entry('demo.a'),
      _entry('demo.railOnly', available: false),
      _entry('demo.b'),
    ],
  );
  final plan = resolveContextMenu(definition: definition, layout: null);
  checkEq('available=false 的项不渲染', _ids(plan.list), ['demo.a', 'demo.b']);

  final layout = setContextMenuPin(
    definition,
    null,
    'demo.railOnly',
    ContextMenuPin.top,
  );
  final pinned = resolveContextMenu(definition: definition, layout: layout);
  check('不可用项即使 pin 了也不渲染', pinned.topRows.isEmpty);
  check(
    '不可用项的偏好仍保留在 order/override 里',
    layout.overrides.containsKey('demo.railOnly'),
  );
}

void _ephemeral() {
  final definition = _definition(
    entries: <ContextMenuEntryDefinition>[
      _entry('demo.a'),
      _entry('demo.dynamic', persistent: false),
      _entry('demo.b'),
    ],
  );
  final layout = setContextMenuPin(
    definition,
    null,
    'demo.dynamic',
    ContextMenuPin.top,
  );
  final plan = resolveContextMenu(
    definition: definition,
    layout: layout,
    maxStripItems: 6,
  );
  checkEq('动态项不接受 pin/隐藏，永远在主列表末尾', _ids(plan.list), ['demo.a', 'demo.b']);
  checkEq('动态项单独一串，渲染时接在主列表后', _ids(plan.ephemeral), ['demo.dynamic']);
}

void _reorder() {
  final definition = _definition();
  final moved = reorderContextMenuBucket(
    definition: definition,
    layout: null,
    bucket: ContextMenuBucket.list,
    oldIndex: 0,
    newIndex: 3,
  );
  final plan = resolveContextMenu(definition: definition, layout: moved);
  // `onReorderItem` 的口径：newIndex 已经是「摘掉之后」的最终位置，不再 -1。
  checkEq('列表内拖到最后一位', _ids(plan.list), [
    'demo.b',
    'demo.c',
    'demo.d',
    'demo.a',
  ]);

  final upward = reorderContextMenuBucket(
    definition: definition,
    layout: moved,
    bucket: ContextMenuBucket.list,
    oldIndex: 2,
    newIndex: 0,
  );
  checkEq(
    '往上拖到第一位',
    _ids(resolveContextMenu(definition: definition, layout: upward).list),
    ['demo.d', 'demo.b', 'demo.c', 'demo.a'],
  );

  var pinned = setContextMenuPin(
    definition,
    null,
    'demo.a',
    ContextMenuPin.top,
  );
  pinned = setContextMenuPin(definition, pinned, 'demo.b', ContextMenuPin.top);
  final topMoved = reorderContextMenuBucket(
    definition: definition,
    layout: pinned,
    bucket: ContextMenuBucket.top,
    oldIndex: 0,
    newIndex: 2,
  );
  checkEq(
    '顶部区段内重排',
    _topIds(resolveContextMenu(definition: definition, layout: topMoved)),
    ['demo.b', 'demo.a'],
  );
  checkEq(
    '重排顶部不影响主列表次序',
    _ids(resolveContextMenu(definition: definition, layout: topMoved).list),
    ['demo.c', 'demo.d'],
  );

  final outOfRange = reorderContextMenuBucket(
    definition: definition,
    layout: null,
    bucket: ContextMenuBucket.list,
    oldIndex: 9,
    newIndex: 0,
  );
  checkEq('越界下标不改次序', outOfRange.order, [
    'demo.a',
    'demo.b',
    'demo.c',
    'demo.d',
  ]);
}

void _json() {
  const layout = ContextMenuScopeLayout(
    order: <String>['demo.b', 'demo.a'],
    overrides: <String, ContextMenuItemOverride>{
      'demo.a': ContextMenuItemOverride(
        visibility: ContextMenuVisibility.collapsed,
        pin: ContextMenuPin.top,
        iconOnly: true,
      ),
    },
  );
  final decoded = ContextMenuScopeLayout.fromJson(layout.toJson());
  check('JSON 往返相等', decoded == layout);

  final tolerant = ContextMenuScopeLayout.fromJson(<String, dynamic>{
    'order': <Object?>['demo.a', 42, '', 'demo.a', null],
    'overrides': <String, dynamic>{
      'demo.a': <String, dynamic>{
        'visibility': 'fromFuture',
        'pin': 'sideways',
        'iconOnly': 'yes',
      },
      'demo.b': 'not-a-map',
    },
  });
  checkEq('坏数据里的 order 只留合法字符串并去重', tolerant.order, ['demo.a']);
  check('认不出的枚举回默认（等价于没设置，因此不落库）', tolerant.overrides['demo.a'] == null);
  check('非对象的 override 丢掉', !tolerant.overrides.containsKey('demo.b'));

  const pristine = ContextMenuScopeLayout();
  check('空布局是 pristine', pristine.isPristine);
  check('只改一项就不是 pristine', !layout.isPristine);
}
