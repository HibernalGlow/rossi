/// Rossi Reader 的页面来源抽象。词汇表在 `CONTEXT.md`「PageSource」。
///
/// # 这一层为什么必须存在
///
/// 在它之前，同一份文件被**打开两次**：CPU 兜底路走 `local_core` 的 FRB 接口开一份，
/// GPU 路让 native 侧再开一份，两边各自维护「有几页、现在是第几页、拒绝原因是哪类」。
/// 两份状态会在三处悄悄漂移：页数（读了两个不同时刻的目录）、拒绝类别
/// （只有 FRB 那条能给出「固实 RAR」这类精确分类）、以及生命周期
/// （会话 id 存在界面里、`dispose` 时不关，于是换书就漏一个会话）。
///
/// 收敛之后：**页表只有一份，会话只有一份，关闭只有一处**。两条显示路径都从
/// 同一个来源取它们各自需要的东西 —— 一条取像素，一条取「让 native 自己去读哪一页」。
///
/// # 它不做什么
///
/// 不含 Flutter widget 依赖，也不持有任何位图：所以它能被单元测试直接驱动，
/// 也能被将来的在线源实现。位图的持有与释放属于**显示节点**，不属于来源。
library;

import 'dart:typed_data';

/// 一页在**来源**眼里的身份。
///
/// 刻意不含像素、也不含解码结果 —— 因为同一页要被两条完全不同的路径消费：
/// - CPU 兜底路要的是**像素**（[PageSource.load]）；
/// - GPU 路要的是「让 native 侧自己去读哪一页」（[PageSource.rasterTargetFor]）。
///
/// 把「页的身份」与「页的内容」分开，是这两条路能共用同一个来源的前提：
/// 一旦来源把「我有哪些页」和「这一页长什么样」揉在一起，GPU 路就只能二选一 ——
/// 要么依赖来源的像素（那就过桥了），要么另开一份来源自己去数页（那就漂移了）。
class PageRef {
  const PageRef({required this.index, required this.name, required this.size});

  /// 页序下标。**权威在 Rust 侧**（`rossi_local_core` 的自然序），Dart 不得重排。
  final int index;

  /// 展示名。
  final String name;

  /// 编码字节数。文件夹来源为文件长度。
  final BigInt size;

  @override
  String toString() => 'PageRef($index, $name, $size)';
}

/// 一页解出来的内容。
///
/// 为什么是**封闭联合**而不是「一个 RGBA 位图」：`CONTEXT.md` 的占位条款要求
/// `PageSource` 不假设「一页 = 一张静态图」（视频页），并说明这个前提
/// 「现在定型几乎免费、以后改很贵」。用 `sealed` 而不是开放继承，是为了让
/// 调用方**必须**在 `switch` 里处理每一种内容 —— 视频页加进来时，
/// 忘记处理的地方会编译失败，而不是把视频当静态图静默画出来。
sealed class PageContent {
  const PageContent();
}

/// 位图页：解码后的 RGBA8（未预乘、行主序）。
class RasterPageContent extends PageContent {
  const RasterPageContent({
    required this.width,
    required this.height,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.rgba,
  });

  /// 解码后的尺寸（降采样之后）。
  final int width;
  final int height;

  /// 解码器输出的原始尺寸（降采样之前）。与 [width] / [height] 分开，
  /// 是为了让「请求的宽度到底生效了没有」在界面上一眼可见。
  final int sourceWidth;
  final int sourceHeight;

  /// `width * height * 4` 字节。
  final Uint8List rgba;
}

/// 一次取页的结果。
///
/// 与 [PageSourceOpen] 一样用联合而不用异常：**「这一页没轮到就作废了」不是错误**。
/// `cancelled` 的那一页完全可能解得出，只是调用方改主意了 —— 把它当异常抛，
/// 界面就会把它显示成「这本解不了」，而那是错的结论。
sealed class PageLoadOutcome {
  const PageLoadOutcome();
}

class PageLoaded extends PageLoadOutcome {
  const PageLoaded(this.content);

  final PageContent content;
}

class PageLoadFailed extends PageLoadOutcome {
  const PageLoadFailed({required this.kind, required this.message});

  final PageLoadFailureKind kind;

  /// 可直接展示的说明（已本地化）。
  final String message;
}

/// 取页失败的类别。
///
/// **刻意不从 FFI 层直接透传**：`flutter_rust_bridge` 生成的枚举会随生成器版本
/// 变化，而界面的分支逻辑不该跟着生成物抖动。映射在 `LocalPageSource` 里显式写出，
/// 上游加一个分支就会编译不过，不会静默落到 `default`。
enum PageLoadFailureKind {
  /// 本地核心没有这个格式的解码器（jxl / heic / heif），要交外壳 ——
  /// 而外壳解得动与否取决于平台（Windows 引擎实测解不动）。
  shellOnlyFormat,

  /// 核心有解码器但没解出来：字节损坏、内容与格式不符等。
  decodeFailed,

  /// **没轮到就作废了**：请求还在排队时被更新的跳页请求取代，或调用方放弃。
  /// 它不是格式问题也不是数据问题 —— 界面不该把它显示成错误。
  cancelled,
}

