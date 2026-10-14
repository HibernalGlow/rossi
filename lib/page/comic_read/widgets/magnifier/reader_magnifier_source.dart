/// 放大镜的**取样来源**：当前页那一份「可以取样的像素」，以及它落在屏幕上的位置。
///
/// 阅读页（宿主）每次把「现在这一页」报进来，子树里的 `ReaderMagnifierLayer`
/// 只读不写。几何全部走 `model/reader_magnifier.dart` 那份移植，这里只负责
/// **状态与生命周期**：谁是当前页、位图解出来没有、换了页要不要重解。
///
/// 为什么要是 `ChangeNotifier` 而不是 Bloc/Cubit：它不是业务状态机，
/// 而是「一页的像素什么时候到位」这一件事的回读路径 —— 与
/// `ReaderHoverController` 同一档（宿主 per-route 造一个、用 scope 递给子树）。
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:zephyr/page/comic_read/model/reader_magnifier.dart';

/// 取样位图**最长边**的上限（设备像素）。
///
/// 放大镜要的是源分辨率的细节，但「每次换页就整幅解一张原图」是一次内存尖峰：
/// 6000×8000 的 RGBA 约 180MB，而悬停检像素根本用不到那么多。
/// 按最长边 2048 收，最坏情况（正方形）约 16MB，在 800% 倍率下仍给得出可检分的像素。
/// 原图本身比这条小的话**不放大**（放大只会白吃内存，见下面的 `scale` 计算）。
const int kReaderLoupeMaxDecodeSide = 2048;

/// 把编码字节解成**最长边不超过 [maxSide]** 的位图；解不动返回 `null`。
///
/// 为什么不是字面意义上的 `ui.instantiateImageCodec(bytes, targetWidth:, targetHeight:)`：
/// 那两个参数**同时给**时引擎按字面值缩放、**不保宽高比**（只有恰好给一个才保），
/// 而「最长边封顶」这件事必须先知道内在尺寸 —— 回调式 API 是唯一给得到的地方。
/// `instantiateImageCodecWithSize` 的 `getTargetSize` 能读到内在宽高，
/// 于是比例在这儿自己算，半页/整页都不会被拉扁。
///
/// 返回 `null` 的下游契约：放大镜**没有像素就整块不画**（判据见 `canSample`），
/// 所以这条路不该把阅读器变成错误页，也不该每根指针都重试一次 ——
/// 重试的节流按页身份记在 `ReaderMagnifierSource` 里。
Future<ui.Image?> decodeReaderLoupeImage(
  Uint8List bytes, {
  int maxSide = kReaderLoupeMaxDecodeSide,
}) async {
  try {
    // buffer 由 instantiateImageCodecWithSize 自己 dispose，这里不能再 dispose 一次。
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (int intrinsicWidth, int intrinsicHeight) {
        final longest = math.max(intrinsicWidth, intrinsicHeight);
        if (maxSide <= 0 || longest <= maxSide) {
          return const ui.TargetImageSize();
        }
        final scale = maxSide / longest;
        return ui.TargetImageSize(
          width: math.max(1, (intrinsicWidth * scale).round()),
          height: math.max(1, (intrinsicHeight * scale).round()),
        );
      },
    );
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  } catch (error) {
    debugPrint('放大镜取样位图解码失败：$error');
    return null;
  }
}

/// 当前页「可取样的那一份像素 + 它在屏幕上的落位」。
///
/// 宿主（阅读页的 image widget）负责在页落位变化时调 [reportPage]；
/// **别在 build 里调** —— 它会 notifyListeners，而子树的放大镜层正听着这个通知。
class ReaderMagnifierSource extends ChangeNotifier {
  Object? _pageIdentity;
  Rect? _globalPageRect;
  Rect _bitmapUvSubRect = const Rect.fromLTRB(0, 0, 1, 1);
  int _rotationDegrees = 0;
  Future<ui.Image?> Function()? _requestImage;

  ui.Image? _image;
  Future<void>? _pending;

  /// 已经解失败过的页：同一页不再重试（否则每根悬停指针都撞一次解码）。
  /// 换页（[reportPage] 的身份变了）或 [clear] 才会再给一次机会。
  Object? _failedIdentity;

  /// 换代计数器：换页身份与 [clear] 都 +1。
  ///
  /// 为什么不能只比页身份：`clear()` 之后再把同一串身份报回来（重开放大镜、
  /// 回到同一页），旧的那次在飞解码会以为「还是当前页」把位图存进来 ——
  /// 而它其实属于上一代，那份像素该交还而不是该用。
  int _generation = 0;

  bool _isDisposed = false;

  /// 当前页的身份（章序+页序那种复合键，由宿主定义）。`null` = 没有页。
  Object? get pageIdentity => _pageIdentity;

  /// 这一页画在屏幕上的矩形（**全局逻辑坐标**，已算过对齐与留白）。
  Rect? get globalPageRect => _globalPageRect;

  /// 这一页用的是位图的哪一块：整页 = `Rect.fromLTRB(0, 0, 1, 1)`；
  /// 横长页被拆成两半时是左/右半（口径同 `PageSlice.uvRect`）。
  Rect get bitmapUvSubRect => _bitmapUvSubRect;

  /// 这一页当前的旋转角；非 360 整数倍时 [canSample] 直接为 false。
  int get rotationDegrees => _rotationDegrees;

