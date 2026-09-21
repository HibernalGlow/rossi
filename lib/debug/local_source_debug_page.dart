import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/src/rust/api/local.dart';

/// 本地来源（判据 A）的调试页：把 `rossi_local_core` 的读取路径真正跑起来。
///
/// 四条边界，写在这里免得以后误读：
///
/// 1. **两条解码路径都在这里，可当场对照。** 「外壳」= 编码字节过桥交给 Flutter 引擎
///    （`docs/v0.1-local-core.md` §9 允许的兜底形态）；「Rust」= `local_page_pixels`
///    解码后把 RGBA 交给 Dart —— 这是 avif 唯一能出图的形态。
///    **两者都不是最终上屏路径**：目标是 Rust 解码后直接进 GPU texture（Phase 1 的
///    `texture-bridge`）。Rust 路目前要把整块 RGBA 过桥，所以本页的帧率**不能**
///    当作判据 B/C 的结论。
/// 1b. **Rust 路的瓶颈不在解码，在搬运，所以它必须降采样。** 2026-09-16 实测
///    （`cargo run -p rossi_local_core --bin scale_probe`，5464×8192 的 AVIF）：
///    Rust 侧全尺寸解码 + 装箱只要 **267 ms**（其中 dav1d 249 ms），
///    而当时 App 里同一页量到 `解码 1526.8 ms` —— **83% 花在「170 MB 过桥 +
///    173 MB 的 `decodeImageFromPixels`」**。位图降到 3.4 MB 时整段掉到 300–400 ms。
///    所以「尺寸」这个开关对 Rust 路不是画质旋钮，是可用性前提；
///    原始尺寸也一并显示出来，好判断降采样到底生效没有。
/// 2. **不缓存归档句柄，只缓存「解好的 ±1 页」。** 每次翻页都重新走
///    `localPageBytes` / `localPagePixels`，顺便让「不常驻句柄」这条性质在 UI 上可见
///    （判据 D 的结构性依据）。缓存只有预取那一份，且是**有界**的（≤3 页 / ≤64 MB，
///    见 `_prefetchMaxEntries`、`_prefetchMaxBytes`）—— 它缓的是**派生结果**，
///    不是归档内容或句柄，所以判据 D 的结论不变。当前页换掉时上一页的解码结果
///    一起释放（`_releaseCurrentImage`，预取也一并丢）—— 真实扫描页单页可达
///    44.8 MPix（RGBA 位图 179 MB），不主动释放会立刻冲垮 Flutter 默认 100 MB
///    的图片缓存，变成「反复解码」。
/// 3. **默认按「显示尺寸」解码。** 对两条路径它都是默认档，但意义不同：
///    外壳路径上它是**量具**（关掉就能看到引擎全尺寸解码的原价，也是判据 C
///    不可能由「Dart/CPU 全尺寸解码」达成的直接证据）；Rust 路径上它是
///    **可用性前提**（全尺寸 = 把 170 MB 搬过桥，见上一条 1b）。
///    代价是放大超过 2× 会看到模糊 —— 属预期，真正的解在 Phase 2 的 tile 化。
/// 3b. **预取相邻页，是「翻页 < 200 ms」唯一成立的理由。** 这本 AVIF 的冷页解码
///    地板是 **270 ms**，而且软硬两侧都压不下去：dav1d 已用满 16 核仍只有 2.25×
///    加速（这条流几乎没有 tile 级并行），NVDEC 直接拒绝 4:4:4
///    （`av1_cuvid: not supported with this chroma format`）。所以只能**不在翻页时解码**：
///    翻完一页后把窗口内的页解好、`ui.Image` 也建好存起来，
///    翻到时路径上只剩「换个引用 + 画一帧」。
///    **成本没消失，是被挪到用户读上一页的时候了** —— 所以页面上必须同时显示
///    「预取时花了多少」，否则那个数字会读成「解码变快了」。预取只走 Rust 路径
///    （外壳路径的位图在全局图片缓存里，那是另一套机制，未接）。
/// 3c. **预取必须给翻页让路，而且这件事比「提高优先级」更重要。**
///    2026-09-16 实测咬过一次：预取**命中**的一页（位图只有 1.5 MB）翻页仍要
///    87–258 ms 才出帧，冷页也从 431 ms 涨到 550–648 ms。原因不是纹理上传
///    （位图小了 10 倍反而更慢），是**预取与翻页同时解码** —— dav1d 一条流几乎
///    不能并行，并发不是分核而是双输，顺带把 Flutter 的帧生产也饿住了。
///    做法照上游 mImageViewer `update_prefetch_window`（`app.rs:55192`）：
///    当前页还没显示出来时取消其它 pending、连新的先読み也不发；
///    我们另加一条「每解完一页重新问一次『用户在等吗』」。
///    字段与显示见 `_prefetchGeneration` / `_prefetchNote` / `_frameCostLabel`。
/// 4. **本页不新增 i18n 键、不注册 auto_route**：调试页属于内部工具，走
///    `MaterialPageRoute` 直连，避免为一个诊断页触发全量 codegen。
///    若将来要转正，再补 `@RoutePage()` 与 `slang` 词条。
class LocalSourceDebugPage extends StatefulWidget {
  const LocalSourceDebugPage({super.key});

  @override
  State<LocalSourceDebugPage> createState() => _LocalSourceDebugPageState();
}

/// 一次翻页的分段记录。留着历史才能对比「全尺寸 vs 显示尺寸」。
class _StageRow {
  _StageRow({
    required this.index,
    required this.mode,
    required this.read,
    required this.decode,
    required this.pack,
    required this.paint,
    required this.total,
    required this.width,
    required this.height,
    required this.cacheHit,
    this.sourceWidth = 0,
    this.sourceHeight = 0,
    this.prefetchHit = false,
    this.prefetchCost,
    this.prefetchDuringDecode = 0,
    this.prefetchWait,
  });

  final int index;
  final String mode;
  final Duration read;

  /// 编码字节 → 位图。
  ///
  /// 两条路径的**含义不同，别直接比**：外壳路径是引擎解码；
  /// Rust 路径是「Rust 解码器 + FRB 过桥」，读页那一段也并了进来（所以 `read` 为 0）。
  final Duration decode;

  /// Rust 路径专有：位图字节 → `ui.Image`（`ui.decodeImageFromPixels`）。
  /// 外壳路径没有这一步，记 0。
  final Duration pack;

  final Duration paint;
  final Duration total;
  final int width;
  final int height;

  /// 解码器输出的原始尺寸（降采样前）。外壳路径拿不到，记 0。
  final int sourceWidth;
  final int sourceHeight;

  final bool cacheHit;

  /// 这一页是**预取命中**：翻页时既没解码也没建图，`decode` / `pack` 都是 0。
  ///
  /// 必须与 `cacheHit` 分开标：`cacheHit` 说的是「图片缓存命中，没重新解码」，
  /// 而这一条是「用户在翻之前我们就解好了」—— 成本没有消失，只是**挪到了翻页之外**。
  final bool prefetchHit;

  /// 预取这一页时实际花掉的（解码 + 建图），用于证明成本只是被挪走而非消失。
  final Duration? prefetchCost;

  /// 这一页**开始解码那一刻**，预取正占着几张许可。
  ///
  /// 这是「解 572 ms 而不是 431 ms」的解释项：dav1d 一条流几乎不并行
  /// （1 核 610–667 ms / 16 核 269–295 ms），所以两个解码同时跑不是分核，是双输。
  /// 记在行上而不是让人自己从「许可 N/6 在用」去推 —— 那个数在翻页结束时就变了。
  final int prefetchDuringDecode;

  /// 翻页等了「正在预取的这一页」多久才拿到图（合并路径，见 `_loadPage`）。
  ///
  /// 走这条路径时 `decode` / `pack` 仍是 0（翻页没解），但**用户确实等了**——
  /// 等待时间记在这里，不记进「屏」，否则历史行会谎报「合 9 ms」。
  final Duration? prefetchWait;

  int get pixels => width * height;

  /// RGBA 位图的字节数 —— 也就是要走一趟 PCIe 的那个量。
  int get bitmapBytes => pixels * 4;

  /// 相对原始像素量省下的比例，0 表示没省。
  double get pixelSaving {
    final source = sourceWidth * sourceHeight;
    if (source == 0) return 0;
    return 1 - pixels / source;
  }
}

/// 预取好的一页：已经解完码、已经建成 `ui.Image`，翻到它时零解码零建图。
///
/// 为什么必须有这个：这本 AVIF 单页冷解码的地板是 **270 ms**
/// （AV1 4:4:4、一个 tile、dav1d 已用满 16 核仍只有 2.25× 加速 —— 见
/// `docs/v0.1-local-core.md` §12.4），而且 **NVDEC 明确拒绝 4:4:4**
/// （`av1_cuvid` 报 `not supported with this chroma format`），
/// 所以「把解码本身做快」这条路在软硬两侧都走不通。
/// 唯一能让翻页掉到 200 ms 以下的办法是**别在翻页时解码**。
class _PrefetchedPage {
  _PrefetchedPage({
    required this.index,
    required this.targetWidth,
    required this.image,
    required this.width,
    required this.height,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.decode,
    required this.pack,
  });

  final int index;

  /// 预取时的目标宽。翻页时若窗口/开关变了，这份就作废（宁可重解也不能给错尺寸）。
  final int? targetWidth;

