import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:zephyr/gpu/gpu_present_bridge.dart';
import 'package:zephyr/src/rust/api/local.dart';

/// 当前在用哪条显示通路。
///
/// 两条路的意义完全不同，所以它不是实现细节、要显示在界面上：
/// - [gpu]：像素全程在显存里，Dart 只拿到一个 textureId；
/// - [cpu]：`local_core` 解码 → RGBA 过桥 → `ui.decodeImageFromPixels`。
///   这是**兜底**，存在的唯一理由是"呈现器还没就绪时别让人对着黑屏"。
enum _Path {
  gpu,
  cpu,
}

/// GPU 上屏调试页（Windows）。
///
/// # 它现在演示的是两件事，而不是一件
///
/// 1. **上屏本身**：本地文件 → Rust 解码 → wgpu 上传/渲染 → GPU→GPU 拷贝
///    → D3D12 共享纹理 → Flutter(D3D11/ANGLE) 合成 → `Texture` 组件。
/// 2. **就绪前的降级**：wgpu device 与管线要 ~1 s 才建好（在后台线程），
///    在那之前这一页走 [GpuPresentState.loading] 分支，用 CPU 兜底路径显示内容，
///    轮询到就绪后再换成共享纹理。
///
/// 第 2 件事不是锦上添花：呈现器是**在 App 启动时**就开始建的（`OnCreate` 里
/// 起线程），所以真实阅读器里"用户还在选书、device 已经建好"是常态，
/// 只有"一进 App 就直冲阅读页"才会真的用上兜底。这条页面要能演示并量出那一段。
///
/// # 判定文案是这个页面存在的理由
///
/// 黑屏的原因可以是七八种（DLL 没构建、adapter 不匹配、纹理没注册、
/// 引擎没来取帧、呈现器还在建……），只显示"黑屏"等于没有信息。
/// 其中 `handleOpened > 0` 是唯一的硬证据：引擎只有确实把这张纹理拿去合成了，
/// 才会去打开我们给的共享句柄。
///
/// 入口：设置 → 全局设置 → 调试 → GPU 上屏（D3D12 共享纹理）
class GpuPresentPage extends StatefulWidget {
  const GpuPresentPage({super.key});

  @override
  State<GpuPresentPage> createState() => _GpuPresentPageState();
}

class _GpuPresentPageState extends State<GpuPresentPage> {
  final GpuPresentBridge _bridge = const GpuPresentBridge();
  final TextEditingController _pathController = TextEditingController(
    text: Platform.environment['ROSSI_GPU_PRESENT_SAMPLE'] ??
        r'D:\1Dev\tmp\rossi-probe\probe.cbz',
  );

  /// 从本页 `initState` 起算。用来看"进这一页之后等了多久才就绪" ——
  /// 它不是 App 冷启动时间（呈现器在 `OnCreate` 就开始建了），别混。
  final Stopwatch _since = Stopwatch()..start();

  Timer? _statsTimer;

  _Path _path = _Path.cpu;

  // ── GPU 路 ──
  GpuPresentState _gpuState = GpuPresentState.loading;
  String _gpuError = '';
  int? _textureId;
  /// 已经按哪个**物理**尺寸初始化过。用来判断 LayoutBuilder 报的尺寸要不要处理。
  Size? _readyPhysicalSize;
  /// 本页打开后过多久呈现器才就绪。`null` = 还没就绪。
  int? _readyAfterMs;
  /// `_ensureTexture` 的自锁。与 `_busy` 分开：后者是"用户动作进行中"（按钮状态），
  /// 而这里是"native 侧同步进行中"，两者不该互相阻塞。
  bool _syncing = false;

  // ── CPU 兜底路 ──
  BigInt? _cpuSourceId;
  ui.Image? _cpuImage;

  // ── 两条路共用的阅读状态 ──
  String _openedPath = '';
  int _pageCount = 0;
  int _index = 0;
  /// 最近一次 LayoutBuilder 报的物理尺寸。供"就绪时补一次同步"用 ——
  /// 那一刻可能没有新的 rebuild 来驱动 `_ensureTexture`。
  Size? _lastPhysicalSize;

  bool _busy = false;
  String? _actionError;
  GpuPresentStats? _stats;