  /// 已解出的取样位图；`null` = 还没解出来（或解不动）。
  ui.Image? get image => _image;

  /// 有像素了吗（与 [canSample] 的区别：这条不看页面矩形与旋转，只问位图在不在）。
  bool get hasImage => _image != null;

  /// 能不能取样。
  ///
  /// 三条都必须是肯定的：落位矩形有效、**位图已经解出来**、这一页没被任意角度旋转
  /// （`readerLoupeSupportedForRotation` 与上游同一口径 —— 旋转下 UV 逆变换没实现，
  /// 与其画错不如不画）。
  ///
  /// 这条就是「控件必须有回读路径」那一条：层**不许**声称自己能从一页没有像素的画面上取样。
  bool get canSample {
    final rect = _globalPageRect;
    return rect != null &&
        rect.width > 0 &&
        rect.height > 0 &&
        _image != null &&
        readerLoupeSupportedForRotation(_rotationDegrees);
  }

  /// 报告当前页。
  ///
  /// [requestImage] 由宿主决定怎么取字节：在线页走解好的文件路径，
  /// 本地页走 `LocalReadSession.instance.currentSource.getPageBytes(index)`，
  /// 两者都应当经由 [decodeReaderLoupeImage] 收最长边（不这么做就等于绕开内存上限）。
  ///
  /// **同一页重复报告不会重新解码**：页身份没变就留着已经解出的那一份，
  /// 只刷新矩形/UV 子矩形/旋转（翻页动画与滚动每帧都会报告新矩形，这正是懒解码的意义）。
  void reportPage({
    required Object pageIdentity,
    required Rect globalPageRect,
    required Rect bitmapUvSubRect,
    required Future<ui.Image?> Function() requestImage,
    required int rotationDegrees,
  }) {
    if (_isDisposed) return;
    final isSamePage = _pageIdentity == pageIdentity;
    if (!isSamePage) {
      // 换页：旧的那一份不是当前页的像素，立刻交还（原生位图不会自己回收），
      // 在飞的那次解码同时被记为过期（见 `_decode` 里的代次比对）。
      _generation = _generation + 1;
      _releaseImage();
      _pending = null;
      _failedIdentity = null;
    }
    _pageIdentity = pageIdentity;
    _globalPageRect = globalPageRect;
    _bitmapUvSubRect = bitmapUvSubRect;
    _rotationDegrees = rotationDegrees;
    _requestImage = requestImage;
    notifyListeners();
  }

  /// 离开阅读页 / 关掉放大镜时调用。
  void clear() {
    if (_isDisposed) return;
    _generation = _generation + 1;
    _releaseImage();
    _pending = null;
    _failedIdentity = null;
    _pageIdentity = null;
    _globalPageRect = null;
    _bitmapUvSubRect = const Rect.fromLTRB(0, 0, 1, 1);
    _rotationDegrees = 0;
    _requestImage = null;
    notifyListeners();
  }

  /// 触发一次解码（幂等）。
  ///
  /// 在飞的那次没结束、或已经有位图，都不会再调一次 [reportPage] 给的回调；
  /// 解完之后如果页身份已经变了，那份位图直接交还 —— 它不是当前页的像素。
  Future<void> ensureImage() {
    if (_isDisposed) return Future<void>.value();
    if (_image != null) return Future<void>.value();
    final pending = _pending;
    if (pending != null) return pending;
    final request = _requestImage;
    final identity = _pageIdentity;
    if (request == null || identity == null) return Future<void>.value();
    if (_failedIdentity == identity) return Future<void>.value();
    final future = _decode(request, identity, _generation);
    _pending = future;
    return future;
  }

  Future<void> _decode(
    Future<ui.Image?> Function() request,
    Object identity,
    int generation,
  ) async {
    ui.Image? image;
    try {
      image = await request();
    } catch (error) {
      debugPrint('放大镜取样回调抛了：$error');
      image = null;
    }
    final isCurrent =
        !_isDisposed && _generation == generation && _pageIdentity == identity;
    if (isCurrent) {
      _pending = null;
      if (image == null) {
        // 解不动的页记一笔：别每根悬停指针都撞一次解码。
        _failedIdentity = identity;
        return;
      }
      _image = image;
      notifyListeners();
      return;
    }
    // 解回来时已经不是那一页了（或来源整个被销毁、或换过一代）：这一份没有归宿。
    image?.dispose();
  }

  void _releaseImage() {
    _image?.dispose();
    _image = null;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _releaseImage();
    _pending = null;
    _requestImage = null;
    super.dispose();
  }
}

/// 让阅读页把来源交给子树（口径同 `ReaderFullscreenScope.maybeOf` / `ReaderHoverScope.of`）。
///
/// 用 `maybeOf` 而不是 `of`：放大镜是**可选**能力，没有宿主在场时子树该安静地不画，
/// 而不是在断言上炸。
class ReaderMagnifierScope extends InheritedWidget {
  const ReaderMagnifierScope({
    super.key,
    required this.source,
    required super.child,
  });

  final ReaderMagnifierSource source;

  static ReaderMagnifierSource? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ReaderMagnifierScope>()
        ?.source;
  }

  @override
  bool updateShouldNotify(covariant ReaderMagnifierScope oldWidget) =>
      source != oldWidget.source;
}
