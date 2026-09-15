import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

// Rossi — Gate A 第三条路径验证：Flutter GPU（`flutter_gpu` 包）。
//
// 前面两条路径（native / wgpu）都是「外部渲染 → 导出 DXGI shared handle →
// 注册给 Flutter 合成」，实测已经确认：wgpu 的 texture 无法直接导出，必须多走
// 一次 GPU→GPU 拷贝。这一条走的是完全不同的思路：
//
//   Flutter GPU 直接在 Impeller 自己的 device 上分配 texture →
//   写入/渲染 → Texture.asImage() 零拷贝包成 ui.Image → Flutter 直接显示
//
// 全程不涉及跨设备共享、不涉及 handle 注册，理论上没有那次额外拷贝。
//
// 本程序要回答的是「它在 Windows 上到底能不能用」，而不是「它快不快」：
//   - Flutter GPU 只在 Impeller 生效，Windows 桌面后端是 OpenGL ES。
//   - 引擎源码里 Flutter GPU 的注释多处写着 "currently false on the GLES
//     backend"，因此不能凭 Metal/Vulkan 的文档推断 Windows 可用。
//
// 像素约定与 texture-bridge 工程完全一致，所以 capture_probe.py 可以直接复用：
//   顶部 25% 高度：左红 / 中绿 / 右蓝 三条竖带
//   中部：随相位左右往返的白色方块
//   底部 25% 高度：渐变条
//
// 两个模式刻意做在一起，用来把「CPU 上传」的代价单独隔离出来：
//   每帧上传 = 开   每帧把 2.7 MB 像素重新传上去（模拟 CPU 图片路径）
//   每帧上传 = 关   只在初始化时传一次，之后帧只做 asImage + 显示
// 两者的帧率差就是「每帧一次 CPU→GPU 全表面上传」的真实代价。

const int kWidth = 1264;
const int kHeight = 541;

void main(List<String> args) {
  // runner 侧的 GetCommandLineArguments() 不过滤任何参数，但实测 `--no-upload`
  // 到不了这里 —— 带 `--` 前缀的参数会被 embedder 当作引擎开关消费掉。
  // 所以对照开关走环境变量，这条路径不依赖 embedder 的参数转发行为。
  final bool noUpload =
      Platform.environment['ROSSI_GPU_NO_UPLOAD'] == '1' ||
          args.contains('no-upload');
  runApp(GpuProbeApp(uploadPerFrame: !noUpload));
}

class GpuProbeApp extends StatelessWidget {
  const GpuProbeApp({super.key, this.uploadPerFrame = true});

  /// 是否每帧把像素重新上传。关闭后帧只做 asImage + 显示。
  final bool uploadPerFrame;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_gpu_probe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: ProbePage(uploadPerFrame: uploadPerFrame),
    );
  }
}

class ProbePage extends StatefulWidget {
  const ProbePage({super.key, this.uploadPerFrame = true});

  final bool uploadPerFrame;

  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Timer? _statsTimer;

  // ── 初始化结果。失败也必须落盘 ——「能不能初始化」正是本验证的核心问题。
  gpu.GpuContext? _ctx;
  String? _initError;

  gpu.Texture? _texture;
  String? _textureError;
  String _formatName = '—';

  /// ImageSurface 是「渲染后直接当 ui.Image 显示」的正规通道，这里只探测能否创建。
  String _surfaceProbe = '未探测';

  ui.Image? _image;

  /// 每帧是否重新上传像素。切换它会即时改变帧率，用于隔离 CPU 上传成本。
  late bool _uploadPerFrame = widget.uploadPerFrame;

  final Uint8List _pixels = Uint8List(kWidth * kHeight * 4);
  (int, int) _lastBlock = (-1, -1);

  double _phase = 0.0;
  int _frames = 0;
  int _uploads = 0;
  int _asImageCalls = 0;
  double _measuredFps = 0.0;
  int _tickCount = 0;
  String? _workDir;

