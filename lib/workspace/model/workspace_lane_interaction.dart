// 纯 Dart 值对象：只保存泳道选择与定位偏好，不定义 operation binding 映射。
class WorkspaceLaneInteraction {
  /// 鼠标进入泳道后，键盘输入目标是否跟随。与自动定位独立。
  final bool inputTargetOnHover;

  /// 悬停驻留后是否自动移动条带，让泳道完整显示。
  final bool autoReveal;

  /// 悬停定位延迟；null 表示随全局 hoverFocusDelayMs 变化。
  final int? hoverDelayMs;

  const WorkspaceLaneInteraction({
    this.inputTargetOnHover = true,
    this.autoReveal = true,
    this.hoverDelayMs,
  }) : assert(hoverDelayMs == null || hoverDelayMs > 0);

  /// 用 `hoverDelayMs: () => null` 恢复继承全局延迟。
  WorkspaceLaneInteraction copyWith({
    bool? inputTargetOnHover,
    bool? autoReveal,
    int? Function()? hoverDelayMs,
  }) => WorkspaceLaneInteraction(
    inputTargetOnHover: inputTargetOnHover ?? this.inputTargetOnHover,
    autoReveal: autoReveal ?? this.autoReveal,
    hoverDelayMs: hoverDelayMs != null ? hoverDelayMs() : this.hoverDelayMs,
  );

  Map<String, Object?> toJson() => {
    'inputTargetOnHover': inputTargetOnHover,
    'autoReveal': autoReveal,
    'hoverDelayMs': hoverDelayMs,
  };

  /// 缺项或坏项逐字段回退；autoReveal 的默认值由旧的泳道类别开关提供。
  factory WorkspaceLaneInteraction.fromJson(
    Map<String, Object?> json, {
    bool defaultAutoReveal = true,
  }) {
    final delay = json['hoverDelayMs'];
    return WorkspaceLaneInteraction(
      inputTargetOnHover: json['inputTargetOnHover'] is bool
          ? json['inputTargetOnHover']! as bool
          : true,
      autoReveal: json['autoReveal'] is bool
          ? json['autoReveal']! as bool
          : defaultAutoReveal,
      hoverDelayMs: delay is int && delay > 0 ? delay : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WorkspaceLaneInteraction &&
      other.inputTargetOnHover == inputTargetOnHover &&
      other.autoReveal == autoReveal &&
      other.hoverDelayMs == hoverDelayMs;

  @override
  int get hashCode => Object.hash(inputTargetOnHover, autoReveal, hoverDelayMs);
}
