// 泳道「激活 / 揭示」选址的**纯 Dart** 判据。
//
//   dart run test/workspace/lane_focus_check.dart
//
// 这段几何值得单独立判据，因为它错的方式**不会报错、只会让画面抖**：
// 「激活一条已经在眼前的泳道」本该一动不动，写成「居中」就会让每次点击都横移一下。
// 这类错误编译得过、也抛不出异常，只有把数字算出来比对才看得见。
//
// 三条不变量：
//   1. **已经在视口里 ⇒ 偏移不变**（契约：minimum horizontal movement）；
//   2. 偏移恒在 `[0, contentWidth - viewportWidth]` 内（越界就是露白 / 滚过头）；
//   3. 比视口宽的泳道对齐**最近的**那条边，不是硬对齐左边。
//
// ignore_for_file: avoid_print
import 'package:zephyr/workspace/model/workspace_lane_focus.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_strip_metrics.dart';

int _passed = 0;

void check(String label, bool condition, [String? detail]) {
  if (!condition) {
    throw StateError('FAIL: $label${detail == null ? '' : ' — $detail'}');
  }
  _passed++;
}

void main() {
  _laneAlreadyVisibleDoesNotMove();
  _cutLaneMovesJustEnough();
  _widerThanViewportAlignsNearestEdge();
  _offsetsStayInRange();
  _noScrollRoomMeansZero();
  _soloReaderFillsViewportAndAlignsItself();
  _revealBringsAdjacentLaneIntoView();
  _focusKeepsReaderSliver();
  _unknownLaneLeavesOffsetAlone();

  print('lane_focus_check: $_passed checks passed');
}

// ── 场景 ─────────────────────────────────────────────────────────────────

/// 三条泳道都摆得下：激活任何一条都不该移动条带。
///
/// 这是本文件最想钉住的一条 —— 「聚焦」不是「居中」。
/// 刻意选一个**有滚动余地**的视口（1000 宽，内容 1260）：余地是 0 的场景里
/// 「不动」是白送的，验不出东西。
void _laneAlreadyVisibleDoesNotMove() {
  final g = _geometry(viewportWidth: 1000, availableWidth: 1000);
  check('构造前提：条带比视口宽（有滚动余地）', g.maxOffset(1000) > 0);
  // 1000 视口下：left 0..380，reader 390..890，right 900..1260。
  check('构造前提：左泳道与 Reader 已经完整可见', g.endOf(LaneId.reader) <= 1000);

  for (final lane in [LaneId.left, LaneId.reader]) {
    final offset = g.focusOffset(
      laneId: lane,
      viewportWidth: 1000,
      currentOffset: 0,
    );
    check('激活已完整可见的 $lane 不动条带', offset == 0.0, '$offset');
  }

  // 换一个视口，富余全部给 Reader 之后条带正好等于视口 —— 仍然不动。
  final exact = _geometry(viewportWidth: 2000, availableWidth: 2000);
  check('构造前提：富余被 Reader 吃满后条带正好等于视口', exact.contentWidth == 2000.0);
  check('正好装下时没有滚动余地', exact.maxOffset(2000) == 0.0);
}

/// 泳道被右边缘裁掉：向左推**刚好够它完整可见**的量，不多不少。
void _cutLaneMovesJustEnough() {
  final g = _geometry(viewportWidth: 1000, availableWidth: 1000);
  // left 0..380，reader 390..890，right 900..1260。
  check('构造前提：右泳道右边缘在视口外', g.endOf(LaneId.right) > 1000);

  final offset = g.focusOffset(
    laneId: LaneId.right,
    viewportWidth: 1000,
    currentOffset: 0,
  );
  check('把右泳道推到刚好完整可见', offset == 260.0, '$offset');
  check(
    '推完之后它的右边缘正好落在视口右边缘',
    g.endOf(LaneId.right) - offset == 1000.0,
    '${g.endOf(LaneId.right) - offset}',
  );

  // 反向：当前已经滚到最右，激活最左边的泳道 → 往右推回刚好够它完整可见。
  final back = g.focusOffset(
    laneId: LaneId.left,
    viewportWidth: 1000,
    currentOffset: 260,
  );
  check('往右推回刚好够左泳道完整可见', back == 0.0, '$back');
}

