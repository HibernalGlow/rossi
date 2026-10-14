part of '../comic_read.dart';

extension _ComicReadPageOrderPart on _ComicReadPageState {
  /// 把「当前章按显示顺序」的那份排列交给会话中枢。
  ///
  /// 为什么由这里发布而不是让下游各自算：缩略图条、滑动条预览、页名提示、
  /// 工作区的页面列表四处分都按下标取「这一格画哪一页」，而它们拿到的只是
  /// 会话中枢那一份页表。让每一处自己去读档位与手动排列，就会变成四套排序判据，
  /// 其中任何一套写错都只会表现成「某一处和画面差一页」。
  ///
  /// 挂在 `onReady` 上而不是档位监听上：这一处每次设置变化都会走一遍，
  /// 而 [ReaderSessionCoordinator.updateDisplayOrder] 自己会比对旧值，
  /// 排列没变时一条通知都不会发。
  void _publishPageOrder(ReadSettingState readSetting) {
    final docs = epInfo.docs;
    if (readSetting.readerPageOrderMode == ReaderPageOrderMode.source) {
      ReaderSessionCoordinator.instance.updateDisplayOrder(null);
      return;
    }
    final order = context.read<ReaderPageOrderCubit>().resolveOrder(
      chapterId: epInfo.epId,
      mode: readSetting.readerPageOrderMode,
      docs: docs,
    );
    // 长度对不上就当没排序：宁可退回原样，也不要让下游按下标取到越界的那一页。
    ReaderSessionCoordinator.instance.updateDisplayOrder(
      order.length == docs.length ? order : null,
    );
  }
}
