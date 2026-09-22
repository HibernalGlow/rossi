import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/src/rust/api/local.dart';
part 'parts/local_source_debug_models_part.dart';
part 'parts/local_source_debug_load_part.dart';
part 'parts/local_source_debug_prefetch_part.dart';
part 'parts/local_source_debug_view_part.dart';


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
///    当前页还没显示出来时取消其它 pending、连新的预取也不发；
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

  // ───────────────────────── 预取 ─────────────────────────
  //
  // 为什么预取是这个页面最该有的东西：冷页解码的地板是 270 ms（见
  // `docs/v0.1-local-core.md` §12.4），软硬两侧都压不下去 ——
  // 所以「翻页 < 200 ms」只能靠**不在翻页时解码**。
  // 成本没有消失，是从翻页路径挪到了用户正在读当前页的那段时间里。
  // 页面上必须同时显示「预取当时花了多少」，否则这个数字像是凭空变出来的。

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

}

