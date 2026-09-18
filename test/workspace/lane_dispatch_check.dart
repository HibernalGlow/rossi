// 「推入落到哪个面板」的**纯 Dart** 判据。
//
// 本机 `flutter test` 起不来（flutter_tester 的 WebSocket 握手失败），
// 所以凡是能从 widget 里抽出来的判据都抽到这里，用
//   dart run test/workspace/lane_dispatch_check.dart
// 直接跑。**没有 package:test 依赖**，失败就抛 StateError 并以非零码退出。
//
// 这段记账值得单独立判据，因为它错的方式全是静默的：页面开进一个看不见的面板，
// 或者该接管时没接管（于是全屏盖住整个工作台）。两种都不报错、不抛异常。
//
// ignore_for_file: avoid_print
import 'package:zephyr/workspace/router/workspace_lane_dispatch.dart';

int _passed = 0;

void check(String label, bool condition, [String? detail]) {
  if (!condition) {
    throw StateError('FAIL: $label${detail == null ? '' : ' — $detail'}');
  }
  _passed++;
}

// 真实 id：左右泳道**各有一个面板**，身份必须是 (泳道, 面板)，不能只看面板。
const _leftBookshelf = WorkspaceLaneHost('left', 'bookshelf');
const _leftShelf = WorkspaceLaneHost('left', 'shelf');
const _rightDiscover = WorkspaceLaneHost('right', 'discover');
const _rightTools = WorkspaceLaneHost('right', 'tools');

/// 左泳道的书架与右泳道的书架：**面板名相同、泳道不同**。
///
/// 这一对才是「身份是 (泳道, 面板)」的判据 —— 上面那两组对照连
/// `panelId` 都不同，只比 `panelId` 的实现在它们面前照样通过。
const _leftShelfSameName = WorkspaceLaneHost('left', 'bookshelf');
const _rightShelfSameName = WorkspaceLaneHost('right', 'bookshelf');

WorkspaceLaneDispatch get _dispatch {
  final d = WorkspaceLaneDispatch.instance;
  d.reset();
  return d;
}

void main() {
  _hostIdentity();
  _noInteractionFallsThrough();
  _interactionPicksThatPanel();
  _liveHostReplacedByNewVisiblePanel();
  _returningToOldPanelDoesNotReviveRecord();
  _hiddenPanelCannotStealTarget();
  _unregisterClearsTarget();
  _unregisterIsOwnerScoped();
  _lastInteractionWinsAcrossLanes();
  _resetClearsEverything();
  print('lane_dispatch_check: $_passed checks passed');
}

// ── 场景 ──────────────────────────────────────────────────────────────────

void _hostIdentity() {
  check('同面板不同泳道不是同一个主机', _leftShelfSameName != _rightShelfSameName);
  check('同泳道不同面板不是同一个主机', _leftBookshelf != _leftShelf);
  check('值相等算同一个主机', _leftBookshelf == const WorkspaceLaneHost('left', 'bookshelf'));
  check(
    'hashCode 与相等性一致',
    _leftBookshelf.hashCode == const WorkspaceLaneHost('left', 'bookshelf').hashCode,
  );
  check(
    '同名不同泳道的 hashCode 也分开（否则会互相顶掉）',
    _leftShelfSameName.hashCode != _rightShelfSameName.hashCode,
  );
  check('可读标识带泳道前缀', _rightTools.debugKey == 'right/tools');
  check('同名不同泳道的标识不同', _leftShelfSameName.debugKey != _rightShelfSameName.debugKey);
}

/// 没人在泳道里点过 → 不接管（调用方应当原样放行全屏推入）。
void _noInteractionFallsThrough() {
  final d = _dispatch;
  d.registerHost(_rightTools);
  check('登记了但没交互 → 不接管', d.resolveTarget() == null);
}

/// 在哪条泳道的面板里按下的，就落回那里。
void _interactionPicksThatPanel() {
  final d = _dispatch;
  d.registerHost(_rightTools);
  d.noteInteraction(_rightTools);
  check('交互过的面板成为落点', d.resolveTarget() == _rightTools);
  check('落点记录得住', d.lastInteracted == _rightTools);
}

/// 同一条泳道换了可见面板 → 旧记录作废。
///
/// 留下的旧记录指向一个**已经不在屏幕上**的面板，会把这之后的一次推入
/// 开进隐藏面板里（用户看到的现象是「点了没反应」）。
void _liveHostReplacedByNewVisiblePanel() {
  final d = _dispatch;
  d.registerHost(_rightTools);
  d.noteInteraction(_rightTools);
  check('换面板前落点是它', d.resolveTarget() == _rightTools);

  d.registerHost(_rightDiscover);
  check('换面板后旧记录作废', d.resolveTarget() == null);
  check('活主机换成新的', d.liveHostOfLane('right') == _rightDiscover);

  d.noteInteraction(_rightDiscover);
  check('在新面板里点过之后落点跟上', d.resolveTarget() == _rightDiscover);
}

