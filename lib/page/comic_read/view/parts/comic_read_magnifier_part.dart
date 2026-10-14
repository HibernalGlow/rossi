part of '../comic_read.dart';

extension _ComicReadMagnifierPart on _ComicReadPageState {
  /// 放大镜覆盖层。
  ///
  /// 挂在正文之上、上下栏之下（`ComicReadSuccessWidget` 的 Stack 里那个位置）：
  /// 放进栏里就会跟着栏一起被揭示掉，而「指针还悬在画面上」这件事与栏开不开无关。
  Widget _magnifierLayerWidget() {
    final readSetting = context.select(
      (GlobalSettingCubit c) => c.state.readSetting,
    );
    if (!readSetting.magnifierEnabled) {
      // 关掉时不挂任何监听：`ReaderMagnifierLayer` 自己会退回空壳，
      // 但这里连订阅指针的必要性都省掉 —— 阅读页每多一个 MouseRegion
      // 都是每一帧的命中测试成本。
      return const Positioned.fill(
        child: IgnorePointer(child: SizedBox.shrink()),
      );
    }
    return Positioned.fill(
      child: ReaderMagnifierLayer(
        source: _magnifierSource,
        enabled: true,
        mode: readSetting.magnifierMode,
        zoomPercent: readSetting.magnifierZoomPercent,
        sizeLogical: readSetting.magnifierSizeLogical,
        locked: readSetting.magnifierLocked,
        onLockChanged: (locked) => context
            .read<GlobalSettingCubit>()
            .updateReadSetting((s) => s.copyWith(magnifierLocked: locked)),
      ),
    );
  }

  /// 把取样窗口交给子树 —— 必须是**正文的祖先**，否则页那侧取不到它。
  ///
  /// 每一页落位之后自己报告（见 `ReadImageWidget._reportMagnifierPage`），
  /// 所以这里只负责把 store 递下去，不在这里猜哪一页是当前页。
  Widget _withMagnifierScope(Widget child) =>
      ReaderMagnifierScope(source: _magnifierSource, child: child);
}
