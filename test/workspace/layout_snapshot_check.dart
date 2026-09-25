// 工作台布局**快照往返**的纯 Dart 判据 —— 「重启之后回来的是不是同一套布局」
// 这件事的唯一证据。
//
//   dart run test/workspace/layout_snapshot_check.dart
//
// 断言方式是**深度比较两份 JSON**（而不是逐字段挑几个比）：只比几项的话，
// 新加一个字段忘了写进 `toJson` 就会静默通过，而它的后果恰恰是
// 「这个设置重启就没了」—— 也就是本次要修的那个问题本身。
//
// 另一半是**退化**：配置文件被手改坏时，坏掉的那一项退回默认，
// 其余各项必须**原样保留**。整组判废是最糟的失败方式 —— 用户只是手滑改错一个数字，
// 却把整套布局弄丢了。
//
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_interaction_settings.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/model/workspace_panel_bar.dart';
import 'package:zephyr/workspace/model/workspace_reveal_zones.dart';

int _passed = 0;

/// 一份**刻意不对称**的唤出区：四条边各不相同、且带 0.1 的小数。
///
/// 对称的值（左右同宽、整数）会让「右泳道读成了左泳道」这类错位静默通过。
const WorkspaceRevealZones _richZones = WorkspaceRevealZones(
  left: WorkspaceRevealZone(x: 0, y: 12.5, width: 3, height: 70),
  right: WorkspaceRevealZone(x: 97, y: 12.5, width: 3, height: 70),
  top: WorkspaceRevealZone(x: 20, y: 0, width: 60, height: 2.5),
  bottom: WorkspaceRevealZone(x: 20, y: 97.5, width: 60, height: 2.5),
);

void check(String label, bool condition, [String? detail]) {
  if (!condition) {
    throw StateError('FAIL: $label${detail == null ? '' : ' — $detail'}');
  }
  _passed++;
}