  final ui.Image image;
  final int width;
  final int height;
  final int sourceWidth;
  final int sourceHeight;

  /// 预取时花掉的两段成本，翻页后原样报出来。
  final Duration decode;
  final Duration pack;

  int get bytes => width * height * 4;

  void dispose() => image.dispose();
}

/// 这一页让谁来解码。
///
/// 这一维是 `avif` 逼出来的：Windows 引擎（`flutter_windows.dll`）没有链入 AV1
/// 解码器，外壳路径对它**必然失败**；而 Rust 侧（dav1d）能解。
/// 留着开关是为了让两条路径的耗时当场可比，而不是只能信文档里的数字。
enum _DecoderMode {
  /// 先试 Rust；它明确回答「这页归外壳」时才退回外壳。
  auto('解码器：自动'),

  /// 只走 Rust（`local_page_pixels`）。avif 唯一能出图的形态。
  rust('解码器：Rust'),

  /// 只走外壳（Flutter / Skia），即「编码字节过桥」。
  shell('解码器：外壳');

  const _DecoderMode(this.label);

  final String label;
}

class _LocalSourceDebugPageState extends State<LocalSourceDebugPage> {
  BigInt? _sessionId;
  LocalSourceInfo? _info;
  LocalRejection? _rejection;
  List<LocalPageInfo> _pages = const [];

  String? _error;
  bool _busy = false;

  /// 当前展示的页（-1 表示没有）。
  int _current = 0;
  Uint8List? _currentBytes;
  int? _currentBytesIndex;

  /// 当前页的 provider —— 持有它才能在换页时把上一页从图片缓存里踢掉。
  ImageProvider? _provider;

  /// Rust 解码路径产出的位图。非 null 时优先渲染，同时 `_provider` 会被清空。
  ///
  /// 两条路径的资源**互斥**，都靠 `_releaseCurrentImage()` 统一释放：
  /// 一页 44.8 MPix 的 RGBA 是 179 MB，漏掉任一边都会把内存顶上去。
  ui.Image? _rustImage;

  /// 解码器选择。默认 `auto`：Rust 优先，格式归外壳时自动退回。
  _DecoderMode _decoderMode = _DecoderMode.auto;

  /// 最近一次翻页的分段耗时与解出的尺寸。
  _StageRow? _stage;

  /// 最近若干次翻页（新→旧），用于对比解码模式切换前后的差异。
  final List<_StageRow> _history = [];

  /// 按显示尺寸解码（默认开）。关掉即量全尺寸成本。
  bool _displaySizedDecode = true;

  /// 后台预取相邻页（默认开）。关掉即回到「每次翻页现解」的对照形态。
  bool _prefetchEnabled = true;

  /// 预取缓存：页号 → 已解好且已建图的页。
  ///
  /// 有界（`_prefetchMaxEntries` / `_prefetchMaxBytes`）：一页显示尺寸约 4 MB 位图，
  /// 但**全尺寸是 179 MB** —— 那种档位下不开预取，见 `_prefetchPage`。
  final Map<int, _PrefetchedPage> _prefetch = {};

  /// 正在解的预取（index → 那一路的 future）。
  ///
  /// 有了让路机制还差一块：用户翻到「正在预取的那一页」时，那一路已经
  /// in-flight、取消不掉 —— 没有这张表的话翻页会**再解一遍同一页**
  /// （实测 2026-09-16：翻页 699 ms + 预取 829 ms，同一页并发解两次）。
  /// 翻页先查这里：等在跑的那路解完直接用。等待严格优于并发 ——
  /// 等待期内没有第二路在抢核；上游不需要这一步是因为它一张图一个核。
  final Map<int, Future<void>> _prefetchInFlight = {};

  /// 正在跑的翻页（index → 那一路的 future），防止快速连点造成同页双解。
  final Map<int, Future<void>> _turnInFlight = {};

  static const int _prefetchMaxEntries = 3;

  /// 预取缓存的总字节上限。超过就从「离当前页最远」的开始扔。
  static const int _prefetchMaxBytes = 64 << 20;

  /// 预取代号：每次翻页 +1，让上一轮「预取邻居」的循环自己退场。
  ///
  /// 它取代了原先那个 `bool _prefetchBusy`：「同一时刻只跑一个预取」现在由
  /// **代号退场**保证（翻页时上一轮直接结束）。
  ///
  /// **别再指望「High 预留 2 张许可」来保证预取不拖慢翻页** —— 那只保证翻页
  /// *拿得到许可*，不保证它*不跟预取分核*。dav1d 一条流几乎不并行，所以
  /// 「两张许可同时跑」= 两边都慢近一倍。上游也踩过同一个坑（`app.rs:55196`：
  /// 判断「有 High 预留枠就不需要取消 pending」而撤掉让路逻辑，实机 p50 148→396 ms）。
  /// 真正管用的是代号退场 + `_prefetchNeighbors` 里那个「用户在等吗」的每页复查。
  int _prefetchGeneration = 0;

  /// 上一次翻页/跳页的时刻。上游 `last_prefetch_scroll_at` 在分页阅读下的对应物
  /// —— 判决（`local_prefetch_decision`）用它算「静默了多久」。
  DateTime? _lastTurnAt;

  /// 当前这一页是否还在加载。上游 `visible_state_pending` 的对应物：
  /// 还在加载就不该让预取去抢许可，否则用户正在等的那一页会排在预取后面。
  bool _loadInFlight = false;

  /// 最近一次预取判决。**显示用** —— 让「现在为什么不预取」看得见：
  /// 只显示「没预取」的话，分不清是「还没静默」还是「当前页还在加载」。
  LocalPrefetchDecision? _lastPrefetchDecision;

  /// 调度器快照：此刻在跑/在等几个解码。这是许可模型的**可观测面** ——
  /// 没有它，「预取有没有在抢当前页的许可」只能靠感觉。
  LocalPageLoadStats? _loadStats;

  /// 「这一轮预取为什么中途收手」——让路 / 退场的原因。**显示用**。
  ///
  /// 与 `_lastPrefetchDecision`（准入门）分开：门说的是「这一刻该不该发」，
  /// 这里说的是「已经在跑的这一轮为什么停了」。缺了它，
  /// 「预取在给翻页让路」和「预取卡死了」在界面上长得一模一样。
  String? _prefetchNote;

  /// 最近一帧的耗时分解。
  ///
  /// **「上屏」不能用 postFrame 相减去量** —— 那里混着「等下一帧 vsync」的时间，
  /// 于是「143 ms」到底是**等**出来的还是**画**出来的分不清。这条纪律项目里早写过
  /// （见 `docs/v0.1-local-core.md` §12.2），但一直只是纪律；2026-09-16 有实测数据
  /// 咬人（命中预取的一页报 143–258 ms）才补上这个量具。
  ui.FrameTiming? _lastTiming;

  /// 由 `LayoutBuilder` 回填的预览区宽度（逻辑像素），用于估算解码目标宽度。
  double _viewerWidth = 0;

  /// 「逐页计时」的结果：每页耗时（毫秒）。
  List<double>? _sweepMs;
  double? _sweepTotalMs;

  int _probeCount = 0;

