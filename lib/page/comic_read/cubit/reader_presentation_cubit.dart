import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/model/reader_presentation.dart';

/// 顶栏缩放 / 旋转面板所操作的那一份状态。
///
/// ## 为什么不是直接放 `ReadSettingState`
///
/// 照 neoview 的 `viewDefaults` 分界：`fitMode` / `autoRotation` / `widePageStretch`
/// 是「看完这一页还想保持」的偏好，落盘；`manualScale` 与 `rotation` 是「这一页我要
/// 凑近看个细节」，**只活在本次阅读会话里**，换书即归零。
/// 阅读页每个 route 一份本 cubit，正好就是那个会话边界；把五个字段一起塞进全局设置
/// 会让「上一本在 400% 看插图」跟到下一本的第一页。
///
/// 落盘的那三项由本 cubit **单向写回** [GlobalSettingCubit]，别处没有第二个写者，
/// 所以不存在两边不同步的问题。
class ReaderPresentationCubit extends Cubit<ReaderPresentation> {
  ReaderPresentationCubit({required GlobalSettingCubit settings})
    : _settings = settings,
      super(
        ReaderPresentation(
          fitMode: settings.state.readSetting.readerFitMode,
          autoRotation: settings.state.readSetting.readerAutoRotation,
          widePageStretch: settings.state.readSetting.readerWidePageStretch,
        ),
      );

  final GlobalSettingCubit _settings;

  /// 换缩放模式。
  ///
  /// 一并把手动缩放打回 100% —— 与 neoview 同一口径：留着上一次的倍率，
  /// 「适应宽度」点下去会变成一个看不出适应了什么的结果。
  void setFitMode(ReaderFitMode mode) =>
      _apply(state.copyWith(fitMode: mode, manualScale: 1));

  /// 设手动缩放（入参会被收到 0.1~8，见 [normalizeReaderManualScale]）。
  void setManualScale(double scale) =>
      _apply(state.copyWith(manualScale: normalizeReaderManualScale(scale)));

  /// 短按百分比：回到 100%。
  void resetManualScale() => _apply(state.copyWith(manualScale: 1));

  /// `reader.zoom-in` / `reader.zoom-out`：一次 ×1.1 或 ÷1.1。
  void stepScale(int direction) =>
      _apply(state.copyWith(manualScale: state.scaledByStep(direction)));

  /// 顺时针转 `quarterTurns` 个直角（`reader.rotate-clockwise` 用 1，
  /// `reader.rotate-180` 用 2）。
  void rotate(int quarterTurns) => _apply(state.rotated(quarterTurns));

  void setAutoRotation(ReaderAutoRotation mode) =>
      _apply(state.copyWith(autoRotation: mode));

  void setWidePageStretch(ReaderWidePageStretch mode) =>
      _apply(state.copyWith(widePageStretch: mode));

  /// 「重置视图」：只清呈现层，**不动**单双页 / 阅读方向 / 页面顺序。
  ///
  /// 与 neoview 同一边界：那边重置的是 `presentation`，`layout.pageMode` 与
  /// `readingDirection` 各自有自己的持久化，不归这个按钮管。
  void resetView() =>
      _apply(ReaderPresentation.defaultPresentation);

  void _apply(ReaderPresentation next) {
    if (next == state) return;
    emit(next);

    final persisted = _settings.state.readSetting;
    if (persisted.readerFitMode == next.fitMode &&
        persisted.readerAutoRotation == next.autoRotation &&
        persisted.readerWidePageStretch == next.widePageStretch) {
      return;
    }
    _settings.updateReadSetting(
      (s) => s.copyWith(
        readerFitMode: next.fitMode,
        readerAutoRotation: next.autoRotation,
        readerWidePageStretch: next.widePageStretch,
      ),
    );
  }
}
