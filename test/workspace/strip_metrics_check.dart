// 泳道条带宽度分配的**纯 Dart** 判据。
//
// 本机 `flutter test` 起不来（flutter_tester 的 WebSocket 握手失败），
// 所以凡是能从 widget 里抽出来的判据都抽到这里，用
//   dart run test/workspace/strip_metrics_check.dart
// 直接跑。**没有 package:test 依赖**，失败就抛 StateError 并以非零码退出。
//
// 这段几何值得单独立判据，因为它是唯一一处「算错了不会编译失败、不会抛异常，
// 只会在界面右侧糊一条黄黑斜纹」的逻辑。2026-09-18 就是这么漏过去的：
// 富余按**视口宽**算而不是按**扣掉内边距的可用宽**算，`Row` 被撑出容器 16px，
// Flutter 画出 `RIGHT OVERFLOWED BY 16 PIXELS`（把右端那行旋转文字转正读出来的）。
// 看上去那条斜纹像界面装饰，所以没有人把它当错误。
//
// 两条不变量（每个场景都验）：
//   1. `contentWidth` == 所有槽位宽度之和（否则「算的」和「画的」是两回事）；
//   2. 不滚动 ⇒ `contentWidth` ≤ 可用宽（否则 Flutter 就画斜纹）。
//
// ignore_for_file: avoid_print
import 'dart:math' as math;

import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_strip_metrics.dart';

int _passed = 0;

/// 浮点比较容差（不是布局容差）。布局容差在 `WorkspaceStripMetrics.fitTolerance`。
const double _eps = 1e-9;

void check(String label, bool condition, [String? detail]) {
  if (!condition) {
    throw StateError('FAIL: $label${detail == null ? '' : ' — $detail'}');
  }
  _passed++;
}

void main() {
  _wideWindowGivesSpareToReader();
  _theExactSixteenPixels();
  _panelLanesAreAbsolute();
  _narrowWindowScrollsWithoutSquashingLanes();
  _subPixelDeficitIsAbsorbed();
  _collapsedMiddleLaneDropsBothHandles();
  _collapsedEdgeLaneKeepsTheRemainingHandle();
  _resizerSlotsCarryTheirPair();
  _missingReaderLaneLeavesSlack();
  _soloWithNavigatorRailKeepsStripFitting();
  _soloWithoutNavigatorRailPushesLanesOff();
  _collapsedSoloLaneDoesNotRailOthers();
  print('strip_metrics_check: $_passed checks passed');
}

// ── 脚手架 ────────────────────────────────────────────────────────────────

double _available(double viewportWidth) =>
    math.max(0.0, viewportWidth - WorkspaceStripMetrics.defaultPadding * 2);

WorkspaceStripMetrics _resolve(
  double viewportWidth, {
  WorkspaceLayoutConfig? layout,
  String? soloLaneId,
  bool showLaneNavigatorInSolo = false,
}) => WorkspaceStripMetrics.resolve(
  layout: layout ?? WorkspaceLayoutConfig.defaults(),
  viewportWidth: viewportWidth,
  availableWidth: _available(viewportWidth),
  resizerWidth: WorkspaceStripMetrics.defaultResizerWidth,
  soloLaneId: soloLaneId,
  showLaneNavigatorInSolo: showLaneNavigatorInSolo,
);

double? _laneWidth(WorkspaceStripMetrics m, String laneId) {
  for (final slot in m.slots) {
    if (slot.laneId == laneId) return slot.width;
  }
  return null;
}

List<WorkspaceStripSlot> _resizers(WorkspaceStripMetrics m) =>
    m.slots.where((s) => s.isResizer).toList();

double _slotWidthSum(WorkspaceStripMetrics m) =>
    m.slots.fold(0.0, (sum, slot) => sum + slot.width);

/// 每个场景都要成立的两条不变量。
void _invariants(String label, WorkspaceStripMetrics m, double available) {
  check(
    '$label：槽位之和 == contentWidth',
    (_slotWidthSum(m) - m.contentWidth).abs() < _eps,
    '槽位和 ${_slotWidthSum(m)} vs contentWidth ${m.contentWidth}',
  );
  if (!m.needsScroll) {
    check(
      '$label：不滚动就必须装得下',
      m.contentWidth <= available + _eps,
      'content ${m.contentWidth} > available $available',
    );
  }
}