  @override
  void initState() {
    super.initState();
    // 「上屏」这把尺子的修正件，见 `_lastTiming` 的说明。
    WidgetsBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  void _onFrameTimings(List<ui.FrameTiming> timings) {
    if (timings.isEmpty) return;
    _lastTiming = timings.last;
    // 刻意不 setState：在帧回调里重建会自己制造抖动，量具就成了噪声源。
    // 这个数在下一次由别的原因触发的重建里顺带显示出来。
  }

  /// 一帧的耗时分解，一行字。
  String _frameCostLabel() {
    final t = _lastTiming;
    if (t == null) return '—';
    return 'build ${t.buildDuration.inMilliseconds} '
        'raster ${t.rasterDuration.inMilliseconds} '
        'vsync ${t.vsyncOverhead.inMilliseconds} ms';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeTimingsCallback(_onFrameTimings);
    // 页面销毁时把会话还回去，否则反复进出会看到探针单调上升。
    final id = _sessionId;
    if (id != null) {
      localClose(id: id);
    }
    _releaseCurrentImage();
    super.dispose();
  }

  /// 释放当前页的两条显示资源，连同预取缓存。
  ///
  /// 外壳路径的位图挂在全局图片缓存里，要 `evict`；Rust 路径的是我们自己的
  /// `ui.Image`，要 `dispose`。**两条都必须走这里** —— 一页 44.8 MPix 是 179 MB，
  /// 漏掉任一边都会在翻几页之后把内存顶上去（曾观测到 RSS 592 MB）。
  /// 预取缓存也在这里统一丢：它是「另一个会话 / 另一本书」的位图，留着没有意义。
  void _releaseCurrentImage() {
    final provider = _provider;
    _provider = null;
    unawaited(provider?.evict());

    final rustImage = _rustImage;
    _rustImage = null;
    rustImage?.dispose();

    _clearPrefetch();
  }

  Future<void> _refreshProbe() async {
    final n = localOpenSessionCount();
    if (mounted) setState(() => _probeCount = n);
  }

  Future<void> _closeCurrent({bool silent = false}) async {
    final id = _sessionId;
    if (id == null) return;
    localClose(id: id);
    // 解绑是大位图的唯一释放途径（见类注释第 2 条）。
    _releaseCurrentImage();
    if (!mounted) return;
    setState(() {
      _sessionId = null;
      _info = null;
      _pages = const [];
      _currentBytes = null;
      _currentBytesIndex = null;
      _stage = null;
      _history.clear();
      _sweepMs = null;
      _sweepTotalMs = null;
      if (!silent) _rejection = null;
    });
    await _refreshProbe();
  }

  Future<void> _openPath(String path) async {
    // 打点的目的是**让下一次原生崩溃有现场**。
    // 起因：一次 `zephyr has stopped working` 在 flutter run 控制台里
    // 一行输出都没有（无 Dart 异常、Windows 事件日志也无记录），
    // 事后完全无法判断崩溃前走到哪一步。这条日志就是给那种情况留的指纹。
    final swOpen = Stopwatch()..start();
    debugPrint('[local-debug] open 开始: $path');

    setState(() {
      _busy = true;
      _error = null;
      _rejection = null;
    });

    try {
      // 先关掉上一个会话：调试页要能体现「换书 = 释放」。
      await _closeCurrent(silent: true);

      final result = await openLocalSource(path: path);

      final rejection = result.rejection;
      if (rejection != null) {
        debugPrint(
          '[local-debug] open 被拒绝: ${rejection.kind} ${rejection.message}',
        );
        if (!mounted) return;
        setState(() {
          _rejection = rejection;
          _info = null;
          _pages = const [];
        });
        return;
      }

      final info = result.source!;
      debugPrint(
        '[local-debug] open 成功(未取页): id=${info.id} '
        'kind=${info.kind} pages=${info.pageCount} '
        'bytes=${info.totalBytes} ${swOpen.elapsedMilliseconds}ms',
      );

      final pages = await localSourcePages(id: info.id);
      debugPrint(
        '[local-debug] 取页完成: ${pages.length} 条 '
        '${swOpen.elapsedMilliseconds}ms',
      );

      if (!mounted) return;
      // 换书了：上一本解好的位图一页都不能留。
      _clearPrefetch();
      setState(() {
        _sessionId = info.id;
        _info = info;
        _pages = pages;
        _current = 0;
        _currentBytes = null;
        _currentBytesIndex = null;
        _stage = null;
        _history.clear();
        _sweepMs = null;
        _sweepTotalMs = null;
      });
      await _refreshProbe();
      if (pages.isNotEmpty) {
        await _loadPage(0);
      } else {
        // 0 页必须留下声音：否则「没反应」和「崩溃」在日志里长得一样。
        debugPrint(
          '[local-debug] 打开成功但 0 页 —— '
          '归档里没有任何 v0.1 能识别的页面: $path',
        );
      }
      debugPrint('[local-debug] open 流程结束 ${swOpen.elapsedMilliseconds}ms');
    } catch (e, st) {
      debugPrint('openLocalSource failed: $e\n$st');
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFolder() async {
    final path = await getDirectoryPath();
    if (path == null || path.isEmpty) return;
    await _openPath(path);
  }

  Future<void> _pickArchive() async {
    const group = XTypeGroup(
      label: '漫画归档',
      extensions: ['cbz', 'cbr', 'zip', 'rar'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return;
    await _openPath(file.path);
  }

  /// 目标解码宽度（物理像素）。
  ///
  /// 取预览区宽度 × 设备像素比；还没布局过就退回窗口宽度的估算值。
  /// 解码宽度只影响**显示**，不影响从归档里读出来的编码字节。
  int? _targetDecodeWidth() {
    if (!_displaySizedDecode) return null;
    final media = MediaQuery.maybeOf(context);
    if (media == null) return null;
    final logical = _viewerWidth > 0 ? _viewerWidth : media.size.width * 0.6;
    final px = (logical * media.devicePixelRatio).round();
    return px.clamp(64, 8192);
  }

  /// 解码失败时给一句**能指导下一步**的话。
  ///
  /// 直接把引擎原文丢出来（`Exception: Could not decompress image.`）等于把内部
  /// 细节推给用户；他真正需要知道的是「换个格式 / 等哪个功能 / 是不是书坏了」。
  /// 这里的措辞有实测依据，别随手改软：`integration_test/avif_decode_probe_test.dart`。
  static const _shellOnlyExtensions = {'jxl', 'heic', 'heif'};

  String _explainDecodeFailure(int index, int byteCount, String? errorText) {
    final name = index < _pages.length ? _pages[index].name : '';
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();

    // 编码字节读出来了 = 归档读取这一步没问题，失败发生在解码那一步。
    final head =
        '第 $index 页解码失败。\n'
        '编码字节 $byteCount B 已完整读出（归档读取正常，失败在解码这一步）。';

    if (ext == 'avif') {
      // 这条现在是「走错了路」而不是「做不到」——Rust 侧有 dav1d。
      // 措辞别改软，实测依据在 integration_test/avif_decode_probe_test.dart。
      return '$head\n'
          '该页是 .avif，**Rust 侧能解**（dav1d），解不了的是当前这条「外壳」路径：'
          'flutter_windows.dll 没有链入 AV1 解码器 —— 实测它读得出尺寸、给不出像素，'
          '而同尺寸 JPEG 完全正常。把上面的解码器切到「自动」或「Rust」即可。';
    }

    if (_shellOnlyExtensions.contains(ext)) {
      return '$head\n'
          '该页是 .$ext：本 crate 与这台机器的引擎都没有这种格式的解码器。'
          '这是已知平台限制，不是书坏了。';
    }
    return '$head\n引擎报错：${errorText ?? '未知'}';
  }

  /// 翻页入口：按 `_decoderMode` 决定让谁解。
  ///
  Future<void> _loadPage(int index, {bool force = false}) async {
    final id = _sessionId;
    if (id == null || index < 0 || index >= _pages.length) return;
    if (!force && _currentBytesIndex == index && _rustImage != null) {
      setState(() => _current = index);
      return;
    }
    if (!force && _currentBytesIndex == index && _currentBytes != null) {
      setState(() => _current = index);
      return;
    }

    // 同一页只允许一路翻页在跑。快速连点会让两个 `_loadPage(index)` 同时进来，
    // 都过不了上面的守卫（`_currentBytesIndex` 还没变）。实测（2026-09-16）：
    // 两路一起挤进「等在跑的预取」，预取产出只够一路拿到命中，另一路
    // 「没产出，掉回正常翻页」把同一页**再解一遍**（index=4 / 21 各一次）。
    // `force`（重读语义）刻意不参与去重。
    final existingTurn = _turnInFlight[index];
    if (existingTurn != null && !force) {
      await existingTurn;
      return;
    }
    final task = _loadPageTask(id, index, force: force);
    if (!force) {
      _turnInFlight[index] = task;
    }
    try {
      await task;
    } finally {
      if (!force) _turnInFlight.remove(index);
    }
  }

  /// `auto` 的语义是「**Rust 优先，格式归外壳时退回**」，不是「随便挑一个能用的」。
  /// 只有 Rust 明确回答 `shellOnlyFormat` 才算「这页归外壳」；解码失败是另一回事，
  /// 那种情况就地报错 —— 偷偷换条路会把失败藏起来，而失败正是这张页面要显示的东西。
  Future<void> _loadPageTask(
    BigInt id,
    int index, {
    required bool force,
  }) async {
    // 这两个是给预取判决用的状态（上游 `last_prefetch_scroll_at` 与
    // `visible_state_pending` 的对应物）。判决本身在 Rust 侧，这里只报事实。
    _lastTurnAt = DateTime.now();
    _loadInFlight = true;

    // ── 用户要翻页了：立刻让在跑的预取退场 ──
    //
    // 照的是 mImageViewer `update_prefetch_window` 的做法（`src/app.rs:55192`）：
    // **当前页还没有可显示内容的时候，取消其它 pending，并且连新的先読み也不发**。
    // 上游把这段撤过（判断「有 High 预留枠就不需要」），实机立刻变差：
    // 页面完成 p50 **148 ms → 396 ms**；理由是「已经拿到许可的先読み 会 commit 到
    // 一段不可中断的读取上」。所以这不是保守，是被数据逼回来的一行。
    //
    // 我们这边比上游更硬：dav1d 一条流几乎不能并行（实测 1 核 610–667 ms /
    // 16 核 269–295 ms，1→16 只有 2.25×），所以「预取与翻页并发」不是分核，
    // 而是**两边都慢近一倍**。观测到的正是这个：预取单独跑 431.6 ms，
    // 而它与翻页并发时，翻页那一次报 572–648 ms。
    //
    // 正在跑的那一页**取消不掉**（dav1d 一次调用不可中断，`acquire_cancellable`
    // 只覆盖「等许可」阶段）—— 但它跑完就会看到代号变了而退出循环，
    // 不会再发起下一页。这与上游 `pending.cancel()` 的覆盖面一致。
    _prefetchGeneration++;
    _prefetchNote = null;

    // 相邻页 = 顺序翻页；跨页与「重读当前页」= 跳页。
    //
    // 这个区分交给 Rust 调度器（`FsPageLoadContract`）：`LatestSeek` 会把同一会话里
    // **还在排队**的旧请求作废 —— 用户已经改主意了，中间那些页读完也没人看。
    // 而 `Sequential` 永不作废：连翻三页就是三页都要，中间那页用户真的看过。
    final contract = (index - _current).abs() == 1
        ? LocalPageLoadContract.sequential
        : LocalPageLoadContract.latestSeek;

    // 预取命中：翻页路径上只剩下「换个引用 + 画一帧」。
    // `force`（重读本页 / 切开关）刻意绕过它 —— 那是「立刻重新解一遍」的语义。
    if (!force) {
      final hit = _takePrefetch(index);
      if (hit != null) {
        _presentPrefetched(index, hit);
        _loadInFlight = false;
        return;
      }
      // 翻到了「正在预取的那一页」：等在跑的那一路，而不是再解一遍。
      // 让路机制只挡「发起下一页」，挡不住已经 in-flight 的那路 ——
      // 观测到的正是这个洞：翻页 699 ms + 预取 829 ms，同一页并发解两次。
      // 预取那路万一没产出（解失败 / 单页超预算），掉回正常翻页路径重解。
      final inFlight = _prefetchInFlight[index];
      if (inFlight != null) {
        final swWait = Stopwatch()..start();
        debugPrint('[local-debug] 翻页目标正在预取，等在跑的那一路 index=$index');
        await inFlight;
        final waited = swWait.elapsed;
        debugPrint(
          '[local-debug] 等预取完成 index=$index 等${waited.inMilliseconds}ms',
        );
        final hitAfterWait = _takePrefetch(index);
        if (hitAfterWait != null) {
          _presentPrefetched(
            index,
            hitAfterWait,
            waitedWhilePrefetching: waited,
          );
          _loadInFlight = false;
          unawaited(_refreshLoadStats());
          return;
        }
        debugPrint('[local-debug] 在跑的预取没产出，掉回正常翻页 index=$index');
      }
    }

    try {
      if (_decoderMode != _DecoderMode.shell) {
        final settled = await _loadPageViaRust(id, index, contract: contract);
        if (settled) return;
        debugPrint('[local-debug] Rust 判定这页归外壳，退回外壳路径 index=$index');
      }
      await _loadPageViaShell(id, index);
    } finally {
      // 出图了才算「可见区就绪」。预取的 100 ms 静默期是从**上一次翻页**算起的，
      // 不是从这里算起，所以不需要在这里再加延迟。
      _loadInFlight = false;
      unawaited(_refreshLoadStats());
    }
  }

  /// 外壳路径：把**编码字节**交给 Flutter 引擎解。
  ///
  /// 这是最早的形态，留着有两个理由：引擎认识的格式（jpg / png / …）走这条更省内存
  /// （能按显示尺寸解，不必全尺寸 RGBA 过桥），而且两条路径的耗时需要有个对照。
  Future<void> _loadPageViaShell(BigInt id, int index) async {
    final swAll = Stopwatch()..start();
    debugPrint('[local-debug] 读页开始 index=$index');

    // ── 第 1 段：读页（归档 → Rust → FRB → Dart 字节）──
    final swRead = Stopwatch()..start();
    final Uint8List bytes;
    try {
      bytes = await localPageBytes(id: id, index: index);
    } catch (e) {
      debugPrint('[local-debug] 读页失败 index=$index: $e');
      if (!mounted) return;
      setState(() => _error = '读第 $index 页失败：$e');
      return;
    }
    swRead.stop();
    final read = swRead.elapsed;
    debugPrint(
      '[local-debug] 读页完成 index=$index ${bytes.length} B '
      '${read.inMilliseconds}ms（解码前）',
    );
    if (!mounted) return;

    // ── 第 2 段：解码。解码宽度决定像素量，像素量决定解码与上屏的成本。──
    final targetWidth = _targetDecodeWidth();
    // 显式标注类型：`MemoryImage` 与 `ResizeImage` 的三元表达式会被推断成 `Object`。
    final ImageProvider<Object> provider = targetWidth == null
        ? MemoryImage(bytes)
        : ResizeImage(
            MemoryImage(bytes),
            width: targetWidth,
            allowUpscaling: false,
          );
    final mode = targetWidth == null ? '全尺寸' : '显示 ${targetWidth}px';

    final previous = _provider;
    _provider = provider;
    unawaited(previous?.evict());

    final swDecode = Stopwatch()..start();
    final stream = provider.resolve(ImageConfiguration.empty);
    var handled = false;

    void finish({
      required ui.Image? image,
      required Duration decode,
      required bool cacheHit,
      required bool isError,
      String? errorText,
    }) {
      if (handled || !mounted) return;
      handled = true;
      if (isError) {
        setState(() {
          _current = index;
          _currentBytes = bytes;
          _currentBytesIndex = index;
          _error = _explainDecodeFailure(index, bytes.length, errorText);
        });
        return;
      }

      // 第 3 段：解码完成 → 含该图的下一帧绘制结束。含纹理上传与首帧绘制。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final total = swAll.elapsed;
        final paint = total - read - decode;
        final width = image?.width ?? 0;
        final height = image?.height ?? 0;
        setState(() {
          _current = index;
          _currentBytes = bytes;
          _currentBytesIndex = index;
          // 上一页失败留下的说明要清掉，否则翻到好页也还挂着红字。
          _error = null;
          _stage = _StageRow(
            index: index,
            mode: mode,
            read: read,
            decode: decode,
            // 外壳路径没有「位图字节 → ui.Image」这一步：引擎一步到位。
            pack: Duration.zero,
            paint: paint.isNegative ? Duration.zero : paint,
            total: total,
            width: width,
            height: height,
            cacheHit: cacheHit,
          );
          _history.insert(0, _stage!);
          if (_history.length > 6) _history.removeLast();
        });
        debugPrint(
          '[local-debug] 翻页完成 index=$index $mode '
          '读${read.inMilliseconds} 解${decode.inMilliseconds} '
          '屏${paint.inMilliseconds} 合${total.inMilliseconds}ms '
          '${width}x$height',
        );
      });
    }

    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, synchronousCall) {
        swDecode.stop();
        // 同步回调 = 命中 Flutter 图片缓存，这一次没有真的解码。
        finish(
          image: info.image,
          decode: synchronousCall ? Duration.zero : swDecode.elapsed,
          cacheHit: synchronousCall,
          isError: false,
        );
        stream.removeListener(listener);
      },
      onError: (error, stackTrace) {
        debugPrint('decode page $index failed: $error');
        finish(
          image: null,
          decode: swDecode.elapsed,
          cacheHit: false,
          isError: true,
          errorText: error.toString(),
        );
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
  }

  /// Rust 路径：`local_page_pixels` —— Rust 解码后把 RGBA 交给 Dart 上屏。
  ///
  /// 返回值是「这件事办完了吗」：`false` 表示 Rust **明确回答这页归外壳**
  /// （`shellOnlyFormat`），调用方该退回外壳路径。这不是错误，是格式归属 ——
  /// 归属与失败必须分开，否则 `auto` 会退化成「随便挑一条能走的路」。
  ///
  /// ## 计时口径与外壳路径不同，别直接比
  ///
  /// 这里「解码」= Rust 解码器 **+ FRB 过桥**（字节量级 = 位图大小），
  /// 读页那一段并了进来（所以 `read` 记 0）；「建图」= `decodeImageFromPixels`。
  /// **Rust 侧解码本身的单价从 Dart 侧量不到**，要用
  /// `cargo run -p rossi_local_core --bin scale_probe` 量。
  ///
  /// ## `targetWidth` 不是可选优化
  ///
  /// 不给宽度就是原尺寸：44.8 MPix 的页解出 170.8 MB 位图，实测这一整段
  /// 要 1526 ms，而 Rust 侧纯解码只要 267 ms —— **83% 花在搬那 170 MB 上**。
  /// 给了宽度之后位图缩到几 MB，这一段跟着掉到 300–400 ms 量级。
  Future<bool> _loadPageViaRust(
    BigInt id,
    int index, {
    required LocalPageLoadContract contract,
  }) async {
    final swAll = Stopwatch()..start();
    final targetWidth = _targetDecodeWidth();

    // 开始解码之前先看一眼许可：预取正占着几张？这一趟解码会跟它抢核，
    // 抢到的结果是**两边都慢**（dav1d 一条流几乎不并行），所以把它记在行上。
    final beforeStats = await localPageLoadStats();
    final concurrentPrefetch = beforeStats.runningNormal;

    final swBridge = Stopwatch()..start();
    debugPrint(
      '[local-debug] Rust 解码开始 index=$index target=$targetWidth '
      '并发的预取=$concurrentPrefetch 许可在跑=${beforeStats.running}'
      '（预取 ${beforeStats.runningNormal}）等 ${beforeStats.waiting}',
    );

    final LocalPageDecodeResult result;
    try {
      result = await localPagePixels(
        id: id,
        index: index,
        targetWidth: targetWidth,
        // 用户此刻在等这一页：`High`。调度器为此留了 2 张许可**不给**预取 ——
        // 「预取不会拖慢翻页」在结构上就是这么成立的，不靠调参。
        priority: LocalPageLoadPriority.high,
        contract: contract,
      );
    } catch (e) {
      debugPrint('[local-debug] Rust 解码调用失败 index=$index: $e');
      return false;
    }
    swBridge.stop();

    final pixels = result.pixels;
    final failure = result.failure;

    if (pixels == null) {
      if (failure?.kind == LocalDecodeFailureKind.shellOnlyFormat) {
        return false;
      }
      if (failure?.kind == LocalDecodeFailureKind.cancelled) {
        // 还没轮到就被更新的跳页取代了。**这不是错误** —— 这一页完全可能解得出，
        // 只是没人要了。报成失败会把用户误导成「这本解不了」。
        debugPrint('[local-debug] 请求已作废 index=$index：${failure?.message}');
        return true;
      }
      debugPrint('[local-debug] Rust 解码失败 index=$index: ${failure?.message}');
      if (!mounted) return true;
      setState(() {
        _current = index;
        _error = '第 $index 页 Rust 解码失败。\n${failure?.message ?? '未知原因'}';
      });
      return true;
    }

    final swPack = Stopwatch()..start();
    final decoded = await _imageFromRgba(
      pixels.rgba,
      pixels.width,
      pixels.height,
    );
    swPack.stop();

    if (!mounted) {
      decoded.dispose();
      return true;
    }

    final stale = _rustImage;
    _rustImage = decoded;
    final staleProvider = _provider;
    _provider = null;
    unawaited(staleProvider?.evict());
    stale?.dispose();

    // 这里必须 setState：`RawImage` 不像 `Image` 那样订阅 ImageStream，
    // 少了这一句新位图根本不会被画出来，要等下一次**别的**原因触发的重建。
    // 实测那种「等」能长到 3.9 s —— 用户不动鼠标就一直不出图，
    // 而且它会被算进下面的「上屏」，让这个数字看起来像上屏花了 3.9 s。
    setState(() {
      _current = index;
      _currentBytes = null;
      _currentBytesIndex = index;
      _error = null;
    });

    // 上屏：与外壳路径同一套口径 —— 等含这张图的下一帧画完再收尾。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_rustImage, decoded)) return;
      final total = swAll.elapsed;
      final bridge = swBridge.elapsed;
      final pack = swPack.elapsed;
      final paint = total - bridge - pack;
      setState(() {
        _stage = _StageRow(
          index: index,
          mode: 'Rust ${pixels.width}px',
          read: Duration.zero,
          decode: bridge,
          pack: pack,
          paint: paint.isNegative ? Duration.zero : paint,
          total: total,
          width: pixels.width,
          height: pixels.height,
          sourceWidth: pixels.sourceWidth,
          sourceHeight: pixels.sourceHeight,
          cacheHit: false,
          prefetchDuringDecode: concurrentPrefetch,
        );
        _history.insert(0, _stage!);
        if (_history.length > 6) _history.removeLast();
      });
      debugPrint(
        '[local-debug] Rust 翻页完成 index=$index '
        '桥${bridge.inMilliseconds} 图${pack.inMilliseconds} '
        '屏${paint.inMilliseconds} 合${total.inMilliseconds}ms '
        '${pixels.sourceWidth}x${pixels.sourceHeight}'
        '→${pixels.width}x${pixels.height}'
        '${concurrentPrefetch > 0 ? " [与 $concurrentPrefetch 张预取并发]" : ""}',
      );
      // 这一页已经上屏，用户接下来多半在读它 —— 这段时间正好用来解下一页。
      _schedulePrefetch();
    });
    return true;
  }

  /// 预取命中：翻页路径上没有任何解码、没有 `decodeImageFromPixels`。
  ///
  /// 这条路径**只可能出现在 Rust 解码路径上**：预取本身走的就是 `local_page_pixels`。
  /// 页面上必须同时报出「预取时花了多少」，否则这个 20 ms 看起来像是解码变快了 ——
  /// 实际是那 300 ms 被挪到了用户读上一页的时候。
  void _presentPrefetched(
    int index,
    _PrefetchedPage hit, {
    Duration? waitedWhilePrefetching,
  }) {
    final swAll = Stopwatch()..start();

    final stale = _rustImage;
    _rustImage = hit.image;
    final staleProvider = _provider;
    _provider = null;
    unawaited(staleProvider?.evict());
    stale?.dispose();

    setState(() {
      _current = index;
      _currentBytes = null;
      _currentBytesIndex = index;
      _error = null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_rustImage, hit.image)) return;
      final total = swAll.elapsed;
      setState(() {
        _stage = _StageRow(
          index: index,
          mode: '预取命中',
          read: Duration.zero,
          decode: Duration.zero,
          pack: Duration.zero,
          paint: total,
          total: total,
          width: hit.width,
          height: hit.height,
          sourceWidth: hit.sourceWidth,
          sourceHeight: hit.sourceHeight,
          cacheHit: false,
          prefetchHit: true,
          prefetchCost: hit.decode + hit.pack,
          prefetchWait: waitedWhilePrefetching,
        );
        _history.insert(0, _stage!);
        if (_history.length > 6) _history.removeLast();
      });
      debugPrint(
        '[local-debug] 预取命中 index=$index 屏${total.inMilliseconds}ms '
        '（预取时解${hit.decode.inMilliseconds} 图${hit.pack.inMilliseconds}'
        '${waitedWhilePrefetching != null ? "，等预取${waitedWhilePrefetching.inMilliseconds}ms" : ""}）',
      );
      _schedulePrefetch();
    });
  }

  Future<ui.Image> _imageFromRgba(Uint8List rgba, int width, int height) {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  // ───────────────────────── 预取 ─────────────────────────
  //
  // 为什么预取是这个页面最该有的东西：冷页解码的地板是 270 ms（见
  // `docs/v0.1-local-core.md` §12.4），软硬两侧都压不下去 ——
  // 所以「翻页 < 200 ms」只能靠**不在翻页时解码**。
  // 成本没有消失，是从翻页路径挪到了用户正在读当前页的那段时间里。
  // 页面上必须同时显示「预取当时花了多少」，否则这个数字像是凭空变出来的。

  /// 刷新调度器快照。翻完一页调一次就够 —— 它不是实时表，是「此刻许可怎么分的」。
  Future<void> _refreshLoadStats() async {
    final stats = await localPageLoadStats();
    if (!mounted) return;
    setState(() => _loadStats = stats);
  }

  String _loadStatsLabel() {
    final stats = _loadStats;
    if (stats == null) return '—';
    final busy = stats.running + stats.cancelling;
    return '$busy/${stats.totalLimit} 张在用'
        '（${stats.runningNormal} 张是预取；预留 ${stats.highReserved} 张给翻页），'
        '${stats.waiting} 个在等';
  }

  /// 把当前页的相邻页排进预取队列。
  ///
  /// **判决在 Rust 侧**（`local_prefetch_decision` → 上游 `decide_prefetch_allowed`），
  /// 这里只递状态、并按节奏再问一次。目标顺序同样来自 Rust
  /// （`local_prefetch_targets` → 上游 `interleaved_prefetch_positions`）。
  ///
  /// **刻意不在这一层写第二套策略。** 一旦本地也判一次，`rossi_local_core::prefetch_policy`
  /// 里那 13 条测试就管不到真实行为了 —— 我们手搓的「180 ms 延迟 + 一个布尔」
  /// 就是它的退化版，被替换掉正是这次搬运的目的。
  void _schedulePrefetch() {
    if (!_prefetchEnabled) return;
    // 用户明确选了「外壳」就别再走 Rust 解 —— 预取缓存会被 `_takePrefetch`
    // 直接采用，那就等于偷偷把解码器换回去了。
    if (_decoderMode == _DecoderMode.shell) return;
    final id = _sessionId;
    if (id == null) return;
    final generation = ++_prefetchGeneration;
    unawaited(_prefetchNeighbors(id, generation));
  }

  Future<void> _prefetchNeighbors(BigInt id, int generation) async {
    // 等放行。上游是每帧问一次 `decide_prefetch_allowed`；宿主从 egui 的帧循环
    // 换成 Flutter 之后，改成每 50 ms 问一次 —— 同一个门槛，只是问的节奏变了。
    //
    // 代号（`_prefetchGeneration`）在**两个**地方 +1：翻页发起时（`_loadPage`，
    // 对应上游「当前页不可显示 ⇒ 取消其它 pending」）和本函数被重新调度时。
    // 所以下面每个检查点都会在翻页的瞬间直接退场 —— 连翻时一页都不会解，
    // 那是有意的：dav1d 吃满 16 核，跟正在等的那次翻页抢核就是拖慢用户。
    for (var round = 0; ; round++) {
      if (!mounted || generation != _prefetchGeneration) return;
      final decision = await localPrefetchDecision(
        msSinceLastTurn: _lastTurnAt == null
            ? null
            : BigInt.from(
                DateTime.now().difference(_lastTurnAt!).inMilliseconds,
              ),
        visiblePending: _loadInFlight ? 1 : 0,
      );
      if (!mounted || generation != _prefetchGeneration) return;
      if (_lastPrefetchDecision?.reason != decision.reason) {
        setState(() => _lastPrefetchDecision = decision);
      }
      if (decision.allowed) break;
      // 3 秒 backstop 之后判决必然放行（上游保证）。问到 4 秒还拦着，
      // 说明是判决本身出了问题，不是「还没到点」—— 退场而不是死循环。
      if (round > 80) {
        debugPrint('[local-debug] 预取放弃：判决持续拦截 ${decision.message}');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    // 判决放行了，这一轮真的开始跑 —— 把上一轮的收手理由清掉。
    // 不清的话，「预取在让路」会一直挂在界面上，看起来像预取再也没动过。
    if (_prefetchNote != null) setState(() => _prefetchNote = null);

    // 目标顺序 `+1, -1, +2, …`（同距离 forward 先），边界由上游函数处理。
    //
    // **窗口大小是刻意偏离上游的，而且理由不是「上游的页便宜」。**
    //
    // 上游全屏页预取的默认窗口是 `prefetch_forward = 12` / `prefetch_back = 4`
    // （`settings.rs:6065`，keep 各 +1）。它敢开这么大，是因为它的解码**一张只占一个核**：
    // 全屏解码主路径是 `image` crate（`canonical_image_loader.rs:453/466`
    // → zune-jpeg / png，都是单线程），**WIC 只是第二顺位 fallback**（:455/468，
    // 顺序被测试 `byte_fallback_order_is_image_then_wic_then_susie` 钉住），
    // 而 `wic_decoder.rs` 本身也是「全尺寸、单线程、不做解码侧缩放」。
    // 于是「6 张许可」在上游是**真并行**（6 个核），窗口开大 = 纯赚吞吐。
    // 上游单张解码其实也不快 —— 它快在**用并发把单张的慢藏起来**。
    //
    // **更要紧的是**：这套模型建立在「一张图一个核」上，而 `image` 的 avif 后端是
    // `dav1d::Decoder::new()`（`image-0.25.10/src/codecs/avif/decoder.rs:82`，
    // 默认 `n_threads = 0` = auto）—— **一条流吃满 16 核**（1→16 核只有 2.25×，
    // 见 §12.4）。**AVIF 会把上游那套模型同样打破**；我们整本都是 AVIF，
    // 所以**我们从一开始就没有那条路可走，这不是我们的实现缺陷**。
    //
    // 所以窗口按「用户读一页能备好几页」定，不照抄 12/4（那会变成一轮预取跑 8.7 秒、
    // 全程占着核）。而且串行之下**窗口不是瓶颈、吞吐才是**：用户读一页 2 秒，
    // 最多也就备好 3–4 页。
    //
    // 要把上游那条「并发换吞吐」的路在我们这边重新打开，唯一的钥匙是
    // **按优先级分配 dav1d 的线程数**（翻页全核 / 预取少核），而 `image` 不暴露
    // `dav1d::Settings`。见 `docs/v0.1-local-core.md` §12.6 末段。
    final targets = await localPrefetchTargets(
      pos: _current,
      n: _pages.length,
      forward: 2,
      back: 1,
    );
    if (!mounted || generation != _prefetchGeneration) return;
    for (var i = 0; i < targets.length; i++) {
      final target = targets[i];
      if (!mounted || generation != _prefetchGeneration) return;
      if (_prefetch.containsKey(target)) continue;

      // 每页之间重新问一次「用户在等吗」。用户完全可能在我们解上一页的时候翻页了 ——
      // 光靠开头的 generation 检查挡不住这种（那时循环已经在 await 里）。
      // 这不是「等一会儿再来」，而是**整轮退出**：下一轮由翻页完成后的
      // `_schedulePrefetch` 重新发起。
      final stats = await localPageLoadStats();
      if (!mounted || generation != _prefetchGeneration) return;
      final highRunning = stats.running - stats.runningNormal;
      if (highRunning > 0 || stats.waiting > 0) {
        final why =
            '让路：用户在等（翻页在跑 $highRunning 张 / 排队 ${stats.waiting} 个），'
            '本轮还剩 ${targets.length - i} 页没备';
        debugPrint('[local-debug] 预取$why');
        setState(() => _prefetchNote = why);
        return;
      }

      await _prefetchPage(id, target);
    }
  }

  /// 解好并建好一页，收进预取缓存。任何失败都**静默放弃**：
  /// 预取是机会主义行为，它失败不该在界面上留下错误，更不能顶掉当前页。
  Future<void> _prefetchPage(BigInt id, int index) async {
    // 全尺寸一页是 179 MB 位图，预取三页就是 500 MB —— 那种档位不预取。
    if (!_displaySizedDecode) return;
    // 同一页只允许一路在解：老一轮被 generation 退场后，它 await 的那一页
    // 仍在解；新一轮如果瞄准同一页，必须跳过而不是叠上去。
    if (_prefetchInFlight.containsKey(index)) return;
    final task = _prefetchPageTask(id, index);
    _prefetchInFlight[index] = task;
    try {
      await task;
    } finally {
      _prefetchInFlight.remove(index);
    }
  }

  Future<void> _prefetchPageTask(BigInt id, int index) async {
    final targetWidth = _targetDecodeWidth();
    final stale = _prefetch[index];
    if (stale != null && stale.targetWidth == targetWidth) return;

    final swDecode = Stopwatch()..start();
    final LocalPageDecodeResult result;
    try {
      result = await localPagePixels(
        id: id,
        index: index,
        targetWidth: targetWidth,
        // 预取可以等：`Normal` 拿不到那 2 张留给 `High` 的许可，所以
        // 「预取占满许可、用户翻页排在后面」在结构上不会发生。
        priority: LocalPageLoadPriority.normal,
        contract: LocalPageLoadContract.sequential,
      );
    } catch (e) {
      debugPrint('[local-debug] 预取失败 index=$index: $e');
      return;
    }
    final pixels = result.pixels;
    if (pixels == null) {
      // 归外壳、解不开、或被更新的跳页作废 —— 三种都留给翻页时按正常流程处理。
      // 预取是机会主义行为：它失败不该在界面上留下错误，更不能顶掉当前页。
      return;
    }
    final decode = swDecode.elapsed;

    final swPack = Stopwatch()..start();
    final image = await _imageFromRgba(
      pixels.rgba,
      pixels.width,
      pixels.height,
    );
    final pack = swPack.elapsed;

    if (!mounted) {
      image.dispose();
      return;
    }
    _storePrefetch(
      _PrefetchedPage(
        index: index,
        targetWidth: targetWidth,
        image: image,
        width: pixels.width,
        height: pixels.height,
        sourceWidth: pixels.sourceWidth,
        sourceHeight: pixels.sourceHeight,
        decode: decode,
        pack: pack,
      ),
    );
    debugPrint(
      '[local-debug] 预取完成 index=$index '
      '解${decode.inMilliseconds} 图${pack.inMilliseconds}ms '
      '${pixels.width}x${pixels.height}',
    );
  }

  void _storePrefetch(_PrefetchedPage page) {
    // 一页自己就吃满整个预算（4K 窗口 × 大图可以到 80 MB 以上）：干脆不缓存。
    // 判据 D 要的是「连读三本 RSS 增幅 ≤5%」，缓存宁可小。
    if (page.bytes > _prefetchMaxBytes) {
      debugPrint(
        '[local-debug] 预取放弃 index=${page.index}：'
        '单页 ${(page.bytes / 1e6).toStringAsFixed(1)} MB 超过预算',
      );
      page.dispose();
      return;
    }

    _prefetch[page.index] = page;
    // 超限就从「离当前页最远」的开始扔 —— 相邻页才是下一个会被翻到的。
    while (_prefetch.length > 1 &&
        (_prefetch.length > _prefetchMaxEntries ||
            _totalPrefetchBytes() > _prefetchMaxBytes)) {
      final victim = _prefetch.keys.reduce(
        (a, b) => (a - _current).abs() >= (b - _current).abs() ? a : b,
      );
      _prefetch.remove(victim)?.dispose();
    }
  }

  int _totalPrefetchBytes() =>
      _prefetch.values.fold(0, (sum, p) => sum + p.bytes);

  /// 取走一页预取结果。尺寸对不上就丢掉（宁可重解也不能显示错尺寸）。
  _PrefetchedPage? _takePrefetch(int index) {
    final hit = _prefetch.remove(index);
    if (hit == null) return null;
    if (hit.targetWidth != _targetDecodeWidth()) {
      hit.dispose();
      return null;
    }
    return hit;
  }

  /// 丢掉全部预取。翻页宽度、解码器开关、会话变化之后都要走这一趟 ——
  /// 拿着旧尺寸的位图显示，比慢更糟。
  void _clearPrefetch() {
    _prefetchGeneration++;
    for (final page in _prefetch.values) {
      page.dispose();
    }
    _prefetch.clear();
  }

  /// 逐页读一遍并计时。这条曲线是 `docs/v0.1-local-core.md` §7 那把尺子：
  /// 近似常量 ⇒ 归档支持按需 seek；随 N 线性增长 ⇒ 实际在解压整段。
  ///
  /// 注意：这里量的是**过桥 + 编码字节**的耗时，不含解码与上屏；
  /// 绝对值比 Rust 侧探针高，但**增长形态**仍然说明问题。
  Future<void> _sweep() async {
    final id = _sessionId;
    if (id == null || _pages.isEmpty) return;

    // 逐页计时量的是读页耗时，60 ms 量级的信号扛不住旁边一个吃满核的 dav1d ——
    // 先让预取退场，否则这把尺子会量到别人的噪声。
    _clearPrefetch();

    setState(() {
      _busy = true;
      _sweepMs = null;
      _sweepTotalMs = null;
    });

    final swAll = Stopwatch()..start();
    final out = <double>[];
    try {
      for (var i = 0; i < _pages.length; i++) {
        final sw = Stopwatch()..start();
        await localPageBytes(id: id, index: i);
        sw.stop();
        out.add(sw.elapsedMicroseconds / 1000.0);
      }
      swAll.stop();
      if (!mounted) return;
      setState(() {
        _sweepMs = out;
        _sweepTotalMs = swAll.elapsedMicroseconds / 1000.0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '逐页计时中断：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
      _schedulePrefetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地来源调试（判据 A）'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '会话数 $_probeCount',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _toolbar(),
          const Divider(height: 1),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _toolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _pickFolder,
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: const Text('打开文件夹'),
          ),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _pickArchive,
            icon: const Icon(Icons.archive_outlined, size: 18),
            label: const Text('打开 CBZ / CBR'),
          ),
          OutlinedButton.icon(
            onPressed: _busy || _sessionId == null ? null : _sweep,
            icon: const Icon(Icons.timer_outlined, size: 18),
            label: const Text('逐页计时'),
          ),
          Tooltip(
            message: _displaySizedDecode
                ? '当前：解码到预览区像素尺寸。关掉可量全尺寸解码的原始成本。'
                : '当前：按归档里的原始尺寸解码（44.8 MPix 会解出 179 MB 位图）。',
            child: FilterChip(
              selected: _displaySizedDecode,
              avatar: Icon(
                _displaySizedDecode
                    ? Icons.fit_screen_outlined
                    : Icons.photo_size_select_actual_outlined,
                size: 18,
              ),
              label: Text(_displaySizedDecode ? '尺寸：显示' : '尺寸：全尺寸'),
              onSelected: (v) {
                setState(() => _displaySizedDecode = v);
                // 预取缓存是按目标宽度存的，尺寸一变就整批作废。
                _clearPrefetch();
                // 重新读当前页，让两种模式的数字直接可比。
                _loadPage(_current, force: true);
              },
            ),
          ),
          Tooltip(
            message:
                '谁负责解这一页。点按循环切换：\n'
                '自动 = Rust 优先，Rust 明确说「归外壳」时才退回引擎；\n'
                'Rust = 只走 Rust 解码器（avif 唯一能出图的形态）；\n'
                '外壳 = 编码字节过桥交给引擎，只有引擎认识的格式能出图。',
            child: ActionChip(
              avatar: const Icon(Icons.memory_outlined, size: 18),
              label: Text(_decoderMode.label),
              onPressed: () {
                final next = switch (_decoderMode) {
                  _DecoderMode.auto => _DecoderMode.rust,
                  _DecoderMode.rust => _DecoderMode.shell,
                  _DecoderMode.shell => _DecoderMode.auto,
                };
                setState(() => _decoderMode = next);
                // 换了解码器，旧预取是另一条路解出来的，不能混用。
                _clearPrefetch();
                // 立刻重读本页：这个开关的意义就是让两条路的数字当场可比。
                _loadPage(_current, force: true);
              },
            ),
          ),
          Tooltip(
            message: _prefetchEnabled
                ? '当前：翻完一页就顺手解下一页（±1），翻页时直接用已解好的位图。\n'
                      '关掉即可看到「每次翻页现解」的原始数字。\n'
                      '预取缓存：${_prefetch.length} 页 / '
                      '${(_totalPrefetchBytes() / 1e6).toStringAsFixed(1)} MB'
                : '当前：不预取，每次翻页都现解。\n'
                      '这本 AVIF 单页冷解码的地板是 270 ms（一个 tile、dav1d 已用满核），'
                      '所以「翻页 < 200 ms」只能靠预取把解码挪出翻页路径。',
            child: FilterChip(
              selected: _prefetchEnabled,
              avatar: Icon(
                _prefetchEnabled
                    ? Icons.bolt_outlined
                    : Icons.hourglass_empty_outlined,
                size: 18,
              ),
              label: Text(_prefetchEnabled ? '预取：开' : '预取：关'),
              onSelected: (v) {
                setState(() => _prefetchEnabled = v);
                if (!v) {
                  _clearPrefetch();
                } else {
                  _schedulePrefetch();
                }
              },
            ),
          ),
          OutlinedButton.icon(
            onPressed: _busy || _sessionId == null
                ? null
                : () => _loadPage(_current, force: true),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重读本页'),
          ),
          OutlinedButton.icon(
            onPressed: _sessionId == null ? null : () => _closeCurrent(),
            icon: const Icon(Icons.close, size: 18),
            label: const Text('关闭会话'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final n = localCloseAll();
              if (!mounted) return;
              _releaseCurrentImage();
              setState(() {
                _sessionId = null;
                _info = null;
                _pages = const [];
                _currentBytes = null;
                _currentBytesIndex = null;
                _stage = null;
                _history.clear();
              });
              debugPrint('closeAll released $n session(s)');
              await _refreshProbe();
            },
            icon: const Icon(Icons.layers_clear_outlined, size: 18),
            label: const Text('关闭全部'),
          ),
          if (_busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    final rejection = _rejection;
    if (rejection != null) return _rejectionView(rejection);

    final info = _info;
    if (info == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '选一个漫画文件夹，或一个 CBZ / CBR 归档。\n'
            '读取路径：Dart → FRB → rossi_local_core → 归档，每页都重开归档（不常驻句柄）。\n'
            '翻页后看「分段耗时」：读页 / 解码 / 上屏 各占多少。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _infoBar(info),
        if (_error != null)
          Container(
            width: double.infinity,
            color: Colors.red.withValues(alpha: 0.12),
            padding: const EdgeInsets.all(8),
            child: Text(_error!, style: const TextStyle(fontSize: 12)),
          ),
        _stageView(),
        if (_sweepMs != null) _sweepView(),
        const Divider(height: 1),
        Expanded(
          child: Row(
            children: [
              SizedBox(width: 240, child: _pageList()),
              const VerticalDivider(width: 1),
              Expanded(child: _viewer()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoBar(LocalSourceInfo info) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          Text(
            '来源：${_kindLabel(info.kind)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text('会话 id：${info.id}'),
          Text('页数：${info.pageCount}'),
          Text('总字节：${info.totalBytes}'),
          Text(
            info.path,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  static String _fmtMs(Duration d) =>
      (d.inMicroseconds / 1000.0).toStringAsFixed(1);

  /// 分段耗时面板 —— 本页存在的主要理由。
  ///
  /// 一个数字不够：`读页 60 ms` 看着没事，`解码 500 ms` 才是手感。三段分开才归得了因。
  Widget _stageView() {
    final stage = _stage;
    final cache = PaintingBinding.instance.imageCache;

    return Container(
      width: double.infinity,
      color: Colors.amber.withValues(alpha: 0.10),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stage == null)
            const Text(
              '翻页后这里会显示 读页 / 解码 / 上屏 的分段耗时。',
              style: TextStyle(fontSize: 12),
            )
          else ...[
            Text(
              '第 ${stage.index + 1} 页（${stage.mode}）：'
              '读页 ${_fmtMs(stage.read)} ms › '
              '解码 ${stage.prefetchHit ? "预取命中" : (stage.cacheHit ? "缓存命中" : "${_fmtMs(stage.decode)} ms")} › '
              '${stage.pack > Duration.zero ? "建图 ${_fmtMs(stage.pack)} ms › " : ""}'
              '上屏 ${_fmtMs(stage.paint)} ms · '
              '合计 ${_fmtMs(stage.total)} ms',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              '${stage.sourceWidth > 0 && stage.sourceWidth != stage.width ? "原始 ${stage.sourceWidth}×${stage.sourceHeight} → 解出 ${stage.width}×${stage.height}（像素 −${(stage.pixelSaving * 100).toStringAsFixed(1)}%）" : "解出 ${stage.width}×${stage.height}"}'
              '${stage.pixels > 0 ? " = ${(stage.pixels / 1e6).toStringAsFixed(1)} MPix" : ""}'
              '${stage.pixels > 0 ? " · RGBA 位图 ${(stage.bitmapBytes / 1e6).toStringAsFixed(1)} MB" : ""}'
              ' · 编码字节 ${_currentBytes?.length ?? 0} B'
              ' （${sniffImageFormat(_currentBytes)}）',
              style: const TextStyle(fontSize: 12),
            ),
            if (stage.prefetchHit) ...[
              const SizedBox(height: 3),
              Text(
                '本页是预取来的：翻页本身只花了「上屏」那 '
                '${_fmtMs(stage.paint)} ms，解码与建图都不在翻页路径上。\n'
                '成本没有消失 —— 这一页当初解了 '
                '${_fmtMs(stage.prefetchCost ?? Duration.zero)} ms（解码 + 建图），'
                '${stage.prefetchWait != null ? "而且翻页等了它 ${_fmtMs(stage.prefetchWait!)} ms（等在跑的那路，好过再解一遍）。\n" : ""}关掉「预取：开」再翻这一页，'
                '就能看到它的真实总价。',
                style: TextStyle(fontSize: 11, color: Colors.teal.shade700),
              ),
            ],
            if (stage.prefetchDuringDecode > 0) ...[
              const SizedBox(height: 3),
              Text(
                '本次解码开始时预取正占着 ${stage.prefetchDuringDecode} 张许可 —— '
                '这两个解码是**同时**跑的。dav1d 一条流几乎不能并行'
                '（1 核 610–667 ms / 16 核 269–295 ms），所以并发不是分核而是两边都慢，'
                '顺带把 Flutter 的帧生产也饿住（命中预取却还要等 100+ ms 出帧就是这个）。\n'
                '翻页时已经让预取退场（`_prefetchGeneration`），但**已经在解的那一页取消不掉** '
                '（dav1d 一次调用不可中断）—— 这是这个形态的残余成本，'
                '上游也是同一处妥协（`app.rs:55198`）。',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
              ),
            ],
            if (!_displaySizedDecode && stage.mode.startsWith('Rust')) ...[
              const SizedBox(height: 3),
              Text(
                '注：当前是「全尺寸」，Rust 路径会把整块 RGBA 搬过桥 —— '
                '这一页的位图 ${(stage.bitmapBytes / 1e6).toStringAsFixed(1)} MB 里，'
                '大部分时间花在搬运而不是解码。切到「显示」可直接对照。',
                style: const TextStyle(fontSize: 11, color: Colors.red),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              '全局图片缓存：${(cache.currentSizeBytes / 1e6).toStringAsFixed(1)} MB '
              '/ 上限 ${(cache.maximumSizeBytes / 1e6).toStringAsFixed(0)} MB '
              '· 条目数 ${cache.currentSize}'
              '${stage.cacheHit ? "（本页命中缓存，未重新解码）" : ""}'
              '   ｜   预取缓存：${_prefetch.length} 页 / '
              '${(_totalPrefetchBytes() / 1e6).toStringAsFixed(1)} MB'
              '   ｜   解码许可：${_loadStatsLabel()}',
              style: TextStyle(
                fontSize: 11,
                color: cache.currentSizeBytes > cache.maximumSizeBytes
                    ? Colors.red
                    : Colors.grey,
              ),
            ),
            if (_lastPrefetchDecision != null) ...[
              const SizedBox(height: 3),
              Text(
                '预取门（Rust 侧判决，不是本地判断）：'
                '${_lastPrefetchDecision!.allowed ? "放行" : "拦截"}'
                ' · ${_lastPrefetchDecision!.message}'
                '   [${_lastPrefetchDecision!.reason}]',
                style: TextStyle(
                  fontSize: 11,
                  color: _lastPrefetchDecision!.allowed
                      ? Colors.teal.shade700
                      : Colors.grey.shade700,
                ),
              ),
            ],
            if (_prefetchNote != null) ...[
              const SizedBox(height: 3),
              Text(
                '预取收手：$_prefetchNote',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
              ),
            ],
            const SizedBox(height: 3),
            Text(
              // 「上屏」这个数要用这一行来读：它把「等下一帧」与「画这一帧」分开了。
              // 143 ms 的「上屏」若对应 raster 3 ms，那 140 ms 是**等**出来的
              // （CPU 被解码占满，Flutter 的帧生产排在后面），不是纹理上传慢。
              '最近一帧：${_frameCostLabel()}   ｜   '
              '（「上屏」= 换引用到下一帧画完，含等 vsync；'
              '真正画的耗时看 raster）',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
          if (_history.length > 1) ...[
            const SizedBox(height: 6),
            const Text(
              '最近几次（新→旧）：',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            for (final row in _history)
              Text(
                '  第 ${(row.index + 1).toString().padLeft(3)} 页  ${row.mode.padRight(11)}'
                '  读 ${_fmtMs(row.read).padLeft(7)}  解 ${_fmtMs(row.decode).padLeft(8)}'
                '  装 ${_fmtMs(row.pack).padLeft(6)}  屏 ${_fmtMs(row.paint).padLeft(6)}'
                '  合 ${_fmtMs(row.total).padLeft(8)} ms'
                // 病根直接标在行上。让用户自己从「许可 1/6 在用」推出
                // 「所以这一行是被预取拖慢的」，是我不该让他做的事。
                '${row.prefetchDuringDecode > 0 ? "  ⟵ 解码时与预取并发（${row.prefetchDuringDecode} 张）" : ""}'
                '${row.prefetchWait != null ? "  ⟵ 等在跑的预取 ${_fmtMs(row.prefetchWait!)} ms（合并路径）" : ""}',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: row.prefetchDuringDecode > 0
                      ? Colors.orange.shade800
                      : null,
                ),
              ),
          ],
          const SizedBox(height: 3),
          const Text(
            '口径：读页含归档解压与 FRB 过桥；解码是编码字节→位图'
            '（Rust 路径这一段还会把 RGBA 搬过桥）；「装」是位图字节→ui.Image'
            '（只有 Rust 路径有）；上屏是解码完成→含该图的下一帧绘制完（含纹理上传）。'
            '解码宽度 = 预览区宽度 × 设备像素比，两条路径都遵守。\n'
            '「预取命中」那一行的解码/建图是 0，因为成本已经在你读上一页时付掉了 —— '
            '同一页关掉预取再翻一次，才是它的真实总价。',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _pageList() {
    return ListView.builder(
      itemCount: _pages.length,
      itemBuilder: (context, i) {
        final p = _pages[i];
        final selected = i == _current;
        return ListTile(
          dense: true,
          selected: selected,
          leading: SizedBox(
            width: 36,
            child: Text(
              '${p.index + 1}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${p.size} B'),
          onTap: () => _loadPage(i),
        );
      },
    );
  }

  Widget _viewer() {
    // 0 页时**不要**留一个转圈：那看起来像「还在加载」，实际是「这本没页可看」。
    // 触发过一次真实误判 —— 归档里 30 张全是 `.avif`（v0.1 当时不认），
    // 用户看到的就是空列表 + 转圈，只能描述成「打开 zip 没反应/崩了」。
    if (_pages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '这个来源里**没有**可显示的页面（0 页）。\n'
            '常见原因：归档里全是 v0.1 不认识的格式，或图片都在被忽略的目录里（隐藏 / __MACOSX）。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 回填给下一次翻页估算解码宽度（首次翻页时还没布局，会退回窗口宽度估算）。
              _viewerWidth = constraints.maxWidth;
              final rustImage = _rustImage;
              final provider = _provider;
              if (rustImage == null && provider == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return InteractiveViewer(
                maxScale: 8,
                child: rustImage != null
                    // Rust 路径：位图已经解好了，直接画。
                    ? RawImage(image: rustImage, fit: BoxFit.contain)
                    : Image(
                        image: provider!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _current > 0 ? () => _loadPage(_current - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('${_current + 1} / ${_pages.length}'),
              IconButton(
                onPressed: _current < _pages.length - 1
                    ? () => _loadPage(_current + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sweepView() {
    final ms = _sweepMs!;
    final sorted = [...ms]..sort();
    double pick(double q) =>
        sorted[((sorted.length - 1) * q).round().clamp(0, sorted.length - 1)];

    final first5 =
        ms.take(5).fold<double>(0, (a, b) => a + b) / ms.take(5).length;
    final last5 =
        ms.reversed.take(5).fold<double>(0, (a, b) => a + b) /
        ms.reversed.take(5).length;
    final ratio = first5 == 0 ? double.infinity : last5 / first5;

    final verdict = ratio < 2.0 ? '近似常量 → 按需 seek，未整段解压' : '随页序增长 → 疑似整段解压';

    return Container(
      width: double.infinity,
      color: Colors.blueGrey.withValues(alpha: 0.08),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '逐页读一遍 ${ms.length} 页：合计 ${_sweepTotalMs!.toStringAsFixed(1)} ms  '
            '· p50 ${pick(0.5).toStringAsFixed(2)} ms  '
            '· p95 ${pick(0.95).toStringAsFixed(2)} ms  '
            '· max ${sorted.last.toStringAsFixed(2)} ms',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '前 5 页均值 ${first5.toStringAsFixed(2)} ms → 后 5 页均值 '
            '${last5.toStringAsFixed(2)} ms（×${ratio.toStringAsFixed(2)}）：$verdict',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 4),
          const Text(
            '口径：含 FRB 过桥与编码字节拷贝，不含解码与上屏；看增长形态，不看绝对值。',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _rejectionView(LocalRejection r) {
    final (icon, hint) = switch (r.kind) {
      LocalRejectionKind.unknownFormat => (
        Icons.help_outline,
        '支持图片 / 视频文件、文件夹及 CBZ / CBR；暂不支持 7z、PDF。',
      ),
      LocalRejectionKind.rarSolid => (
        Icons.compress,
        '固实压缩：读第 N 页要先解压前 N-1 页，与「翻页 p95 ≤ 16.7ms」不相容。'
            '可用其它工具重新打包为 CBZ（zip）后重试。',
      ),
      LocalRejectionKind.rarNestedArchive => (
        Icons.account_tree_outlined,
        '归档里套了归档。v0.1 明确不展开嵌套——这是唯一会需要临时文件的场景。',
      ),
      LocalRejectionKind.rarEncrypted => (
        Icons.lock_outline,
        '加密归档：v0.1 不提供密码输入。',
      ),
      LocalRejectionKind.notFound => (Icons.link_off, '路径不存在或不可读。'),
      LocalRejectionKind.io => (Icons.error_outline, 'IO 或解析失败（含归档损坏）。'),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44),
            const SizedBox(height: 12),
            Text(
              '已被拒绝（${r.kind.name}）',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(r.message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => setState(() => _rejection = null),
              child: const Text('换一个'),
            ),
          ],
        ),
      ),
    );
  }

  String _kindLabel(LocalSourceKind kind) => switch (kind) {
    LocalSourceKind.folder => '散图文件夹',
    LocalSourceKind.zip => 'ZIP 归档',
    LocalSourceKind.rar => 'RAR 归档',
    LocalSourceKind.mediaFile => '图片 / 视频文件',
  };
}

/// 从编码字节的魔数判断格式。
///
/// 只看前 16 字节，不解码 —— 目的是让「解码 500 ms」这个数字带上上下文：
/// 44.8 MPix 的 JPEG 慢是必然的，跟读取路径无关。
String sniffImageFormat(Uint8List? bytes) {
  if (bytes == null || bytes.length < 12) return '未知';
  final b = bytes;
  if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'JPEG';
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return 'PNG';
  }
  if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'GIF';
  if (b[0] == 0x42 && b[1] == 0x4D) return 'BMP';
  if (b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return 'WebP';
  }
  return '未知';
}
