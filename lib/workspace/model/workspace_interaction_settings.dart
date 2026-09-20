// 本文件**刻意不 import Flutter**：它要能被 JSON 往返（持久化判据）与
// `dart run` 直接断言。见 `workspace_layout_config.dart` 顶部的同一说明。
import 'package:zephyr/workspace/model/workspace_reveal_zones.dart';

/// 工作台的**交互延时与开关** —— 与几何分开记账（neoview：`Reader hover-focus
/// behavior and delays` 用独立的 canonical 组）。
///
/// 为什么延时不能共用一个：契约明确要求三套延时**互相独立**
/// （候选间的口径差异会让手感莫名其妙，而文档里这句话正是为此写的）：
///
/// - **Reader 悬停聚焦**（[hoverFocusDelayMs]）：指针停在**非激活的 Reader 泳道**
///   里多久才把它激活并恢复独占；
/// - **边缘揭示**（[edgeRevealDelayMs]）：Reader 处于激活且独占时，指针停在
///   视口**左右边缘**多久才把相邻泳道揭示出来；
/// - **揭示恢复**（[edgeRevealRestoreDelayMs]）：离开一条**未被激活**的揭示之后
///   多久回到 Reader。
///
/// 三者**都不是**四边栏那套「边缘抽屉」的显示延时（契约：`neither uses the
/// edge-shell show delay`）—— 那一套管的是另一条呈现路径，混用会让某一个
/// 先被调快的手感连带改坏另一个。
class WorkspaceInteractionSettings {
  /// 是否启用「悬停即聚焦非激活的 Reader 泳道」。关掉后只能靠点击激活。
  final bool hoverFocusEnabled;

  /// Reader 悬停聚焦的驻留延时（毫秒）。
  final int hoverFocusDelayMs;

  /// 左右边缘揭示的驻留延时（毫秒）。左右**共用**一个值。
  final int edgeRevealDelayMs;

  /// 离开未被激活的揭示后，回到 Reader 的延时（毫秒）。
  final int edgeRevealRestoreDelayMs;

  /// 聚焦相邻泳道时，给 Reader 留出的窄缝宽度（像素）。
  ///
  /// 它决定「用户在别处干活时还能不能一眼看见 Reader 的边、并且一下点回去」。
  /// 契约对它的措辞是 `keeps a narrow portion of Reader visible where possible`。
  final double readerPeekWidth;

  /// Reader 被**聚焦**时是否顺带进入独占（neoview `readerSoloOnFocus`）。
  ///
  /// 默认关 —— 这一项与 neoview 的默认值**刻意不同**：本项目的独占此前只能
  /// 手动点栏头的「独占该栏」，默认打开会让「点一下 Reader」这个动作
  /// 附带一个把其余泳道推出视口的后果，对老用户是凭空多出来的手感。
  final bool autoSoloOnFocus;

  /// Reader 独占时，其余泳道是否收成**紧凑轨**留在条带里
  /// （neoview `showLaneNavigatorInReaderSolo`）。
  ///
  /// 关掉时独占就是字面意思的「只剩一条」：其余泳道被推出视口，只能靠
  /// 左右唤出区调回来。打开时它们各留 `WorkspaceLayoutConfig.collapsedLaneWidth`
  /// 的宽度，等于一条常驻的泳道切换栏。
  final bool showLaneNavigatorInSolo;

  /// 是否允许用户**手动横向拖动**整条泳道条带。
  ///
  /// 默认开，同样是**保持改造前的行为**（条带此前一直可滚）。关掉之后
  /// 条带仍然会按激活 / 揭示自己滚到该看的位置 —— 这个开关管的是
  /// 「用户自己伸手拖」这一条路径，不是滚动本身。
  final bool manualScrollEnabled;

  /// 工作台**顶栏**画不画（`WorkspaceTopChrome`：退出 / 当前书名 / 切模式 / 重置布局）。
  ///
  /// 默认**关**。理由是那条顶栏在泳道模式下是**第二层顶栏**：每条泳道自带栏头，
  /// 桌面端上面还叠着 macOS / Windows 的窗口标题栏，而它自己只多给一颗返回键。
  ///
  /// 关掉之后出口剩三条，所以这一项才敢默认关：
  /// - 泳道「更多」菜单里的「退出工作台」（三条泳道都有，右键栏头同一条路）；
  /// - `Esc`（`BreezeWorkspacePage` 的 `CallbackShortcuts`）；
  /// - 触摸屏的系统返回键 / 侧滑。
  ///
  /// **代价要认**：沉浸四边栏模式没有泳道栏头，于是那边只剩 `Esc` 与系统返回键。
  final bool showTopChrome;

  /// 四条边的悬停唤出区（neoview `edgeRevealZones`）。
  ///
  /// 左右两条决定「指针停在离边缘多远的地方」开始为揭示计时；
  /// 上下两条决定顶栏与阅读器底栏的唤出带摆在哪儿。
  final WorkspaceRevealZones revealZones;

  const WorkspaceInteractionSettings({
    this.hoverFocusEnabled = true,
    this.hoverFocusDelayMs = 420,
    this.edgeRevealDelayMs = 320,
    this.edgeRevealRestoreDelayMs = 600,
    this.readerPeekWidth = 56,
    this.autoSoloOnFocus = false,
    this.showLaneNavigatorInSolo = false,
    this.manualScrollEnabled = true,
    this.showTopChrome = false,
    this.revealZones = WorkspaceRevealZones.defaults,
  });