/// 旧实现（已修）的条带宽度：**富余按视口宽算**。
///
/// 刻意照抄当时的算式，好让「这条斜纹就是这么来的」变成一条可执行的断言 ——
/// 而不是只写在注释里的一句话。它随默认布局一起取真实数值，不会与现状脱钩。
double _legacyRowWidth(WorkspaceLayoutConfig layout, double viewportWidth) {
  var total = 0.0;
  for (final laneId in layout.laneOrder) {
    final lane = layout.lanes[laneId];
    if (lane == null) continue;
    total += lane.collapsed
        ? WorkspaceLayoutConfig.collapsedLaneWidth
        : lane.resolveWidth(viewportWidth);
  }
  final visibleCount = layout.laneOrder
      .where((id) => layout.lanes[id] != null && !layout.lanes[id]!.collapsed)
      .length;
  total +=
      WorkspaceStripMetrics.defaultResizerWidth * math.max(0, visibleCount - 1);

  final spare = viewportWidth - total; // ← bug：这里用的是视口宽
  if (spare > 0 && layout.lanes[LaneId.reader]?.collapsed == false) {
    total = viewportWidth;
  }
  return total;
}

WorkspaceLayoutConfig _withLane(String laneId, {bool? collapsed}) {
  final defaults = WorkspaceLayoutConfig.defaults();
  final lane = defaults.lanes[laneId]!;
  return defaults.copyWith(
    lanes: {
      ...defaults.lanes,
      laneId: collapsed == null ? lane : lane.copyWith(collapsed: collapsed),
    },
  );
}

// ── 场景 ──────────────────────────────────────────────────────────────────

/// 宽窗口：富余全部给阅读器，条带精确填满可用宽。
void _wideWindowGivesSpareToReader() {
  const vw = 1625.0; // 现网截图实测的窗口逻辑宽
  final m = _resolve(vw);
  final available = _available(vw); // 1609

  check('宽窗口不滚动', !m.needsScroll);
  check(
    '宽窗口下 contentWidth 精确等于可用宽',
    (m.contentWidth - available).abs() < _eps,
    '${m.contentWidth} vs $available',
  );
  check('左泳道保持绝对宽 380', _laneWidth(m, LaneId.left) == 380.0);
  check('右泳道保持绝对宽 360', _laneWidth(m, LaneId.right) == 360.0);
  // 阅读器标称 = 1625 × 0.5 = 812.5；再吃掉富余 1609 − 1572.5 = 36.5
  check(
    '富余全部给阅读器（812.5 + 36.5 = 849）',
    _laneWidth(m, LaneId.reader) == 849.0,
    '实际 ${_laneWidth(m, LaneId.reader)}',
  );
  _invariants('宽窗口', m, available);
}

/// 回归：同一窗口下旧算式**恰好溢出 16px**（= 左右内边距之和），新算式不溢出。
void _theExactSixteenPixels() {
  const vw = 1625.0;
  final available = _available(vw);
  final legacyOverflow =
      _legacyRowWidth(WorkspaceLayoutConfig.defaults(), vw) - available;

  check(
    '旧算式的溢出量正好是左右内边距之和（16px）',
    legacyOverflow == 16.0,
    '实际 $legacyOverflow',
  );
  check(
    '溢出的量等于 2 × defaultPadding',
    legacyOverflow == WorkspaceStripMetrics.defaultPadding * 2,
  );

  final m = _resolve(vw);
  check('新算式在同一窗口下不溢出', !m.needsScroll && m.contentWidth <= available + _eps);
}

/// 面板泳道是**绝对像素**：窗口变宽变窄都不夹取。
void _panelLanesAreAbsolute() {
  final narrow = _resolve(1200);
  final wide = _resolve(2400);

  check('窗口 1200 时左泳道仍是 380', _laneWidth(narrow, LaneId.left) == 380.0);
  check('窗口 2400 时左泳道仍是 380', _laneWidth(wide, LaneId.left) == 380.0);
  check('窗口 1200 时右泳道仍是 360', _laneWidth(narrow, LaneId.right) == 360.0);
  check('窗口 2400 时右泳道仍是 360', _laneWidth(wide, LaneId.right) == 360.0);

  // 阅读器是比例：1625×0.5=812.5 / 2400×0.5=1200，都被夹在 [400, 2000] 内
  check(
    '窗口 2400 时阅读器标称 1200 + 富余 424',
    _laneWidth(wide, LaneId.reader) == 1624.0,
  );
  _invariants('窗口 1200', narrow, _available(1200));
  _invariants('窗口 2400', wide, _available(2400));
}

