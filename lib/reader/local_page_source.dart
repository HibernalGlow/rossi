import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/src/rust/api/local.dart';

/// 本地来源（散图文件夹 / CBZ / CBR）在 [PageSource] 上的实现。
///
/// # 它同时是**会话的唯一持有者**
///
/// `local_core` 的会话 id 在这里归口：打开、取页、关闭都经过这一个对象。
/// 这不是整洁问题 —— 会话是判据 D 的观测对象（`localOpenSessionCount()`
/// 不允许单调上升），而**会话泄漏不体现在 RSS 里**，只能靠计数看。
/// 收敛之前，界面自己存着 id 且 `dispose` 里从不关闭，于是「重复打开同一本书」
/// 与「切页时换源」都会各漏一个会话。
///
/// # 与 GPU 路的关系
///
/// GPU 路**不走这里取像素**：它拿 [rasterTargetFor] 给出的 `(path, index)`，
/// 由 native 侧自己打开文件、自己解码（像素不过桥）。两侧能对同一页达成一致，
/// 是因为跑的是同一份枚举代码（`rossi_gpu_present` 依赖 `rossi_local_core`），
/// 而不是因为在这里做了什么同步 —— 所以页数要被交叉校验，见 [GpuPresentController]。
class LocalPageSource implements PageSource {
  /// 位置参数而不是命名参数：字段是私有的，而**命名参数不能以下划线开头**，
  /// 于是「命名 + 私有字段」只能退化成初始化列表赋值（会被 lint 判为多余）。
  /// 这个构造函数本来也只有内部调用点，不值得为它换一套字段命名。
  LocalPageSource._(this._id, this._path, this._pages);

  final BigInt _id;
  final String _path;
  final List<PageRef> _pages;

  bool _closed = false;

  @override
  String get path => _path;

  @override
  List<PageRef> get pages => _pages;

  @override
  int get pageCount => _pages.length;

  /// 打开一个本地来源。
  ///
  /// 返回联合而不是抛异常，理由与 FFI 层一致：**拒绝是预期结果之一**，
  /// 而调用方要对不同类别给不同的下一步动作。抛异常会把「这本是固实 RAR」
  /// 和「程序出错了」压成同一条提示。
  static Future<PageSourceOpen> open(String path) async {
    final LocalSourceOpenResult result = await openLocalSource(path: path);

    final LocalSourceInfo? info = result.source;
    if (info == null) {
      final LocalRejection? rejection = result.rejection;
      return PageSourceRejected(
        kind: _rejectionKind(rejection?.kind),
        message: rejection?.message ?? '打不开：$path',
      );
    }

    final List<LocalPageInfo> pages = await localSourcePages(id: info.id);
    if (pages.isEmpty) {
      // 空来源在本地核心是**正常打开**，但一个 0 页的来源没有任何可用性。
      // 在这里就关掉会话并按 `empty` 归类，免得界面显示「0 / 0 页」
      // 却说不清是"还没打开"还是"打开了但没有页" —— 这两种要给的提示完全不同。
      localClose(id: info.id);
      return PageSourceRejected(
        kind: PageSourceRejectionKind.empty,
        message: switch (info.kind) {
          LocalSourceKind.folder => '这个文件夹里没有可显示的图片',
          LocalSourceKind.zip => '这个压缩包里没有可显示的图片',
          LocalSourceKind.rar => '这个压缩包里没有可显示的图片',
        },
      );
    }

    final List<PageRef> refs = <PageRef>[
      for (final LocalPageInfo page in pages)
        PageRef(index: page.index, name: page.name, size: page.size),
    ];
    return PageSourceOpened(LocalPageSource._(info.id, info.path, refs));
  }

  @override
  RasterTargetRef? rasterTargetFor(int index) {
    if (index < 0 || index >= _pages.length) {
      return null;
    }
    return RasterTargetRef(path: _path, index: index);
  }

  @override
  Future<PageLoadOutcome> load(
    int index, {
    int? targetWidth,
    PageLoadIntent intent = PageLoadIntent.interactive,
  }) async {
    final LocalPageDecodeResult result = await localPagePixels(
      id: _id,
      index: index,
      targetWidth: targetWidth,
      priority: switch (intent) {
        PageLoadIntent.interactive => LocalPageLoadPriority.high,
        PageLoadIntent.prefetch => LocalPageLoadPriority.normal,
      },
      // 目前只有顺序阅读：翻页与预取都**不**作废已受理的目标 ——
      // 连翻三页就是三页都要，中间那页用户真的看过。
      // 跳页（`LatestSeek`）要等阅读器有页列表 / 滑杆时再加：
      // 那时才存在「用户已经改主意，排队中的旧请求该全部作废」这个前提。
      contract: LocalPageLoadContract.sequential,
    );

    final LocalPagePixels? pixels = result.pixels;
    if (pixels != null) {
      return PageLoaded(
        RasterPageContent(
          width: pixels.width,
          height: pixels.height,
          sourceWidth: pixels.sourceWidth,
          sourceHeight: pixels.sourceHeight,
          rgba: pixels.rgba,
        ),
      );
    }

    final LocalDecodeFailure? failure = result.failure;
    return PageLoadFailed(
      kind: _failureKind(failure?.kind),
      message: failure?.message ?? '第 ${index + 1} 页没能解出来',
    );
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    localClose(id: _id);
  }

  /// FFI 枚举 → 本层枚举。**逐项写出而不是 `default`**：
  /// 上游加一个拒绝类别时这里会编译不过，而不是静默归到 `io`。
  static PageSourceRejectionKind _rejectionKind(LocalRejectionKind? kind) {
    switch (kind) {
      case LocalRejectionKind.unknownFormat:
        return PageSourceRejectionKind.unknownFormat;
      case LocalRejectionKind.rarSolid:
        return PageSourceRejectionKind.rarSolid;
      case LocalRejectionKind.rarNestedArchive:
        return PageSourceRejectionKind.rarNestedArchive;
      case LocalRejectionKind.rarEncrypted:
        return PageSourceRejectionKind.rarEncrypted;
      case LocalRejectionKind.notFound:
        return PageSourceRejectionKind.notFound;
      case LocalRejectionKind.io:
        return PageSourceRejectionKind.io;
      case null:
        return PageSourceRejectionKind.io;
    }
  }

  static PageLoadFailureKind _failureKind(LocalDecodeFailureKind? kind) {
    switch (kind) {
      case LocalDecodeFailureKind.shellOnlyFormat:
        return PageLoadFailureKind.shellOnlyFormat;
      case LocalDecodeFailureKind.decodeFailed:
        return PageLoadFailureKind.decodeFailed;
      case LocalDecodeFailureKind.cancelled:
        return PageLoadFailureKind.cancelled;
      case null:
        return PageLoadFailureKind.decodeFailed;
    }
  }
}