/// 深度相等（顺序无关地比 Map 的键，List 按序比）。
bool _sameJson(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!_sameJson(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameJson(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// 走一遍真实的持久化路径：编码成 JSON 文本、再解回来。
WorkspaceLayoutSnapshot? _throughDisk(WorkspaceLayoutSnapshot snapshot) {
  final text = jsonEncode(snapshot.toJson());
  final decoded = jsonDecode(text);
  final json = WorkspaceLayoutSnapshot.decode(decoded);
  if (json == null) return null;
  return WorkspaceLayoutSnapshot.fromJson(json);
}

void main() {
  _defaultsRoundTrip();
  _fullCustomStateRoundTrip();
  _unknownVersionIsRejected();
  _nonObjectIsRejected();
  _unknownLaneIdsInOrderAreDroppedAndMissingOnesAppended();
  _danglingSoloLaneIsDropped();
  _badLaneFieldFallsBackWithoutLosingTheRestOfThatLane();
  _activePanelAndActiveLanePointingNowhereAreDropped();
  _badInteractionFieldsFallBackPerField();
  _badBoardEntriesAreDroppedAndGoodOnesKept();
  _transientThingsAreNotInTheSnapshot();

  print('layout_snapshot_check: $_passed checks passed');
}

/// 出厂状态往返之后仍然是出厂状态。
void _defaultsRoundTrip() {
  final defaults = WorkspaceLayoutSnapshot.defaults();
  final restored = _throughDisk(defaults);
  check('默认快照能读回来', restored != null);
  check('默认快照逐项往返无损', _sameJson(restored!.toJson(), defaults.toJson()));
  check('默认模式是泳道', restored.mode == WorkspaceMode.swimlane);
  check('默认没有激活泳道', restored.activeLaneId == null);
}

/// 一整套被用户改过的状态（每一项都非默认）往返无损。
void _fullCustomStateRoundTrip() {
  final defaults = WorkspaceLayoutSnapshot.defaults();
  final lanes = Map<String, LaneConfig>.from(defaults.layout.lanes);

  // 左侧：折叠 + 宽度改过 + 面板栏拖成了竖轨。
  lanes[LaneId.left] = lanes[LaneId.left]!.copyWith(
    width: 421.5,
    collapsed: true,
    panelBar: const PanelBarLayout(
      mode: PanelBarMode.pinned,
      dock: PanelBarDock.left,
      constrained: false,
    ),
  );
  // 阅读器：比例改过 + 面板栏悬浮在右下。
  lanes[LaneId.reader] = lanes[LaneId.reader]!.copyWith(
    width: 733.25,
    widthRatio: () => 0.37,
    panelBar: const PanelBarLayout(
      mode: PanelBarMode.floating,
      dock: PanelBarDock.bottom,
      positionX: 78.5,
      positionY: 22.25,
      constrained: true,
    ),
  );

  final snapshot = WorkspaceLayoutSnapshot(
    mode: WorkspaceMode.edges,
    layout: WorkspaceLayoutConfig(
      laneOrder: const [
        LaneId.right,
        LaneId.reader,
        LaneId.left,
      ], // 用户把右泳道拖到了最左
      lanes: lanes,
      soloLaneId: LaneId.reader,
      edgeLeftOpen: true,
      edgeBottomOpen: true,
    ),
    board: const WorkspaceBoardLayout(
      panels: {
        'shelf': PanelLayout(
          visible: false,
          order: 3,
          side: WorkspacePanelSide.left,
        ),
      },
      cards: {
        'history_shelf': CardLayout(
          panelId: 'sources',
          visible: true,
          order: 2,
          expanded: false,
        ),
      },
    ),
    activePanel: const {'left': 'shelf', 'right': 'tools'},
    activeLaneId: LaneId.reader,
    interaction: const WorkspaceInteractionSettings(
      hoverFocusEnabled: false,
      panelHoverFocusEnabled: false,
      hoverFocusDelayMs: 250,
      edgeRevealDelayMs: 150,
      edgeRevealRestoreDelayMs: 900,
      revealFocusesLane: false,
      readerPeekWidth: 72,
      autoSoloOnFocus: true,
      showLaneNavigatorInSolo: true,
      manualScrollEnabled: false,
      showTopChrome: true,
      revealZones: _richZones,
    ),
  );

  final restored = _throughDisk(snapshot);
  check('自定义快照能读回来', restored != null);
  check(
    '自定义快照逐项往返无损（含泳道顺序、比例、折叠、面板栏、记账、延时）',
    _sameJson(restored!.toJson(), snapshot.toJson()),
    '${restored.toJson()}',
  );
  check('泳道顺序保住了重排', restored.layout.laneOrder.first == LaneId.right);
  check('比例泳道的比例保住了', restored.layout.lanes[LaneId.reader]!.widthRatio == 0.37);
  check('折叠保住了', restored.layout.lanes[LaneId.left]!.collapsed);
  check(
    '悬浮面板栏的位置与约束都保住了',
    restored.layout.lanes[LaneId.reader]!.panelBar.mode ==
            PanelBarMode.floating &&
        restored.layout.lanes[LaneId.reader]!.panelBar.positionX == 78.5 &&
        restored.layout.lanes[LaneId.reader]!.panelBar.constrained,
  );
  check('solo 偏好保住了', restored.layout.soloLaneId == LaneId.reader);
  check(
    '四边栏抽屉状态保住了',
    restored.layout.edgeLeftOpen && !restored.layout.edgeRightOpen,
  );
  check('激活面板保住了', restored.activePanel['right'] == 'tools');
  check('激活泳道保住了', restored.activeLaneId == LaneId.reader);
  check('悬停聚焦开关保住了', !restored.interaction.hoverFocusEnabled);
  check('面板泳道悬停聚焦开关保住了', !restored.interaction.panelHoverFocusEnabled);
  check('呼出后自动聚焦开关保住了', !restored.interaction.revealFocusesLane);
  check(
    '三个延时保住了',
    restored.interaction.hoverFocusDelayMs == 250 &&
        restored.interaction.edgeRevealDelayMs == 150 &&
        restored.interaction.edgeRevealRestoreDelayMs == 900,
  );
  check('Reader 窄缝宽保住了', restored.interaction.readerPeekWidth == 72);
  check('自动独占开关保住了', restored.interaction.autoSoloOnFocus);
  check('独占时显示切换栏保住了', restored.interaction.showLaneNavigatorInSolo);
  check('「允许手动横向滚动」关掉这件事保住了', !restored.interaction.manualScrollEnabled);
  check('「顶栏画出来」这件事保住了（出厂默认是不画）', restored.interaction.showTopChrome);
  check(
    '四条唤出区整体保住（含 0.1 的百分比精度）',
    restored.interaction.revealZones == _richZones,
    '${restored.interaction.revealZones.toJson()}',
  );
  check('被收起的面板保住了', restored.board.panelLayout('shelf')!.visible == false);
  check(
    '卡片换过面板 + 折叠态保住了',
    restored.board.cardLayout('history_shelf')!.panelId == 'sources' &&
        !restored.board.cardLayout('history_shelf')!.expanded,
  );
}

/// 快照格式版本不认识 ⇒ 当作「读不出来」（回默认），而不是猜着解析。
void _unknownVersionIsRejected() {
  check(
    '版本不匹配 → 拒绝',
    WorkspaceLayoutSnapshot.decode(const {'version': 999}) == null,
  );
  check(
    '没有版本字段 → 拒绝',
    WorkspaceLayoutSnapshot.decode(const {'mode': 'edges'}) == null,
  );
  check(
    '版本正确 → 接受',
    WorkspaceLayoutSnapshot.decode(const {
          'version': WorkspaceLayoutSnapshot.currentVersion,
        }) !=
        null,
  );
}

void _nonObjectIsRejected() {
  check('解出来是列表 → 拒绝', WorkspaceLayoutSnapshot.decode(const [1, 2]) == null);
  check('解出来是字符串 → 拒绝', WorkspaceLayoutSnapshot.decode('nope') == null);
  check('解出来是 null → 拒绝', WorkspaceLayoutSnapshot.decode(null) == null);
}

/// `laneOrder` 归一化：未知 id 丢掉、缺的补上（将来加泳道不需要写迁移）。
void _unknownLaneIdsInOrderAreDroppedAndMissingOnesAppended() {
  final snapshot = WorkspaceLayoutSnapshot.fromJson(const <String, Object?>{
    'version': 1,
    'layout': <String, Object?>{
      'laneOrder': ['right', 'ghost_lane', 'left'],
    },
  });

  check(
    '未知泳道被丢掉',
    !snapshot.layout.laneOrder.contains('ghost_lane'),
    '${snapshot.layout.laneOrder}',
  );
  check(
    '已知泳道保持用户给的相对顺序',
    snapshot.layout.laneOrder.take(2).join(',') == 'right,left',
    '${snapshot.layout.laneOrder}',
  );
  check(
    '缺掉的已知泳道按默认顺序补到末尾（reader 不会消失）',
    snapshot.layout.laneOrder.contains(LaneId.reader),
    '${snapshot.layout.laneOrder}',
  );
  check(
    '一条泳道都不丢',
    snapshot.layout.laneOrder.length == LaneId.defaultOrder.length,
  );
}

/// solo 指向一条不存在的泳道 ⇒ 丢掉（否则条带永远算不出独占泳道）。
void _danglingSoloLaneIsDropped() {
  final snapshot = WorkspaceLayoutSnapshot.fromJson(const <String, Object?>{
    'version': 1,
    'layout': <String, Object?>{
      'soloLaneId': 'ghost_lane',
      'lanes': <String, Object?>{
        'reader': <String, Object?>{'collapsed': true},
      },
    },
  });
  check('悬空的 solo 记录被丢掉', snapshot.layout.soloLaneId == null);
  check(
    '同一块里合法的字段不受影响（reader 的折叠保住了）',
    snapshot.layout.lanes[LaneId.reader]!.collapsed,
  );
}

/// 一条泳道里坏掉一个字段：它退回默认，**这条泳道的其它字段不受影响**。
void _badLaneFieldFallsBackWithoutLosingTheRestOfThatLane() {
  final snapshot = WorkspaceLayoutSnapshot.fromJson(const <String, Object?>{
    'version': 1,
    'layout': <String, Object?>{
      'lanes': <String, Object?>{
        'left': <String, Object?>{'width': 'wide', 'collapsed': true},
        'right': <String, Object?>{'width': 512, 'panelBar': 'nope'},
      },
    },
  });

  final left = snapshot.layout.lanes[LaneId.left]!;
  check(
    '非法宽度退回默认宽度',
    left.width == WorkspaceLayoutConfig.defaults().lanes[LaneId.left]!.width,
    '${left.width}',
  );
  check('同一条泳道的折叠没被连带丢掉', left.collapsed);

  final right = snapshot.layout.lanes[LaneId.right]!;
  check('右泳道的合法宽度保住了', right.width == 512);
  check('非法面板栏退回默认面板栏', right.panelBar == const PanelBarLayout());
}

/// 指向不存在的泳道 / 空面板 id 的「激活面板」记录丢掉。
void _activePanelAndActiveLanePointingNowhereAreDropped() {
  final snapshot = WorkspaceLayoutSnapshot.fromJson(const <String, Object?>{
    'version': 1,
    'activePanel': <String, Object?>{
      'left': 'shelf',
      'ghost_lane': 'shelf',
      'right': '',
    },
    'activeLaneId': 'ghost_lane',
  });
  check('合法记录留住', snapshot.activePanel['left'] == 'shelf');
  check('指向不存在泳道的记录丢掉', !snapshot.activePanel.containsKey('ghost_lane'));
  check('空面板 id 丢掉', !snapshot.activePanel.containsKey('right'));
  check('指向不存在泳道的激活泳道丢掉', snapshot.activeLaneId == null);
}

/// 交互设置里坏掉一项只影响那一项；非正延时退回默认（0 延时会横跳）。
void _badInteractionFieldsFallBackPerField() {
  const fallback = WorkspaceInteractionSettings();
  final snapshot = WorkspaceLayoutSnapshot.fromJson(const <String, Object?>{
    'version': 1,
    'interaction': <String, Object?>{
      'hoverFocusEnabled': 'yes',
      'panelHoverFocusEnabled': 'nope',
      'hoverFocusDelayMs': 0,
      'edgeRevealDelayMs': -5,
      'edgeRevealRestoreDelayMs': 640,
      'readerPeekWidth': 9999,
      'autoSoloOnFocus': 'yes',
      'showLaneNavigatorInSolo': true,
      'revealZones': '不是对象',
    },
  });

  check(
    '非布尔开关退回默认',
    snapshot.interaction.hoverFocusEnabled == fallback.hoverFocusEnabled,
  );
  check('非布尔的「面板悬停聚焦」退回默认（开）', snapshot.interaction.panelHoverFocusEnabled);
  check(
    '缺项的「呼出后自动聚焦」退回默认（开 —— 老快照升级后这两项默认生效，是刻意的）',
    snapshot.interaction.revealFocusesLane == fallback.revealFocusesLane &&
        fallback.revealFocusesLane,
  );
  check(
    '0 延时退回默认（0 会横跳）',
    snapshot.interaction.hoverFocusDelayMs == fallback.hoverFocusDelayMs,
  );
  check(
    '负延时退回默认',
    snapshot.interaction.edgeRevealDelayMs == fallback.edgeRevealDelayMs,
  );
  check('合法的延时保住', snapshot.interaction.edgeRevealRestoreDelayMs == 640);
  check('越界的缝宽被夹到 400', snapshot.interaction.readerPeekWidth == 400);
  check('非布尔的自动独占退回默认（关）', !snapshot.interaction.autoSoloOnFocus);
  check('合法的切换栏「开」保住', snapshot.interaction.showLaneNavigatorInSolo);
  check(
    '缺项的「允许手动滚动」退回默认（开 —— 保持改造前的手感）',
    snapshot.interaction.manualScrollEnabled,
  );
  check(
    '缺项的「全屏时禁止横向拖动泳道」退回默认（开 —— 老快照升级后直接生效）',
    snapshot.interaction.blockManualScrollInReaderFullscreen,
  );
  check(
    '缺项的「顶栏」退回默认（关）—— 老快照里没有这个键，升级之后顶栏就是不画',
    !snapshot.interaction.showTopChrome,
  );
  check(
    '唤出区整块不是对象时回默认，且不牵连别的项',
    snapshot.interaction.revealZones == WorkspaceRevealZones.defaults &&
        snapshot.interaction.edgeRevealRestoreDelayMs == 640,
  );
}

/// 记账里非法的项丢掉、合法的留住。
void _badBoardEntriesAreDroppedAndGoodOnesKept() {
  final snapshot = WorkspaceLayoutSnapshot.fromJson(const <String, Object?>{
    'version': 1,
    'board': <String, Object?>{
      'panels': <String, Object?>{
        'shelf': <String, Object?>{
          'visible': false,
          'order': 1,
          'side': 'left',
        },
        'tools': <String, Object?>{
          'visible': 'no',
          'order': 2,
          'side': 'right',
        },
        'sources': <String, Object?>{
          'visible': true,
          'order': 0,
          'side': 'diagonal',
        },
      },
      'cards': <String, Object?>{
        'history_shelf': <String, Object?>{
          'panelId': 'shelf',
          'visible': true,
          'order': 0,
        },
        'download_shelf': <String, Object?>{'panelId': 42},
      },
    },
  });

  check('合法面板项留住', snapshot.board.panelLayout('shelf')!.visible == false);
  check('visible 非法的面板项丢掉', snapshot.board.panelLayout('tools') == null);
  check('side 不认识的面板项丢掉', snapshot.board.panelLayout('sources') == null);
  check(
    '合法卡片项留住（expanded 缺省补 true）',
    snapshot.board.cardLayout('history_shelf')!.expanded,
  );
  check(
    'panelId 非字符串的卡片项丢掉',
    snapshot.board.cardLayout('download_shelf') == null,
  );
}

/// **瞬态项不在快照里**（契约：`Transient edge reveal and live scroll offset
/// are not persisted`）。这条用「键不存在」来验 —— 将来有人把滚动偏移加进来
/// （看起来很方便），这里会红。
void _transientThingsAreNotInTheSnapshot() {
  final json = WorkspaceLayoutSnapshot.defaults().toJson();
  check(
    '没有实时滚动偏移',
    !json.containsKey('scrollOffset') && !json.containsKey('stripOffset'),
  );
  check('没有瞬态边缘揭示', !json.containsKey('revealedLaneId'));
  check('没有当前在读的那一本', !json.containsKey('readerTarget'));
  check(
    '顶层键就是约定的那几个',
    _sameJson(json.keys.toList()..sort(), const [
      'activeLaneId',
      'activePanel',
      'board',
      'interaction',
      'layout',
      'mode',
      'version',
    ]),
    '${json.keys.toList()}',
  );
}
