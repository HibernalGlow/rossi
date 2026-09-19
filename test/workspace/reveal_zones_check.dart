// 悬停唤出区的**纯 Dart** 判据（「设置 → 布局」那块画布的全部算术）。
//
// 跑法与其余 check 一样：`dart test/workspace/reveal_zones_check.dart`
// （没有 package:test 依赖，失败抛 StateError 并以非零码退出）。
//
// 值得单独立判据的三处：
// 1. **联动**是「改一条边顺带改对侧」，写错方向（比如把右镜像成 x 而不是
//    100-x-width）在界面上只是「看起来差不多」，靠眼看发现不了；
// 2. **夹取**决定「输入 100 会怎样」，漏一次就会把画不出来的矩形存进磁盘；
// 3. **命中顺序**决定两角重叠时谁赢 —— 那是个真实存在的状态（左右两条
//    被拖到很宽时会盖住上下两条），必须有唯一答案。
//
// ignore_for_file: avoid_print
import 'package:zephyr/workspace/model/workspace_reveal_zones.dart';

int _passed = 0;

void check(String label, bool condition, [String? detail]) {
  if (!condition) {
    throw StateError('FAIL: $label${detail == null ? '' : ' — $detail'}');
  }
  _passed++;
}

void main() {
  _percentClamping();
  _zoneClamping();
  _mirroring();
  _linking();
  _drawing();
  _cornerResizeAnchorsTheOppositeCorner();
  _hitOrder();
  _jsonRoundTrip();
  _lenientFromJson();
  print('reveal_zones_check: $_passed checks passed');
}

// ── 夹取 ──────────────────────────────────────────────────────────────────

void _percentClamping() {
  check('负数夹到 0', clampRevealPercent(-12) == 0);
  check('超过 99 夹到 99', clampRevealPercent(140) == 99);
  check('保留 0.1 精度', clampRevealPercent(10.74) == 10.7);
  check('四舍五入到 0.1', clampRevealPercent(10.751) == 10.8);
  // NaN / Infinity 会从除法里来（视口宽为 0 时），存进 JSON 会让下次读盘炸掉。
  check('NaN 退回 0', clampRevealPercent(double.nan) == 0);
  check('Infinity 夹到 99', clampRevealPercent(double.infinity) == 99);
}

void _zoneClamping() {
  const wide = WorkspaceRevealZone(x: 90, y: 0, width: 50, height: 50);
  final clamped = wide.clamped();
  check('宽不超过右边界', clamped.width == 10.0, '${clamped.width}');
  check('高不超过下边界', clamped.height == 50.0, '${clamped.height}');
  check('原点不动（改宽不挪 x）', clamped.x == 90.0);

  const tiny = WorkspaceRevealZone(x: 5, y: 5, width: 0, height: 0);
  check('零面积被抬到 1%（命中不了的唤出区不该存在）', tiny.clamped().width == 1.0);
  check('零高度同样抬到 1%', tiny.clamped().height == 1.0);

  const originOver = WorkspaceRevealZone(x: 120, y: 200, width: 30, height: 30);
  final over = originOver.clamped();
  check('原点越界先夹回 99', over.x == 99.0 && over.y == 99.0);
  check('夹完原点再夹宽高', over.width == 1.0 && over.height == 1.0);
}

// ── 镜像与联动 ────────────────────────────────────────────────────────────

void _mirroring() {
  const zone = WorkspaceRevealZone(x: 4, y: 10, width: 2, height: 80);
  final h = zone.mirrored(horizontal: true);
  check('水平镜像贴右边', h.x == 94.0, '${h.x}');
  check('水平镜像不动 y / 宽 / 高', h.y == 10 && h.width == 2 && h.height == 80);
  // y=10、height=80 上下对称（10..90），镜像回自身 —— 镜像是「贴到对侧」，
  // 不是「把 y 取反」，这条正好把两者区分开。
  check('上下对称的矩形垂直镜像回自身', zone.mirrored(horizontal: false).y == 10.0);

  const low = WorkspaceRevealZone(x: 30, y: 5, width: 40, height: 10);
  final v = low.mirrored(horizontal: false);
  check('垂直镜像贴下边', v.y == 85.0, '${v.y}');
  check('垂直镜像不动 x / 宽 / 高', v.x == 30 && v.width == 40 && v.height == 10);

  const tall = WorkspaceRevealZone(x: 0, y: 9, width: 4, height: 81);
  check('镜像后仍然夹得住', tall.mirrored(horizontal: false).y == 10.0);
}

