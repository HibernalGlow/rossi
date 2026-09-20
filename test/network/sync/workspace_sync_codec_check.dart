// 工作台布局**跨设备同步块**的纯 Dart 判据。
//
//   dart run test/network/sync/workspace_sync_codec_check.dart
//
// 验的是两件事，各自对应一类**不会报错**的失败：
//
// 1. **该带走的都得带走**（往返后深度相等）。少带一项的表现是「A 机摆好的东西
//    在 B 机上没出现」，日志里干干净净；
// 2. **不该带走的必须按本位活着**（`activeLaneId`、四个抽屉开关）。带走它们的
//    表现是「B 机一启动，四边栏抽屉自己全拉开了 / 交互跳到别的泳道」，
//    同样不报错，而且用户找不到是谁干的。
//
// 深度比较两份 JSON（而不是挑几个字段比）：新加一个字段忘了进编码器就会静默通过，
// 而它的后果恰恰是「这个设置同步不过去」—— 也就是本次要修的那个问题本身。
//
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:zephyr/network/sync/workspace_sync_codec.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_interaction_settings.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/model/workspace_panel_bar.dart';
import 'package:zephyr/workspace/model/workspace_reveal_zones.dart';

int _passed = 0;

void check(String label, bool condition, [String? detail]) {
  if (!condition) {
    throw StateError('FAIL: $label${detail == null ? '' : ' — $detail'}');
  }
  _passed++;
}

/// 深度相等（Map 比键，List 按序比）。
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

/// 四条边各不相同、带 0.1 的小数 —— 对称的整数唤出区会让「左右读反」静默通过。
const WorkspaceRevealZones _richZones = WorkspaceRevealZones(
  left: WorkspaceRevealZone(x: 0, y: 12.5, width: 3, height: 70),
  right: WorkspaceRevealZone(x: 97, y: 12.5, width: 3, height: 70),
  top: WorkspaceRevealZone(x: 20, y: 0, width: 60, height: 2.5),
  bottom: WorkspaceRevealZone(x: 20, y: 97.5, width: 60, height: 2.5),
);

/// A 机：一处**处处非默认**的布局（每个字段都换掉默认值，默认值相等会让
/// 「这一项根本没进编码器」静默通过）。
WorkspaceLayoutSnapshot _deviceA() => WorkspaceLayoutSnapshot(
  mode: WorkspaceMode.edges,
  layout: WorkspaceLayoutConfig(
    laneOrder: const [LaneId.reader, LaneId.left, LaneId.right],
    lanes: const {
      LaneId.left: LaneConfig(
        width: 411.5,
        minWidth: 301.5,
        maxWidth: 640.25,
        collapsed: true,
        title: '书架',
        panelBar: PanelBarLayout(
          mode: PanelBarMode.floating,
          dock: PanelBarDock.bottom,
          positionX: 12.5,
          positionY: 88.5,
          constrained: false,
        ),
      ),
      LaneId.reader: LaneConfig(
        width: 777.5,
        widthRatio: 0.375,
        minWidth: 401.25,
        maxWidth: 1800.5,
        title: '阅读器',
      ),
      LaneId.right: LaneConfig(width: 322.5, title: '工具'),
    },
    soloLaneId: LaneId.right,
  ),
  board: const WorkspaceBoardLayout(
    panels: {
      'shelf': PanelLayout(visible: true, order: 0, side: WorkspacePanelSide.left),
      'tools': PanelLayout(visible: false, order: 1, side: WorkspacePanelSide.right),
    },
    cards: {
      'favorite': CardLayout(panelId: 'shelf', visible: true, order: 0),
      'download': CardLayout(
        panelId: 'tools',
        visible: false,
        order: 2,
        expanded: false,
      ),
    },
  ),
  activePanel: const {LaneId.left: 'shelf', LaneId.right: 'tools'},
  activeLaneId: LaneId.reader,
  interaction: const WorkspaceInteractionSettings(
    hoverFocusEnabled: false,
    hoverFocusDelayMs: 111,
    edgeRevealDelayMs: 222,
    edgeRevealRestoreDelayMs: 333,
    readerPeekWidth: 61.5,
    autoSoloOnFocus: true,
    showLaneNavigatorInSolo: true,
    manualScrollEnabled: false,
    showTopChrome: true,
    revealZones: _richZones,
  ),
);

