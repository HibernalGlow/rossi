// 面板操作栏（浮动 / 换边停靠 / 限制在泳道内）的**纯 Dart** 判据。
//
//   dart run test/workspace/panel_bar_check.dart
//
// 这段几何的两个错误方式都很难在界面上看出来：
//   - 吸附阈值没了 ⇒ 任何一次拖动都把面板栏吸到最近那条边，**用户永远拖不出悬浮态**；
//   - 悬浮位置不夹取 ⇒ 拖到边上就被 `Stack` 裁掉一半，看起来像「面板栏坏了」。
// 两者都不会报错，只能算出来比。
//
// ignore_for_file: avoid_print
import 'package:zephyr/workspace/model/workspace_panel_bar.dart';

int _passed = 0;

void check(String label, bool condition, [String? detail]) {
  if (!condition) {
    throw StateError('FAIL: $label${detail == null ? '' : ' — $detail'}');
  }
  _passed++;
}

void main() {
  _defaultsAreHeaderMounted();
  _dockDirections();
  _dockCandidatePicksNearestEdgeWithinThreshold();
  _dockCandidateRefusesFarAndOutside();
  _floatingOffsetCentersAndClamps();
  _percentRoundTrip();
  _jsonRoundTrip();
  _jsonFallsBackPerField();

  print('panel_bar_check: $_passed checks passed');
}

/// 默认形态 = 钉在泳道栏头里（`isTitleMounted`），不额外占位。
///
/// Rossi 与 neoview 的默认**有意不同**（那边默认钉在自己那条边 = 一根竖轨）：
/// 本项目的面板页签一直长在泳道栏头里，升级不该改变默认版式。
void _defaultsAreHeaderMounted() {
  const layout = PanelBarLayout();
  check('默认是钉住', layout.mode == PanelBarMode.pinned);
  check('默认钉在顶部', layout.dock == PanelBarDock.top);
  check('默认限制在泳道内', layout.constrained);
  check('默认状态下挂进栏头（不额外占位）', layout.isTitleMounted);
  check('默认停靠点就是 top', PanelBarDock.defaultDock() == PanelBarDock.top);

  final floating = layout.copyWith(mode: PanelBarMode.floating);
  check('悬浮时不挂栏头（它要自己浮着）', !floating.isTitleMounted);
  final dockedLeft = layout.copyWith(dock: PanelBarDock.left);
  check('钉在左边时也不挂栏头（那是一条竖轨）', !dockedLeft.isTitleMounted);
}

void _dockDirections() {
  check(
    '顶/底是横向排布',
    PanelBarDock.top.isHorizontal && PanelBarDock.bottom.isHorizontal,
  );
  check(
    '左/右是纵向排布',
    !PanelBarDock.left.isHorizontal && !PanelBarDock.right.isHorizontal,
  );
}

/// 靠边够近才吸附；阈值边界**含**该值。
void _dockCandidatePicksNearestEdgeWithinThreshold() {
  const lane = PanelBarBounds(left: 0, top: 0, width: 400, height: 300);

  check(
    '左上角附近 → 左（离左 10 比离上 150 近）',
    panelBarDockCandidate(lane: lane, x: 10, y: 150) == PanelBarDock.left,
  );
  check(
    '右侧 → 右',
    panelBarDockCandidate(lane: lane, x: 390, y: 150) == PanelBarDock.right,
  );
  check(
    '顶部中间 → 顶',
    panelBarDockCandidate(lane: lane, x: 200, y: 5) == PanelBarDock.top,
  );
  check(
    '底部中间 → 底',
    panelBarDockCandidate(lane: lane, x: 200, y: 295) == PanelBarDock.bottom,
  );
  check(
    '正好在阈值上（64）算吸附',
    panelBarDockCandidate(lane: lane, x: 64, y: 150) == PanelBarDock.left,
  );
  check(
    '超出阈值 1px（65）就不吸附',
    panelBarDockCandidate(lane: lane, x: 65, y: 150) == null,
  );

  // 四边等距时结果必须是**确定的**（取枚举顺序里第一个）。
  // 若排序不稳，同一次拖动在不同帧里会吸到不同的边，面板栏会抖。
  const square = PanelBarBounds(left: 0, top: 0, width: 100, height: 100);
  check(
    '四边等距（50,50）稳定地给出 left',
    panelBarDockCandidate(lane: square, x: 50, y: 50) == PanelBarDock.left,
  );
}

/// 泳道正中 / 泳道外 → 不吸附（`null` = 转成**悬浮**）。
///
/// 这一条是「用户还拖不拖得出悬浮态」的全部依据：没有它，
/// 面板栏会被永远吸在某条边上。
void _dockCandidateRefusesFarAndOutside() {
  const lane = PanelBarBounds(left: 0, top: 0, width: 400, height: 300);
  check(
    '泳道正中：离四边都 > 阈值 → 不吸附（转悬浮）',
    panelBarDockCandidate(lane: lane, x: 200, y: 150) == null,
  );
  check(
    '泳道外（左）→ 不吸附',
    panelBarDockCandidate(lane: lane, x: -5, y: 150) == null,
  );
  check(
    '泳道外（下）→ 不吸附',
    panelBarDockCandidate(lane: lane, x: 200, y: 400) == null,
  );

  // 阈值可调：把它放大到 200，正中也会被吸到**最近的那条边**。
  // 400×300 的泳道正中离上边 150、离左右各 200 —— 最近的是上边，不是左边。
  check(
    '阈值放大后正中吸到最近的上边',
    panelBarDockCandidate(lane: lane, x: 200, y: 150, threshold: 200) ==
        PanelBarDock.top,
  );
}