/// 打开来源的结果：要么拿到来源，要么拿到**可分类的**拒绝原因。
sealed class PageSourceOpen {
  const PageSourceOpen();
}

class PageSourceOpened extends PageSourceOpen {
  const PageSourceOpened(this.source);

  final PageSource source;
}

class PageSourceRejected extends PageSourceOpen {
  const PageSourceRejected({required this.kind, required this.message});

  final PageSourceRejectionKind kind;

  /// 可直接展示给用户的说明（已本地化）。
  final String message;
}

/// 一个来源为什么不可用。
///
/// 前六项来自本地核心的 `UnsupportedSource` + IO 分类；`empty` 是我们这一层加的，
/// 因为**空来源在本地核心是正常打开**（`LocalSource::is_empty()` 为 true 而不是报错），
/// 于是「格式对、但里面没有可显示的页」这件事只能在这里被翻译成给用户看的说法。
///
/// 分类的意义在于下一步动作不同：「这本是固实 RAR，v0.1 打不开」和
/// 「路径不存在」对用户是两件事，不该共用一句提示。
enum PageSourceRejectionKind {
  /// 扩展名不在 v0.1 范围内（7z / PDF / 视频……）。
  unknownFormat,

  /// 固实（solid）RAR：读第 N 页要解压前 N-1 页。
  rarSolid,

  /// 归档里含嵌套归档（v0.1 不展开）。
  rarNestedArchive,

  /// 加密 RAR（v0.1 不提供密码输入）。
  rarEncrypted,

  /// 路径不存在或不可读。
  notFound,

  /// 其他 IO / 解析失败（含归档损坏）。
  io,

  /// 打开成功，但里面没有可显示的页（空文件夹 / 0 页归档）。
  empty,
}

/// 让**渲染后端**自己读这一页所需的身份。
///
/// 它存在的理由：GPU 路的契约是「像素不过桥」，所以后端必须能自己打开文件、
/// 自己读第 N 页。而「同一页」在两侧必须指同一件东西 —— 这里的 [index] 与
/// [PageRef.index] 同源（都来自 `rossi_local_core` 的页序），因此
/// `(path, index)` 是一个**跨后端有效的页标识**，不需要第二个来源去数页。
///
/// 注意这条一致性**不是**靠在这里做同步维持的，而是因为两侧跑的是同一份枚举代码
/// （`rossi_gpu_present` 依赖 `rossi_local_core`，用的是同一个 `LocalSource::open`）。
/// 也正因为它依赖「两侧同一份代码」这个前提，显示节点必须**交叉校验页数**
/// （见 `GpuPresentController.present`）—— 前提失效时要能立刻发现，而不是画错页。
class RasterTargetRef {
  const RasterTargetRef({required this.path, required this.index});

  final String path;
  final int index;

  @override
  String toString() => 'RasterTargetRef($path#$index)';
}

/// 这次取页的意图。它决定优先级与契约，语义见 `CONTEXT.md`「页加载许可」。
///
/// 只给两个值而不是把优先级 / 契约直接摊开：调用方关心的是**谁在等**，
/// 而「谁在等」到「用哪张许可」的映射应当是唯一的、写在一处的。
enum PageLoadIntent {
  /// 用户此刻在等这一页 → `High` + `Sequential`。
  ///
  /// `High` 的意义是调度器为此留了 2 张许可只给它 —— 「预取把许可占满、
  /// 用户那一页排在后面」因此在结构上不可能，不靠调参。
  interactive,

  /// 预取 / 预热 → `Normal` + `Sequential`，可以等。
  prefetch,
}

/// Reader 唯一的页面来源抽象。
///
/// 「唯一」是指**同一个已打开的来源同时服务两条显示路径**，而不是
/// 「两条路径各有一个实现」。
abstract class PageSource {
  /// 页表。**页序权威在 Rust 侧**，实现不得重排。
  List<PageRef> get pages;

  int get pageCount;

  /// 这个来源的根路径。GPU 路要用它让 native 侧自己打开同一份文件。
  String get path;

  /// 让渲染后端按自己读数的方式拿到这一页；下标越界返回 `null`。
  ///
  /// 返回 `null` 而不是抛异常：显示节点在切页时可能拿着上一份来源的下标，
  /// 那不是错误，是该被忽略的过期输入。
  RasterTargetRef? rasterTargetFor(int index);

  /// 取一页的内容（CPU 兜底路用）。越界由实现决定报错方式。
  Future<PageLoadOutcome> load(
    int index, {
    int? targetWidth,
    PageLoadIntent intent = PageLoadIntent.interactive,
  });

  /// 关闭来源、释放会话。
  ///
  /// **必须幂等**：显示节点切换与页面销毁都会调它，两条路径都可能在
  /// 「已经关了」之后再调一次。
  Future<void> close();

  /// 获取该页在磁盘上的直接文件路径（散图文件夹有效，归档内图片返回 null）。
  Future<String?> getPageFilePath(int index) => Future.value(null);

  /// 获取该页的原始编码字节（JPEG/PNG/WebP 等）。
  Future<Uint8List?> getPageBytes(int index) => Future.value(null);
}