  WorkspaceInteractionSettings copyWith({
    bool? hoverFocusEnabled,
    int? hoverFocusDelayMs,
    int? edgeRevealDelayMs,
    int? edgeRevealRestoreDelayMs,
    double? readerPeekWidth,
    bool? autoSoloOnFocus,
    bool? showLaneNavigatorInSolo,
    bool? manualScrollEnabled,
    bool? showTopChrome,
    WorkspaceRevealZones? revealZones,
  }) {
    return WorkspaceInteractionSettings(
      hoverFocusEnabled: hoverFocusEnabled ?? this.hoverFocusEnabled,
      hoverFocusDelayMs: hoverFocusDelayMs ?? this.hoverFocusDelayMs,
      edgeRevealDelayMs: edgeRevealDelayMs ?? this.edgeRevealDelayMs,
      edgeRevealRestoreDelayMs:
          edgeRevealRestoreDelayMs ?? this.edgeRevealRestoreDelayMs,
      readerPeekWidth: readerPeekWidth ?? this.readerPeekWidth,
      autoSoloOnFocus: autoSoloOnFocus ?? this.autoSoloOnFocus,
      showLaneNavigatorInSolo:
          showLaneNavigatorInSolo ?? this.showLaneNavigatorInSolo,
      manualScrollEnabled: manualScrollEnabled ?? this.manualScrollEnabled,
      showTopChrome: showTopChrome ?? this.showTopChrome,
      revealZones: revealZones ?? this.revealZones,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'hoverFocusEnabled': hoverFocusEnabled,
    'hoverFocusDelayMs': hoverFocusDelayMs,
    'edgeRevealDelayMs': edgeRevealDelayMs,
    'edgeRevealRestoreDelayMs': edgeRevealRestoreDelayMs,
    'readerPeekWidth': readerPeekWidth,
    'autoSoloOnFocus': autoSoloOnFocus,
    'showLaneNavigatorInSolo': showLaneNavigatorInSolo,
    'manualScrollEnabled': manualScrollEnabled,
    'showTopChrome': showTopChrome,
    'revealZones': revealZones.toJson(),
  };

  /// 从 JSON 还原；**任何一项缺失或非法都退回该项的默认值**，绝不抛异常、
  /// 也不整组丢弃 —— 配置文件被手改坏一个数字，不该让整套布局回到出厂。
  factory WorkspaceInteractionSettings.fromJson(Map<String, Object?> json) {
    const fallback = WorkspaceInteractionSettings();
    return WorkspaceInteractionSettings(
      hoverFocusEnabled: json['hoverFocusEnabled'] is bool
          ? json['hoverFocusEnabled']! as bool
          : fallback.hoverFocusEnabled,
      hoverFocusDelayMs: _positiveInt(
        json['hoverFocusDelayMs'],
        fallback.hoverFocusDelayMs,
      ),
      edgeRevealDelayMs: _positiveInt(
        json['edgeRevealDelayMs'],
        fallback.edgeRevealDelayMs,
      ),
      edgeRevealRestoreDelayMs: _positiveInt(
        json['edgeRevealRestoreDelayMs'],
        fallback.edgeRevealRestoreDelayMs,
      ),
      readerPeekWidth: json['readerPeekWidth'] is num
          ? (json['readerPeekWidth']! as num)
                .toDouble()
                .clamp(0, 400)
                .toDouble()
          : fallback.readerPeekWidth,
      autoSoloOnFocus: json['autoSoloOnFocus'] is bool
          ? json['autoSoloOnFocus']! as bool
          : fallback.autoSoloOnFocus,
      showLaneNavigatorInSolo: json['showLaneNavigatorInSolo'] is bool
          ? json['showLaneNavigatorInSolo']! as bool
          : fallback.showLaneNavigatorInSolo,
      manualScrollEnabled: json['manualScrollEnabled'] is bool
          ? json['manualScrollEnabled']! as bool
          : fallback.manualScrollEnabled,
      showTopChrome: json['showTopChrome'] is bool
          ? json['showTopChrome']! as bool
          : fallback.showTopChrome,
      revealZones: WorkspaceRevealZones.fromJson(json['revealZones']),
    );
  }

  /// 小于等于 0 的延时是**非法**的（0 延时等于「一进入就触发」，会让画面
  /// 在指针扫过时反复横跳）。非整数、非数字同样退回默认值。
  static int _positiveInt(Object? value, int fallback) {
    if (value is! int || value <= 0) return fallback;
    return value;
  }

  @override
  bool operator ==(Object other) =>
      other is WorkspaceInteractionSettings &&
      other.hoverFocusEnabled == hoverFocusEnabled &&
      other.hoverFocusDelayMs == hoverFocusDelayMs &&
      other.edgeRevealDelayMs == edgeRevealDelayMs &&
      other.edgeRevealRestoreDelayMs == edgeRevealRestoreDelayMs &&
      other.readerPeekWidth == readerPeekWidth &&
      other.autoSoloOnFocus == autoSoloOnFocus &&
      other.showLaneNavigatorInSolo == showLaneNavigatorInSolo &&
      other.manualScrollEnabled == manualScrollEnabled &&
      other.showTopChrome == showTopChrome &&
      other.revealZones == revealZones;

  @override
  int get hashCode => Object.hash(
    hoverFocusEnabled,
    hoverFocusDelayMs,
    edgeRevealDelayMs,
    edgeRevealRestoreDelayMs,
    readerPeekWidth,
    autoSoloOnFocus,
    showLaneNavigatorInSolo,
    manualScrollEnabled,
    showTopChrome,
    revealZones,
  );
}