/// 悬浮位置：按中心点百分比摆放，并且**夹进容器**（越界会被裁掉一半）。
void _floatingOffsetCentersAndClamps() {
  const bounds = PanelBarBounds(left: 0, top: 0, width: 400, height: 300);

  final centered = panelBarFloatingOffset(
    bounds: bounds,
    positionX: 50,
    positionY: 50,
    barWidth: 100,
    barHeight: 40,
  );
  check(
    '50%/50% → 左上角 (150,130)',
    centered.left == 150.0 && centered.top == 130.0,
    '$centered',
  );

  final topLeft = panelBarFloatingOffset(
    bounds: bounds,
    positionX: 0,
    positionY: 0,
    barWidth: 100,
    barHeight: 40,
  );
  check(
    '0%/0% 被夹到 (0,0)（不是负数）',
    topLeft.left == 0.0 && topLeft.top == 0.0,
    '$topLeft',
  );

  final bottomRight = panelBarFloatingOffset(
    bounds: bounds,
    positionX: 100,
    positionY: 100,
    barWidth: 100,
    barHeight: 40,
  );
  check(
    '100%/100% 被夹到右下角内 (300,260)',
    bottomRight.left == 300.0 && bottomRight.top == 260.0,
    '$bottomRight',
  );

  // 容器比面板栏还小：夹取不能反过来把 left 推到负数。
  const tiny = PanelBarBounds(left: 10, top: 20, width: 40, height: 30);
  final overflow = panelBarFloatingOffset(
    bounds: tiny,
    positionX: 100,
    positionY: 100,
    barWidth: 100,
    barHeight: 40,
  );
  check(
    '容器比面板栏小 → 退回容器左上角，不出现负偏移',
    overflow.left == 10.0 && overflow.top == 20.0,
    '$overflow',
  );
}

/// 松手时「像素 → 百分比」要能反算回来（否则悬浮一次就漂一点）。
void _percentRoundTrip() {
  const bounds = PanelBarBounds(left: 0, top: 0, width: 400, height: 300);
  final percent = panelBarPercentFromOffset(
    bounds: bounds,
    left: 150,
    top: 130,
    barWidth: 100,
    barHeight: 40,
  );
  check(
    '(150,130) 反算回 50%/50%',
    percent.x == 50.0 && percent.y == 50.0,
    '$percent',
  );

  final back = panelBarFloatingOffset(
    bounds: bounds,
    positionX: percent.x,
    positionY: percent.y,
    barWidth: 100,
    barHeight: 40,
  );
  check('再算回去还是 (150,130)', back.left == 150.0 && back.top == 130.0, '$back');

  const degenerate = PanelBarBounds(left: 0, top: 0, width: 0, height: 0);
  final zero = panelBarPercentFromOffset(
    bounds: degenerate,
    left: 0,
    top: 0,
    barWidth: 10,
    barHeight: 10,
  );
  check('容器尺寸为 0 时给 50%（不除零）', zero.x == 50.0 && zero.y == 50.0);
}

void _jsonRoundTrip() {
  const layout = PanelBarLayout(
    mode: PanelBarMode.floating,
    dock: PanelBarDock.bottom,
    positionX: 12.5,
    positionY: 88,
    constrained: false,
  );
  final restored = PanelBarLayout.fromJson(layout.toJson());
  check('悬浮往返保持模式', restored.mode == PanelBarMode.floating);
  check('悬浮往返保持「钉回去的边」', restored.dock == PanelBarDock.bottom);
  check('往返保持位置', restored.positionX == 12.5 && restored.positionY == 88);
  check('往返保持「允许移出泳道」', !restored.constrained);
  check('往返后与原值相等', restored == layout);

  // 悬浮 + 停靠边是**合法**组合（那条边是「钉回去时钉哪」的记录），
  // 不能在读回来时被改写成别的，否则用户的选择被悄悄丢掉。
  final floatingTop = PanelBarLayout.fromJson(const <String, Object?>{
    'mode': 'floating',
    'dock': 'top',
  });
  check(
    '悬浮 + top 原样保留（不是非法组合）',
    floatingTop.mode == PanelBarMode.floating &&
        floatingTop.dock == PanelBarDock.top,
  );
}

/// 缺项 / 非法项**只影响它自己**。
void _jsonFallsBackPerField() {
  final empty = PanelBarLayout.fromJson(const <String, Object?>{});
  check('空 JSON → 默认钉在顶部', empty == const PanelBarLayout());

  final badDock = PanelBarLayout.fromJson(const <String, Object?>{
    'dock': 'diagonal',
  });
  check('不认识的停靠边 → 退回默认边', badDock.dock == PanelBarDock.top);

  final badPercent = PanelBarLayout.fromJson(const <String, Object?>{
    'positionX': 500,
    'positionY': 'middle',
  });
  check('越界百分比被夹到 100', badPercent.positionX == 100);
  check('非数字百分比退回 50', badPercent.positionY == 50);

  final badMode = PanelBarLayout.fromJson(const <String, Object?>{
    'mode': 'sticky',
  });
  check('不认识模式 → 钉住', badMode.mode == PanelBarMode.pinned);

  final badConstrained = PanelBarLayout.fromJson(const <String, Object?>{
    'constrained': 'yes',
  });
  check('非布尔的 constrained → 默认 true', badConstrained.constrained);
}
