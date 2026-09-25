part of '../global_setting.dart';
// 提示条与切换提示的设置（rossi）


/// 提示条（toast）在屏幕上的停靠位置，九宫格。
///
/// 口径参考 neoview 的「提示悬浮窗」：位置可配、可调边距，
/// 对应关系 [ToastPosition.topLeft] → `Alignment.topLeft` 等。
enum ToastPosition {
  topLeft,
  topCenter,
  topRight,
  middleLeft,
  center,
  middleRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}


extension ToastPositionExtension on ToastPosition {
  String get label {
    switch (this) {
      case ToastPosition.topLeft:
        return t.settings.toastPositionTopLeft;
      case ToastPosition.topCenter:
        return t.settings.toastPositionTopCenter;
      case ToastPosition.topRight:
        return t.settings.toastPositionTopRight;
      case ToastPosition.middleLeft:
        return t.settings.toastPositionMiddleLeft;
      case ToastPosition.center:
        return t.settings.toastPositionCenter;
      case ToastPosition.middleRight:
        return t.settings.toastPositionMiddleRight;
      case ToastPosition.bottomLeft:
        return t.settings.toastPositionBottomLeft;
      case ToastPosition.bottomCenter:
        return t.settings.toastPositionBottomCenter;
      case ToastPosition.bottomRight:
        return t.settings.toastPositionBottomRight;
    }
  }
}


/// 提示条设置的读入口。
///
/// 提示（toast）会在**任意时刻**被触发（后台下载完成、同步失败……），
/// 这些调用点多半拿不到 `BuildContext`/Cubit，所以这里直接从本地库读；
/// 本地库还没起来（启动早期）或已关闭时回落到默认样式 ——
/// 绝不让「读设置」本身把提示炸掉。
ToastSettingState get toastSetting {
  try {
    return objectbox.userSettingBox.get(1)?.globalSetting.toastSetting ??
        const ToastSettingState();
  } catch (_) {
    return const ToastSettingState();
  }
}


/// 提示条（toast）的位置、时长与外观。
///
/// 字段口径（对齐 neoview 的 switchToast 配置，落到 Flutter 的九宫格 + 尺寸）：
/// - [position] / [edgePadding]：停靠位置与距屏幕边缘的安全留白；
/// - [durationMs]：自动关闭时长，`0` 表示常驻（只能手动关闭）；
/// - [maxWidth]：卡片最大宽度（手机端还会被屏幕宽度再夹一次）；
/// - [opacityPercent]：整卡不透明度；
/// - [maxVisible]：同屏最多堆叠条数，超出时挤掉最旧的一条；
/// - [animationDurationMs]：进出场动画时长；
/// - [liquidGlass]：液态玻璃（模糊 + 半透明）背景；
/// - [showProgressBar] / [showIcon] / [showCloseButton]：进度条、类型图标、关闭按钮。
@freezed
abstract class ToastSettingState with _$ToastSettingState {
  const factory ToastSettingState({
    @Default(ToastPosition.topRight) ToastPosition position,
    @Default(12) int edgePadding,
    @Default(3000) int durationMs,
    @Default(400) int maxWidth,
    @Default(100) int opacityPercent,
    @Default(3) int maxVisible,
    @Default(220) int animationDurationMs,
    @Default(false) bool liquidGlass,
    @Default(true) bool showProgressBar,
    @Default(true) bool showIcon,
    @Default(true) bool showCloseButton,
  }) = _ToastSettingState;

  factory ToastSettingState.fromJson(Map<String, dynamic> json) =>
      _$ToastSettingStateFromJson(json);
}


/// 「切换提示」（neoview N-17 switch-toast）的触发开关与文案模板。
///
/// 上游卡片里「提示悬浮窗」那一节（X/Y、透明度、液态玻璃）**不在这里** ——
/// Rossi 的提示条外观统一由 [ToastSettingState] 的九宫格 + 尺寸负责
/// （见 `toast_setting_page`），本设置只管「什么时候提示、提示什么」。
/// 上游的 `enableAction`（按键操作提示）在 Rossi 还没有统一的按键执行挂点，
/// 本轮不搬（口径登记在 `docs/ROADMAP.md`）。
@freezed
abstract class SwitchToastSettingState with _$SwitchToastSettingState {
  const factory SwitchToastSettingState({
    /// 切换书籍（含首次进入一本书）时显示提示。上游同款：默认关。
    @Default(false) bool enableBook,

    /// 翻页时显示提示。
    @Default(false) bool enablePage,

    /// 翻到最后一页 / 在最后一页继续向前翻页时显示提示（上游 `enableBoundaryToast`）。
    @Default(false) bool enableBoundaryToast,

    /// 模板变量为 `{{book.*}}` / `{{page.*}}`，语义与上游
    /// `renderReaderSwitchToastTemplate` 逐条对照（见
    /// `lib/util/toast/switch_toast_template.dart`）。
    @Default(
      '已切换到 {{book.displayName}}（第 {{book.currentPageDisplay}} / {{book.totalPages}} 页）',
    )
    String bookTitleTemplate,
    @Default('路径：{{book.path}}') String bookDescriptionTemplate,
    @Default('第 {{page.indexDisplay}} / {{book.totalPages}} 页')
    String pageTitleTemplate,

    /// 上游默认是「分辨率 + 文件大小」，但 Rossi 的页表（`Doc`）没有这两项，
    /// 换成页文件名 —— 刻意偏离，见 `docs/ROADMAP.md`。
    @Default('{{page.name}}') String pageDescriptionTemplate,

    /// 边界提示文案（对齐上游 `enableBoundaryToast` 的语义，Rossi 侧不带模板变量）。
    @Default('已经是最后一页') String lastPageMessage,
  }) = _SwitchToastSettingState;

  factory SwitchToastSettingState.fromJson(Map<String, dynamic> json) =>
      _$SwitchToastSettingStateFromJson(json);
}


/// 切换提示设置的读入口（非 widget 上下文也能读）。
///
/// 与 [toastSetting] 同理：运行时在**任意时刻**由会话总线触发，拿不到 Cubit，
/// 「读设置」本身绝不能把提示炸掉。
SwitchToastSettingState get switchToastSetting {
  try {
    return objectbox.userSettingBox.get(1)?.globalSetting.switchToastSetting ??
        const SwitchToastSettingState();
  } catch (_) {
    return const SwitchToastSettingState();
  }
}