/// 装不下：各自保持存储宽度、整条带横向滚动，**不许把泳道压扁**。
void _narrowWindowScrollsWithoutSquashingLanes() {
  const vw = 900.0;
  final m = _resolve(vw);
  final available = _available(vw); // 884

  check('窄窗口要横向滚动', m.needsScroll);
  check('左泳道没有被压向 minWidth', _laneWidth(m, LaneId.left) == 380.0);
  check('右泳道没有被压向 minWidth', _laneWidth(m, LaneId.right) == 360.0);
  check(
    '阅读器停在标称 450（450 < 窗口一半才会用 minWidth）',
    _laneWidth(m, LaneId.reader) == 450.0,
  );
  check('contentWidth = 380+450+360+20', m.contentWidth == 1210.0);
  check('可用宽只有 884', available == 884.0);
  _invariants('窄窗口', m, available);
}

/// 亚像素差：只多 0.3px 也要从阅读器身上抹平，**不能留着让 Flutter 画斜纹**。
void _subPixelDeficitIsAbsorbed() {
  // 760 + vw/2 − (vw − 16) = −0.3  ⇒  vw = 1551.4
  const vw = 1551.4;
  final m = _resolve(vw);
  final available = _available(vw);

  check('差 0.3px 不触发滚动', !m.needsScroll);
  check(
    '差 0.3px 被阅读器吃掉，contentWidth 精确等于可用宽',
    (m.contentWidth - available).abs() < _eps,
    '${m.contentWidth} vs $available',
  );
  check(
    '阅读器 = 775.7 − 0.3 = 775.4',
    (_laneWidth(m, LaneId.reader)! - 775.4).abs() < 1e-6,
    '实际 ${_laneWidth(m, LaneId.reader)}',
  );
  _invariants('亚像素差', m, available);

  // 但差到 1px 就不再抹平：宁可横向滚动，也不接受一条 1px 的斜纹。
  // 760 + vw/2 − (vw − 16) = −1  ⇒  vw = 1550
  final borderline = _resolve(1550.0);
  check('差 1px 就走滚动，不容忍', borderline.needsScroll);
  _invariants('1px 差', borderline, _available(1550.0));
}

/// 折叠泳道夹在中间：两侧都是折叠轨的邻居，**一个手柄都不该有**。
void _collapsedMiddleLaneDropsBothHandles() {
  final layout = _withLane(LaneId.reader, collapsed: true);

  final m = _resolve(1625.0, layout: layout);
  check('折叠的阅读器只占 44dp', _laneWidth(m, LaneId.reader) == 44.0);
  check('折叠轨标记为 collapsed', m.slots[1].collapsed);
  check('左右两条被折叠轨隔开，没有手柄', _resizers(m).isEmpty, '${_resizers(m)}');
  check('contentWidth = 380+44+360', m.contentWidth == 784.0);
  _invariants('折叠中间泳道', m, _available(1625.0));

  // 关键：可用宽正好 784 时不该滚动。
  // 「手柄数 = 可见泳道数 − 1」会多算一个 10px 手柄（那条手柄根本画不出来），
  // 于是 794 > 784，条带在还放得下的时候就横向滚起来。
  final tight = _resolve(800.0, layout: layout);
  check('可用宽 784 时恰好放下，不滚动', !tight.needsScroll);
  check(
    '此时 contentWidth 等于可用宽（794 是错的）',
    tight.contentWidth == 784.0,
    '${tight.contentWidth}',
  );
  _invariants('折叠中间泳道（紧凑）', tight, _available(800.0));
}

/// 折叠最左侧：它和阅读器之间不放手柄，但阅读器与右泳道之间要放。
void _collapsedEdgeLaneKeepsTheRemainingHandle() {
  final layout = _withLane(LaneId.left, collapsed: true);
  final m = _resolve(1625.0, layout: layout);
  final available = _available(1625.0);

  check('左侧折叠轨 44dp', _laneWidth(m, LaneId.left) == 44.0);
  check('只剩一个手柄', _resizers(m).length == 1, '${_resizers(m)}');
  check(
    '手柄分开的是 reader→right',
    _resizers(m).single.beforeLaneId == LaneId.reader &&
        _resizers(m).single.afterLaneId == LaneId.right,
  );
  // 44 + 812.5 + 360 + 10 = 1226.5；富余 1609 − 1226.5 = 382.5 给阅读器
  check('阅读器吃掉富余 → 1195', _laneWidth(m, LaneId.reader) == 1195.0);
  check('条带仍精确填满', (m.contentWidth - available).abs() < _eps);
  _invariants('折叠最左', m, available);
}

