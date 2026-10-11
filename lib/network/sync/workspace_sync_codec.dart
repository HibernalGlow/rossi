// 本文件**刻意不 import Flutter**：它是「工作台布局能不能跨设备跑一个来回」
// 这个问题的判据唯一落点，而本机 `flutter test` 起不来时只能靠纯 Dart VM 脚本
// （`dart run test/network/sync/workspace_sync_codec_check.dart`）验它。
// 与 `workspace_layout_config.dart` 顶部同一条纪律。

import 'dart:convert';

import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_interaction_settings.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';

/// 工作台布局的**同步块**编解码。
///
/// # 为什么需要一层编解码，而不是把整个 `workspace_layout.json` 搬上云
///
/// `WorkspaceLayoutSnapshot` 里混着两类东西（口径见 `WorkspaceLayoutSnapshot`
/// 的文档）：**用户的布局偏好**，以及**这一秒的画面**。整份搬上云 = 把第二类
/// 也同步过去，而它的语义恰恰是「不该跟着走」：
///
/// - [WorkspaceLayoutSnapshot.activeLaneId]（当前激活泳道）：同步它等于
///   「在 A 机点了 Reader，B 机也跳到 Reader」—— 这不是偏好，是一次交互的残留；
/// - `WorkspaceLayoutConfig.edgeLeftOpen` 等四个抽屉开关：同步它等于
///   「B 机一启动，四边栏的抽屉已经全拉开」。抽屉是「用户刚刚把指针伸到边上」
///   的后果，与 `Transient edge reveal` 同一条理由。
///
/// 所以这一层做的是一件事：**只放行第一类，第二类按本机值原样带回去**。
/// 注意 [decode] 的方向 —— 它**不是**「从零构造」，而是「拿云端覆盖本机」，
/// 因此本机独有的字段天然存活，不需要再写一遍保留逻辑。
abstract final class WorkspaceSyncCodec {
  /// 顶层里**本机独有**、不进云端的字段。
  static const List<String> localOnlySnapshotKeys = <String>[
    // 快照格式版本是**本机**对这份 JSON 的解释约定，云端那份有自己的
    // payload `schemaVersion`；两者混在一起会让「升级块的 schema」被误当成
    // 「升级本地文件格式」。
    'version',
    'activeLaneId',
  ];

  /// `layout` 里**本机独有**（瞬态抽屉）的字段。
  static const List<String> localOnlyLayoutKeys = <String>[
    'edgeLeftOpen',
    'edgeRightOpen',
    'edgeTopOpen',
    'edgeBottomOpen',
  ];

  /// 布局 → 同步块数据。
  ///
  /// 产物是 JSON 可编码的普通 Map（过一遍 `jsonEncode`/`jsonDecode`），
  /// 于是它进 payload 后的字节与「同一份布局在两台设备上算出的 md5」一致 ——
  /// 块内容哈希是这套同步的**唯一**变更检测手段，这里差一个 `Object?` 与
  /// `dynamic` 的装箱就会让 md5 每次都不同，表现为「每轮同步都在上传」。
  static Map<String, dynamic> encode(WorkspaceLayoutSnapshot snapshot) {
    final json = _map(snapshot.toJson());
    for (final key in localOnlySnapshotKeys) {
      json.remove(key);
    }

    final layout = _map(json['layout']);
    for (final key in localOnlyLayoutKeys) {
      layout.remove(key);
    }
    json['layout'] = layout;

    return json;
  }

