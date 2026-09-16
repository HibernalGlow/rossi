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
///    `texture-bridge`）。Rust 路目前要把整块 RGBA 过桥（44.8 MPix = 179 MB），
///    所以本页的帧率**不能**当作判据 B/C 的结论。
/// 2. **不做页面缓存。** 每次翻页都重新 `localPageBytes`，顺便让「不常驻句柄」
///    这条性质在 UI 上可见（判据 D 的结构性依据）。只保留当前页，**换页时连上一页
///    的解码结果一起 `evict`** —— 真实扫描页单页可达 44.8 MPix（RGBA 位图 179 MB），
///    不主动释放会立刻冲垮 Flutter 默认 100 MB 的图片缓存，变成「反复解码」。
/// 3. **默认按「显示尺寸」解码，这是量具不是优化。** 实测一本 29 页、单页
///    JPEG 5464×8192 的 CBZ：读页 15–60 ms、**解码约 500 ms**、上屏数十 ms。
///    关掉这个开关就能看到全尺寸解码的原始成本 —— 这正是判据 C
///    （p95 ≤ 16.7 ms）不可能由「Dart/CPU 全尺寸解码」路径达成的直接证据。
///    放大超过 2× 会看到模糊，属预期。
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
    required this.paint,
    required this.total,
    required this.width,
    required this.height,
    required this.cacheHit,
  });

  final int index;
  final String mode;
  final Duration read;
  final Duration decode;
  final Duration paint;
  final Duration total;
  final int width;
  final int height;
  final bool cacheHit;

  int get pixels => width * height;

  /// RGBA 位图的字节数 —— 也就是要走一趟 PCIe 的那个量。
  int get bitmapBytes => pixels * 4;
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

  /// 由 `LayoutBuilder` 回填的预览区宽度（逻辑像素），用于估算解码目标宽度。
  double _viewerWidth = 0;

  /// 「逐页计时」的结果：每页耗时（毫秒）。
  List<double>? _sweepMs;
  double? _sweepTotalMs;

  int _probeCount = 0;

  @override
  void dispose() {
    // 页面销毁时把会话还回去，否则反复进出会看到探针单调上升。
    final id = _sessionId;
    if (id != null) {
      localClose(id: id);
    }
    _releaseCurrentImage();
    super.dispose();
  }

  /// 释放当前页的两条显示资源。
  ///
  /// 外壳路径的位图挂在全局图片缓存里，要 `evict`；Rust 路径的是我们自己的
  /// `ui.Image`，要 `dispose`。**两条都必须走这里** —— 一页 44.8 MPix 是 179 MB，
  /// 漏掉任一边都会在翻几页之后把内存顶上去（曾观测到 RSS 592 MB）。
  void _releaseCurrentImage() {
    final provider = _provider;
    _provider = null;
    unawaited(provider?.evict());

    final rustImage = _rustImage;
    _rustImage = null;
    rustImage?.dispose();
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
        debugPrint('[local-debug] open 被拒绝: ${rejection.kind} ${rejection.message}');
        if (!mounted) return;
        setState(() {
          _rejection = rejection;
          _info = null;
          _pages = const [];
        });
        return;
      }

      final info = result.source!;
      debugPrint('[local-debug] open 成功(未取页): id=${info.id} '
          'kind=${info.kind} pages=${info.pageCount} '
          'bytes=${info.totalBytes} ${swOpen.elapsedMilliseconds}ms');

      final pages = await localSourcePages(id: info.id);
      debugPrint('[local-debug] 取页完成: ${pages.length} 条 '
          '${swOpen.elapsedMilliseconds}ms');

      if (!mounted) return;
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
        debugPrint('[local-debug] 打开成功但 0 页 —— '
            '归档里没有任何 v0.1 能识别的页面: $path');
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
    final logical =
        _viewerWidth > 0 ? _viewerWidth : media.size.width * 0.6;
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
    final head = '第 $index 页解码失败。\n'
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
  /// `auto` 的语义是「**Rust 优先，格式归外壳时退回**」，不是「随便挑一个能用的」。
  /// 只有 Rust 明确回答 `shellOnlyFormat` 才算「这页归外壳」；解码失败是另一回事，
  /// 那种情况就地报错 —— 偷偷换条路会把失败藏起来，而失败正是这张页面要显示的东西。
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

    if (_decoderMode != _DecoderMode.shell) {
      final settled = await _loadPageViaRust(id, index);
      if (settled) return;
      debugPrint('[local-debug] Rust 判定这页归外壳，退回外壳路径 index=$index');
    }
    await _loadPageViaShell(id, index);
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
    debugPrint('[local-debug] 读页完成 index=$index ${bytes.length} B '
        '${read.inMilliseconds}ms（解码前）');
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
            paint: paint.isNegative ? Duration.zero : paint,
            total: total,
            width: width,
            height: height,
            cacheHit: cacheHit,
          );
          _history.insert(0, _stage!);
          if (_history.length > 6) _history.removeLast();
        });
        debugPrint('[local-debug] 翻页完成 index=$index $mode '
            '读${read.inMilliseconds} 解${decode.inMilliseconds} '
            '屏${paint.inMilliseconds} 合${total.inMilliseconds}ms '
            '${width}x$height');
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
  /// 计时口径与外壳路径不同，**别直接比**：这里「解码」一段包含 Rust 解码 +
  /// FRB 过桥（44.8 MPix 就是 179 MB）+ `decodeImageFromPixels` 建纹理，
  /// 读页那一段合并了进来（所以 `read` 记 0）。两边真正可比的是「上屏」。
  Future<bool> _loadPageViaRust(BigInt id, int index) async {
    final swAll = Stopwatch()..start();
    final swDecode = Stopwatch()..start();
    debugPrint('[local-debug] Rust 解码开始 index=$index');

    final LocalPageDecodeResult result;
    try {
      result = await localPagePixels(id: id, index: index);
    } catch (e) {
      debugPrint('[local-debug] Rust 解码调用失败 index=$index: $e');
      return false;
    }

    final pixels = result.pixels;
    final failure = result.failure;

    if (pixels == null) {
      if (failure?.kind == LocalDecodeFailureKind.shellOnlyFormat) {
        return false;
      }
      debugPrint('[local-debug] Rust 解码失败 index=$index: ${failure?.message}');
      if (!mounted) return true;
      setState(() {
        _current = index;
        _error = '第 $index 页 Rust 解码失败。\n${failure?.message ?? '未知原因'}';
      });
      return true;
    }

    final decoded = await _imageFromRgba(
      pixels.rgba,
      pixels.width,
      pixels.height,
    );
    swDecode.stop();

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

    // 上屏：与外壳路径同一套口径 —— 等含这张图的下一帧画完再收尾。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_rustImage, decoded)) return;
      final total = swAll.elapsed;
      final decode = swDecode.elapsed;
      final paint = total - decode;
      setState(() {
        _current = index;
        _currentBytes = null;
        _currentBytesIndex = index;
        _error = null;
        _stage = _StageRow(
          index: index,
          mode: 'Rust 解码',
          read: Duration.zero,
          decode: decode,
          paint: paint.isNegative ? Duration.zero : paint,
          total: total,
          width: pixels.width,
          height: pixels.height,
          cacheHit: false,
        );
        _history.insert(0, _stage!);
        if (_history.length > 6) _history.removeLast();
      });
      debugPrint('[local-debug] Rust 翻页完成 index=$index '
          '解${decode.inMilliseconds} 屏${paint.inMilliseconds} '
          '合${total.inMilliseconds}ms ${pixels.width}x${pixels.height}');
    });
    return true;
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

  /// 逐页读一遍并计时。这条曲线是 `docs/v0.1-local-core.md` §7 那把尺子：
  /// 近似常量 ⇒ 归档支持按需 seek；随 N 线性增长 ⇒ 实际在解压整段。
  ///
  /// 注意：这里量的是**过桥 + 编码字节**的耗时，不含解码与上屏；
  /// 绝对值比 Rust 侧探针高，但**增长形态**仍然说明问题。
  Future<void> _sweep() async {
    final id = _sessionId;
    if (id == null || _pages.isEmpty) return;

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
                // 重新读当前页，让两种模式的数字直接可比。
                _loadPage(_current, force: true);
              },
            ),
          ),
          Tooltip(
            message: '谁负责解这一页。点按循环切换：\n'
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
                // 立刻重读本页：这个开关的意义就是让两条路的数字当场可比。
                _loadPage(_current, force: true);
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
          Text('来源：${_kindLabel(info.kind)}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('会话 id：${info.id}'),
          Text('页数：${info.pageCount}'),
          Text('总字节：${info.totalBytes}'),
          Text(info.path, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  static String _fmtMs(Duration d) => (d.inMicroseconds / 1000.0).toStringAsFixed(1);

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
            const Text('翻页后这里会显示 读页 / 解码 / 上屏 的分段耗时。',
                style: TextStyle(fontSize: 12))
          else ...[
            Text(
              '第 ${stage.index + 1} 页（${stage.mode}）：'
              '读页 ${_fmtMs(stage.read)} ms › '
              '解码 ${stage.cacheHit ? "缓存命中" : "${_fmtMs(stage.decode)} ms"} › '
              '上屏 ${_fmtMs(stage.paint)} ms · '
              '合计 ${_fmtMs(stage.total)} ms',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              '解出 ${stage.width}×${stage.height}'
              '${stage.pixels > 0 ? " = ${(stage.pixels / 1e6).toStringAsFixed(1)} MPix" : ""}'
              '${stage.pixels > 0 ? " · RGBA 位图 ${(stage.bitmapBytes / 1e6).toStringAsFixed(1)} MB" : ""}'
              ' · 编码字节 ${_currentBytes?.length ?? 0} B'
              ' （${sniffImageFormat(_currentBytes)}）',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              '全局图片缓存：${(cache.currentSizeBytes / 1e6).toStringAsFixed(1)} MB '
              '/ 上限 ${(cache.maximumSizeBytes / 1e6).toStringAsFixed(0)} MB '
              '· 条目数 ${cache.currentSize}'
              '${stage.cacheHit ? "（本页命中缓存，未重新解码）" : ""}',
              style: TextStyle(
                fontSize: 11,
                color: cache.currentSizeBytes > cache.maximumSizeBytes
                    ? Colors.red
                    : Colors.grey,
              ),
            ),
          ],
          if (_history.length > 1) ...[
            const SizedBox(height: 6),
            const Text('最近几次（新→旧）：', style: TextStyle(fontSize: 11, color: Colors.grey)),
            for (final row in _history)
              Text(
                '  第 ${(row.index + 1).toString().padLeft(3)} 页  ${row.mode.padRight(11)}'
                '  读 ${_fmtMs(row.read).padLeft(7)}  解 ${_fmtMs(row.decode).padLeft(8)}'
                '  屏 ${_fmtMs(row.paint).padLeft(6)}  合 ${_fmtMs(row.total).padLeft(8)} ms',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
          ],
          const SizedBox(height: 3),
          const Text(
            '口径：读页含归档解压与 FRB 过桥；解码是编码字节→位图；上屏是解码完成→含该图的下一帧绘制完'
            '（含纹理上传）。解码宽度 = 预览区宽度 × 设备像素比。',
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

    final first5 = ms.take(5).fold<double>(0, (a, b) => a + b) / ms.take(5).length;
    final last5 =
        ms.reversed.take(5).fold<double>(0, (a, b) => a + b) / ms.reversed.take(5).length;
    final ratio = first5 == 0 ? double.infinity : last5 / first5;

    final verdict = ratio < 2.0
        ? '近似常量 → 按需 seek，未整段解压'
        : '随页序增长 → 疑似整段解压';

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
          'v0.1 只认散图文件夹 / CBZ / CBR。7z、PDF、视频都在这条线之外。',
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
      LocalRejectionKind.notFound => (
          Icons.link_off,
          '路径不存在或不可读。',
        ),
      LocalRejectionKind.io => (
          Icons.error_outline,
          'IO 或解析失败（含归档损坏）。',
        ),
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
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'PNG';
  if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'GIF';
  if (b[0] == 0x42 && b[1] == 0x4D) return 'BMP';
  if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
      b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
    return 'WebP';
  }
  return '未知';
}