/// **切回**旧面板不算「用户又点过它」—— 旧记录不许复活。
///
/// 这条是单独一个场景，因为它钉的是**另一条实现**：上一条场景里
/// 「换面板后旧记录作废」既可以由 `registerHost` 的作废做到，也可以由
/// `resolveTarget` 的「记录 ∩ 仍活着」做到 —— 两条实现互为兜底，
/// 单删任一条，上一条场景都照样绿（变异验证实测如此）。
/// 判据必须各钉一条，否则「拿掉一半兜底」永远测不出来。
///
/// A → B → A 是唯一能分开它们的序列：记录停在 A，去 B，再回 A。
/// - 正确实现：去 B 那一步就把记录作废了，回 A 时**没有落点** ⇒ 不接管；
/// - 只靠求交：记录一直是 A，回到 A 时 A 恰好又「活着」 ⇒ 落点凭空复活。
void _returningToOldPanelDoesNotReviveRecord() {
  final d = _dispatch;
  d.registerHost(_rightTools);
  d.noteInteraction(_rightTools);

  d.registerHost(_rightDiscover); // 切走（没在 discover 里点过）
  d.registerHost(_rightTools); // 又切回来

  check('切回来但没重新交互 → 不接管', d.resolveTarget() == null, '旧记录复活了');
  check('活主机确实是切回来的那个', d.liveHostOfLane('right') == _rightTools);

  // 真的点一次，才重新有落点。
  d.noteInteraction(_rightTools);
  check('重新交互后落点回来', d.resolveTarget() == _rightTools);
}

/// 不可见的面板**抢不走**落点。
///
/// `IndexedStack` 会把访问过的面板都留在树里（切走不重建、不丢滚动位置），
/// 它们的 `Listener` 也还挂着 —— 没有这条约束，隐藏面板就能偷偷改写落点。
void _hiddenPanelCannotStealTarget() {
  final d = _dispatch;
  d.registerHost(_rightTools);
  d.noteInteraction(_rightDiscover); // 没登记的（隐藏的）面板上报交互
  check('未登记面板的交互被忽略', d.lastInteracted == null);
  check('落点仍为空', d.resolveTarget() == null);

  d.noteInteraction(_rightTools);
  check('登记过的那一个才记得住', d.resolveTarget() == _rightTools);
}

/// 面板被卸载（泳道收起 / 模式切换 / 工作台退出）→ 不再往那儿开。
void _unregisterClearsTarget() {
  final d = _dispatch;
  d.registerHost(_rightTools);
  d.noteInteraction(_rightTools);
  d.unregisterHost(_rightTools);
  check('注销后不接管', d.resolveTarget() == null);
  check('交互记录也清掉', d.lastInteracted == null);
}

/// 注销是**只注销自己**的：退出动画里的旧面板不能抹掉刚上来的新面板。
void _unregisterIsOwnerScoped() {
  final d = _dispatch;
  d.registerHost(_rightTools);
  d.registerHost(_rightDiscover);
  d.unregisterHost(_rightTools); // 旧面板的 dispose 迟到
  check('旧面板的注销不影响新面板', d.liveHostOfLane('right') == _rightDiscover);

  d.noteInteraction(_rightDiscover);
  check('仍然能接管', d.resolveTarget() == _rightDiscover);
}

/// 两条泳道各有各的面板，但落点只有**最后交互的那一个**。
void _lastInteractionWinsAcrossLanes() {
  final d = _dispatch;
  d.registerHost(_leftBookshelf);
  d.registerHost(_rightTools);

  d.noteInteraction(_leftBookshelf);
  check('先点在左泳道 → 落左泳道', d.resolveTarget() == _leftBookshelf);

  d.noteInteraction(_rightTools);
  check('再点在右泳道 → 落右泳道', d.resolveTarget() == _rightTools);

  // 右泳道换面板时只作废右泳道的记录；左泳道此刻也不是落点了（最后交互已换）。
  d.registerHost(_rightDiscover);
  check('右泳道换面板后落点为空', d.resolveTarget() == null);
  check('左泳道的登记没被动过', d.liveHostOfLane('left') == _leftBookshelf);

  // 跨泳道**不是**同一个主机：左泳道那个品牌的面板不该被右泳道的记录顶掉。
  check('左右泳道的活主机各自独立', d.liveHostOfLane('right') == _rightDiscover);
}

void _resetClearsEverything() {
  final d = _dispatch;
  d.registerHost(_leftBookshelf);
  d.noteInteraction(_leftBookshelf);
  d.reset();
  check('reset 清掉落点', d.resolveTarget() == null);
  check('reset 清掉活主机', d.liveHostOfLane('left') == null);
}
