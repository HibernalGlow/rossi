import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/page_source.dart';

/// 邻页的「只预取、不上屏」节点。
///
/// # 它解决的是这个回归
///
/// 以前每个 slot 都挂 `ImageSurface`，所以你在第 N 页时，**下一页已经被邻页 slot
/// 解好并画在它自己那一格里了** —— 翻过去是瞬间的。为了避免多个 slot 抢唯一那张
/// 上屏纹理（Ping-Pong → 红黄闪），改成只有当前页挂 `ImageSurface` 之后，这个
/// 「顺手把邻页解好」的副作用一起消失了，翻页退回成现场等 400–500 ms 的解码。
///
/// 本节点把丢掉的那部分单独补回来：它照常请求 native 侧解码并生成当前视口尺寸的
/// 预渲染帧（翻过去时 `show` 就能 <1 ms 命中），但**不写用户的 display buffer**，
/// 所以不会跟当前页抢纹理。
///
/// # 它和「邻页那个 `ImageSurface`」不是一件事
///
/// 邻页的 `ImageSurface` 解的是**给 Flutter 画的位图**（像素要过桥），用于翻页
/// 滑动期间那一半的画面；本节点解的是**给共享纹理用的帧**（像素不过桥），
/// 用于翻过去之后 `<1 ms` 就出图。两者目的地不同，谁也替不了谁。
///
/// # 它自己什么都不画
///
/// `SizedBox.shrink`：画面由旁边那个 `ImageSurface` 负责，这里只借 Flutter 的
/// 布局算出物理尺寸去发一次请求。
///
/// # 发不出去要重试，不能"发过就算了"
///
/// 它的第一次尝试常常落在「呈现器还没 `open` 过」或「native 侧还在建」的窗口里，
/// 那两件事都是**暂时**的。发一次就不再发，等于把这个机制整个废掉 ——
/// 详见 [_maxAttempts]。
class NeighborPagePrefetch extends StatefulWidget {
  const NeighborPagePrefetch({
    super.key,
    required this.source,
    required this.index,
    required this.presenter,
  });

  final PageSource source;
  final int index;
  final GpuPresentController presenter;

  @override
  State<NeighborPagePrefetch> createState() => _NeighborPagePrefetchState();
}

class _NeighborPagePrefetchState extends State<NeighborPagePrefetch> {
  /// 一次落空就放弃是**不够**的。
  ///
  /// [GpuPresentController.prepareNeighbor] 会在几种**正常**情形下返回 false ——
  /// 这一份来源还没被 native `open` 过（`_pushedPath` 还没建立）、呈现器还在
  /// 后台建、页面下标越界、或这一页刚好撞上一次解码失败。从前这里把
  /// `(页, 尺寸)` 一次性锁死、第一次落空就再不发，于是「预取了」只体现在日志里，
  /// 翻过去照样现场等 400–500 ms 的解码。
  ///
  /// 有限次 + **短**间隔就够：这不是"必须成功"的任务，而是**趁用户还在读这一页
  /// 的时候把下一页备好**。
  ///
  /// 间隔必须短于"连翻的间隔"：连翻时每页只停留两三百毫秒，而一次 `prepare`
  /// 本身要 200–300 ms —— 如果这里等 250 ms 才重试，那个重试几乎必然落在
  /// 用户已经翻走之后，等于白等。上限只是防止某一页永远准备不了时无限重试。
  static const int _maxAttempts = 30;
  static const Duration _retryDelay = Duration(milliseconds: 100);

  /// 已经**安排过**请求的（页 + 物理尺寸）。这个节点会在每次布局后被回调，
  /// 不去重就是每帧一次跨语言往返。
  int? _requestedIndex;
  String? _requestedSize;

  /// 当前这一轮要准备的物理尺寸（重试时要用它）。
  Size? _target;

  Timer? _retry;
  int _attempts = 0;

  @override
  void didUpdateWidget(NeighborPagePrefetch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index ||
        !identical(oldWidget.source, widget.source)) {
      _resetRound();
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    _retry = null;
    super.dispose();
  }

  void _resetRound() {
    _requestedIndex = null;
    _requestedSize = null;
    _target = null;
    _attempts = 0;
    _retry?.cancel();
    _retry = null;
  }

  Future<void> _attempt(Size physicalSize) async {
    if (!mounted) {
      return;
    }
    // **不要挤在"正在上屏"那一次前面**。
    //
    // macOS 上 `show` / `prepare` / `open` 共用**同一条串行队列**（见
    // `GpuPresentBridgeMac` 的 `workerQueue`），所以一次 `prepare` 会实实在在地
    // 插在当前页 `show` 前面，把翻页推迟一个全尺寸解码的时间。避开它是对的。
    //
    // 但判据**不能**用 `presentedFrame == null` 当「当前页还没出图」：`present()`
    // 一开头就把已完成帧清成 null（那是为了不让旧帧被当成新结果），于是**每次
    // 翻页之后的第一瞬间它都是 null**，而这个节点恰好就在那一刻被重建 ——
    // 那个判据会把它自己挡在门外，白白吃掉一个重试间隔。真正要避开的只有
    // 「当前页正在上屏」，用 `isPresenting` 判断才是准的。
    if (widget.presenter.isPresenting) {
      _scheduleRetry();
      return;
    }
    final bool accepted = await widget.presenter.prepareNeighbor(
      source: widget.source,
      index: widget.index,
      physicalSize: physicalSize,
    );
    if (!mounted) {
      return;
    }
    if (accepted) {
      return;
    }
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_attempts >= _maxAttempts) {
      return;
    }
    _attempts++;
    _retry?.cancel();
    _retry = Timer(_retryDelay, () {
      final Size? size = _target;
      if (!mounted || size == null) {
        return;
      }
      unawaited(_attempt(size));
    });
  }

  @override
  Widget build(BuildContext context) {
    final double devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size physicalSize = Size(
          constraints.maxWidth * devicePixelRatio,
          constraints.maxHeight * devicePixelRatio,
        );
        final String sizeKey =
            '${physicalSize.width.round()}x${physicalSize.height.round()}';
        final bool alreadyRequested =
            _requestedIndex == widget.index && _requestedSize == sizeKey;
        if (!alreadyRequested &&
            physicalSize.width >= 1 &&
            physicalSize.height >= 1) {
          _requestedIndex = widget.index;
          _requestedSize = sizeKey;
          _target = physicalSize;
          _attempts = 0;
          _retry?.cancel();
          // 不能在 build 里 await：下一帧再发。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            unawaited(_attempt(physicalSize));
          });
        }
        return const SizedBox.shrink();
      },
    );
  }
}