/// B 机：一份**本机独有的部分与 A 完全不同**的布局（四个抽屉全开、
/// 激活泳道在左栏），用来证明这些字段没被云端改写。
WorkspaceLayoutSnapshot _deviceB() => WorkspaceLayoutSnapshot(
  mode: WorkspaceMode.swimlane,
  layout: WorkspaceLayoutConfig.defaults().copyWith(
    edgeLeftOpen: true,
    edgeRightOpen: true,
    edgeTopOpen: true,
    edgeBottomOpen: true,
  ),
  board: const WorkspaceBoardLayout(),
  activePanel: const {LaneId.reader: 'page-list'},
  activeLaneId: LaneId.left,
  interaction: const WorkspaceInteractionSettings(),
);

void main() {
  _roundTripKeepsEverything();
  _localOnlyFieldsStayLocal();
  _encodingIsStable();
  _localOnlyFieldsDoNotChangeTheHash();
  _brokenBlocksDegradePerBlock();
  _strayActivePanelRecordsAreDropped();
  _usableBlockHeuristic();
  print('workspace_sync_codec_check: $_passed checks passed');
}

// ── 1. 该带走的都带走 ────────────────────────────────────────────────────

void _roundTripKeepsEverything() {
  final source = _deviceA();
  final target = _deviceB();
  final decoded = WorkspaceSyncCodec.decode(
    WorkspaceSyncCodec.encode(source),
    base: target,
  );

  check('模式取云端', decoded.mode == WorkspaceMode.edges);
  check(
    '泳道顺序取云端',
    decoded.layout.laneOrder.join(',') == 'reader,left,right',
    decoded.layout.laneOrder.join(','),
  );
  check('泳道宽度取云端', decoded.layout.lanes[LaneId.left]!.width == 411.5);
  check('阅读器宽度比例取云端', decoded.layout.lanes[LaneId.reader]!.widthRatio == 0.375);
  check('折叠状态取云端', decoded.layout.lanes[LaneId.left]!.collapsed);
  check('泳道标题取云端', decoded.layout.lanes[LaneId.left]!.title == '书架');
  check(
    '面板栏模式取云端',
    decoded.layout.lanes[LaneId.left]!.panelBar.mode == PanelBarMode.floating,
  );
  check(
    '面板栏停靠边取云端',
    decoded.layout.lanes[LaneId.left]!.panelBar.dock == PanelBarDock.bottom,
  );
  check(
    '面板栏悬浮位置取云端',
    decoded.layout.lanes[LaneId.left]!.panelBar.positionX == 12.5 &&
        decoded.layout.lanes[LaneId.left]!.panelBar.positionY == 88.5,
  );
  check(
    '面板栏不限制在泳道内取云端',
    !decoded.layout.lanes[LaneId.left]!.panelBar.constrained,
  );
  check('solo 取云端', decoded.layout.soloLaneId == LaneId.right);

  check(
    '面板位置取云端',
    decoded.board.panelLayout('tools')?.side == WorkspacePanelSide.right &&
        decoded.board.panelLayout('tools')?.order == 1,
  );
  check('面板可见性取云端', decoded.board.panelLayout('tools')?.visible == false);
  check(
    '卡片归属面板取云端',
    decoded.board.cardLayout('download')?.panelId == 'tools',
  );
  check('卡片次序取云端', decoded.board.cardLayout('download')?.order == 2);
  check('卡片折叠取云端', decoded.board.cardLayout('download')?.expanded == false);
  check('卡片可见性取云端', decoded.board.cardLayout('download')?.visible == false);

  check(
    '激活面板取云端',
    decoded.activePanel[LaneId.left] == 'shelf' &&
        decoded.activePanel[LaneId.right] == 'tools',
  );

  check('悬停聚焦开关取云端', !decoded.interaction.hoverFocusEnabled);
  check('悬停聚焦延时取云端', decoded.interaction.hoverFocusDelayMs == 111);
  check('边缘揭示延时取云端', decoded.interaction.edgeRevealDelayMs == 222);
  check('揭示恢复延时取云端', decoded.interaction.edgeRevealRestoreDelayMs == 333);
  check('Reader 窄缝宽取云端', decoded.interaction.readerPeekWidth == 61.5);
  check('聚焦即独占取云端', decoded.interaction.autoSoloOnFocus);
  check('solo 里留泳道导航取云端', decoded.interaction.showLaneNavigatorInSolo);
  check('手动横向拖动取云端', !decoded.interaction.manualScrollEnabled);
  check('工作台顶栏取云端', decoded.interaction.showTopChrome);
  check(
    '唤出区取云端',
    _sameJson(decoded.interaction.revealZones.toJson(), _richZones.toJson()),
  );

  // 整体深度比较：上面逐项挑的是「会不会漏」，这一条管「会不会多」——
  // 比如顺手把 activeLaneId 也带过来了。
  final expected = WorkspaceLayoutSnapshot(
    mode: source.mode,
    layout: source.layout.copyWith(
      edgeLeftOpen: target.layout.edgeLeftOpen,
      edgeRightOpen: target.layout.edgeRightOpen,
      edgeTopOpen: target.layout.edgeTopOpen,
      edgeBottomOpen: target.layout.edgeBottomOpen,
    ),
    board: source.board,
    activePanel: source.activePanel,
    activeLaneId: target.activeLaneId,
    interaction: source.interaction,
  );
  check(
    '往返之后整份快照与期望深相等',
    _sameJson(decoded.toJson(), expected.toJson()),
    'decoded=${jsonEncode(decoded.toJson())}',
  );
}

