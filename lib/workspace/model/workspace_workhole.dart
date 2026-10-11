/// Workhole 的呈现档位。
///
/// 前三档对应参考设计里的吸附点；[custom] 表示用户拖拽过工作孔边缘，
/// 实际宽度由布局配置里的 `edge*Width` 记录。
enum WorkspaceWorkholeSize {
  peek,
  workbench,
  takeover,
  custom;

  static WorkspaceWorkholeSize fromJson(
    Object? value, {
    WorkspaceWorkholeSize fallback = workbench,
  }) {
    if (value is! String) return fallback;
    for (final size in values) {
      if (size.name == value) return size;
    }
    return fallback;
  }
}
