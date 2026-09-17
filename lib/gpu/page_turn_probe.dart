import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:zephyr/gpu/gpu_present_page.dart';

/// 翻页量具（无人值守模式）。
///
/// # 为什么它必须长在 App 自己身上
///
/// 判据 C 看的是**帧时间分布**（p95 ≤ 16.7 ms、p99 ≤ 33 ms、没有 > 100 ms 的单帧），
/// 而这件事手点量不出来 —— 手点十来页得到的是"感觉"，不是分布。而且判据**只在 Release
/// 下成立**，`flutter test` 只能跑 Debug（`integration_test` 走的也是 Debug App），
/// 所以量具只能挂在 App 里，由 Release 产物自己跑出来。
///
/// # 怎么用
///
/// 设 `ROSSI_PAGE_TURN_LOG=<基路径>` 启动。App 会**绕开正常启动**（不建数据库、不连网、
/// 不还原窗口尺寸），直接进 GPU 上屏页，等呈现器就绪 → 打开来源 → 自动翻 N 页，
/// 然后写三个文件并退出：
///
/// - `<基路径>`：人读的汇总（配置 + 每轮一行 + 分位数 + 判据 C 的判定）；
/// - `<基路径>.turns.csv`：每轮一行（Dart 侧 present 往返 + Rust 侧分段 + 目标尺寸）；
/// - `<基路径>.frames.csv`：每帧一行（build / raster / span）。
///
/// 汇总文件**不是**最后才写的：开跑前先把 `.turns.csv` 的表头落盘 —— 万一中途挂住，
/// 至少还能分出「没跑起来」和「跑了没结果」（这两者看起来都是"没有文件"，
/// 而这个区别决定了该往哪儿查）。
///
/// | 环境变量 | 默认 | 含义 |
/// | --- | --- | --- |
/// | `ROSSI_PAGE_TURN_LOG` | —— | 输出基路径。**没设就不进量具模式** |
/// | `ROSSI_GPU_PRESENT_SAMPLE` | 页面里那个默认样本 | 打开哪一个来源 |
/// | `ROSSI_PAGE_TURN_TURNS` | `8` | 翻几页 |
/// | `ROSSI_PAGE_TURN_DWELL_MS` | `900` | 每页停多久（等这一轮落定） |
/// | `ROSSI_PAGE_TURN_READY_MS` | `10000` | 等呈现器就绪的上限 |
///
/// # 三个口径上的选择
///
/// - **"这一页等了多久"用 [GpuPresentController.lastPresentMs]**，不用手表从 Dart 侧
///   量。它是 `present()` 的整段往返，**含**跨语言调用与 native 侧全部工作（解码 →
///   上传 → 渲染 → `CopyResource` → 通知引擎）。从 Dart 再往下（引擎何时合成这一帧）
///   就观测不到了，再往下量只能得到"我 await 完了"，没有意义。
/// - **帧按"落在哪一轮"归属**，靠 `FrameTiming` 回调和轮次的序号区间对齐，不靠时间戳。
///   引擎时钟与 `DateTime` 不是一个纪元，硬换算会引入一个查不出来的偏移；
///   而帧是按序到达的，序号区间是精确的。
/// - **判据 C 不含第 1 轮**。第 1 轮是"打开来源后的首屏"，冷启动那一页（判据 B 管它），
///   它的帧会被算进 p95 里把判据判死。排除，但**单独报一节**——排除口径必须可见。
///   另外单列 `span`（被推迟了多久），那是"窗口冻没冻"的读数。
class PageTurnProbe {
  PageTurnProbe._();

  static const String _logVar = 'ROSSI_PAGE_TURN_LOG';

  /// `.turns.csv` 的表头。集中在这里定义 —— 页面在开跑前要先把表头落盘
  /// （万一挂住，至少能分出"没跑"和"跑了没结果"），两边各写一份迟早会写岔。
  static const String turnsCsvHeader =
      'turn,page,native_page,path,handle_opened,frames_before,frames_after,'
      'present_ms,present_seq,cache_hit,rust_total_ms,rust_decode_ms,rust_upload_ms,'
      'rust_submit_ms,'
      'decoded_w,decoded_h,target_w,target_h,source_w,source_h,'
      'init_ms,init_device_ms,prefetch_decoded,prefetch_enabled,'
      'show_async,show_busy_rejected\n';