// ── 2. 不该带走的按本位活着 ──────────────────────────────────────────────

void _localOnlyFieldsStayLocal() {
  final encoded = WorkspaceSyncCodec.encode(_deviceA());

  check('云端块里没有 version', !encoded.containsKey('version'));
  check('云端块里没有 activeLaneId', !encoded.containsKey('activeLaneId'));
  final layoutJson = encoded['layout'];
  check('云端块里 layout 是个对象', layoutJson is Map);
  for (final key in WorkspaceSyncCodec.localOnlyLayoutKeys) {
    check(
      '云端块里没有 $key',
      layoutJson is Map && !layoutJson.containsKey(key),
      '$key 进了同步块 ⇒ 另一台设备一启动抽屉自己就开了',
    );
  }

  final decoded = WorkspaceSyncCodec.decode(encoded, base: _deviceB());
  check(
    '四个抽屉开关按本机值保留',
    decoded.layout.edgeLeftOpen &&
        decoded.layout.edgeRightOpen &&
        decoded.layout.edgeTopOpen &&
        decoded.layout.edgeBottomOpen,
  );
  check('激活泳道按本机值保留', decoded.activeLaneId == LaneId.left);
}

// ── 3. 编码稳定 / 可 JSON 往返 ────────────────────────────────────────────

