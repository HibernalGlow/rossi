import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

// Rossi — Gate A 验证程序。
//
// 同一套像素约定跑两条独立路径，用来把两个互不相干的风险分开验证：
//
//   风险 1（native）：原生 D3D12 手写渲染 → DXGI shared texture → Flutter 合成
//   风险 2（wgpu）：  wgpu 渲染 → 同 device 上 GPU 拷贝到 shared texture → Flutter 合成
//
// 两条路径都画同样的内容：
//   1. 顶部从左到右 红 / 绿 / 蓝 三条纯色带
//      —— 通道顺序检查。若红蓝互换，说明格式被当成 RGBA 解释了。
//   2. 中部一个左右往返移动的白色方块
//      —— 证明帧在持续更新，不是只画了一次。
//   3. 底部一条随相位渐变的横条。
//
// 像素约定刻意保持一致，所以截屏校验脚本可以两条路径复用，
// 也能直接用肉眼比对两者是否一致。
//
// 同一时刻只渲染正在显示的那一条，避免无谓的双份开销。

void main() {
  runApp(const GateAApp());
}

enum Backend { native, wgpu }

extension BackendInfo on Backend {
  String get label => this == Backend.native ? 'native' : 'wgpu';

  /// 两条路径各有一个 MethodChannel，名字必须不同
  /// （一个 channel 名只能挂一个处理器）。
  String get channelName => this == Backend.native
      ? 'rossi/poc/texture_bridge'
      : 'rossi/poc/wgpu_bridge';

  String get statsFileName => this == Backend.native
      ? 'poc-native-stats.json'
      : 'poc-wgpu-stats.json';
}

class GateAApp extends StatelessWidget {
  const GateAApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rossi Gate A GPU Texture PoC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const ProbePage(),
    );
  }
}

class ProbePage extends StatefulWidget {
  const ProbePage({super.key});

  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Timer? _statsTimer;

  /// 默认落在 wgpu 上：本轮要验证的就是这条路径。
  Backend _backend = Backend.wgpu;

  final Map<Backend, int> _textureIds = <Backend, int>{};
  final Map<Backend, Map<Object?, Object?>> _stats =
      <Backend, Map<Object?, Object?>>{};
  final Map<Backend, Object?> _errors = <Backend, Object?>{};

  double _phase = 0.0;
  bool _renderEnabled = true;
  bool _inFlight = false;

  // Dart 侧实测吞吐，不是引擎内部帧率 —— 用来观察每帧一次平台通道往返的代价。
  int _tickCount = 0;
  double _measuredFps = 0.0;

  // 把原生侧诊断数据落盘，便于在无人肉眼看画面的情况下自动判定通道是否打通。
  // 真正确凿的证据是 handleOpened > 0：说明引擎确实打开了我们给的 shared handle。
  String? _workDir;