  static String get logPath => (Platform.environment[_logVar] ?? '').trim();

  /// 设了 `ROSSI_PAGE_TURN_LOG` 就进量具模式。
  static bool get isRequested => logPath.isNotEmpty;

  /// 要打开的来源。空串表示用页面里那个默认值。
  static String get sample =>
      (Platform.environment['ROSSI_GPU_PRESENT_SAMPLE'] ?? '').trim();

  static int get turns => _intFromEnv('ROSSI_PAGE_TURN_TURNS', 8);

  /// 每轮往前翻几页。默认 1（顺序读）。
  ///
  /// **设成大于预取半径（±2）是为了专门制造"冷页"。** 顺序翻页下几乎每一轮都被
  /// 预取命中，于是 `show` 那条"现解一页"的路径根本不被走到 —— 而它正是"窗口会
  /// 不会被冻住"的那条路。跨着翻（比如 10）时落点旁边没有任何已解好的页，
  /// **每一轮都是冷页**，这条路径才被真正压到。
  static int get stride => _intFromEnv('ROSSI_PAGE_TURN_STRIDE', 1);
  static int get dwellMs => _intFromEnv('ROSSI_PAGE_TURN_DWELL_MS', 900);
  static int get readyTimeoutMs => _intFromEnv('ROSSI_PAGE_TURN_READY_MS', 10000);

  static int _intFromEnv(String name, int fallback) {
    final int? parsed = int.tryParse((Platform.environment[name] ?? '').trim());
    return (parsed == null || parsed <= 0) ? fallback : parsed;
  }
}

/// 量具**启动阶段**失败时，把异常落到盘上（`<基路径>.boot-error.txt`）。
///
/// 为什么非要写文件：Windows 的 runner 是 GUI 子系统，没有控制台 —— `print` 与
/// 未捕获异常都不会出现在任何地方。少了这一步，量具失败的表现是「rc=1、无输出、
/// 无文件」，与「启动就崩」完全分不开（这个坑实际吃过一次）。
/// 所以量具的失败路径**只认文件**。
Future<void> writeProbeBootFailure(Object error, StackTrace stack) async {
  try {
    final File file = File('${PageTurnProbe.logPath}.boot-error.txt');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      'PROBE BOOT FAILED\n'
      'time  : ${DateTime.now().toIso8601String()}\n'
      'error : $error\n\n$stack\n',
      flush: true,
    );
  } catch (_) {
    // 连错误都写不出去时不再往上抛 —— 原来那个异常才是要报告的。
  }
}

/// 一帧的耗时。判据 C 看的是 [frameMs]。
class ProbeFrame {
  ProbeFrame(this.index, this.buildMs, this.rasterMs, this.spanMs);

  final int index;
  final double buildMs;
  final double rasterMs;

  /// `vsyncStart` 到 `rasterFinish`。含被 platform 线程挡住而推迟的时间，
  /// 所以"native 同步解码把 UI 冻住"这类故障会**只**在这个数上暴露。
  final double spanMs;

  /// 这一帧真正花掉的时间。取舍见 `docs/v0.1_acceptance.md` 判据 C。
  double get frameMs => buildMs + rasterMs;

  String toCsvRow() =>
      '$index,${buildMs.toStringAsFixed(3)},${rasterMs.toStringAsFixed(3)},'
      '${spanMs.toStringAsFixed(3)},${frameMs.toStringAsFixed(3)}';
}

/// 一轮翻页的记录。
class ProbeTurn {
  ProbeTurn({
    required this.turn,
    required this.page,
    required this.path,
    required this.handleOpened,
    required this.framesBefore,
    required this.framesAfter,
    required this.presentMs,
    required this.presentSeq,
    required this.showAsync,
    required this.showBusyRejected,
    required this.rust,
  });

  final int turn;
  final int page;

  /// 这一轮显示节点走的是哪条路（`gpu` / `cpu`）。
  ///
  /// **必须记下来**：基线只有在 `gpu` 上才有意义。混进 CPU 兜底的那些轮次
  /// 量的是另一条路径的延迟，拿它们当"GPU 路上屏的基线"是错的。
  final String path;