  @override
  void initState() {
    super.initState();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_refreshStats());
    });
    unawaited(_watchGpuReadiness());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshStats());
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _pathController.dispose();
    _releaseCpuImage();
    super.dispose();
  }

  // ───────────────────────── 就绪等待与切换 ─────────────────────────

  /// 盯住后台创建进度，就绪后切到 GPU 路。
  ///
  /// 用轮询而不是让 native 侧回调：回调要从后台线程 post 到平台线程再 invoke，
  /// 而这里等的是**一次性**的信号，~1 s 的窗口里每 120 ms 问一次的代价可以忽略。
  /// 少一条跨线程路径就少一类"析构顺序"的 bug。
  Future<void> _watchGpuReadiness() async {
    if (!GpuPresentBridge.isPlatformSupported) {
      if (mounted) {
        setState(() {
          _gpuState = GpuPresentState.unsupported;
          _gpuError = '当前平台没有 D3D12 共享纹理这条路';
        });
      }
      return;
    }

    while (mounted && _gpuState == GpuPresentState.loading) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) {
        return;
      }

      final GpuPresentStatus status;
      try {
        status = await _bridge.status();
      } catch (error) {
        if (mounted) {
          setState(() {
            _gpuState = GpuPresentState.failed;
            _gpuError = '查询呈现器状态失败: $error';
          });
        }
        return;
      }
      if (!mounted) {
        return;
      }

      if (status.state == GpuPresentState.loading) {
        continue;
      }

      setState(() {
        _gpuState = status.state;
        _gpuError = status.error;
        if (status.state == GpuPresentState.ready) {
          _readyAfterMs = _since.elapsedMilliseconds;
        }
      });

      if (status.state == GpuPresentState.ready) {
        // 就绪这一刻可能没有新的 rebuild，所以这里主动补一次同步。
        final Size? size = _lastPhysicalSize;
        if (size != null) {
          await _ensureTexture(size);
        }
      }
      return;
    }
  }

  // ───────────────────────── GPU 路 ─────────────────────────

  /// 按控件当前的**物理**尺寸让 native 侧准备纹理，并在第一次就绪时从兜底切过来。
  ///
  /// 必须是物理像素：Flutter 的纹理按物理像素合成。传逻辑尺寸会在 1.5x / 2x
  /// 缩放的屏幕上得到一张被拉伸的模糊图，而且引擎随后会用物理尺寸来问
  /// `SurfaceCallback`，两边永远对不上，于是反复重建 —— 症状是拖窗口时画面闪烁。
  Future<void> _ensureTexture(Size physicalSize) async {
    _lastPhysicalSize = physicalSize;
    if (!GpuPresentBridge.isPlatformSupported || _syncing) {
      return;
    }
    if (_readyPhysicalSize == physicalSize && _textureId != null) {
      return;
    }

    _syncing = true;
    try {
      final GpuPresentStatus status = await _bridge.tryInit(
        width: physicalSize.width.round(),
        height: physicalSize.height.round(),
      );
      if (!mounted) {
        return;
      }

      if (status.state != GpuPresentState.ready) {
        // 未就绪就维持现状：兜底路径继续显示，等 `_watchGpuReadiness` 那边报信。
        setState(() {
          _gpuState = status.state;
          _gpuError = status.error;
        });
        return;
      }

      final bool switching = _path != _Path.gpu;
      setState(() {
        _textureId = status.textureId;
        _readyPhysicalSize = physicalSize;
        _gpuState = GpuPresentState.ready;
        _gpuError = '';
        _readyAfterMs ??= _since.elapsedMilliseconds;
        if (switching) {
          _path = _Path.gpu;
        }
      });

      if (_openedPath.isNotEmpty && _pageCount > 0) {
        if (switching) {
          // 兜底路持有的是**另一份**来源（`local_core` 那边开的），切过来要重新 open。
          await _openOnGpu(_openedPath, _index);
        } else {
          // 同一条路、只是尺寸变了：native 侧已按新尺寸重建目标并重画当前页，
          // 这里补一次通知，保证"拖完窗口还能看到内容"而不是一片底色。
          await _bridge.show(_index);
        }
      }
      await _refreshStats();
    } catch (error) {
      if (mounted) {
        setState(() => _actionError = '初始化失败: $error');
      }
    } finally {
      _syncing = false;
    }
  }

  /// 用 GPU 路打开并呈现。两条调用点：用户点"打开"，以及从兜底切过来。
  Future<void> _openOnGpu(String path, int index) async {
    final int count = await _bridge.open(path);
    if (!mounted) {
      return;
    }
    final int safeIndex = _clampIndex(index, count);
    if (count > 0) {
      await _bridge.show(safeIndex);
    }
    if (!mounted) {
      return;
    }
    final ui.Image? stale = _cpuImage;
    setState(() {
      _pageCount = count;
      _index = safeIndex;
      _cpuImage = null;
    });
    // 兜底那几张位图此刻没人要了。它们单张可以到 179 MB 量级，留着不是小事。
    stale?.dispose();
  }

  // ───────────────────────── CPU 兜底路 ─────────────────────────

  /// 兜底路径：`local_core` 解码 → RGBA 过桥 → `ui.decodeImageFromPixels`。
  ///
  /// 与 GPU 路共用同一个文件，但是**两份独立的来源状态**。这是本方案已知的代价，
  /// 也是 §7 里"接线进阅读器时页来源应当统一"那条的由来。
  Future<void> _openOnCpu(String path) async {
    final LocalSourceOpenResult result = await openLocalSource(path: path);
    final LocalSourceInfo? source = result.source;
    if (source == null) {
      throw StateError(result.rejection?.message ?? '打不开：$path');
    }
    final List<LocalPageInfo> pages = await localSourcePages(id: source.id);
    if (!mounted) {
      return;
    }

    _cpuSourceId = source.id;
    setState(() {
      _pageCount = pages.length;
      _index = 0;
    });
    if (pages.isNotEmpty) {
      await _showOnCpu(0);
    }
  }

  Future<void> _showOnCpu(int index) async {
    final BigInt? id = _cpuSourceId;
    if (id == null) {
      return;
    }
    final LocalPageDecodeResult result = await localPagePixels(
      id: id,
      index: index,
      targetWidth: _targetDecodeWidth(),
      // 用户此刻在等这一页：`High`。调度器为此留了 2 张许可**不给**预取 ——
      // 「预取不会拖慢翻页」在结构上就是这么成立的，不靠调参。
      priority: LocalPageLoadPriority.high,
      contract: LocalPageLoadContract.sequential,
    );
    final LocalPagePixels? pixels = result.pixels;
    if (pixels == null) {
      throw StateError(result.failure?.message ?? 'Rust 侧没能解出第 ${index + 1} 页');
    }

    final ui.Image image = await _imageFromRgba(pixels.rgba, pixels.width, pixels.height);
    if (!mounted) {
      image.dispose();
      return;
    }
    final ui.Image? stale = _cpuImage;
    setState(() => _cpuImage = image);
    // 先换再释放：反过来会让这一帧的绘制拿到一个已 dispose 的位图。
    stale?.dispose();
  }

  /// 兜底路径的解码宽度：按控件的物理宽度解，**不要全尺寸**。
  ///
  /// 不给宽度的代价是量过的：44.8 MPix 的一页解出 170.8 MB 位图，这一段要 1526 ms；
  /// 给了宽度之后位图缩到几 MB，整段掉到 300–400 ms 量级。
  int? _targetDecodeWidth() {
    final Size? size = _lastPhysicalSize;
    if (size == null) {
      return null;
    }
    final int width = size.width.round();
    return width > 0 ? width : null;
  }

  Future<ui.Image> _imageFromRgba(Uint8List rgba, int width, int height) {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  void _releaseCpuImage() {
    _cpuImage?.dispose();
    _cpuImage = null;
  }

  static int _clampIndex(int index, int count) {
    if (count <= 0 || index < 0) {
      return 0;
    }
    return index >= count ? count - 1 : index;
  }

  // ───────────────────────── 动作 ─────────────────────────

  Future<void> _refreshStats() async {
    if (!GpuPresentBridge.isPlatformSupported) {
      return;
    }
    try {
      final GpuPresentStats stats = await _bridge.stats();
      if (!mounted) {
        return;
      }
      setState(() => _stats = stats);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _actionError = '读取统计失败: $error');
    }
  }

  Future<void> _open() async {
    final String path = _pathController.text.trim();
    if (path.isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      if (_path == _Path.gpu) {
        await _openOnGpu(path, 0);
      } else {
        await _openOnCpu(path);
      }
      _openedPath = path;
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _pageCount = 0;
        _actionError = '$error';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _show(int index) async {
    if (index < 0 || index >= _pageCount) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (_path == _Path.gpu) {
        await _bridge.show(index);
      } else {
        await _showOnCpu(index);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _index = index;
        _actionError = null;
      });
      await _refreshStats();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _actionError = '呈现第 ${index + 1} 页失败: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  // ───────────────────────── 界面 ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final double devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('GPU 上屏（D3D12 共享纹理）'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新统计',
            onPressed: _refreshStats,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: Container(
              color: const Color(0xFF05050A),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final Size physicalSize = Size(
                    constraints.maxWidth * devicePixelRatio,
                    constraints.maxHeight * devicePixelRatio,
                  );
                  if (physicalSize.width >= 1 && physicalSize.height >= 1) {
                    // 不能在 build 里直接 await：下一帧再安排。
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      unawaited(_ensureTexture(physicalSize));
                    });
                  }
                  return _buildSurface(constraints);
                },
              ),
            ),
          ),
          _buildPanel(devicePixelRatio),
        ],
      ),
    );
  }

  Widget _buildSurface(BoxConstraints constraints) {
    if (_path == _Path.gpu) {
      final int? textureId = _textureId;
      if (textureId == null) {
        return _hint('呈现目标还没建好…');
      }
      // 纹理铺满整个盒子，是**故意**的：页的等比缩放与留边在 Rust 侧
      // 的着色器里完成，所以这张纹理本来就已经是"屏幕上的那一幅"。
      // 这里再套一层 AspectRatio 或 BoxFit 只会引入第二次缩放。
      return SizedBox(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        child: Texture(textureId: textureId),
      );
    }

    final ui.Image? image = _cpuImage;
    if (image == null) {
      return _hint(_fallbackHint());
    }
    // CPU 路没有着色器，留边只能交给 `BoxFit.contain` —— 用同一个语义
    // （等比缩放 + 留边），这样两条路切换时画面不会跳。
    return SizedBox(
      width: constraints.maxWidth,
      height: constraints.maxHeight,
      child: RawImage(
        image: image,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }

  Widget _hint(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF8B949E)),
        ),
      ),
    );
  }

  String _fallbackHint() {
    if (!GpuPresentBridge.isPlatformSupported) {
      return '当前平台没有这条路径。\n\nD3D12 共享纹理是 Windows 专属；\n'
          'macOS / Linux / 移动端走各自的上屏路径（尚未实现）。';
    }
    if (_openedPath.isEmpty) {
      return '尚未打开来源。\n\n呈现器就绪前这里走 CPU 兜底路径 ——\n'
          '现在打开一个文件就能看到它工作。';
    }
    return '正在解码第 ${_index + 1} 页…';
  }

  Widget _buildPanel(double devicePixelRatio) {
    final GpuPresentStats? stats = _stats;

    return Container(
      color: const Color(0xFF12141A),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _pathController,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '本地来源（散图文件夹 / .cbz / .cbr）',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _open(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _busy ? null : _open,
                child: const Text('打开'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              FilledButton.tonal(
                onPressed: !_busy && _index > 0 ? () => _show(_index - 1) : null,
                child: const Text('上一页'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed:
                    !_busy && _index + 1 < _pageCount ? () => _show(_index + 1) : null,
                child: const Text('下一页'),
              ),
              const SizedBox(width: 16),
              Text(
                _pageCount == 0 ? '尚未打开来源' : '第 ${_index + 1} / $_pageCount 页',
                style: const TextStyle(fontSize: 14, color: Color(0xFFE6EDF3)),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  _verdict(),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _verdictOk() ? const Color(0xFF7CE38B) : const Color(0xFFFF9C6B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 22,
            runSpacing: 6,
            children: <Widget>[
              _stat(
                '显示通路',
                _path == _Path.gpu ? 'GPU 共享纹理' : 'CPU 兜底（就绪前的降级）',
              ),
              _stat('呈现器', _gpuStateLabel()),
              if (stats != null) ...<Widget>[
                _stat('适配器', stats.adapter.isEmpty ? '—' : stats.adapter),
                _stat('LUID 命中 Flutter', stats.luidKnown ? '是' : '否（跨卡共享有风险）'),
                _stat('目标尺寸（物理）', '${stats.width} × ${stats.height}'),
                _stat('控件 DPR', devicePixelRatio.toStringAsFixed(2)),
                _stat(
                  'tex${_textureId ?? ''}',
                  stats.textureId < 0 ? '未注册' : '已注册 #${stats.textureId}',
                ),
                _stat('引擎打开句柄', '${stats.handleOpened}'),
                _stat('已通知取帧', '${stats.framesMarked}'),
                _stat('目标重建', '${stats.resizes}'),
                if (stats.probe.isNotEmpty) ...<Widget>[
                  _stat(
                    '呈现器构建',
                    '${stats.probeDouble('initMs').toStringAsFixed(0)} ms'
                        '（device ${stats.probeDouble('initDeviceMs').toStringAsFixed(0)}'
                        ' / 管线 ${stats.probeDouble('initPipelineMs').toStringAsFixed(0)}）',
                  ),
                  _stat(
                    '解码档位',
                    '${stats.probeInt('decodedWidth')} × ${stats.probeInt('decodedHeight')}',
                  ),
                  _stat(
                    '原图',
                    '${stats.probeInt('sourceWidth')} × ${stats.probeInt('sourceHeight')}',
                  ),
                  _stat('解码', '${stats.probeDouble('decodeMs').toStringAsFixed(1)} ms'),
                  _stat('上传', '${stats.probeDouble('uploadMs').toStringAsFixed(1)} ms'),
                  _stat(
                    '渲染+提交',
                    '${stats.probeDouble('submitMs').toStringAsFixed(1)} ms',
                  ),
                  _stat('合计', '${stats.probeDouble('totalMs').toStringAsFixed(1)} ms'),
                  _stat(
                    '直接共享 wgpu 纹理',
                    '${stats['directShareOfWgpuTexture'] ?? '—'}',
                  ),
                  _stat('拷贝路径', '${stats['copyPath'] ?? '—'}'),
                ],
              ],
            ],
          ),
          if (stats != null && stats.probeRaw.isEmpty &&
              (_gpuState == GpuPresentState.ready ||
                  _gpuState == GpuPresentState.failed))
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'native 侧没有返回 Rust 侧诊断（DLL 与桥的版本可能不匹配）。',
                style: TextStyle(fontSize: 12, color: Color(0xFFFF9C6B)),
              ),
            ),
          if (_actionError != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _actionError!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFFF7B72)),
            ),
          ],
        ],
      ),
    );
  }

  String _gpuStateLabel() {
    switch (_gpuState) {
      case GpuPresentState.loading:
        return '后台创建中（本页已等 ${_since.elapsedMilliseconds} ms）';
      case GpuPresentState.ready:
        final int? ms = _readyAfterMs;
        return ms == null ? '就绪' : '就绪（本页等了 $ms ms）';
      case GpuPresentState.failed:
        return '失败';
      case GpuPresentState.unsupported:
        return '本平台无此路径';
    }
  }

  /// 把这个页面要回答的问题直接写在脸上。
  bool _verdictOk() =>
      _path == _Path.gpu && _gpuState == GpuPresentState.ready && (_stats?.handleOpened ?? 0) > 0;

  String _verdict() {
    if (!GpuPresentBridge.isPlatformSupported) {
      return '当前平台不支持';
    }
    switch (_gpuState) {
      case GpuPresentState.loading:
        return '呈现器仍在后台创建 —— 此刻显示的是 CPU 兜底路径';
      case GpuPresentState.unsupported:
        return '当前平台没有这条路';
      case GpuPresentState.failed:
        return 'GPU 路径不可用：$_gpuError（继续走 CPU 兜底）';
      case GpuPresentState.ready:
        final GpuPresentStats? stats = _stats;
        if (stats == null) {
          return '已就绪，正在读统计…';
        }
        if (stats.handleOpened > 0) {
          return '链路已通：引擎已打开共享句柄 ${stats.handleOpened} 次，画面来自 Rust 侧纹理';
        }
        if (stats.framesMarked > 0) {
          return '已通知引擎 ${stats.framesMarked} 次，但引擎还没来取帧（纹理未真正上屏？）';
        }
        return _pageCount == 0 ? '已就绪，尚未打开来源' : '已就绪，尚未呈现任何页';
    }
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E))),
        Text(value, style: const TextStyle(fontSize: 14, color: Color(0xFFE6EDF3))),
      ],
    );
  }
}
