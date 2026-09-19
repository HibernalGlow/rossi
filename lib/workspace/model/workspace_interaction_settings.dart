// 本文件**刻意不 import Flutter**：它要能被 JSON 往返（持久化判据）与
// `dart run` 直接断言。见 `workspace_layout_config.dart` 顶部的同一说明。

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

  const WorkspaceInteractionSettings({
    this.hoverFocusEnabled = true,
    this.hoverFocusDelayMs = 420,
    this.edgeRevealDelayMs = 320,
    this.edgeRevealRestoreDelayMs = 600,
    this.readerPeekWidth = 56,
  });

  WorkspaceInteractionSettings copyWith({
    bool? hoverFocusEnabled,
    int? hoverFocusDelayMs,
    int? edgeRevealDelayMs,
    int? edgeRevealRestoreDelayMs,
    double? readerPeekWidth,
  }) {
    return WorkspaceInteractionSettings(
      hoverFocusEnabled: hoverFocusEnabled ?? this.hoverFocusEnabled,
      hoverFocusDelayMs: hoverFocusDelayMs ?? this.hoverFocusDelayMs,
      edgeRevealDelayMs: edgeRevealDelayMs ?? this.edgeRevealDelayMs,
      edgeRevealRestoreDelayMs:
          edgeRevealRestoreDelayMs ?? this.edgeRevealRestoreDelayMs,
      readerPeekWidth: readerPeekWidth ?? this.readerPeekWidth,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'hoverFocusEnabled': hoverFocusEnabled,
    'hoverFocusDelayMs': hoverFocusDelayMs,
    'edgeRevealDelayMs': edgeRevealDelayMs,
    'edgeRevealRestoreDelayMs': edgeRevealRestoreDelayMs,
    'readerPeekWidth': readerPeekWidth,
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
      other.readerPeekWidth == readerPeekWidth;

  @override
  int get hashCode => Object.hash(
    hoverFocusEnabled,
    hoverFocusDelayMs,
    edgeRevealDelayMs,
    edgeRevealRestoreDelayMs,
    readerPeekWidth,
  );
}
