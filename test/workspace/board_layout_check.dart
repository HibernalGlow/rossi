// 面板 / 卡片布局记账的**纯 Dart** 判据。
//
// 本机 `flutter test` 起不来（flutter_tester 的 WebSocket 握手失败），
// 所以凡是能从 widget 里抽出来的判据都抽到这里，用
//   dart run test/workspace/board_layout_check.dart
// 直接跑。**没有 package:test 依赖**，失败就抛 StateError 并以非零码退出。
//
// ignore_for_file: avoid_print
import 'package:zephyr/workspace/model/workspace_board_layout.dart';

int _passed = 0;

void check(String label, bool condition, [String? detail]) {
  if (!condition) {
    throw StateError('FAIL: $label${detail == null ? '' : ' — $detail'}');
  }
  _passed++;
}

void main() {
  _panelPlacement();
  _panelCrossLane();
  _panelVisibility();
  _cardMove();
  _cardTieBreak();
  _cardPlaceAcrossPanels();
  _cardVisibilityAndExpansion();
  print('board_layout_check: $_passed checks passed');
}

// ── 面板 ──────────────────────────────────────────────────────────────────

void _panelPlacement() {
  const board = WorkspaceBoardLayout();

  final moved = board.placePanel(
    panelId: 'sources',
    side: WorkspacePanelSide.right,
    siblingIds: const ['discover', 'tools'],
    insertIndex: 0,
  );
  check('面板重排后自己在第 0 位', moved.panelLayout('sources')?.order == 0);
  check('兄弟依次后移', moved.panelLayout('discover')?.order == 1);
  check('兄弟二也后移', moved.panelLayout('tools')?.order == 2);
  check(
    '重排保留同侧',
    moved.panelLayout('sources')?.side == WorkspacePanelSide.right,
  );
  check('重排后面板可见', moved.panelLayout('sources')?.visible == true);
}

void _panelCrossLane() {
  const board = WorkspaceBoardLayout();

  final moved = board.placePanel(
    panelId: 'sources',
    side: WorkspacePanelSide.left,
    siblingIds: const ['shelf'],
    insertIndex: 1,
  );
  check(
    '跨泳道后面板换了 side',
    moved.panelLayout('sources')?.side == WorkspacePanelSide.left,
  );
  check('跨泳道后次序按落点算', moved.panelLayout('sources')?.order == 1);
  check('落点前面的兄弟不变', moved.panelLayout('shelf')?.order == 0);

  final clamped = board.placePanel(
    panelId: 'sources',
    side: WorkspacePanelSide.left,
    siblingIds: const ['shelf'],
    insertIndex: 99,
  );
  check('越界插入下标被夹到末尾', clamped.panelLayout('sources')?.order == 1);
}

void _panelVisibility() {
  const board = WorkspaceBoardLayout();
  final hidden = board.setPanelVisible(
    panelId: 'sources',
    side: WorkspacePanelSide.right,
    order: 1,
    visible: false,
  );
  check('隐藏面板', hidden.panelLayout('sources')?.visible == false);
  check(
    '隐藏不改 side',
    hidden.panelLayout('sources')?.side == WorkspacePanelSide.right,
  );
}

// ── 卡片 ──────────────────────────────────────────────────────────────────

void _cardMove() {
  const board = WorkspaceBoardLayout();
  const order = ['favorite', 'history', 'download'];

  final moved = board.moveCard('download', -1, order);
  check('上移不是空操作', moved != null);
  check('上移后次序换了', moved!.cardLayout('download')?.order == 1);
  check('被换下去的卡补到原下标', moved.cardLayout('history')?.order == 2);
  // 一次移动把**整条面板的次序钉下来**：没被换到的那张也写下 0，
  // 否则它的次序要靠默认值推、与已显式记录的兄弟混在一起容易打架。
  check('没被换到的卡也写下自己的位次', moved.cardLayout('favorite')?.order == 0);

  check('首项上移返回 null', board.moveCard('favorite', -1, order) == null);
  check('末项下移返回 null', board.moveCard('download', 1, order) == null);
  check('不在序列里的卡返回 null', board.moveCard('nope', 1, order) == null);
}

void _cardTieBreak() {
  // 次序必须是**全序**：order 相同按 id 字典序，否则同一份配置在不同构建里
  // 会排出不同的轨，图标位置莫名其妙地漂。
  final ordered = sortByOrder(
    const ['b', 'a', 'c'],
    (id) => id == 'c' ? 0 : 1,
  );
  check('order 小者在前', ordered.first == 'c');
  check('order 相同时按 id 字典序', ordered[1] == 'a' && ordered[2] == 'b');
}

void _cardPlaceAcrossPanels() {
  const board = WorkspaceBoardLayout();

  final moved = board.placeCard(
    cardId: 'local_folder',
    panelId: 'shelf',
    siblingCardIds: const ['history', 'favorite'],
    insertIndex: 1,
    fallbackFor: (id) =>
        const CardLayout(panelId: 'sources', visible: true, order: 0),
  );
  check('卡片换了面板', moved.cardLayout('local_folder')?.panelId == 'shelf');
  check('卡片落在指定下标', moved.cardLayout('local_folder')?.order == 1);
  check('落点前的兄弟重新编号', moved.cardLayout('history')?.order == 0);
  check('落点后的兄弟重新编号', moved.cardLayout('favorite')?.order == 2);
  // 同一次搬移把**目标面板里所有卡**都显式记成这个面板：否则兄弟的归属
  // 要靠它们各自的默认值推，一旦有人默认值不同，面板成员关系就会自相矛盾。
  check('兄弟也显式记入目标面板', moved.cardLayout('favorite')?.panelId == 'shelf');
  check('没有记录时用兜底值补展开态', moved.cardLayout('local_folder')?.expanded == true);
}

void _cardVisibilityAndExpansion() {
  const board = WorkspaceBoardLayout();

  final hidden = board.setCardVisible(
    cardId: 'download',
    panelId: 'shelf',
    order: 2,
    visible: false,
  );
  check('隐藏卡片', hidden.cardLayout('download')?.visible == false);

  // 展开态与可见性互不覆盖：折叠一张卡不该把它重新显示出来。
  final collapsed = hidden.setCardExpanded(
    cardId: 'download',
    panelId: 'shelf',
    order: 2,
    expanded: false,
  );
  check('折叠生效', collapsed.cardLayout('download')?.expanded == false);
  check('折叠不改变可见性', collapsed.cardLayout('download')?.visible == false);
  check('折叠不改变归属', collapsed.cardLayout('download')?.panelId == 'shelf');
}