/// 比视口宽的泳道：对齐**最近的**那条边（移动更少），而不是硬对齐左边。
void _widerThanViewportAlignsNearestEdge() {
  final layout = _layout(rightWidth: 620);
  final g = _geometry(
    viewportWidth: 600,
    availableWidth: 600,
    layout: layout,
  );
  // left 0..380，reader 390..790，right 800..1420；右泳道 620 > 视口 600。
  check('构造前提：右泳道比视口宽', g.width[LaneId.right]! > 600);

  final fromLeft = g.focusOffset(
    laneId: LaneId.right,
    viewportWidth: 600,
    currentOffset: 0,
  );
  check('从左往右进来 → 对齐左边缘 800', fromLeft == 800.0, '$fromLeft');

  final fromRight = g.focusOffset(
    laneId: LaneId.right,
    viewportWidth: 600,
    currentOffset: 820,
  );
  check('从右往左进来 → 对齐右边缘 820', fromRight == 820.0, '$fromRight');
}

/// 偏移恒在合法区间内。
void _offsetsStayInRange() {
  final g = _geometry(viewportWidth: 1000, availableWidth: 1000);
  final limit = g.maxOffset(1000);
  for (final lane in [LaneId.left, LaneId.reader, LaneId.right]) {
    for (final current in [-500.0, 0.0, 130.0, 9999.0]) {
      final offset = g.focusOffset(
        laneId: lane,
        viewportWidth: 1000,
        currentOffset: current,
      );
      check(
        'focus($lane, current=$current) 落在 [0,$limit]',
        offset >= 0 && offset <= limit,
        '$offset',
      );
    }
  }
  check('内容比视口宽时上限为正', limit == 260.0, '$limit');
}

/// 条带装得下 ⇒ 没有可滚的余地 ⇒ 任何选址都是 0。
void _noScrollRoomMeansZero() {
  final g = _geometry(viewportWidth: 4000, availableWidth: 4000);
  check('装得下时上限是 0（不是负数）', g.maxOffset(4000) == 0.0);
  for (final lane in [LaneId.left, LaneId.reader, LaneId.right]) {
    check(
      '装得下时 $lane 的选址是 0',
      g.focusOffset(laneId: lane, viewportWidth: 4000, currentOffset: 0) == 0.0,
    );
  }
  check(
    'reveal 在装得下时也是 0',
    g.revealOffset(laneId: LaneId.right, viewportWidth: 4000) == 0.0,
  );
}

/// Reader 独占：它的生效宽度就是整条可用宽，条带把它**对齐到视口**。
void _soloReaderFillsViewportAndAlignsItself() {
  final g = _geometry(
    viewportWidth: 600,
    availableWidth: 600,
    soloLaneId: LaneId.reader,
  );
  check(
    'solo 下 Reader 的宽度 = 可用宽',
    g.width[LaneId.reader] == 600.0,
    '${g.width[LaneId.reader]}',
  );
  check('构造前提：solo 下条带必然装不下', g.contentWidth > 600);

  final offset = g.focusOffset(
    laneId: LaneId.reader,
    viewportWidth: 600,
    currentOffset: 0,
  );
  check(
    '把 Reader 的左边缘对齐到视口左边缘',
    offset == g.start[LaneId.reader]!,
    '$offset vs ${g.start[LaneId.reader]}',
  );
  check('对齐后 Reader 恰好铺满视口', g.endOf(LaneId.reader) - offset == 600.0);
}

/// 边缘揭示：把相邻泳道**看全**推进视口（Reader 该让多少让多少）。
void _revealBringsAdjacentLaneIntoView() {
  final g = _geometry(
    viewportWidth: 600,
    availableWidth: 600,
    soloLaneId: LaneId.reader,
  );
  // left 0..380，reader 390..990，right 1000..1360；上限 = 1360-600 = 760。
  final revealRight = g.revealOffset(
    laneId: LaneId.right,
    viewportWidth: 600,
  );
  check('揭示右泳道 → 滚到 760', revealRight == 760.0, '$revealRight');
  check(
    '揭示后右泳道完整可见',
    g.start[LaneId.right]! >= revealRight &&
        g.endOf(LaneId.right) <= revealRight + 600,
  );
  check(
    '揭示后 Reader 仍有一部分在视口里（不是整条消失）',
    g.endOf(LaneId.reader) > revealRight,
    'reader end ${g.endOf(LaneId.reader)} vs $revealRight',
  );

  final revealLeft = g.revealOffset(laneId: LaneId.left, viewportWidth: 600);
  check('揭示左泳道 → 滚回 0', revealLeft == 0.0, '$revealLeft');
}