  @override
  void initState() {
    super.initState();
    _workDir = Directory.current.path;
    _ticker = createTicker(_onTick)..start();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  MethodChannel _channelFor(Backend backend) =>
      MethodChannel(backend.channelName);

  Future<void> _refresh() async {
    for (final Backend backend in Backend.values) {
      try {
        final Map<Object?, Object?>? result = await _channelFor(backend)
            .invokeMethod<Map<Object?, Object?>>('getStats');
        if (!mounted) {
          return;
        }
        if (result == null) {
          continue;
        }
        setState(() {
          _stats[backend] = result;
          _errors[backend] = null;
          final Object? id = result['textureId'];
          if (id is int && id >= 0) {
            _textureIds[backend] = id;
          }
        });
      } catch (error) {
        if (!mounted) {
          return;
        }
        setState(() => _errors[backend] = error);
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _measuredFps = _tickCount.toDouble();
      _tickCount = 0;
    });
    unawaited(_writeStats());
  }

  void _onTick(Duration elapsed) {
    if (!_renderEnabled || _inFlight) {
      return;
    }
    if (_textureIds[_backend] == null) {
      return;
    }
    // 2 秒一个来回。
    _phase = (elapsed.inMicroseconds % 2000000) / 2000000.0;
    _inFlight = true;
    _channelFor(_backend)
        .invokeMethod<bool>('renderFrame', <String, Object?>{'phase': _phase})
        .then((_) {
      _inFlight = false;
      _tickCount++;
    }).catchError((Object _) {
      _inFlight = false;
    });
  }

  Future<void> _writeStats() async {
    final String? dir = _workDir;
    if (dir == null) {
      return;
    }
    for (final Backend backend in Backend.values) {
      final Map<Object?, Object?> stats = _stats[backend] ?? const {};
      if (stats.isEmpty) {
        continue;
      }
      try {
        final Map<String, Object?> payload = <String, Object?>{
          'backend': backend.label,
          'verdict': stats['ok'] == true ? 'channel_ok' : 'init_failed',
          'stats': stats,
          'measuredFps': backend == _backend ? _measuredFps : null,
          'textureId': _textureIds[backend],
          'renderEnabled': _renderEnabled,
          'writtenAt': DateTime.now().toIso8601String(),
        };
        await File('$dir${Platform.pathSeparator}${backend.statsFileName}')
            .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
      } catch (_) {
        // 落盘失败不影响验证本身，忽略。
      }
    }
  }

  Future<void> _forceRecreate() async {
    try {
      await _channelFor(_backend).invokeMethod<bool>('forceRecreate');
    } catch (error) {
      if (mounted) {
        setState(() => _errors[_backend] = error);
      }
    }
    await _refresh();
  }

  Map<Object?, Object?> get _currentStats =>
      _stats[_backend] ?? const <Object?, Object?>{};

  String _value(String key) {
    final Object? value = _currentStats[key];
    return value == null ? '—' : '$value';
  }

  @override
  Widget build(BuildContext context) {
    final int? textureId = _textureIds[_backend];

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: Container(
              color: Colors.black,
              child: textureId == null
                  ? Center(
                      child: Text(
                        _errors[_backend] != null
                            ? '${_backend.label} 平台通道异常：${_errors[_backend]}'
                            : '${_backend.label} 尚未拿到 textureId，原生侧可能初始化失败',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : SizedBox.expand(child: Texture(textureId: textureId)),
            ),
          ),
          _buildPanel(),
        ],
      ),
    );
  }

  Widget _buildPanel() {
    final bool ok = _currentStats['ok'] == true;
    final String error = _value('error');
    final bool isWgpu = _backend == Backend.wgpu;

    final String verdict;
    if (_errors[_backend] != null) {
      verdict = '平台通道异常：${_errors[_backend]}';
    } else if (!ok) {
      verdict = '初始化失败：${error == '—' ? '(无错误信息)' : error}';
    } else {
      verdict = isWgpu
          ? 'wgpu 路径已出画，native 与 wgpu 可切换比对'
          : 'native 路径已出画（风险 1 回归）';
    }

    return Container(
      color: const Color(0xFF12141A),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              SegmentedButton<Backend>(
                segments: const <ButtonSegment<Backend>>[
                  ButtonSegment<Backend>(
                    value: Backend.native,
                    label: Text('native (风险1)'),
                  ),
                  ButtonSegment<Backend>(
                    value: Backend.wgpu,
                    label: Text('wgpu (风险2)'),
                  ),
                ],
                selected: <Backend>{_backend},
                onSelectionChanged: (Set<Backend> selection) {
                  setState(() => _backend = selection.first);
                },
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  verdict,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: ok ? const Color(0xFF7CE38B) : const Color(0xFFFF7B72),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 22,
            runSpacing: 6,
            children: <Widget>[
              _stat('adapter', _value('adapter')),
              if (isWgpu)
                _stat('复用 Flutter adapter', _value('luidKnown'))
              else
                _stat('复用 Flutter adapter', _value('usingFlutterAdapter')),
              _stat('texture 尺寸', '${_value('width')} × ${_value('height')}'),
              _stat('已渲染帧', _value('frames')),
              _stat('重建次数', _value('recreates')),
              _stat('handle 被打开', _value('handleOpened')),
              _stat('Dart 侧实测', '${_measuredFps.toStringAsFixed(0)} 帧/秒'),
            ],
          ),
          if (isWgpu) ...<Widget>[
            const SizedBox(height: 8),
            _keyEvidence(),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              FilledButton.tonal(
                onPressed: _forceRecreate,
                child: const Text('强制重建 texture'),
              ),
              const SizedBox(width: 10),
              FilledButton.tonal(
                onPressed: () =>
                    setState(() => _renderEnabled = !_renderEnabled),
                child: Text(_renderEnabled ? '暂停渲染' : '继续渲染'),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '拖动窗口边框改变尺寸，观察「texture 尺寸」与「重建次数」是否跟随。',
                  style: TextStyle(fontSize: 12, color: Color(0xFF8B949E)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 把「为什么必须多走一次 GPU 拷贝」这条结论直接摆到面板上。
  ///
  /// 它是从 Rust 侧实测回来的 HRESULT，不是我们的断言。
  Widget _keyEvidence() {
    final Object? probe = _currentStats['probe'];
    String direct = '—';
    String initMs = '—';
    String matched = '—';
    if (probe is String && probe.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(probe);
        if (decoded is Map<String, Object?>) {
          direct = '${decoded['directShareOfWgpuTexture']}';
          initMs = '${decoded['initMs']}';
          matched = '${decoded['adapterMatched']}';
        }
      } catch (_) {
        // 解析失败就保持占位符。
      }
    }

    return Row(
      children: <Widget>[
        _stat('adapter LUID 命中', matched),
        const SizedBox(width: 22),
        _stat('探针初始化', '$initMs ms'),
        const SizedBox(width: 22),
        _stat('直接共享 wgpu texture', direct),
      ],
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