  /// 引擎打开共享句柄的次数。`> 0` 是"链路真通"的唯一硬证据 —— 它积累，
  /// 所以看它有没有比上一轮变大，比看绝对值有用。
  final int handleOpened;

  final int framesBefore;
  final int framesAfter;

  /// Dart 侧量到的 present 往返（毫秒）。`null` = 这一轮没有真的交出去页。
  final int? presentMs;

  /// 记这一轮时 [GpuPresentController.presentCount] 的值。
  ///
  /// 页号会重复（连翻绕回、反复点同一页），所以"页号对得上"不足以证明这一轮的
  /// `presentMs` 是**这一次**量出来的。看它比上一轮大了没有，才是硬证据。
  final int presentSeq;

  /// 桥这一份进程是不是把 `show` 放在工作线程上跑的（`ROSSI_GPU_SHOW_ASYNC`）。
  ///
  /// **A/B 时必须先看这个**：它记的是"开关真的生效了"，而不是"我设了环境变量"。
  /// 开关没生效时两组数据几乎一样，看着就像"这个改动没用"。
  ///
  /// `null` = native 侧没上报（`stats` 还没刷到）。**必须与 `false` 分开** ——
  /// 把"没拿到"当成"对照组"正是这一条要防的误读。
  final bool? showAsync;

  /// 因为"上一页还在呈现"而被拒掉的 `show` 次数。正常恒为 0 ——
  /// 不为 0 说明 Dart 侧出现了没被 `await` 串起来的并发。
  final int showBusyRejected;

  /// Rust 侧诊断快照（可能为 null：还没刷到）。
  final Map<String, Object?>? rust;

  double? _double(String key) {
    final Object? value = rust?[key];
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }

  int? _int(String key) {
    final Object? value = rust?[key];
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  String _num(String key, {int digits = 1}) {
    final double? value = _double(key);
    return value == null ? '' : value.toStringAsFixed(digits);
  }

  /// 布尔按 `1`/`0` 写，取不到写空 —— CSV 里三种状态（真/假/没有）必须分得开。
  String _bool(String key) {
    final Object? value = rust?[key];
    return value is bool ? (value ? '1' : '0') : '';
  }

  String toCsvRow() {
    return <String>[
      '$turn',
      '$page',
      _int('pageIndex')?.toString() ?? '',
      _csv(path),
      '$handleOpened',
      '$framesBefore',
      '$framesAfter',
      presentMs?.toString() ?? '',
      '$presentSeq',
      _bool('cacheHit'),
      _num('totalMs'),
      _num('decodeMs'),
      _num('uploadMs'),
      _num('submitMs'),
      _int('decodedWidth')?.toString() ?? '',
      _int('decodedHeight')?.toString() ?? '',
      _int('width')?.toString() ?? '',
      _int('height')?.toString() ?? '',
      _int('sourceWidth')?.toString() ?? '',
      _int('sourceHeight')?.toString() ?? '',
      _num('initMs', digits: 0),
      _num('initDeviceMs', digits: 0),
      _int('prefetchDecoded')?.toString() ?? '',
      _bool('prefetchEnabled'),
      showAsync == null ? '' : (showAsync! ? '1' : '0'),
      '$showBusyRejected',
    ].join(',');
  }

  /// 这一轮对应的帧。
  List<ProbeFrame> framesIn(List<ProbeFrame> all) {
    final int from = framesBefore.clamp(0, all.length);
    final int to = framesAfter.clamp(from, all.length);
    return all.sublist(from, to);
  }
}

/// 一次量具运行：收帧、记轮次、写文件。
class PageTurnProbeRun {
  final List<ProbeFrame> _frames = <ProbeFrame>[];
  final List<ProbeTurn> _turns = <ProbeTurn>[];
  final List<String> _notes = <String>[];

  bool _recording = false;

  /// 已经收到的帧数。轮次用它划"这一轮落在哪几帧"。
  int get frameCount => _frames.length;

  void startRecording() {
    if (_recording) {
      return;
    }
    _recording = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<ui.FrameTiming> timings) {
    for (final ui.FrameTiming timing in timings) {
      _frames.add(
        ProbeFrame(
          _frames.length,
          timing.buildDuration.inMicroseconds / 1000.0,
          timing.rasterDuration.inMicroseconds / 1000.0,
          timing.totalSpan.inMicroseconds / 1000.0,
        ),
      );
    }
  }