  @override
  void initState() {
    super.initState();
    _workDir = Directory.current.path;
    _initialize();
    _ticker = createTicker(_onTick)..start();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _writeStats());
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _ticker.dispose();
    _image?.dispose();
    super.dispose();
  }

  // ───────────────────────────── 初始化 ─────────────────────────────

  void _initialize() {
    // 顶层 final `gpuContext` 是惰性初始化的，第一次访问才会去建 context。
    // 引擎没有以 --enable-flutter-gpu 启动时这里会抛异常，必须捕获，
    // 否则 Dart 侧直接崩，什么都看不到。
    try {
      _ctx = gpu.gpuContext;
    } catch (error) {
      _initError = error.toString();
      return;
    }

    final gpu.GpuContext ctx = _ctx!;

    try {
      final gpu.Texture texture = ctx.createTexture(
        gpu.StorageMode.hostVisible,
        kWidth,
        kHeight,
        format: ctx.defaultColorFormat,
        enableRenderTargetUsage: true,
        enableShaderReadUsage: true,
      );
      _formatName = texture.format.name;
      _texture = texture;
    } catch (error) {
      _textureError = error.toString();
      return;
    }

    _buildBaseImage();

    try {
      final gpu.GpuImageSurface surface =
          ctx.createImageSurface(kWidth, kHeight);
      // 没有 present 过，currentImage 按文档应为 null。
      _surfaceProbe = '创建成功 ${surface.width}×${surface.height} '
          'format=${surface.format.name} '
          '后备纹理=${surface.debugBackingTextureCount} '
          'currentImage=${surface.currentImage}';
    } catch (error) {
      _surfaceProbe = '创建失败：$error';
    }

    _upload();
    _refreshImage();
  }

  // ───────────────────────── 像素生成（CPU 侧）─────────────────────────
  //
  // 布局与 texture-bridge 的两条路径严格一致。为了不让 Dart 逐像素循环成为
  // 帧率瓶颈，基础图案只画一次；此后每帧只擦除旧方块、画新方块。

  void _buildBaseImage() {
    for (int y = 0; y < kHeight; y++) {
      for (int x = 0; x < kWidth; x++) {
        final int i = (y * kWidth + x) * 4;
        int r = 0;
        int g = 0;
        int b = 0;

        if (y < kHeight ~/ 4) {
          // 顶部三色带：通道顺序检查。
          final int third = x * 3 ~/ kWidth;
          if (third == 0) {
            r = 255;
          } else if (third == 1) {
            g = 255;
          } else {
            b = 255;
          }
        } else if (y >= kHeight * 3 ~/ 4) {
          // 底部渐变：只让它有内容，不参与校验。
          final int span = kHeight - (kHeight * 3 ~/ 4);
          final int v = span <= 0 ? 0 : (y - kHeight * 3 ~/ 4) * 200 ~/ span;
          r = 40;
          g = 40;
          b = 40 + v;
        }

        _pixels[i] = r;
        _pixels[i + 1] = g;
        _pixels[i + 2] = b;
        _pixels[i + 3] = 255;
      }
    }
  }

  void _paintBlock(int left, int top, int w, int h, int value) {
    for (int y = top; y < top + h; y++) {
      if (y < 0 || y >= kHeight) {
        continue;
      }
      int base = (y * kWidth + left) * 4;
      for (int x = 0; x < w; x++) {
        final int px = left + x;
        if (px < 0 || px >= kWidth) {
          base += 4;
          continue;
        }
        _pixels[base] = value;
        _pixels[base + 1] = value;
        _pixels[base + 2] = value;
        _pixels[base + 3] = 255;
        base += 4;
      }
    }
  }

  int get _blockW => kWidth ~/ 5;
  int get _blockH => kHeight ~/ 8;

  void _updateMovingBlock() {
    final (int, int) previous = _lastBlock;
    if (previous.$1 >= 0) {
      _paintBlock(previous.$1, previous.$2, _blockW, _blockH, 0);
    }
    // 2 秒一个来回，与另外两条路径一致。
    final int travel = kWidth - _blockW;
    final int x = ((_phase * 2 - 1).abs() * travel).round();
    final int y = kHeight ~/ 2 - _blockH ~/ 2;
    _paintBlock(x, y, _blockW, _blockH, 255);
    _lastBlock = (x, y);
  }

  void _upload() {
    final gpu.Texture? texture = _texture;
    if (texture == null) {
      return;
    }
    try {
      texture.overwrite(_pixels.buffer.asByteData());
      _uploads++;
    } catch (error) {
      _textureError = 'overwrite 失败：$error';
    }
  }

  void _refreshImage() {
    final gpu.Texture? texture = _texture;
    if (texture == null) {
      return;
    }
    try {
      final ui.Image image = texture.asImage();
      final ui.Image? previous = _image;
      setState(() => _image = image);
      _asImageCalls++;
      // 每帧新建的 ui.Image 是引擎侧引用，不释放会持续占显存。
      previous?.dispose();
    } catch (error) {
      _textureError = 'asImage 失败：$error';
    }
  }

  // ───────────────────────────── 帧驱动 ─────────────────────────────

  void _onTick(Duration elapsed) {
    if (_texture == null) {
      return;
    }
    _phase = (elapsed.inMicroseconds % 2000000) / 2000000.0;
    _updateMovingBlock();
    if (_uploadPerFrame) {
      _upload();
    }
    _refreshImage();
    _frames++;
    _tickCount++;
  }

  void _tick() {
    if (!mounted) {
      return;
    }
    setState(() {
      _measuredFps = _tickCount.toDouble();
      _tickCount = 0;
    });
    unawaited(_writeStats());
  }

  Future<void> _writeStats() async {
    final String? dir = _workDir;
    if (dir == null) {
      return;
    }
    final Map<String, Object?> payload = <String, Object?>{
      'backend': 'flutter_gpu',
      'ok': _texture != null,
      'initError': _initError,
      'textureError': _textureError,
      'format': _formatName,
      'width': kWidth,
      'height': kHeight,
      'surfaceProbe': _surfaceProbe,
      'frames': _frames,
      'uploads': _uploads,
      'asImageCalls': _asImageCalls,
      'uploadPerFrame': _uploadPerFrame,
      'measuredFps': _measuredFps,
      'writtenAt': DateTime.now().toIso8601String(),
    };
    try {
      await File('$dir${Platform.pathSeparator}flutter-gpu-stats.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    } catch (_) {
      // 落盘失败不影响验证本身。
    }
  }

  // ───────────────────────────── 界面 ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: Container(
              color: Colors.black,
              child: _image == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: SelectableText(
                          _initError != null
                              ? 'Flutter GPU 初始化失败：\n$_initError'
                              : _textureError != null
                                  ? 'Flutter GPU 纹理失败：\n$_textureError'
                                  : '尚未出画',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFFF7B72)),
                        ),
                      ),
                    )
                  : SizedBox.expand(
                      // fit: fill 与另外两条路径一致，避免尺寸差异影响截图校验。
                      child: RawImage(image: _image, fit: BoxFit.fill),
                    ),
            ),
          ),
          _buildPanel(),
        ],
      ),
    );
  }

  Widget _buildPanel() {
    final bool ok = _texture != null;
    final String verdict;
    if (_initError != null) {
      verdict = 'Flutter GPU 不可用（context 初始化失败）';
    } else if (_textureError != null) {
      verdict = 'Flutter GPU 可用，但纹理环节失败';
    } else if (ok) {
      verdict = 'Flutter GPU 已出画：asImage() 直接产出 ui.Image，无跨设备共享';
    } else {
      verdict = '尚未完成初始化';
    }

    return Container(
      color: const Color(0xFF12141A),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  verdict,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color:
                        ok ? const Color(0xFF7CE38B) : const Color(0xFFFF7B72),
                  ),
                ),
              ),
              FilledButton.tonal(
                onPressed: () {
                  setState(() => _uploadPerFrame = !_uploadPerFrame);
                  unawaited(_writeStats());
                },
                child: Text(_uploadPerFrame ? '每帧上传：开' : '每帧上传：关'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 22,
            runSpacing: 6,
            children: <Widget>[
              _stat('纹理格式', _formatName),
              _stat('尺寸', '$kWidth × $kHeight'),
              _stat('已渲染帧', '$_frames'),
              _stat('像素上传次数', '$_uploads'),
              _stat('asImage 次数', '$_asImageCalls'),
              _stat('Dart 侧实测', '${_measuredFps.toStringAsFixed(0)} 帧/秒'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'ImageSurface 探测：$_surfaceProbe',
            style: const TextStyle(fontSize: 12, color: Color(0xFF8B949E)),
          ),
          if (_textureError != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              _textureError!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFFF7B72)),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            '切换「每帧上传」可直接对比 CPU→GPU 全表面上传的代价：'
            '开启时每帧重传 2.7 MB 像素，关闭时帧只做 asImage + 显示。',
            style: TextStyle(fontSize: 12, color: Color(0xFF8B949E)),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E)),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 14, color: Color(0xFFE6EDF3)),
        ),
      ],
    );
  }
}