void _encodingIsStable() {
  final a = WorkspaceSyncCodec.encode(_deviceA());
  final b = WorkspaceSyncCodec.encode(_deviceA());
  check(
    '同一份布局两次编码深相等（块哈希才可能稳定）',
    _sameJson(a, b),
    '块哈希不稳定 ⇒ 每轮同步都在上传',
  );
  check('编码产物能 JSON 往返', _sameJson(jsonDecode(jsonEncode(a)), a));

  final factoryA = WorkspaceSyncCodec.encode(WorkspaceLayoutSnapshot.defaults());
  final factoryB = WorkspaceSyncCodec.encode(WorkspaceLayoutSnapshot.defaults());
  check('出厂布局编码也稳定', _sameJson(factoryA, factoryB));
  check(
    '出厂布局与改动过的布局编码不同',
    !_sameJson(factoryA, a),
    '这条不成立 ⇒ 「本机是不是出厂值」那个判据永远为真，云端布局永远进不来',
  );
}

// ── 4. 本机独有的字段不影响块哈希 ────────────────────────────────────────

void _localOnlyFieldsDoNotChangeTheHash() {
  final a = _deviceA();
  final twin = WorkspaceLayoutSnapshot(
    mode: a.mode,
    layout: a.layout.copyWith(
      edgeLeftOpen: true,
      edgeRightOpen: true,
      edgeTopOpen: true,
      edgeBottomOpen: true,
    ),
    board: a.board,
    activePanel: a.activePanel,
    activeLaneId: LaneId.left,
    interaction: a.interaction,
  );

  check(
    '只差抽屉与激活泳道 ⇒ 两块完全相同',
    _sameJson(
      WorkspaceSyncCodec.encode(a),
      WorkspaceSyncCodec.encode(twin),
    ),
    '不等 ⇒ 「只是把指针伸到边上」也会被当成布局改动推上云端',
  );
}

// ── 5. 坏块逐块退化 ─────────────────────────────────────────────────────

void _brokenBlocksDegradePerBlock() {
  final base = _deviceB();
  final decoded = WorkspaceSyncCodec.decode(
    const <String, dynamic>{
      'mode': 'not-a-mode',
      'layout': 'not-a-map',
      'board': 42,
      'interaction': <dynamic>[],
    },
    base: base,
  );

  check('认不出的模式退回本机', decoded.mode == base.mode);
  check(
    '坏 layout 退回本机',
    _sameJson(decoded.layout.toJson(), base.layout.toJson()),
  );
  check('坏 board 退回本机', decoded.board.isEmpty);
  check(
    '坏 interaction 退回本机',
    decoded.interaction.hoverFocusDelayMs == base.interaction.hoverFocusDelayMs,
  );
  // 逐块退化的关键是**别的块照常应用**：全判废会让「云端格式演进一次」
  // 变成「所有设备上布局回出厂」。
  final partial = WorkspaceSyncCodec.decode(
    const <String, dynamic>{'layout': 'not-a-map', 'mode': 'swimlane'},
    base: base,
  );
  check('一块坏不影响另一块', partial.mode == WorkspaceMode.swimlane);
}

// ── 6. 指向不存在泳道的记录要丢掉 ────────────────────────────────────────

void _strayActivePanelRecordsAreDropped() {
  final decoded = WorkspaceSyncCodec.decode(
    const <String, dynamic>{
      'activePanel': {
        'ghost-lane': 'ghost-panel',
        LaneId.left: '',
        LaneId.right: 'tools',
      },
    },
    base: _deviceB(),
  );

  check('不存在的泳道记录丢掉', !decoded.activePanel.containsKey('ghost-lane'));
  check('空面板 id 丢掉', !decoded.activePanel.containsKey(LaneId.left));
  check('正常记录照常应用', decoded.activePanel[LaneId.right] == 'tools');
}

// ── 7. 「这份块能不能用」 ────────────────────────────────────────────────

void _usableBlockHeuristic() {
  check('空块不可用', !WorkspaceSyncCodec.isUsableBlock(const <String, dynamic>{}));
  check(
    '只有 mode 也算可用',
    WorkspaceSyncCodec.isUsableBlock(const <String, dynamic>{'mode': 'swimlane'}),
  );
  check(
    '只有无关字段不算可用',
    !WorkspaceSyncCodec.isUsableBlock(const <String, dynamic>{'whatever': 1}),
  );
}