  void note(String text) {
    _notes.add(text);
  }

  void recordTurn(ProbeTurn turn) {
    _turns.add(turn);
  }

  /// 把三份文件写出去。返回汇总文本（也写到基路径）。
  Future<String> finish() async {
    if (_recording) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
      _recording = false;
    }
    final String summary = _buildSummary();
    await _write(PageTurnProbe.logPath, summary);
    await _write('${PageTurnProbe.logPath}.turns.csv', _turnsCsv());
    await _write('${PageTurnProbe.logPath}.frames.csv', _framesCsv());
    return summary;
  }

  Future<void> _write(String path, String content) async {
    final File file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
  }

  String _turnsCsv() {
    final StringBuffer out = StringBuffer();
    out.write(PageTurnProbe.turnsCsvHeader);
    for (final ProbeTurn turn in _turns) {
      out.writeln(turn.toCsvRow());
    }
    return out.toString();
  }

  String _framesCsv() {
    final StringBuffer out = StringBuffer();
    out.writeln('index,build_ms,raster_ms,span_ms,frame_ms');
    for (final ProbeFrame frame in _frames) {
      out.writeln(frame.toCsvRow());
    }
    return out.toString();
  }

  String _buildSummary() {
    final StringBuffer out = StringBuffer();
    out.writeln('# 翻页量具');
    out.writeln();
    out.writeln('来源     : ${PageTurnProbe.sample.isEmpty ? '(页面默认)' : PageTurnProbe.sample}');
    out.writeln('轮数     : ${PageTurnProbe.turns}');
    out.writeln('每轮停留 : ${PageTurnProbe.dwellMs} ms');
    out.writeln('收帧总数 : ${_frames.length}');
    out.writeln();
    if (_notes.isNotEmpty) {
      out.writeln('## 过程');
      for (final String note in _notes) {
        out.writeln('- $note');
      }
      out.writeln();
    }

    out.writeln('## 每轮');
    out.writeln();
    out.writeln(
      '| 轮 | 页 | 通路 | 命中预取 | present ms | Rust 合计 | 解码 | 上传 | 渲染提交 | '
      '档位 | 目标 | 本轮帧数 | 本轮最大帧 ms |',
    );
    out.writeln(
      '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |',
    );
    for (final ProbeTurn turn in _turns) {
      final List<ProbeFrame> frames = turn.framesIn(_frames);
      double maxFrame = 0;
      for (final ProbeFrame frame in frames) {
        if (frame.frameMs > maxFrame) {
          maxFrame = frame.frameMs;
        }
      }
      out.writeln(
        '| ${turn.turn} | ${turn.page + 1} | ${turn.path} | '
        '${turn._bool('cacheHit') == '1' ? '✅' : '—'} | '
        '${turn.presentMs ?? '—'} | ${turn._num('totalMs')} | '
        '${turn._num('decodeMs')} | ${turn._num('uploadMs')} | '
        '${turn._num('submitMs')} | '
        '${turn._int('decodedWidth') ?? '?'}×${turn._int('decodedHeight') ?? '?'} | '
        '${turn._int('width') ?? '?'}×${turn._int('height') ?? '?'} | '
        '${frames.length} | ${frames.isEmpty ? '—' : maxFrame.toStringAsFixed(1)} |',
      );
    }
    out.writeln();

    // ── 预取 ──
    //
    // 这一段是"这一页为什么快/为什么慢"的直接答案。只看 `present ms` 的话，
    // 命中缓存的 5 ms 和"这页本来就小"的 5 ms 长得一模一样。
    if (_turns.isNotEmpty) {
      final ProbeTurn last = _turns.last;
      final String enabled = last._bool('prefetchEnabled');
      final int hits = _turns.where((ProbeTurn t) => t._bool('cacheHit') == '1').length;
      out.writeln('## 预取');
      out.writeln();
      out.writeln(
        '- 开关：${switch (enabled) {
          '1' => '开',
          '0' => '**关**（这一份是"没有预取"的对照）',
          _ => 'native 侧没上报',
        }}',
      );
      out.writeln('- 命中预取的轮次：$hits / ${_turns.length}');
      out.writeln('- 后台解出并放进缓存：${last._int('prefetchDecoded') ?? '—'} 页');
      out.writeln('- 解完发现已过期而丢掉：${last._int('prefetchStale') ?? '—'} 页');
      out.writeln('- 被容量/字节上限挤掉：${last._int('prefetchEvicted') ?? '—'} 页');
      out.writeln('- 缓存占用：${last._int('cacheBytes') ?? '—'} B');
      out.writeln();
    }

    // ── 这份基线是不是 GPU 路的 ──
    //
    // 不校验这一条，量出来的可能是"CPU 兜底路"的延迟，而它长得也挺像样。
    final int gpuTurns = _turns.where((ProbeTurn t) => t.path == 'gpu').length;
    final int lastOpened = _turns.isEmpty ? 0 : _turns.last.handleOpened;
    out.writeln('## 基线有效性');
    out.writeln();
    out.writeln('- 走 GPU 路的轮次：$gpuTurns / ${_turns.length}');
    out.writeln(
      '- 引擎打开共享句柄累计：$lastOpened '
      '${lastOpened > 0 ? '✅ 链路真通' : '❌ 引擎一次都没来取帧'}',
    );
    // `show` 到底在哪个线程上跑 —— A/B 的第一件事是**先证明开关生效了**。
    // 不先看这一条，两组读数一旦接近就会被读成"这个改动没用"。
    final bool? showAsync = _turns.isEmpty ? null : _turns.last.showAsync;
    final int busyRejected = _turns.isEmpty ? 0 : _turns.last.showBusyRejected;
    out.writeln(
      '- `show` 跑在：${switch (showAsync) {
        true => '桥的工作线程（默认）',
        false => '**平台线程（对照）**',
        null => 'native 侧没上报',
      }}',
    );
    if (busyRejected > 0) {
      out.writeln(
        '- ⚠️ 有 $busyRejected 次 `show` 因为"上一页还在呈现"被拒 —— '
        'Dart 侧出现了没被 await 串起来的并发，去查调用点。',
      );
    }
    if (lastOpened == 0) {
      out.writeln(
        '- ⚠️ 引擎一次都没来取帧：下面那些"帧"与这张纹理无关，'
        '整份数据的用途只剩下量具自检。',
      );
    }
    if (gpuTurns != _turns.length) {
      out.writeln(
        '- ⚠️ 有轮次落在 CPU 兜底路上。那些轮次**不能**当作 GPU 路的延迟。',
      );
    }
    out.writeln();

    // ── 判据 C ──
    //
    // 口径：帧时间 = `buildDuration + rasterDuration`，取**翻页序列**期间的帧。
    //
    // **第 1 轮（= 打开来源后的首屏）不计入**。它是冷启动那一页，判据 B 管的是它；
    // 把它算进 p95 会让判据 C 直接判死 —— 真发生过：同一份产物、同一本内容，
    // 含第 1 轮 p95 = 34.71 ms ❌（n=57，其中 4 帧来自首屏），不含则是十几毫秒。
    // 但这个"排除"必须**摆出来**，所以首屏单独报在下面，不藏。
    final ProbeTurn? firstTurn = _turns.isEmpty ? null : _turns.first;
    final List<ProbeFrame> turnFrames = <ProbeFrame>[];
    for (final ProbeTurn turn in _turns.skip(1)) {
      turnFrames.addAll(turn.framesIn(_frames));
    }
    out.writeln('## 判据 C（翻页序列的帧，n=${turnFrames.length}）');
    out.writeln();
    out.writeln('> 不含第 1 轮（首屏 = 冷启动，另见下节）。阈值见 `docs/v0.1_acceptance.md`。');
    out.writeln();
    if (turnFrames.isEmpty) {
      out.writeln('没有收到任何帧 —— 量具本身没跑起来，别拿这份数据下结论。');
    } else {
      _writeFrameVerdict(out, turnFrames);
    }
    out.writeln();

    if (firstTurn != null) {
      final List<ProbeFrame> coldFrames = firstTurn.framesIn(_frames);
      final List<double> cold = <double>[];
      for (final ProbeFrame frame in coldFrames) {
        cold.add(frame.frameMs);
      }
      double coldMax = 0;
      for (final double value in cold) {
        if (value > coldMax) {
          coldMax = value;
        }
      }
      out.writeln('## 首屏（不计入判据 C）');
      out.writeln();
      out.writeln(
        '- 第 1 轮：present ${firstTurn.presentMs ?? '—'} ms、帧数 ${cold.length}、'
        '最大帧 ${cold.isEmpty ? '—' : coldMax.toStringAsFixed(1)} ms',
      );
      out.writeln('- 这一轮混着"打开来源 + 第 1 页冷解码"，属于判据 B 的地界。');
      out.writeln();
    }

    // ── 帧跨度 ──
    //
    // `span` 是 `vsyncStart → rasterFinish`，**含排队等待**。所以它不是"这一帧花了多久"，
    // 而是"这一帧被推迟了多久" —— 这才是"窗口冻没冻"的直接读数：
    // native 在 platform 线程上同步解码一页 400 ms 时，跨度会跟着涨到几百毫秒
    // （对照组的 489.41 / 547.01 就是它），而此时 `frameMs` 看着还挺正常。
    final List<double> spans = <double>[];
    for (final ProbeFrame frame in _frames) {
      spans.add(frame.spanMs);
    }
    if (spans.isNotEmpty) {
      final int blocked = spans.where((double value) => value > 100).length;
      out.writeln('## 帧跨度（这一帧被推迟了多久）');
      out.writeln();
      out.writeln(
        '- 中位 ${_percentile(spans, 50).toStringAsFixed(1)} ms、'
        'p95 ${_percentile(spans, 95).toStringAsFixed(1)} ms、'
        '最大 ${spans.reduce((double a, double b) => a > b ? a : b).toStringAsFixed(1)} ms',
      );
      out.writeln(
        '- 跨度 > 100 ms（肉眼能看出停顿）：$blocked 帧${blocked == 0 ? ' ✅' : ' ⚠️'}',
      );
      out.writeln();
    }
    out.writeln('## 翻页延迟');
    out.writeln();
    final List<int> presents = _turns
        .map((ProbeTurn t) => t.presentMs)
        .whereType<int>()
        .toList();
    if (presents.isEmpty) {
      out.writeln('没量到任何一次 present 往返。');
    } else {
      presents.sort();
      out.writeln(
        '- present 往返：中位 ${presents[presents.length ~/ 2]} ms、'
        '最大 ${presents.last} ms（n=${presents.length}）',
      );
    }
    return out.toString();
  }
}

