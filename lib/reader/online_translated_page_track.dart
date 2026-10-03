import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:zephyr/reader/translated_page_controller.dart';
import 'package:zephyr/widgets/picture_bloc/models/picture_info.dart';

/// 在线图源（插件漫画 / 已下载但按下载记录打开的漫画）这一页的**译文轨**。
///
/// # 为什么本地那一路的做法搬不过来
///
/// 本地页由 native 上屏，成品页注进呈现器的增强图轨（见 `TranslatedPageController`
/// 的理由：在 Flutter 侧再盖一层 `Image.file` 会绕开旋转 / 双页 / 页宽适配）。
/// 在线页走的是另一条渲染路 —— `PictureBloc` 解析出一个磁盘路径，交给
/// `ImageDisplay(imagePath:)`。那条路**没有增强图轨可注**，所以这里的「注入」
/// 只能是：登记一张覆盖用的成品页路径，显示端每次 build 来问一次。
///
/// # 为什么这张表按「作用域」而不是按单书会话存
///
/// 本仓已经栽过两次：per-book 的状态塞进单例，换书之后旧书的页号还在表里，
/// 于是新书的第 5 页贴上了旧书第 5 页的产物。这里不加「记得 reset」的约定，
/// 而是把作用域（哪本书的哪一章）当作每一次读写的键的一部分 ——
/// **作用域一变，表自己就空了**，漏调 reset 也污染不到新页。
class OnlineTranslatedPageTrack extends ChangeNotifier {
  OnlineTranslatedPageTrack._();

  static final OnlineTranslatedPageTrack instance =
      OnlineTranslatedPageTrack._();

  /// 给测试一份干净的轨。
  ///
  /// 单例那份跨用例留着上一页的路径与归属，「换书会不会清表」这类判据就测不准了 ——
  /// 而这条链最不该出的错恰好就是串页。
  @visibleForTesting
  factory OnlineTranslatedPageTrack.forTest() => OnlineTranslatedPageTrack._();

  String? _scope;

  /// 槽位 → 显示用哪张图。成品页被登记之后就落在这里。
  final Map<int, String> _displayed = <int, String>{};

  /// 槽位 → 这一页**解析到的原图**磁盘路径。OCR 的输入就是它。
  ///
  /// 由显示端在 build 时填（它手里已经有一份 `PictureBloc` 解析好的路径）：
  /// 这样既不用为了拿输入再走一次 `getCachePicture`（那可能触发一次下载），
  /// 也不会和显示用上的那份不是同一个文件。
  final Map<int, String> _sourcePaths = <int, String>{};

  /// 槽位 → 成品页路径。这份表就是在线档的
  /// [TranslatedPagePresenter.translationOwnedPages]：控制器的归属判据、
  /// 芯片的「这一页已经是译文」都读它。
  final Map<int, String> _overrides = <int, String>{};

  String? get scope => _scope;

  /// 当前是不是一个在线漫画页（正文画过至少一页才有）。
  bool get hasScope => _scope != null;

  Map<int, String> get translationOwnedPages => _overrides;

  /// 这一页**画面上**当前是不是就是那张成品页。
  ///
  /// `null` = 这一页还没在屏上建过（不是「没换上」，是「还不知道」）。
  /// 与本地那一路同一个口径：「注入了」和「画面上换了」是两件事，
  /// 芯片不能拿前者当后者的证据。
  bool? isShowing(String artifactPath, int index) {
    final shown = _displayed[index];
    if (shown == null) return null;
    return shown == artifactPath;
  }

  /// 显示端每次 build 该问的唯一一个问题，顺带把这一页的原图路径记下来。
  ///
  /// 返回覆盖路径（成品页还在、且文件还在）或 `sourcePath`。
  /// 这里在 build 里写表是有意的：记的就是这一帧马上要用那个值，
  /// 放到 postFrame 里只会让芯片在头一帧误判成「取不到输入」。
  /// 不触发 [notifyListeners] —— 否则每次重建都会再排一次重建。
  String displayPathFor({
    required String scope,
    required int index,
    required String sourcePath,
  }) {
    _bindScope(scope);
    _sourcePaths[index] = sourcePath;
    final override = _overrides[index];
    if (override != null && File(override).existsSync()) {
      _displayed[index] = override;
      return override;
    }
    _displayed[index] = sourcePath;
    return sourcePath;
  }

  String? sourcePathFor(int index) => _sourcePaths[index];

  /// 认领这一页：显示端从此画 [artifactPath]。
  void claim(int index, String artifactPath) {
    if (_overrides[index] == artifactPath) return;
    _overrides[index] = artifactPath;
    notifyListeners();
  }

  /// 摘掉认领，回到原图。
  void release(int index) {
    if (_overrides.remove(index) == null) return;
    notifyListeners();
  }

  /// 让显示端重新问一次（注入之后的「重画」，对应本地那路的
  /// `reshowAfterInjection`）。
  void redraw() => notifyListeners();

  /// 换书 / 换章：整张表作废。
  ///
  /// 为什么在这里清而不是靠调用方记得清：这张表按作用域键，
  /// 作用域是显示端报上来的，只有这里知道「换了」。
  void _bindScope(String next) {
    if (_scope == next) return;
    final hadPrevious = _scope != null;
    _scope = next;
    _displayed.clear();
    _sourcePaths.clear();
    _overrides.clear();
    if (hadPrevious) {
      // 在飞的构建要认出自己过期，否则旧章的成品页会注到新章同一序号那页上。
      _resetOnWakeup = true;
    }
    _scheduleWakeup();
  }

  /// 本帧结束后再播报（顺带补上攒下的控制器 reset）。
  ///
  /// 为什么不当场播：[displayPathFor] 是显示端**在 build 里**调的，而芯片与那一页
  /// 都挂着这个 notifier —— 当场 `notifyListeners()` 就是在构建过程中把监听者标脏，
  /// debug 下正是那句 `setState() or markNeedsBuild() called during build`。
  /// 记账照旧同步做完，只有「通知别人来重建」挪到微任务里。
  bool _wakeupScheduled = false;
  bool _resetOnWakeup = false;

  void _scheduleWakeup() {
    if (_wakeupScheduled) return;
    _wakeupScheduled = true;
    scheduleMicrotask(() {
      _wakeupScheduled = false;
      if (_resetOnWakeup) {
        _resetOnWakeup = false;
        TranslatedPageController.instance.reset();
      }
      notifyListeners();
    });
  }
}

/// 这一页属于**哪本书的哪一章** —— 成品页缓存与这张轨共用的作用域键。
///
/// 章必须在里面：只按书分的话，同一本书第 1 章和第 2 章的第 3 页会撞成同一个
/// `p3.png`。章节 id 缺失时往下退到 `storageChapterId`、再退到 `url`，
/// 因为退到空串就等于把所有章并成一个作用域 —— 那正是要防的那件事。
///
/// 返回 `null` 表示「这不像一个在线漫画页」（封面、插件图标之类），
/// 调用方据此不参与译文轨。
String? onlineTranslatedPageScope(PictureInfo info) {
  if (info.cartoonId.isEmpty) return null;
  final chapter = info.chapterId.isNotEmpty
      ? info.chapterId
      : (info.storageChapterId.isNotEmpty ? info.storageChapterId : info.url);
  if (chapter.isEmpty) return null;
  return '${info.from}|${info.cartoonId}|$chapter';
}