  /// 同步块数据 → 布局，[base] 是**本机当前**那份快照。
  ///
  /// 逐块兜底：哪一块读不出/形状不对就退回 [base] 的对应块，其余照常应用 ——
  /// 与 `WorkspaceLayoutSnapshot.fromJson` 同一条纪律（「任何一块坏掉都只影响
  /// 那一块」）。整块数据不是 Map 时调用方不该走到这里（见 `_toJsonMap`）。
  ///
  /// **唯独四个抽屉开关必须显式按本机值写回**：`WorkspaceLayoutConfig.fromJson`
  /// 对缺失项一律取 `false`，而云端**不带**这四个键 ⇒ 不写回就是
  /// 「每同步一次，四个抽屉全被合上」，且用户找不到是谁关的。
  ///
  /// [adoptDesktopGeometry] 决定这台设备要不要采纳云端那份的**呈现模式 + 泳道
  /// 几何**（`mode` / 泳道顺序 / 每条泳道的宽度 / 独占那条是谁）与**边缘唤出区**。
  /// 默认 `true` ⇒ 同族设备之间照旧全套采纳，一个字的行为都没变。
  ///
  /// 触屏设备传 `false`（判据见 `WorkspacePointerMode`），理由不是「布局不好看」：
  /// 面板泳道的宽度是**绝对像素、且刻意不按视口夹取**（ADR-0012 第 5 条），
  /// 桌面那套 380/650/360 原样灌进一台 369dp 的手机，落地结果是
  /// 「一条左栏比屏幕还宽」+「独占被采纳 ⇒ 另外两条被推出视口」，
  /// 而把它们唤回来的那条路是**边缘悬停驻留** —— 触摸屏上永远不触发。
  /// 也就是**进得去出不来**，与 ADR-0012 第 12 条修掉的「没有常驻出口」同一类。
  ///
  /// 刻意**只**挡几何与唤出区：面板与卡片记账（哪个面板停在哪条泳道、次序、
  /// 可见、展开）是真正的跨端偏好，折叠态与面板操作栏摆放同理 —— 那些是
  /// 「用户想怎么组织内容」，不是「这台机器的屏幕上放得下多宽」。
  static WorkspaceLayoutSnapshot decode(
    Map<String, dynamic> data, {
    required WorkspaceLayoutSnapshot base,
    bool adoptDesktopGeometry = true,
  }) {
    final layoutJson = _map(data['layout']);
    var layout = layoutJson.isEmpty
        ? base.layout
        : WorkspaceLayoutConfig.fromJson(layoutJson).copyWith(
            edgeLeftOpen: base.layout.edgeLeftOpen,
            edgeRightOpen: base.layout.edgeRightOpen,
            edgeTopOpen: base.layout.edgeTopOpen,
            edgeBottomOpen: base.layout.edgeBottomOpen,
          );

    final rawBoard = data['board'];
    final board = rawBoard is Map
        ? WorkspaceBoardLayout.fromJson(_map(rawBoard))
        : base.board;

    final rawActivePanel = data['activePanel'];
    final activePanel = <String, String>{};
    if (rawActivePanel is Map) {
      for (final entry in rawActivePanel.entries) {
        final laneId = entry.key;
        final panelId = entry.value;
        if (laneId is! String || panelId is! String) continue;
        // 指向**本机没有的泳道**的记录要丢掉。云端的泳道集合可能与本机不同
        // （将来新增/下线泳道，或两端的构建版本不一致），留着它会让某条泳道
        // 永远显示一个不存在的面板，而界面上没有恢复入口 ——
        // 与 `WorkspaceLayoutSnapshot.fromJson` 里那条同源判断一致。
        if (!layout.lanes.containsKey(laneId) || panelId.isEmpty) continue;
        activePanel[laneId] = panelId;
      }
    } else {
      activePanel.addAll(base.activePanel);
    }

    final rawInteraction = data['interaction'];
    var interaction = rawInteraction is Map
        ? WorkspaceInteractionSettings.fromJson(_map(rawInteraction))
        : base.interaction;

    if (!adoptDesktopGeometry) {
      layout = _keepLocalGeometry(layout, base.layout);
      // 唤出区是**边缘悬停**的几何：在触屏上它一块都点不到，采纳它没有意义，
      // 而「设置 → 布局」里那张画布会把桌面画的那几块原样显示到手机上，
      // 用户会以为它们代表某种本机行为。
      interaction = interaction.copyWith(
        revealZones: base.interaction.revealZones,
      );
    }

    return WorkspaceLayoutSnapshot(
      mode:
          (!adoptDesktopGeometry ? null : _parseMode(data['mode'])) ??
          base.mode,
      layout: layout,
      board: board,
      activePanel: activePanel,
      // 本机独有：谁在这个屏幕上把交互交给了哪条泳道，不该被别的设备改写。
      activeLaneId: base.activeLaneId,
      interaction: interaction,
    );
  }

  /// 把云端那份布局里的**几何**换回本机自己的：泳道顺序、每条泳道的宽度
  /// （绝对像素与视口比例都算几何）、以及「哪条泳道在独占」。
  ///
  /// 折叠态与面板操作栏摆放**不动**（见 [decode] 的口径）。云端有、本机没有的
  /// 泳道原样保留 —— 那是新增泳道下来的正常路径，不是几何冲突。
  static WorkspaceLayoutConfig _keepLocalGeometry(
    WorkspaceLayoutConfig remote,
    WorkspaceLayoutConfig local,
  ) {
    final lanes = <String, LaneConfig>{};
    for (final entry in remote.lanes.entries) {
      final mine = local.lanes[entry.key];
      if (mine == null) {
        lanes[entry.key] = entry.value;
        continue;
      }
      lanes[entry.key] = entry.value.copyWith(
        width: mine.width,
        widthRatio: () => mine.widthRatio,
        minWidth: mine.minWidth,
        maxWidth: mine.maxWidth,
      );
    }
    return remote.copyWith(
      laneOrder: local.laneOrder,
      lanes: lanes,
      soloLaneId: () => local.soloLaneId,
      edgeLeftSize: local.edgeLeftSize,
      edgeRightSize: local.edgeRightSize,
      edgeLeftWidth: () => local.edgeLeftWidth,
      edgeRightWidth: () => local.edgeRightWidth,
    );
  }

  /// 云端那份数据看起来是不是一份**能用的**布局块。
  ///
  /// 只有「顶层是对象且至少带了 layout / board / interaction / mode 之一」才算。
  /// 用来挡住旧版本写进来的空块 —— 空块走 [decode] 会得到「什么都不改」，
  /// 与「云端没有这一块」应该表现一致（跳过），不该白算一次。
  static bool isUsableBlock(Map<String, dynamic> data) {
    for (final key in const <String>[
      'mode',
      'layout',
      'board',
      'interaction',
    ]) {
      if (data[key] != null) return true;
    }
    return false;
  }

  static WorkspaceMode? _parseMode(Object? value) {
    for (final mode in WorkspaceMode.values) {
      if (mode.name == value) return mode;
    }
    return null;
  }

  /// 走一遍 JSON 往返取到 `Map<String, dynamic>`：既统一了泛型（`Object?` 与
  /// `dynamic` 的差别会让块内容 md5 不稳定），也顺手保证「能不能编码」这件事
  /// 在**这里**就暴露，而不是等到加密上传那一步。
  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map) return <String, dynamic>{};
    final normalized = jsonDecode(jsonEncode(value));
    if (normalized is! Map) return <String, dynamic>{};
    return normalized.cast<String, dynamic>();
  }
}