/// 量具模式下启动的那个极小 App。
///
/// 故意不复用正常启动路径：量时间的东西不该被数据库初始化、插件注册、窗口尺寸还原
/// 这些东西影响 —— 而且它们本来就跟这条链路无关。
class PageTurnProbeApp extends StatelessWidget {
  const PageTurnProbeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: GpuPresentPage(),
    );
  }
}

/// CSV 字段转义：含逗号/引号/换行就整体加引号。
String _csv(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

/// 判据 C 的三条阈值摊出来。
void _writeFrameVerdict(StringBuffer out, List<ProbeFrame> frames) {
  final List<double> values = <double>[];
  for (final ProbeFrame frame in frames) {
    values.add(frame.frameMs);
  }
  final double p95 = _percentile(values, 95);
  final double p99 = _percentile(values, 99);
  final double max = values.reduce((double a, double b) => a > b ? a : b);
  out.writeln('- p95 = ${p95.toStringAsFixed(2)} ms ${p95 <= 16.7 ? '✅' : '❌'}（阈值 16.7）');
  out.writeln('- p99 = ${p99.toStringAsFixed(2)} ms ${p99 <= 33 ? '✅' : '❌'}（阈值 33）');
  out.writeln('- max = ${max.toStringAsFixed(2)} ms ${max <= 100 ? '✅' : '❌'}（不许有 > 100 的单帧）');
}

/// 最近秩（nearest-rank）分位数。样本这么少，插值只会让它看着更精确。
double _percentile(List<double> values, double p) {
  if (values.isEmpty) {
    return 0;
  }
  final List<double> sorted = List<double>.of(values)..sort();
  final int rank = (p / 100 * sorted.length).ceil().clamp(1, sorted.length);
  return sorted[rank - 1];
}
