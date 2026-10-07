import 'package:flutter/foundation.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_interaction_settings.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/model/workspace_reader_target.dart';

@immutable
class WorkspaceState {
  final WorkspaceMode mode;
  final WorkspaceLayoutConfig layout;

  /// 面板 / 卡片的布局记账（可见性、次序、卡片归属）。
  final WorkspaceBoardLayout board;

  /// 阅读器泳道当前打开的目标；`null` = 泳道空闲（显示空态画板）。
  final WorkspaceReaderTarget? readerTarget;

  /// 各泳道当前激活的面板 ID（每条泳道**各自独立**，互不覆盖）。
  final Map<String, String> activePanel;

  /// 当前**激活**的泳道 ID。
  ///
  /// 「激活」不是「独占」：独占（solo）是**泳道自己的属性**，激活是
  /// 「工作台当前把交互交给谁」。两条契约建在它之上：
  ///
  /// - 非激活泳道的第一下点击要被工作台**吃掉**（用来激活它），不派发给内容 ——
  ///   但只在「这次聚焦**会移动画面**」那一档吃（见 `SwimlaneWorkspace` 的
  ///   `_activationMovesStrip`）；一条本来就完整可见的泳道，聚焦什么都不动，
  ///   那一下点击就该照常生效。
  /// - 紧凑轨（切换栏）给的是**非激活**的那些泳道：激活哪条，哪条就展开。
  ///
  /// **激活不改 Reader 泳道的宽度**（ADR-0014 的修订记录）。它曾要求「solo 的生效宽度
  /// 以『同时是激活泳道』为前提」，那条前提的代价是：指针停到隔壁泳道上 0.42s，
  /// Reader 就从「占满可用宽」塌回常规宽 —— 一次几百像素的宽度突变会把已上屏的
  /// 纹理判废并按新宽重解（见 `lib/reader/image_surface.dart`），正是「鼠标移过去
  /// 卡一下」里最贵的那一下。条带模型里「显出一条泳道」本来就该靠**移动**，
  /// 不是靠重新排版。面板泳道保持老契约，理由写在 [effectiveSoloLaneId]。
  ///
  /// 为 `null` 表示「还没定过」：此时不吞任何点击，一切按改造前行为派发。
  /// 这个「没定过」的初始态是刻意的 —— 冷启动不该因为一个默认激活项
  /// 就把用户在左泳道里的第一次点击无声吃掉。
  final String? activeLaneId;

  /// 交互延时与开关（悬停聚焦 / 边缘揭示 / 揭示恢复 / Reader 窄缝宽）。
  final WorkspaceInteractionSettings interaction;

  /// 是否处于阅读器铺满窗口全屏状态。
  ///
  /// 在 solo 聚焦基础上去掉顶栏、内边距与边框，使阅读器自身铺满整个工作台窗口。
  final bool isReaderFullscreen;

  const WorkspaceState({
    required this.mode,
    required this.layout,
    this.board = const WorkspaceBoardLayout(),
    this.readerTarget,
    this.activePanel = const <String, String>{},
    this.activeLaneId,
    this.interaction = const WorkspaceInteractionSettings(),
    this.isReaderFullscreen = false,
  });

  factory WorkspaceState.initial() {
    return WorkspaceState(
      mode: WorkspaceMode.swimlane,
      layout: WorkspaceLayoutConfig.defaults(),
      // 布局记账留空 —— 空账 = 全部用注册表里的默认值，
      // 于是「加卡片 / 改默认面板」不需要写迁移，也不会被旧记录挡住。
    );
  }

  /// solo 的**生效**泳道。
  ///
  /// 阅读器全屏是另一条独立的呈现档（它压过一切），优先。
  ///
  /// **Reader 的独占不看激活态**：谁被激活都不改它的宽度。以前那句契约
  /// （`When the Reader lane is **active** and solo is enabled, its effective
  /// width is the workspace viewport width`）在这里被**按用户口径覆盖**了，代价是
  /// 一条真实存在的卡顿：指针每停到隔壁泳道一次，Reader 就从「占满可用宽」塌回
  /// 常规宽，而宽度一变，`ImageSurface` 的物理尺寸就变 —— 已上屏的纹理被判废并
  /// 按新宽重解（`lib/reader/image_surface.dart` 自己记的数是 300–400 ms/页）。
  /// 「显出一条泳道」在这套条带版式里本来就该靠**移动**，不靠重新排版。
  ///
  /// **面板泳道的独占保持老契约**（要同时是激活泳道）。这不是疏忽而是取舍：
  /// 面板泳道的内容是列表与卡片，改宽度没有重解码那笔代价；而一旦解绑，
  /// 「独占一条面板泳道 + 在别处干活」会把其余泳道挤到视口外，
  /// 而把它们呼回来的边缘驻留**只对 Reader 独占**那档开放
  /// （见 `SwimlaneWorkspace._handleStripHover` 的 `soloArmed`），
  /// 于是那个洞只有进得去、没有出得来。
  String? get effectiveSoloLaneId {
    if (isReaderFullscreen) return LaneId.reader;
    final solo = layout.soloLaneId;
    if (solo == null) return null;
    if (solo == LaneId.reader) return LaneId.reader;
    return solo == activeLaneId ? solo : null;
  }

  /// 与 [other] 之间**只差「谁被激活」**吗（其余字段一项都没动）。
  ///
  /// 这是「聚焦落地那一刻该重建谁」的唯一判据：这条成立时，条带几何、每条泳道的
  /// 内容、顶栏那几档都没变，变的只有边框亮不亮、条带停在哪、哪条收成轨。页面层与
  /// 内容槽位据此跳过重 build，把一次 hover 的代价压回「外壳」那一层。
  ///
  /// # 为什么按字段比，而不是给这个类加 `==`
  ///
  /// 所有字段都是 `@immutable` + `copyWith`（改任何一项都会换实例），所以
  /// 「逐字段比同一性」是**保守**的：宁可多重建一次，也不能漏重建。漏重建的表现是
  /// 界面停在旧状态（用户看到的是「点了没反应」），比多 build 一次严重得多。
  /// 反过来，`WorkspaceState` 上挂 `==` 会让「谁被激活」混进全等比较，
  /// 那两个概念本来是分开的 —— 一个问「有没有变」，一个问「变在哪一项」。
  bool differsOnlyByActiveLane(WorkspaceState other) =>
      identical(mode, other.mode) &&
      identical(layout, other.layout) &&
      identical(board, other.board) &&
      identical(readerTarget, other.readerTarget) &&
      identical(activePanel, other.activePanel) &&
      identical(interaction, other.interaction) &&
      isReaderFullscreen == other.isReaderFullscreen &&
      activeLaneId != other.activeLaneId;

  WorkspaceState copyWith({
    WorkspaceMode? mode,
    WorkspaceLayoutConfig? layout,
    WorkspaceBoardLayout? board,
    WorkspaceReaderTarget? Function()? readerTarget,
    Map<String, String>? activePanel,
    String? Function()? activeLaneId,
    WorkspaceInteractionSettings? interaction,
    bool? isReaderFullscreen,
  }) {
    return WorkspaceState(
      mode: mode ?? this.mode,
      layout: layout ?? this.layout,
      board: board ?? this.board,
      readerTarget: readerTarget != null ? readerTarget() : this.readerTarget,
      activePanel: activePanel ?? this.activePanel,
      activeLaneId: activeLaneId != null ? activeLaneId() : this.activeLaneId,
      interaction: interaction ?? this.interaction,
      isReaderFullscreen: isReaderFullscreen ?? this.isReaderFullscreen,
    );
  }
}