/// 聚焦相邻泳道时给 Reader 留一条**窄缝**（契约：a narrow portion of Reader
/// visible where possible）—— 用户点一下这条缝就能回到独占。
void _focusKeepsReaderSliver() {
  final g = _geometry(
    viewportWidth: 600,
    availableWidth: 600,
    layout: _layout(rightWidth: 620),
  );
  // left 0..380，reader 390..790，right 800..1420（620 宽 > 视口 600）。
  final without = g.focusOffset(
    laneId: LaneId.right,
    viewportWidth: 600,
    currentOffset: 0,
  );
  check('不保 Reader 时对齐右泳道左边缘 800', without == 800.0, '$without');

  final withPeek = g.focusOffset(
    laneId: LaneId.right,
    viewportWidth: 600,
    currentOffset: 0,
    readerLaneId: LaneId.reader,
    readerPeekWidth: 56,
    keepReaderVisible: true,
  );
  check('保 Reader 时偏移被拉回 790-56=734', withPeek == 734.0, '$withPeek');
  check(
    '视口左边缘正好落在 Reader 右边缘左侧 56px',
    g.endOf(LaneId.reader) - withPeek == 56.0,
    '${g.endOf(LaneId.reader) - withPeek}',
  );

  // 缝宽不能大过 Reader 自己，也不能大过半个视口。
  final hugePeek = g.focusOffset(
    laneId: LaneId.right,
    viewportWidth: 600,
    currentOffset: 0,
    readerLaneId: LaneId.reader,
    readerPeekWidth: 99999,
    keepReaderVisible: true,
  );
  check(
    '夸张的缝宽被夹到半个视口（300）',
    g.endOf(LaneId.reader) - hugePeek == 300.0,
    '${g.endOf(LaneId.reader) - hugePeek}',
  );
}

/// 不认识的泳道：不动条带（而不是滚到 0 把用户弹回最左）。
void _unknownLaneLeavesOffsetAlone() {
  final g = _geometry(viewportWidth: 1000, availableWidth: 1000);
  check(
    '未知泳道的 focus 保持原偏移',
    g.focusOffset(
          laneId: 'nope',
          viewportWidth: 1000,
          currentOffset: 120,
        ) ==
        120.0,
  );
  check(
    '未知泳道的 reveal 是 0（没有可揭示的目标）',
    g.revealOffset(laneId: 'nope', viewportWidth: 1000) == 0.0,
  );
  check('isLane 能分辨', !g.containsLane('nope') && g.containsLane(LaneId.reader));
}

// ── 夹具 ─────────────────────────────────────────────────────────────────

WorkspaceLayoutConfig _layout({double rightWidth = 360}) {
  final defaults = WorkspaceLayoutConfig.defaults();
  final lanes = Map<String, LaneConfig>.from(defaults.lanes);
  lanes[LaneId.right] = lanes[LaneId.right]!.copyWith(
    width: rightWidth,
    minWidth: 100,
    maxWidth: 700,
  );
  return defaults.copyWith(lanes: lanes);
}

WorkspaceLaneFocusGeometry _geometry({
  required double viewportWidth,
  required double availableWidth,
  WorkspaceLayoutConfig? layout,
  String? soloLaneId,
}) {
  final metrics = WorkspaceStripMetrics.resolve(
    layout: layout ?? WorkspaceLayoutConfig.defaults(),
    viewportWidth: viewportWidth,
    availableWidth: availableWidth,
    resizerWidth: WorkspaceStripMetrics.defaultResizerWidth,
    soloLaneId: soloLaneId,
  );
  return WorkspaceLaneFocusGeometry.fromMetrics(metrics);
}