void _linking() {
  final zones = WorkspaceRevealZones.defaults;
  final next = updateRevealZonesWithLink(
    zones: zones,
    edge: RevealEdge.left,
    zone: const WorkspaceRevealZone(x: 0, y: 20, width: 3, height: 60),
    horizontalLinked: true,
    verticalLinked: true,
  );
  check('联动：改左把右也镜像过去', next.right.x == 97.0, '${next.right.x}');
  check('联动：右的 y / 宽高跟着左', next.right.y == 20 && next.right.height == 60);
  check('联动：上下没被牵连', next.top == zones.top && next.bottom == zones.bottom);

  final alone = updateRevealZonesWithLink(
    zones: zones,
    edge: RevealEdge.left,
    zone: const WorkspaceRevealZone(x: 0, y: 20, width: 3, height: 60),
    horizontalLinked: false,
    verticalLinked: true,
  );
  check('关掉左右联动：右保持出厂', alone.right == zones.right);
  check('关掉左右联动：左仍然改到了', alone.left.width == 3.0);

  final vertical = updateRevealZonesWithLink(
    zones: zones,
    edge: RevealEdge.bottom,
    zone: const WorkspaceRevealZone(x: 30, y: 95, width: 40, height: 5),
    horizontalLinked: true,
    verticalLinked: true,
  );
  check('改下把上镜像过去', vertical.top.y == 0.0 && vertical.top.height == 5.0);
  check('改下不牵连左右', vertical.left == zones.left && vertical.right == zones.right);
}

// ── 画框与四角缩放 ────────────────────────────────────────────────────────

void _drawing() {
  final forward = drawnRevealZone(
    fromX: 10,
    fromY: 20,
    toX: 30,
    toY: 45,
  );
  check('右下方向拖：原点=起点', forward.x == 10 && forward.y == 20);
  check('右下方向拖：宽高=差值', forward.width == 20 && forward.height == 25);

  final backward = drawnRevealZone(
    fromX: 30,
    fromY: 45,
    toX: 10,
    toY: 20,
  );
  check('反向拖得到同一个矩形', backward == forward, '$backward');

  final point = drawnRevealZone(fromX: 50, fromY: 50, toX: 50, toY: 50);
  check('原地点下也给出 1% 的最小矩形', point.width == 1.0 && point.height == 1.0);

  final past = drawnRevealZone(fromX: 90, fromY: 90, toX: 200, toY: 200);
  check('拖出画布外被夹住', past.right <= 100 && past.bottom <= 100, '$past');
}

void _cornerResizeAnchorsTheOppositeCorner() {
  const zone = WorkspaceRevealZone(x: 10, y: 20, width: 30, height: 40);

  final se = resizedRevealZone(
    zone: zone,
    corner: RevealCorner.se,
    xPercent: 60,
    yPercent: 80,
  );
  check('拖东南角：左上角钉住', se.x == 10 && se.y == 20);
  check('拖东南角：右下跟指针', se.right == 60 && se.bottom == 80);

  final nw = resizedRevealZone(
    zone: zone,
    corner: RevealCorner.nw,
    xPercent: 25,
    yPercent: 35,
  );
  check('拖西北角：右下角钉住', nw.right == 40 && nw.bottom == 60, '$nw');
  check('拖西北角：原点被抬到不超过对角减 1', nw.x == 25 && nw.y == 35);

  // 越过对角：不能让矩形翻过来（宽为负），要停在最小 1%。
  final past = resizedRevealZone(
    zone: zone,
    corner: RevealCorner.nw,
    xPercent: 90,
    yPercent: 90,
  );
  check('拖过对角不翻转', past.width == 1.0 && past.height == 1.0, '$past');
  check('拖过对角时对角仍钉住', past.right == 40 && past.bottom == 60, '$past');
}

