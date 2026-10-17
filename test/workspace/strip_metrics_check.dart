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
  _noLaneIsWiderThanTheViewport();
  _soloWithNavigatorRailKeepsStripFitting();
  _soloWithoutNavigatorRailPushesLanesOff();
  _collapsedSoloLaneDoesNotRailOthers();
  _activationNeverChangesWidths();
  _activeLaneIsNeverARail();
  _trailingEdgeResizerAllowsRightExtension();
  print('strip_metrics_check: $_passed checks passed');
}

// ── 脚手架 ────────────────────────────────────────────────────────────────

double _available(double viewportWidth) =>
    math.max(0.0, viewportWidth - WorkspaceStripMetrics.defaultPadding * 2);

WorkspaceStripMetrics _resolve(
  double viewportWidth, {
  WorkspaceLayoutConfig? layout,
  String? soloLaneId,
  String? activeLaneId,
  bool showLaneNavigatorInSolo = false,
}) => WorkspaceStripMetrics.resolve(
  layout: layout ?? WorkspaceLayoutConfig.defaults(),
  viewportWidth: viewportWidth,
  availableWidth: _available(viewportWidth),
  resizerWidth: WorkspaceStripMetrics.defaultResizerWidth,
  soloLaneId: soloLaneId,
  activeLaneId: activeLaneId,
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
  // 阅读器标称 = 1625 × 0.5 = 812.5；
  // 3个手柄 = 30px；再吃掉富余 1609 − (380 + 812.5 + 360 + 30) = 26.5
  check(
    '富余全部给阅读器（812.5 + 26.5 = 839）',
    _laneWidth(m, LaneId.reader) == 839.0,
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
  // 窗口 2400 可用宽 2384；380 + 1200 + 360 + 30 = 1970；富余 414
  check(
    '窗口 2400 时阅读器标称 1200 + 富余 414',
    _laneWidth(wide, LaneId.reader) == 1614.0,
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
  check('contentWidth = 380+450+360+30', m.contentWidth == 1220.0);
  check('可用宽只有 884', available == 884.0);
  _invariants('窄窗口', m, available);
}

/// 窄视口（手机竖屏）上，**任何一条泳道都不许比视口本身还宽**。
///
/// 这条不是审美：一条比屏幕还宽的泳道，滚动余量全花在自己身上，画面上没有任何东西
/// 提示「外面还有别的泳道」—— 而把相邻泳道呼回来的那条路是**边缘悬停**，
/// 触摸屏上永不触发。桌面默认的 380/650/360 配 369dp 的视口恰好三条全超。
///
/// 同时钉住两处**不该**被夹的：折叠轨（44 是设计值）与独占那条（按定义吃满可用宽）。
void _noLaneIsWiderThanTheViewport() {
  const vw = 369.0; // 24129PN74C 竖屏实测逻辑宽（1200px / 3.25）
  final m = _resolve(vw);
  final cap = vw * WorkspaceStripMetrics.maxLaneViewportFactor;

  for (final laneId in const [LaneId.left, LaneId.reader, LaneId.right]) {
    final w = _laneWidth(m, laneId)!;
    check('$laneId 在窄视口上不超过视口宽', w <= vw + _eps, '$w > $vw');
    check('$laneId 被夹到上限', (w - cap).abs() < _eps, '$w vs $cap');
  }
  // 阳性对照：不夹的话这三条是 380 / 400 / 360 —— 少了这两条，
  // 「clamp 写了吗」与「clamp 写了但没生效」在判据里长得一样。
  check('左栏确实被压过（不再保持 380）', _laneWidth(m, LaneId.left) != 380.0);
  check(
    '阅读器连 minWidth=400 都让位（地板取 min(minWidth, cap)）',
    _laneWidth(m, LaneId.reader) == cap,
  );
  _invariants('窄视口夹取', m, _available(vw));

  final defaults = WorkspaceLayoutConfig.defaults();
  final railLayout = defaults.copyWith(
    lanes: {
      for (final entry in defaults.lanes.entries)
        entry.key: entry.value.copyWith(collapsed: entry.key == LaneId.left),
    },
  );
  final rails = _resolve(vw, layout: railLayout);
  check('折叠轨保持 44，不参与夹取', _laneWidth(rails, LaneId.left) == 44.0);

  final solo = _resolve(vw, soloLaneId: LaneId.reader);
  check(
    '独占那条按定义吃满可用宽，不被夹',
    _laneWidth(solo, LaneId.reader) == _available(vw),
    '${_laneWidth(solo, LaneId.reader)} vs ${_available(vw)}',
  );

  // 宽窗口一律不动（回归对）：上限只在「一条就吃满视口」时才够得着。
  final wide = _resolve(1440.0);
  check('宽窗口左栏仍是绝对像素 380', _laneWidth(wide, LaneId.left) == 380.0);
  check('宽窗口右栏仍是绝对像素 360', _laneWidth(wide, LaneId.right) == 360.0);
}

/// 亚像素差：只多 0.3px 也要从阅读器身上抹平，**不能留着让 Flutter 画斜纹**。
void _subPixelDeficitIsAbsorbed() {
  // 770 + vw/2 − (vw − 16) = −0.3  ⇒  vw = 1571.4
  const vw = 1571.4;
  final m = _resolve(vw);
  final available = _available(vw);

  check('差 0.3px 不触发滚动', !m.needsScroll);
  check(
    '差 0.3px 被阅读器吃掉，contentWidth 精确等于可用宽',
    (m.contentWidth - available).abs() < _eps,
    '${m.contentWidth} vs $available',
  );
  check(
    '阅读器 = 785.7 − 0.3 = 785.4',
    (_laneWidth(m, LaneId.reader)! - 785.4).abs() < 1e-6,
    '实际 ${_laneWidth(m, LaneId.reader)}',
  );
  _invariants('亚像素差', m, available);

  // 但差到 1px 就不再抹平：宁可横向滚动，也不接受一条 1px 的斜纹。
  // 770 + vw/2 − (vw − 16) = −1  ⇒  vw = 1570.0
  final borderline = _resolve(1570.0);
  check('差 1px 就走滚动，不容忍', borderline.needsScroll);
  _invariants('1px 差', borderline, _available(1570.0));
}

/// 折叠泳道夹在中间：中间两侧都不放手柄，最右侧未折叠泳道保留其右侧手柄。
void _collapsedMiddleLaneDropsBothHandles() {
  final layout = _withLane(LaneId.reader, collapsed: true);

  final m = _resolve(1625.0, layout: layout);
  check('折叠的阅读器只占 44dp', _laneWidth(m, LaneId.reader) == 44.0);
  check('折叠轨标记为 collapsed', m.slots[1].collapsed);
  check('中间不放手柄，最右侧放手柄', _resizers(m).length == 1, '${_resizers(m)}');
  check('最右侧手柄是 right 边缘手柄', _resizers(m).single.isEdgeResizer);
  check('contentWidth = 380+44+360+10', m.contentWidth == 794.0);
  _invariants('折叠中间泳道', m, _available(1625.0));

  final tight = _resolve(810.0, layout: layout);
  check('可用宽 794 时恰好放下，不滚动', !tight.needsScroll);
  check(
    '此时 contentWidth 等于可用宽',
    tight.contentWidth == 794.0,
    '${tight.contentWidth}',
  );
  _invariants('折叠中间泳道（紧凑）', tight, _available(810.0));
}

/// 折叠最左侧：它和阅读器之间不放手柄，但阅读器与右泳道之间以及右泳道右侧要放。
void _collapsedEdgeLaneKeepsTheRemainingHandle() {
  final layout = _withLane(LaneId.left, collapsed: true);
  final m = _resolve(1625.0, layout: layout);
  final available = _available(1625.0);

  check('左侧折叠轨 44dp', _laneWidth(m, LaneId.left) == 44.0);
  check('剩下两个手柄', _resizers(m).length == 2, '${_resizers(m)}');
  check(
    '手柄分开的是 reader→right 与 right 边缘',
    _resizers(m).first.beforeLaneId == LaneId.reader &&
        _resizers(m).first.afterLaneId == LaneId.right &&
        _resizers(m).last.isEdgeResizer,
  );
  // 44 + 812.5 + 360 + 20 = 1236.5；富余 1609 − 1236.5 = 372.5 给阅读器
  check('阅读器吃掉富余 → 1185', _laneWidth(m, LaneId.reader) == 1185.0);
  check('条带仍精确填满', (m.contentWidth - available).abs() < _eps);
  _invariants('折叠最左', m, available);
}

/// 手柄槽位自带「它分开的是哪一对泳道」，调用方不必再反推。
void _resizerSlotsCarryTheirPair() {
  final m = _resolve(1625.0);
  final shape = m.slots.map((s) => s.laneId ?? '|').join(',');
  check(
    '槽位顺序 = left,|,reader,|,right,|',
    shape == 'left,|,reader,|,right,|',
    shape,
  );

  final pairs = _resizers(
    m,
  ).map((s) => '${s.beforeLaneId}→${s.afterLaneId ?? 'edge'}').toList();
  check(
    '三个手柄分别配对 left→reader、reader→right 与 right→edge',
    pairs.join(' , ') == 'left→reader , reader→right , right→edge',
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
  check('contentWidth = 380+360+20（富余留在右侧，不硬塞）', m.contentWidth == 760.0);
  check('两条面板泳道之间有手柄，最右侧也有手柄', _resizers(m).length == 2);
  check(
    '手柄分开 left→right 与 right 边缘',
    _resizers(m).first.beforeLaneId == LaneId.left &&
        _resizers(m).last.isEdgeResizer,
  );
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

// ── 激活态与宽度的关系（ADR-0014 的修订）──────────────────────────────────

/// **激活不改宽度**。
///
/// 这一条钉的是「鼠标移过去卡一下」里最贵的那一下：宽度一变，`ImageSurface` 的
/// 物理尺寸就变，已上屏的纹理被判废并按新宽重解（`lib/reader/image_surface.dart`
/// 自己记的数是 300–400 ms/页）。所以「谁被激活」**只能**改变条带停在哪、
/// 边框亮不亮、哪条收成轨，不许改变 Reader 那条泳道的宽度。
void _activationNeverChangesWidths() {
  _widthsStableAcrossActivations('不独占', null);
  _widthsStableAcrossActivations('独占 + 不显示切换栏', LaneId.reader);

  // 阳性对照：这条尺子得**看得见**真会变宽的情况 —— 独占开关本身必须改变宽度，
  // 否则上面那一串「没变」可能只是因为宽度根本没被算过。
  const viewport = 1625.0;
  final off = _resolve(viewport, activeLaneId: LaneId.reader);
  final on = _resolve(
    viewport,
    soloLaneId: LaneId.reader,
    activeLaneId: LaneId.reader,
  );
  check(
    '对照：独占**本身**确实把 Reader 撑到可用宽',
    (_laneWidth(on, LaneId.reader)! - _laneWidth(off, LaneId.reader)!) > 100,
    '${_laneWidth(on, LaneId.reader)} vs ${_laneWidth(off, LaneId.reader)}',
  );
}

/// 在 [soloLaneId] 这一档下，把「谁被激活」四档全跑一遍，逐条比对宽度。
void _widthsStableAcrossActivations(String label, String? soloLaneId) {
  const viewport = 1625.0;
  const lanes = <String>[LaneId.left, LaneId.reader, LaneId.right];
  final baseline = _resolve(viewport, soloLaneId: soloLaneId);

  for (final active in <String?>[
    null,
    LaneId.left,
    LaneId.reader,
    LaneId.right,
  ]) {
    final m = _resolve(viewport, soloLaneId: soloLaneId, activeLaneId: active);
    for (final laneId in lanes) {
      check(
        '$label：激活 $active 时 $laneId 的宽度与「还没定」一致',
        (_laneWidth(m, laneId)! - _laneWidth(baseline, laneId)!).abs() < _eps,
        '${_laneWidth(m, laneId)} vs ${_laneWidth(baseline, laneId)}',
      );
    }
    _invariants('$label / 激活 $active', m, _available(viewport));
  }
}

/// 切换栏只压**没被激活**的那些泳道：激活哪条，哪条展开。
///
/// 轨的唯一用途是「点我把交互交给你」（触屏上它是左右泳道**唯一**的把手）。
/// 交互已经交出去了还把它按回 44px，用户点完轨仍然点不动里面的东西。
void _activeLaneIsNeverARail() {
  const rail = WorkspaceLayoutConfig.collapsedLaneWidth;
  final available = _available(1625.0);

  final m = _resolve(
    1625.0,
    soloLaneId: LaneId.reader,
    activeLaneId: LaneId.left,
    showLaneNavigatorInSolo: true,
  );

  check(
    '激活左泳道：它展开成自己的宽度而不是轨',
    _laneWidth(m, LaneId.left)! > rail,
    '${_laneWidth(m, LaneId.left)}',
  );
  check('激活左泳道：右泳道仍是轨', _laneWidth(m, LaneId.right) == rail);
  check(
    '激活左泳道：Reader 只被**轨**扣宽度，不被展开的那条扣',
    _laneWidth(m, LaneId.reader) == available - rail,
    '${_laneWidth(m, LaneId.reader)} vs ${available - rail}',
  );
  _invariants('独占 + 切换栏 + 左被激活', m, available);

  // 对照：把激活收回 Reader 之后，左那条又变回轨（这条规则不是单向的）。
  final backToReader = _resolve(
    1625.0,
    soloLaneId: LaneId.reader,
    activeLaneId: LaneId.reader,
    showLaneNavigatorInSolo: true,
  );
  check('激活回到 Reader：左又收成轨', _laneWidth(backToReader, LaneId.left) == rail);
  check(
    '激活回到 Reader：两条都收成轨 ⇒ Reader 比左被激活那次少一条轨宽',
    _laneWidth(m, LaneId.reader)! - _laneWidth(backToReader, LaneId.reader)! ==
        rail,
    '${_laneWidth(m, LaneId.reader)} vs ${_laneWidth(backToReader, LaneId.reader)}',
  );
}

/// 最右侧泳道的右边存在边缘手柄，可以向右延伸扩展宽度。
void _trailingEdgeResizerAllowsRightExtension() {
  final defaults = WorkspaceLayoutConfig.defaults();
  final m = _resolve(1625.0, layout: defaults);

  check('最右侧泳道是 right', defaults.laneOrder.last == LaneId.right);
  final lastSlot = m.slots.last;
  check('条带最后一个槽位是手柄', lastSlot.isResizer);
  check('该手柄是边缘手柄', lastSlot.isEdgeResizer);
  check('手柄绑定的泳道是 right', lastSlot.beforeLaneId == LaneId.right);
  check('手柄右侧没有泳道', lastSlot.afterLaneId == null);

  // 当最右侧泳道加宽时，条带向右延伸，contentWidth 增加
  final extendedLayout = defaults.copyWith(
    lanes: {
      ...defaults.lanes,
      LaneId.right: defaults.lanes[LaneId.right]!.copyWith(width: 500.0),
    },
  );
  final extended = _resolve(1625.0, layout: extendedLayout);
  check('加宽后右泳道是 500', _laneWidth(extended, LaneId.right) == 500.0);
  check('最后一个槽位依然是手柄', extended.slots.last.isEdgeResizer);
  _invariants('最右侧泳道向右延伸', extended, _available(1625.0));

  // 最右侧泳道折叠时，边缘手柄消失
  final collapsedLayout = defaults.copyWith(
    lanes: {
      ...defaults.lanes,
      LaneId.right: defaults.lanes[LaneId.right]!.copyWith(collapsed: true),
    },
  );
  final collapsedMetrics = _resolve(1625.0, layout: collapsedLayout);
  check('折叠后条带最后一个槽位是折叠轨，不再有手柄', !collapsedMetrics.slots.last.isResizer);
  check('折叠轨是 right', collapsedMetrics.slots.last.laneId == LaneId.right);
}
