part of '../comic_info.dart';

// 从 class _ComicInfoState 搬出的方法组；extension 与宿主类同库，可直接访问私有成员。
extension _ComicInfoRossiActionsPart on _ComicInfoState {
  /// 进阅读器：悬浮按钮与操作行里的「阅读」卡片共用的**唯一**一处入口。
  ///
  /// 参数口径与那颗悬浮按钮原本的写法（以及封面/「继续阅读」两处点击）一致：
  /// 传 `_comicId`（解析后的 id）。类型上悬浮按钮用 [widget.type]、封面点击用
  /// `_type` —— 两者原本就不同，这里不顺手改口径，只保证「同一类入口同一份参数」。
  void _startReading(ComicEntryType entryType) {
    goToComicRead(context, _comicId, entryType, comicInfoDyn, widget.from);
  }
  /// 有指针 ⇒ 正文左右各浮一颗胶囊；触摸端原样返回（底部条是车道 G）。
  ///
  /// 判据用指针而不是视口宽度（口径 4）：带触摸屏的 Windows 笔记本仍然有指针，
  /// 「该不该省鼠标的路」取决于手上是什么，不取决于窗口多宽。
  ///
  /// 几何不在这里算 —— 交给 [ComicInfoActionOverlay]，那样那份 `Positioned` 的落点
  /// 才测得到（第一版写在这里，右边那颗被裁到窗口外没被发现）。
  Widget _withActionRails({required Widget child}) {
    if (!comicInfoPlatformHasPointer(defaultTargetPlatform)) {
      return child;
    }
    final items = comicInfoActionItems();
    List<ComicInfoActionEntry> pick(List<String> ids) => [
      for (final id in ids)
        for (final item in items)
          if (item.actionId == id) item,
    ];

    return ComicInfoActionOverlay(
      scope: this,
      glass: context.watch<GlobalSettingCubit>().state.comicInfoRailLiquidGlass,
      leftItems: pick(const [ComicInfoActionIds.back, ComicInfoActionIds.home]),
      rightItems: pick(const [ComicInfoActionIds.read]),
      child: child,
    );
  }
}
