import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:zephyr/gpu/gpu_present_bridge.dart';
import 'package:zephyr/gpu/page_turn_probe.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/image_surface.dart';
import 'package:zephyr/reader/local_page_source.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/src/rust/api/local.dart';

/// GPU 上屏调试页（Windows）。
///
/// # 它现在只剩三件事
///
/// 1. **打开哪一本**（`LocalPageSource`）与**在第几页**；
/// 2. 挂上显示节点 `ImageSurface`；
/// 3. 把这条链路的判据读数摊在面板上。
///
/// 「现在走哪条路」「纹理注册了没有」「拖窗口之后画面还在不在」这些都不在这一页里 ——
/// 它们在 `ImageSurface` 与 `GpuPresentController` 里。这一页因此可以随便换，
/// 阅读器接进来时换掉的是它，不是节点。
///
/// # 判定文案是这个页面存在的理由
///
/// 黑屏的原因可以是七八种（DLL 没构建、adapter 不匹配、纹理没注册、
/// 引擎没来取帧、呈现器还在建、两侧页数对不上……），只显示"黑屏"等于没有信息。
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
  final TextEditingController _pathController = TextEditingController(
    text: Platform.environment['ROSSI_GPU_PRESENT_SAMPLE'] ??
        r'D:\1Dev\tmp\rossi-probe\probe.cbz',
  );
  final GpuPresentController _presenter = GpuPresentController();

  Timer? _statsTimer;

  /// 已打开的来源。**由本页拥有**：打开与关闭都经过它，
  /// 显示节点只是消费 —— 这正是「页来源只有一份」的落点。
  PageSource? _source;
  String? _rejectedMessage;
  int _index = 0;

  /// 显示节点现在走的是哪条路（由节点回报）。
  ImageSurfacePath _path = ImageSurfacePath.cpu;

  /// `localOpenSessionCount()`：判据 D 的探针。
  ///
  /// 放在这里是有意的 —— 会话泄漏**不体现在 RSS 里**，只能靠这个计数看。
  /// 换书、反复打开同一本、来回切通路之后，它必须回落到基线，不允许单调上升。
  int _sessions = 0;

  bool _busy = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _presenter.start();
    if (PageTurnProbe.isRequested) {
      // 量具模式：**不要**那个 1 秒心跳。它会替我们多打几次 `stats`，而那些调用
      // 同样要过 native 那把锁（`show` 解码时正持着它）—— 正好污染要量的东西。
      unawaited(_autorunProbe());
      return;
    }
    _statsTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_refreshCounters()),
    );
    unawaited(_presenter.refreshStats());
  }

  /// 量具模式：无人值守跑一遍翻页序列。契约见 `page_turn_probe.dart`。
  ///
  /// 顺序有讲究：**先等呈现器就绪、再打开来源**。反过来的话第一页会落在 CPU 兜底路上
  /// （那是另一条路径的延迟），把 GPU 路的基线污染掉。
  Future<void> _autorunProbe() async {
    final PageTurnProbeRun run = PageTurnProbeRun()..startRecording();
    run.note('量具模式：${PageTurnProbe.logPath}');
    run.note('轮数 ${PageTurnProbe.turns}，每轮停留 ${PageTurnProbe.dwellMs} ms');

    // 先把表头落盘：跑挂了也留得下痕迹（否则"没文件"和"没跑"分不出来）。
    try {
      final File header = File('${PageTurnProbe.logPath}.turns.csv');
      await header.parent.create(recursive: true);
      await header.writeAsString(PageTurnProbe.turnsCsvHeader, flush: true);
    } catch (error) {
      run.note('写表头失败（继续跑）：$error');
    }

    try {
      final int waited = await _waitForPresenterReady();
      run.note(
        waited < 0
            ? '等呈现器就绪超时（上限 ${PageTurnProbe.readyTimeoutMs} ms）—— '
                '这份基线会混进 CPU 兜底路径，别当 GPU 路的数用'
            : '呈现器 $waited ms 后就绪',
      );

      final String sample = PageTurnProbe.sample;
      if (sample.isNotEmpty) {
        _pathController.text = sample;
      }
      await _open();
      final PageSource? source = _source;
      if (source == null || !mounted) {
        run.note('来源没打开成功：${_rejectedMessage ?? _actionError ?? '未知原因'}');
        run.note('**这份数据无效**');
        await run.finish();
        exit(2);
      }
      run.note('来源 ${source.path}（${source.pageCount} 页）');

      for (int turn = 0; turn < PageTurnProbe.turns; turn++) {
        // 页号**绕回**，不是夹到最后一页：轮数多于页数时（判据 C 要 100 次）夹住会变成
        // "把同一页反复交出去"，量到的是幂等早退，不是翻页。
        final int page = turn % source.pageCount;
        final int framesBefore = run.frameCount;
        final int seqBefore = _presenter.presentCount;
        _show(page);
        await Future<void>.delayed(
          Duration(milliseconds: PageTurnProbe.dwellMs),
        );
        await _presenter.refreshStats();
        // 只有"这一轮真的交出去过页"才算它的往返：**页号会重复**，所以判据是计数变大，
        // 不是页号对得上 —— 后者会把上一轮的残值记成这一轮的延迟。
        final bool pushed = _presenter.presentCount > seqBefore;
        run.recordTurn(
          ProbeTurn(
            turn: turn,
            page: page,
            path: _path.name,
            handleOpened: _presenter.stats?.handleOpened ?? 0,
            framesBefore: framesBefore,
            framesAfter: run.frameCount,
            presentMs: pushed ? _presenter.lastPresentMs : null,
            presentSeq: _presenter.presentCount,
            rust: _presenter.stats?.probe,
          ),
        );
      }

      final String summary = await run.finish();
      // 控制台在 GUI 子系统下常常不可见，所以真正的交付物是那三个文件；
      // 这句只是给从终端直接拉起的情况留个方便。
      // ignore: avoid_print
      print(summary);
      exit(0);
    } catch (error, stack) {
      run.note('量具自己抛了：$error');
      run.note('$stack');
      await run.finish();
      exit(3);
    }
  }

  /// 等呈现器脱离 `loading`。返回等了多久（毫秒）；没等到返回 -1。
  Future<int> _waitForPresenterReady() async {
    final Stopwatch clock = Stopwatch()..start();
    while (_presenter.state == GpuPresentState.loading &&
        clock.elapsedMilliseconds < PageTurnProbe.readyTimeoutMs) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (_presenter.state != GpuPresentState.ready) {
      return -1;
    }
    return clock.elapsedMilliseconds;
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _pathController.dispose();
    // 本页拥有来源，所以本页负责关闭 —— 且不必 await（析构里没法等）。
    unawaited(_source?.close());
    _presenter.dispose();
    super.dispose();
  }

  Future<void> _refreshCounters() async {
    final int sessions = localOpenSessionCount();
    await _presenter.refreshStats();
    if (!mounted) {
      return;
    }
    setState(() => _sessions = sessions);
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
      final PageSourceOpen result = await LocalPageSource.open(path);
      if (!mounted) {
        return;
      }

      switch (result) {
        case PageSourceRejected(:final message):
          setState(() {
            _rejectedMessage = message;
            _source = null;
            _index = 0;
          });
          return;

        case PageSourceOpened(:final source):
          final PageSource? previous = _source;
          setState(() {
            _source = source;
            _index = 0;
            _rejectedMessage = null;
            _actionError = null;
          });
          // 换书必须关掉上一本：会话是有限的观测对象，漏了就是一个只涨不减的数。
          // 放在 setState 之后关，界面已经不再引用它了。
          await previous?.close();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _actionError = '$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _show(int index) {
    final PageSource? source = _source;
    if (source == null || index < 0 || index >= source.pageCount) {
      return;
    }
    setState(() => _index = index);
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
            onPressed: _refreshCounters,
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
              child: _buildStage(),
            ),
          ),
          ListenableBuilder(
            listenable: _presenter,
            builder: (BuildContext context, Widget? child) =>
                _buildPanel(devicePixelRatio),
          ),
        ],
      ),
    );
  }

  Widget _buildStage() {
    final PageSource? source = _source;
    if (source == null) {
      return _hint(
        _rejectedMessage ??
            '尚未打开来源。\n\n选一个散图文件夹 / .cbz / .cbr；\n'
                '呈现器就绪前这里走 CPU 兜底路径，就绪后自动换成共享纹理。',
      );
    }
    return ImageSurface(
      source: source,
      index: _index,
      presenter: _presenter,
      onPathChanged: (ImageSurfacePath path) {
        if (mounted) {
          setState(() => _path = path);
        }
      },
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

  Widget _buildPanel(double devicePixelRatio) {
    final GpuPresentStats? stats = _presenter.stats;
    final PageSource? source = _source;
    final int pageCount = source?.pageCount ?? 0;

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
                onPressed: _busy || _index <= 0 ? null : () => _show(_index - 1),
                child: const Text('上一页'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _busy || _index + 1 >= pageCount
                    ? null
                    : () => _show(_index + 1),
                child: const Text('下一页'),
              ),
              const SizedBox(width: 16),
              Text(
                pageCount == 0 ? '尚未打开来源' : '第 ${_index + 1} / $pageCount 页',
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
                    color: _verdictOk(stats)
                        ? const Color(0xFF7CE38B)
                        : const Color(0xFFFF9C6B),
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
                _path == ImageSurfacePath.gpu ? 'GPU 共享纹理' : 'CPU 兜底（就绪前的降级）',
              ),
              _stat('呈现器', _gpuStateLabel()),
              // 判据 D 的探针：换书 / 反复打开后这个数必须回落。
              _stat('local_core 会话', '$_sessions'),
              if (stats != null) ...<Widget>[
                _stat('适配器', stats.adapter.isEmpty ? '—' : stats.adapter),
                _stat('LUID 命中 Flutter', stats.luidKnown ? '是' : '否（跨卡共享有风险）'),
                _stat('目标尺寸（物理）', '${stats.width} × ${stats.height}'),
                _stat('控件 DPR', devicePixelRatio.toStringAsFixed(2)),
                _stat(
                  'tex${stats.textureId < 0 ? '' : stats.textureId}',
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
          if (stats != null &&
              stats.probeRaw.isEmpty &&
              (_presenter.state == GpuPresentState.ready ||
                  _presenter.state == GpuPresentState.failed))
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
    switch (_presenter.state) {
      case GpuPresentState.loading:
        return '后台创建中（本页已等 ${_presenter.elapsedMs} ms）';
      case GpuPresentState.ready:
        final int? ms = _presenter.readyAfterMs;
        return ms == null ? '就绪' : '就绪（本页等了 $ms ms）';
      case GpuPresentState.failed:
        return '失败';
      case GpuPresentState.unsupported:
        return '本平台无此路径';
    }
  }

  /// 把这个页面要回答的问题直接写在脸上。
  bool _verdictOk(GpuPresentStats? stats) =>
      _path == ImageSurfacePath.gpu &&
      _presenter.canPresent &&
      (stats?.handleOpened ?? 0) > 0;

  String _verdict(GpuPresentStats? stats) {
    if (!GpuPresentController.isPlatformSupported) {
      return '当前平台不支持';
    }
    final PageSource? source = _source;
    final String? mismatch = source == null ? null : _presenter.mismatchFor(source);
    if (mismatch != null) {
      return mismatch;
    }
    switch (_presenter.state) {
      case GpuPresentState.loading:
        return '呈现器仍在后台创建 —— 此刻显示的是 CPU 兜底路径';
      case GpuPresentState.unsupported:
        return '当前平台没有这条路';
      case GpuPresentState.failed:
        return 'GPU 路径不可用：${_presenter.error}（继续走 CPU 兜底）';
      case GpuPresentState.ready:
        if (stats == null) {
          return '已就绪，正在读统计…';
        }
        if (stats.handleOpened > 0) {
          return '链路已通：引擎已打开共享句柄 ${stats.handleOpened} 次，画面来自 Rust 侧纹理';
        }
        if (stats.framesMarked > 0) {
          return '已通知引擎 ${stats.framesMarked} 次，但引擎还没来取帧（纹理未真正上屏？）';
        }
        return _source == null ? '已就绪，尚未打开来源' : '已就绪，尚未呈现任何页';
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