/// 手柄槽位自带「它分开的是哪一对泳道」，调用方不必再反推。
void _resizerSlotsCarryTheirPair() {
  final m = _resolve(1625.0);
  final shape = m.slots.map((s) => s.laneId ?? '|').join(',');
  check(
    '槽位顺序 = left,|,reader,|,right',
    shape == 'left,|,reader,|,right',
    shape,
  );

  final pairs = _resizers(
    m,
  ).map((s) => '${s.beforeLaneId}→${s.afterLaneId}').toList();
  check(
    '两个手柄分别配对 left→reader 与 reader→right',
    pairs.join(' , ') == 'left→reader , reader→right',
    pairs.join(' , '),
  );
}

/// 没有阅读器泳道（布局里被摘掉）：富余无处可给，但不能溢出。
void _missingReaderLaneLeavesSlack() {
  final defaults = WorkspaceLayoutConfig.defaults();
  final layout = defaults.copyWith(
    lanes: Map<String, LaneConfig>.from(defaults.lanes)..remove(LaneId.reader),
  );
  final m = _resolve(1625.0, layout: layout);

  check('没有弹性泳道时不滚动', !m.needsScroll);
  check('contentWidth = 380+360+10（富余留在右侧，不硬塞）', m.contentWidth == 750.0);
  check('两条面板泳道之间仍有一个手柄', _resizers(m).single.beforeLaneId == LaneId.left);
  _invariants('无阅读器泳道', m, _available(1625.0));
}

// ── 独占 + 泳道切换栏（「设置 → 布局」里的那个开关）─────────────────────────

/// 打开切换栏：其余泳道收成紧凑轨，而轨的宽度**从独占那条身上扣**。
///
/// 这条判据钉的是那个反直觉的顺序：轨加在旁边（而不是从 Reader 身上扣）
/// 会让条带总宽超出可用宽一个轨宽 ⇒ `needsScroll` 为真 ⇒ 那几条轨
/// 正好被推出视口 ——「显示切换栏」的结果是什么都看不见。
void _soloWithNavigatorRailKeepsStripFitting() {
  const rail = WorkspaceLayoutConfig.collapsedLaneWidth;
  final available = _available(1625.0);
  final m = _resolve(
    1625.0,
    soloLaneId: LaneId.reader,
    showLaneNavigatorInSolo: true,
  );

  check('切换栏：左泳道收成紧凑轨', _laneWidth(m, LaneId.left) == rail);
  check('切换栏：右泳道收成紧凑轨', _laneWidth(m, LaneId.right) == rail);
  check(
    '切换栏：Reader 吃掉扣掉两条轨之后剩下的宽度',
    _laneWidth(m, LaneId.reader) == available - rail * 2,
    '${_laneWidth(m, LaneId.reader)} vs ${available - rail * 2}',
  );
  check('切换栏：不滚动', !m.needsScroll);
  // 轨旁边不画手柄（与「折叠泳道旁边不放手柄」同一条规则），
  // 于是拖宽度的手柄在这里应当**全部消失**。
  check('切换栏：紧凑轨之间不再有拖宽度手柄', _resizers(m).isEmpty);
  _invariants('独占 + 切换栏', m, available);
}

/// 关掉切换栏 = 独占就是字面的「只剩一条」：其余泳道保持常规宽并被推出视口，
/// 只能靠左右唤出区调回来。
void _soloWithoutNavigatorRailPushesLanesOff() {
  final m = _resolve(1625.0, soloLaneId: LaneId.reader);

  check('不显示切换栏：左泳道仍是常规宽', _laneWidth(m, LaneId.left) == 380.0);
  check('不显示切换栏：条带要滚（其余泳道在视口外）', m.needsScroll);
  _invariants('独占 + 不显示切换栏', m, _available(1625.0));
}

/// 独占那条泳道**自己**被折叠时不摆切换栏 —— 折叠是更明确的意图，
/// 此时没有任何一条泳道在独占视口，把其余泳道挤成轨没有对应的收益。
void _collapsedSoloLaneDoesNotRailOthers() {
  final defaults = WorkspaceLayoutConfig.defaults();
  final layout = defaults.copyWith(
    lanes: Map<String, LaneConfig>.from(defaults.lanes)
      ..update(LaneId.reader, (lane) => lane.copyWith(collapsed: true)),
  );
  final m = _resolve(
    1625.0,
    layout: layout,
    soloLaneId: LaneId.reader,
    showLaneNavigatorInSolo: true,
  );

  check('独占者自己被折叠时，左泳道不被挤成轨', _laneWidth(m, LaneId.left) == 380.0);
  check('独占者自己被折叠时，右泳道不被挤成轨', _laneWidth(m, LaneId.right) == 360.0);
  _invariants('折叠的独占者 + 切换栏', m, _available(1625.0));
}

