import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/scheduler.dart';
import 'package:zephyr/reader/online_translated_page_track.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/reader/translated_page_controller.dart';

/// 在线档的**呈现适配器**：把「注进 GPU 增强图轨」换成「往译文轨登记一张覆盖路径」。
///
/// 之所以能直接顶替 [TranslatedPagePresenter] 而不新写一台状态机：整页链路
/// （查缓存 → 分析 → 翻译 → 回填 → 归属记账 → 失败上报）与「画面上那张图从哪来」
/// 是两件事，前者在 `TranslatedPageController` 里已经写完了，只有后者分本地/在线两条。
///
/// # 「核对」在这条路上换成了什么
///
/// 本地那一路向呈现器问「这一帧取自增强轨还是原图轨」。这里没有 native 可问，
/// 但**有一个同样硬的证据**：显示端每次 build 都会把它实际拿去画的那个路径
/// 记回译文轨（[OnlineTranslatedPageTrack.displayPathFor]）。
/// 所以「画面换了」在这条路上的含义就是「那一帧确实用了成品页路径」，
/// 而不是「我调用了一次写入」。等一帧再核对，是为了让这个证据真的落地 ——
/// 接线漏了的话这里会回 false，芯片报失败，而不是谎报已显示。
class OnlineTranslatedPageSurface implements TranslatedPagePresenter {
  OnlineTranslatedPageSurface([OnlineTranslatedPageTrack? track])
    : _track = track ?? OnlineTranslatedPageTrack.instance;

  final OnlineTranslatedPageTrack _track;

  @override
  Map<int, String> get translationOwnedPages => _track.translationOwnedPages;

  @override
  Future<bool> setEnhancedImage(int index, String imagePath) async {
    // 成品页与原图**同像素尺寸**（回填那一步是 `picture.toImage(image.width, image.height)`），
    // 所以横长页拆两格时 `PageSlice` 的裁剪对这张图照样成立。
    if (!await File(imagePath).exists()) return false;
    _track.claim(index, imagePath);
    return true;
  }

  @override
  Future<bool> reshowAfterInjection(int index) async {
    _track.redraw();
    // 让界面有机会真的重建一次，再拿「那一帧用了哪个路径」当证据。
    await SchedulerBinding.instance.endOfFrame;
    return _track.isShowing(_track.translationOwnedPages[index] ?? '', index) ==
        true;
  }

  @override
  Future<bool?> presenterUsesEnhanced(int index) async {
    final owned = _track.translationOwnedPages[index];
    if (owned == null) return false;
    return _track.isShowing(owned, index);
  }

  /// 在线这一路没有「对比原图」那种旁路（那是 GPU 呈现器才有的开关）。
  @override
  bool get bypassesEnhancedTrack => false;
}

/// 在线档的**输入视图**：只回答「第 index 页那个文件在哪」。
///
/// `PageSource` 里其余那些成员（页表、页数、光栅句柄、解码）在这条路上没有意义 ——
/// 页表由插件快照给，像素由 `PictureBloc` 那条路解。这里刻意不做成「全都返回空」：
/// 那样一个误用会安静地拿到错的东西，抛出来才会当场被发现。
class OnlineTranslatedPageInput implements PageSource, TranslationScopeBearing {
  OnlineTranslatedPageInput([OnlineTranslatedPageTrack? track])
    : _track = track ?? OnlineTranslatedPageTrack.instance;

  final OnlineTranslatedPageTrack _track;

  @override
  String get path => _track.scope ?? '';

  /// 这一路的产物**必须**按「哪本书的哪一章」分档。
  ///
  /// 在线页没有「一次只打开一个文件」这个前提：同一份配置指纹下面，
  /// A 本第 5 页与 B 本第 5 页会查同一个 `p5.png`。少了这一项，
  /// 端出来的会是另一本书的画面，而芯片说它是译文页。
  @override
  String? get translationCacheScope => _track.scope;

  @override
  Future<String?> getPageFilePath(int index) async =>
      _track.sourcePathFor(index);

  @override
  Future<Uint8List?> getPageBytes(int index) async {
    final source = _track.sourcePathFor(index);
    if (source == null) return null;
    final file = File(source);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Never _notOnThisRoute() =>
      throw UnsupportedError('在线译文的输入视图只提供文件路径；页表与解码属于 PictureBloc 那条路。');

  @override
  List<PageRef> get pages => _notOnThisRoute();

  @override
  int get pageCount => _notOnThisRoute();

  @override
  RasterTargetRef? rasterTargetFor(int index) => _notOnThisRoute();

  @override
  Future<PageLoadOutcome> load(
    int index, {
    int? targetWidth,
    PageLoadIntent intent = PageLoadIntent.interactive,
  }) => _notOnThisRoute();

  @override
  Future<void> close() async {}
}
