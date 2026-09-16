import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:zephyr/gpu/gpu_present_bridge.dart';

/// GPU 上屏调试页（Windows）。
///
/// 它显示的每一个像素都由这条链路产生：
///
/// ```text
/// 本地文件 → Rust 解码 → wgpu 上传/渲染 → GPU→GPU 拷贝 → D3D12 共享纹理
///          → Flutter(D3D11/ANGLE) 合成 → 这个 Texture 组件
/// ```
///
/// 页面最上面那行**判定**是这个页面存在的理由。黑屏的原因可以是七八种
/// （DLL 没构建、adapter 不匹配、纹理没注册、引擎没来取帧……），
/// 只显示"黑屏"等于没有信息。这里按 [GpuPresentStats] 把可区分的几种分开报，
/// 其中 `handleOpened > 0` 是唯一的硬证据：引擎只有确实把这张纹理合成了，
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
    text: Platform.environment['ROSSI_GPU_PRESENT_SAMPLE'] ?? r'D:\1Dev\tmp\rossi-probe\probe.cbz',
  );

  Timer? _statsTimer;

  int? _textureId;
  /// 已经按哪个**物理**尺寸初始化过。用来判断 LayoutBuilder 报的尺寸要不要处理。
  Size? _readyPhysicalSize;

  int _pageCount = 0;
  int _index = 0;

  bool _busy = false;
  String? _actionError;
  GpuPresentStats? _stats;

  @override
  void initState() {
    super.initState();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_refreshStats());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshStats());
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _pathController.dispose();
    super.dispose();
  }

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

  /// 按控件当前的**物理**尺寸让 native 侧准备纹理。
  ///
  /// 必须是物理像素：Flutter 的纹理按物理像素合成。传逻辑尺寸会在 1.5x / 2x
  /// 缩放的屏幕上得到一张被拉伸的模糊图，而且引擎随后会用物理尺寸来问
  /// `SurfaceCallback`，两边永远对不上，于是反复重建 —— 症状是拖窗口时画面闪烁。
  Future<void> _ensureTexture(Size physicalSize) async {
    if (_busy || !GpuPresentBridge.isPlatformSupported) {
      return;
    }
    if (_readyPhysicalSize == physicalSize && _textureId != null) {
      return;
    }
    _busy = true;
    try {
      final int textureId = await _bridge.init(
        width: physicalSize.width.round(),
        height: physicalSize.height.round(),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _textureId = textureId;
        _readyPhysicalSize = physicalSize;
        _actionError = null;
      });
      // 尺寸一变，native 侧会重建目标并重画当前页；把已有的页重呈一次，
      // 保证"拖完窗口还能看到内容"而不是一片底色。
      if (_pageCount > 0) {
        await _bridge.show(_index);
      }
      await _refreshStats();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _actionError = '初始化失败: $error');
    } finally {
      _busy = false;
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
      final int count = await _bridge.open(path);
      if (!mounted) {
        return;
      }
      setState(() {
        _pageCount = count;
        _index = 0;
      });
      await _show(0);
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
      await _bridge.show(index);
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

                  final int? textureId = _textureId;
                  if (textureId == null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _unavailableReason(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF8B949E)),
                        ),
                      ),
                    );
                  }
                  // 纹理铺满整个盒子，是**故意**的：页的等比缩放与留边在 Rust 侧
                  // 的着色器里完成，所以这张纹理本来就已经是"屏幕上的那一幅"。
                  // 这里再套一层 AspectRatio 或 BoxFit 只会引入第二次缩放。
                  return SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: Texture(textureId: textureId),
                  );
                },
              ),
            ),
          ),
          _buildPanel(devicePixelRatio),
        ],
      ),
    );
  }

  String _unavailableReason() {
    if (!GpuPresentBridge.isPlatformSupported) {
      return '当前平台没有这条路径。\n\nD3D12 共享纹理是 Windows 专属；\n'
          'macOS / Linux / 移动端走各自的上屏路径（尚未实现）。';
    }
    final String? error = _actionError;
    if (error != null) {
      return error;
    }
    final GpuPresentStats? stats = _stats;
    if (stats != null && !stats.ok) {
      return 'native 侧不可用：\n${stats.error}';
    }
    return '正在初始化呈现目标…';
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
                onPressed: !_busy && _index + 1 < _pageCount ? () => _show(_index + 1) : null,
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
                  _verdict(stats),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _verdictOk(stats) ? const Color(0xFF7CE38B) : const Color(0xFFFF9C6B),
                  ),
                ),
              ),
            ],
          ),
          if (stats != null) ...<Widget>[
            const SizedBox(height: 12),
            Wrap(
              spacing: 22,
              runSpacing: 6,
              children: <Widget>[
                _stat('适配器', stats.adapter.isEmpty ? '—' : stats.adapter),
                _stat('LUID 命中 Flutter', stats.luidKnown ? '是' : '否（跨卡共享有风险）'),
                _stat('目标尺寸（物理）', '${stats.width} × ${stats.height}'),
                _stat('控件 DPR', devicePixelRatio.toStringAsFixed(2)),
                _stat('tex$textureId', stats.textureId < 0 ? '未注册' : '已注册 #${stats.textureId}'),
                _stat('引擎打开句柄', '${stats.handleOpened}'),
                _stat('已通知取帧', '${stats.framesMarked}'),
                _stat('目标重建', '${stats.resizes}'),
                if (stats.probe.isNotEmpty) ...<Widget>[
                  _stat('解码档位', '${stats.probeInt('decodedWidth')} × ${stats.probeInt('decodedHeight')}'),
                  _stat('原图', '${stats.probeInt('sourceWidth')} × ${stats.probeInt('sourceHeight')}'),
                  _stat('解码', '${stats.probeDouble('decodeMs').toStringAsFixed(1)} ms'),
                  _stat('上传', '${stats.probeDouble('uploadMs').toStringAsFixed(1)} ms'),
                  _stat('渲染+提交', '${stats.probeDouble('submitMs').toStringAsFixed(1)} ms'),
                  _stat('合计', '${stats.probeDouble('totalMs').toStringAsFixed(1)} ms'),
                  _stat('直接共享 wgpu 纹理', '${stats['directShareOfWgpuTexture'] ?? '—'}'),
                  _stat('拷贝路径', '${stats['copyPath'] ?? '—'}'),
                ],
              ],
            ),
            if (stats.probeRaw.isEmpty && stats.ok)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'native 侧没有返回 Rust 侧诊断（DLL 与桥的版本可能不匹配）。',
                  style: TextStyle(fontSize: 12, color: Color(0xFFFF9C6B)),
                ),
              ),
          ],
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

  /// 把这个页面要回答的问题直接写在脸上。
  bool _verdictOk(GpuPresentStats? stats) =>
      stats != null && stats.ok && stats.handleOpened > 0;

  String _verdict(GpuPresentStats? stats) {
    if (!GpuPresentBridge.isPlatformSupported) {
      return '当前平台不支持';
    }
    if (stats == null) {
      return '正在读取统计…';
    }
    if (!stats.ok) {
      return 'native 侧不可用：${stats.error}';
    }
    if (stats.handleOpened > 0) {
      return '链路已通：引擎已打开共享句柄 ${stats.handleOpened} 次，画面来自 Rust 侧纹理';
    }
    if (stats.framesMarked > 0) {
      return '已通知引擎 ${stats.framesMarked} 次，但引擎还没来取帧（纹理未真正上屏？）';
    }
    return '已就绪，尚未呈现任何页';
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