// ── 命中 ──────────────────────────────────────────────────────────────────

void _hitOrder() {
  const zones = WorkspaceRevealZones(
    left: WorkspaceRevealZone(x: 0, y: 0, width: 20, height: 100),
    right: WorkspaceRevealZone(x: 80, y: 0, width: 20, height: 100),
    top: WorkspaceRevealZone(x: 0, y: 0, width: 100, height: 20),
    bottom: WorkspaceRevealZone(x: 0, y: 80, width: 100, height: 20),
  );
  check('正中不命中任何边', zones.edgeAt(xPercent: 50, yPercent: 50) == null);
  check('贴左命中左', zones.edgeAt(xPercent: 5, yPercent: 50) == RevealEdge.left);
  check('贴右命中右', zones.edgeAt(xPercent: 95, yPercent: 50) == RevealEdge.right);
  check('贴顶命中上', zones.edgeAt(xPercent: 50, yPercent: 5) == RevealEdge.top);
  check('贴底命中下', zones.edgeAt(xPercent: 50, yPercent: 95) == RevealEdge.bottom);
  // 左上角同时落在左与斯里 —— 换泳道比唤出顶栏更明确，所以左赢。
  check('两角重叠时左右优先于上下', zones.edgeAt(xPercent: 5, yPercent: 5) == RevealEdge.left);
  check('边界点算命中（含端点）', zones.edgeAt(xPercent: 20, yPercent: 50) == RevealEdge.left);
}

// ── JSON ──────────────────────────────────────────────────────────────────

void _jsonRoundTrip() {
  const zones = WorkspaceRevealZones(
    left: WorkspaceRevealZone(x: 0, y: 12.5, width: 3, height: 70),
    right: WorkspaceRevealZone(x: 97, y: 12.5, width: 3, height: 70),
    top: WorkspaceRevealZone(x: 20, y: 0, width: 60, height: 2.5),
    bottom: WorkspaceRevealZone(x: 20, y: 97.5, width: 60, height: 2.5),
  );
  final restored = WorkspaceRevealZones.fromJson(
    zones.toJson().cast<String, Object?>(),
  );
  check('四条边都往返得回来', restored == zones, '$restored');
}

void _lenientFromJson() {
  final json = WorkspaceRevealZones.defaults.toJson()
    ..['top'] = {'x': 'not a number', 'y': 5, 'width': 90, 'height': 4}
    ..['bottom'] = '不是对象';
  final restored = WorkspaceRevealZones.fromJson(json.cast<String, Object?>());
  // 手改坏一个数字不该让整块回到出厂：**一项坏只退回那一项**。
  check('top 里坏掉的 x 退回默认', restored.top.x == WorkspaceRevealZones.defaults.top.x);
  check('top 里合法的 y / 宽 / 高保住', restored.top.y == 5 && restored.top.width == 90 && restored.top.height == 4, '${restored.top}');
  check('整条不是对象时那一条回默认', restored.bottom == WorkspaceRevealZones.defaults.bottom);
  check('没被动过的左保住', restored.left == WorkspaceRevealZones.defaults.left);

  final outOfRange = WorkspaceRevealZones.fromJson(<String, Object?>{
    'left': <String, Object?>{'x': -50, 'y': 0, 'width': 999, 'height': 999},
  });
  check('越界的原点被夹回', outOfRange.left.x == 0);
  check('越界的宽高被夹回画布内', outOfRange.left.right <= 100 && outOfRange.left.bottom <= 100, '${outOfRange.left}');

  check('整块不是对象时回默认', WorkspaceRevealZones.fromJson(null) == WorkspaceRevealZones.defaults);
}
