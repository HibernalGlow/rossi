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
/// 1. **这里走的是 Dart 兜底显示路径。** 用 `Image` 让 Flutter 解码，
///    即「编码字节过桥」——`docs/v0.1-local-core.md` §9 明确允许，用于兜底与
///    尺寸探测。**目标形态是 Rust 侧解码后直接进 GPU texture**（Phase 1 的
///    `texture-bridge`），本页不代表最终上屏路径，不要拿它的帧率当判据 B/C。
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
    // 大位图不主动踢会一直挂在全局图片缓存里。
    _provider?.evict();
    super.dispose();
  }

  Future<void> _refreshProbe() async {
    final n = localOpenSessionCount();
    if (mounted) setState(() => _probeCount = n);
  }

  Future<void> _closeCurrent({bool silent = false}) async {
    final id = _sessionId;
    if (id == null) return;
    localClose(id: id);
    final old = _provider;
    _provider = null;
    // 解绑是大位图的唯一释放途径（见类注释第 2 条）。
    unawaited(old?.evict());
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
        if (!mounted) return;
        setState(() {
          _rejection = rejection;
          _info = null;
          _pages = const [];
        });
        return;
      }

      final info = result.source!;
      final pages = await localSourcePages(id: info.id);

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
      }
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

  Future<void> _loadPage(int index, {bool force = false}) async {
    final id = _sessionId;
    if (id == null || index < 0 || index >= _pages.length) return;
    if (!force && _currentBytesIndex == index && _currentBytes != null) {
      setState(() => _current = index);
      return;
    }

    final swAll = Stopwatch()..start();

    // ── 第 1 段：读页（归档 → Rust → FRB → Dart 字节）──
    final swRead = Stopwatch()..start();
    final Uint8List bytes;
    try {
      bytes = await localPageBytes(id: id, index: index);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '读第 $index 页失败：$e');
      return;
    }
    swRead.stop();
    final read = swRead.elapsed;
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
    }) {
      if (handled || !mounted) return;
      handled = true;
      if (isError) {
        setState(() {
          _current = index;
          _currentBytes = bytes;
          _currentBytesIndex = index;
          _error = '第 $index 页解码失败（编码字节 ${bytes.length} B）';
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
        );
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
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
              label: Text(_displaySizedDecode ? '解码：显示尺寸' : '解码：全尺寸'),
              onSelected: (v) {
                setState(() => _displaySizedDecode = v);
                // 重新读当前页，让两种模式的数字直接可比。
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
              final old = _provider;
              _provider = null;
              unawaited(old?.evict());
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
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 回填给下一次翻页估算解码宽度（首次翻页时还没布局，会退回窗口宽度估算）。
              _viewerWidth = constraints.maxWidth;
              final provider = _provider;
              if (provider == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return InteractiveViewer(
                maxScale: 8,
                child: Image(image: provider, fit: BoxFit.contain, gaplessPlayback: true),
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
