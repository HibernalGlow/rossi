/// 用**真实编码**的样本再验一遍引擎语义：h264 + aac + 章节 + 字幕。
///
/// 前面那套探针的片源是合成的（未压缩 AVI / WAV），有几件事它天生问不到：
/// - 章节：AVI 装不了章节，而 `chapter-list` 的毫秒精度、`add chapter` 的跳转
///   都是 mimage/neo 共有的一条功能；
/// - 真解码器路径：h264 的 `video-codec`、关键帧结构下的**精确定位**、
///   `hwdec=auto` 在 macOS 上到底有没有走 VideoToolbox；
/// - 波形：symphonia 解 aac-in-mp4 / aac-in-mkv 是声明过的能力（Cargo 里开了
///   `isompv`/`mkv`/`aac`），但 WAV 测不到它。
///
/// 样本用系统里的 ffmpeg 现场生成（**没有 ffmpeg 就整条 skip**，不会留一个永远红的测试）；
/// 它是工具链产物、不是分发的素材，所以不进仓库。
library;

import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:zephyr/src/rust/api/local.dart';
import 'package:zephyr/src/rust/frb_generated.dart';
import 'package:zephyr/video/controller/mpv_video_transport.dart';
import 'package:zephyr/video/controller/video_transport.dart';

String? _libmpv() {
  for (final p in const [
    '/opt/homebrew/opt/mpv/lib/libmpv.2.dylib',
    '/opt/homebrew/lib/libmpv.2.dylib',
    '/usr/local/lib/libmpv.2.dylib',
  ]) {
    try {
      DynamicLibrary.open(p);
      return p;
    } catch (_) {}
  }
  return null;
}

/// 生成一个 4 s、25 fps、160x120 的 h264 + aac + 两章的 mkv，外加一个 mp4 变体。
Future<Map<String, String>?> _makeSamples() async {
  final dir = Directory.systemTemp.createTempSync('rossi-real');
  final meta = File('${dir.path}/meta.txt')
    ..writeAsStringSync(
      ';FFMETADATA1\n'
      '[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=1500\ntitle=one\n'
      '[CHAPTER]\nTIMEBASE=1/1000\nSTART=1500\nEND=4000\ntitle=two\n',
    );
  final srt = File('${dir.path}/s.srt')
    ..writeAsStringSync('1\n00:00:01,000 --> 00:00:02,000\nrossi\n\n');
  final mkv = '${dir.path}/real.mkv';
  final mp4 = '${dir.path}/real.mp4';
  final r = await Process.run('ffmpeg', <String>[
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-f',
    'lavfi',
    '-i',
    'testsrc2=size=160x120:rate=25:duration=4',
    '-f',
    'lavfi',
    '-i',
    'sine=frequency=220:sample_rate=44100:duration=4',
    '-f',
    'srt',
    '-i',
    srt.path,
    '-f',
    'ffmetadata',
    '-i',
    meta.path,
    '-map',
    '0:v',
    '-map',
    '1:a',
    '-map',
    '2:s',
    '-map_metadata',
    '3',
    '-c:v',
    'libx264',
    '-pix_fmt',
    'yuv420p',
    '-c:a',
    'aac',
    '-c:s',
    'ass',
    mkv,
  ]);
  if (r.exitCode != 0) {
    return null;
  }
  final r2 = await Process.run('ffmpeg', <String>[
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-i',
    mkv,
    '-map_metadata',
    '-1',
    '-c:v',
    'copy',
    '-c:a',
    'copy',
    '-c:s',
    'mov_text',
    '-movflags',
    '+faststart',
    mp4,
  ]);
  if (r2.exitCode != 0) {
    return <String, String>{'mkv': mkv};
  }
  return <String, String>{'mkv': mkv, 'mp4': mp4};
}

/// 再要一个**带容器转置**的样本（手机拍的视频就是这种）。
/// `-display_rotation` 在 ffmpeg 9 里得写在 `-i` 前面（当输入选项），
/// 写成输出选项会被拒；`-metadata:s:v:0 rotate=90` 则会被新版的 mp4 muxer 丢掉。
Future<String?> _makeRotated() async {
  final dir = Directory.systemTemp.createTempSync('rossi-rot');
  final out = '${dir.path}/rot.mp4';
  final r = await Process.run('ffmpeg', <String>[
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-display_rotation:v:0',
    '90',
    '-f',
    'lavfi',
    '-i',
    'testsrc2=size=160x120:rate=25:duration=2',
    '-c:v',
    'libx264',
    '-pix_fmt',
    'yuv420p',
    out,
  ]);
  return r.exitCode == 0 ? out : null;
}

/// 打开到 ready（或带着原因失败）。
Future<VideoEnginePhase> _ready(
  MpvVideoTransport transport,
  String path, {
  VideoOpenOptions options = const VideoOpenOptions(autoplay: false),
}) async {
  final seen = transport.phaseStream.firstWhere(
    (p) => p == VideoEnginePhase.ready || p == VideoEnginePhase.failed,
  );
  await transport.open('file://$path', options: options);
  return seen.timeout(const Duration(seconds: 50));
}

void main() {
  late final Map<String, String>? samples;
  late final String? lib;

  setUpAll(() async {
    lib = _libmpv();
    samples = await _makeSamples();
  });

  void skipUnlessReady() {
    if (lib == null) {
      markTestSkipped('没有可加载的 libmpv（brew install mpv）');
    } else if (samples == null) {
      markTestSkipped('没有 ffmpeg，造不出真实编码的样本（brew install ffmpeg）');
    } else {
      MediaKit.ensureInitialized(libmpv: lib);
      NativePlayer.test = true;
    }
    if (samples == null || lib == null) return;
  }

  test('章节：毫秒精度解析 + 真的跳得过去', () async {
    skipUnlessReady();
    if (samples == null) return;
    final player = Player();
    final transport = MpvVideoTransport(player: player);
    expect(
      await _ready(transport, samples!['mkv']!),
      VideoEnginePhase.ready,
      reason: '真实 mkv 解不出来：${transport.failureReason}',
    );
    final meta = await _untilValue(
      () async => transport.metadata,
      (m) => m.chapters.length >= 2,
      what: 'chapter-list 解出两条章节',
    );
    expect(
      meta.chapters.map((c) => c.title),
      containsAll(<String>['one', 'two']),
    );
    // 缺陷 ⑨ 的回归判据：以前按 `toInt()` 取整，1.5 s 会变成 1 s。
    expect(
      meta.chapters[1].at.inMilliseconds,
      closeTo(1500, 60),
      reason: '章节起点该保毫秒精度，拿到的是 ${meta.chapters[1].at}',
    );

    final native = player.platform as NativePlayer;
    await transport.jumpChapter(1);
    expect(
      await _untilValue(
        () async => double.tryParse(await native.getProperty('playback-time')),
        (v) => v != null && (v - 1.5).abs() < 0.2,
        what: '下一章跳到 1.5 s',
      ),
      closeTo(1.5, 0.2),
    );
    await transport.jumpChapter(-1);
    expect(
      await _untilValue(
        () async => double.tryParse(await native.getProperty('playback-time')),
        (v) => v != null && v < 0.2,
        what: '上一章回到开头',
      ),
      lessThan(0.2),
    );
    await transport.close();
    await player.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('真实解码：编码名、精确定位、硬解、截图、音轨', () async {
    skipUnlessReady();
    if (samples == null) return;
    final player = Player();
    final transport = MpvVideoTransport(player: player);
    expect(
      await _ready(
        transport,
        samples!['mkv']!,
        options: const VideoOpenOptions(autoplay: false, deinterlace: true),
      ),
      VideoEnginePhase.ready,
    );
    final native = player.platform as NativePlayer;

    final meta = await _untilValue(
      () async => transport.metadata,
      (m) => (m.videoCodec ?? '').isNotEmpty && m.width == 160,
      what: 'video-codec 与宽解出来',
    );
    // mpv 的 `video-codec` 给的是**描述串**（`h.264 / avc / mpeg-4 avc / ...`），
    // 不是短标记 —— 信息卡那行本来就长这样，判据只能按子串认。
    expect(meta.videoCodec?.toLowerCase(), contains('264'));
    expect(meta.frameRate ?? 0, closeTo(25, 0.5));
    expect((meta.audioCodec ?? '').toLowerCase(), contains('aac'));

    // 去隔行是 open 时按设置写的，回读确认它真的落到了引擎。
    expect(
      await _untilValue(
        () => native.getProperty('deinterlace'),
        (v) => v == 'yes',
        what: 'deinterlace=yes',
      ),
      'yes',
    );
    // 硬解只能验到「请求值落到了引擎」：libmpv 里没有渲染面时 vo=null，
    // `hwdec-current` 是空的（真机上才谈得上「到底走没走 VideoToolbox」= 验收 D8）。
    // 但这一条不是废话 —— 它同时守住「设置页的硬解开关会不会被 media_kit 覆盖回 auto」。
    expect(
      await _untilValue(
        () => native.getProperty('hwdec'),
        (v) => v == (Platform.isAndroid ? 'auto-safe' : 'auto'),
        what: 'hwdec=auto 落在引擎上',
      ),
      Platform.isAndroid ? 'auto-safe' : 'auto',
    );

    // 关键流下的精确定位：3.0 s 要落在 ±150 ms（h264 默认 GOP 比 rawvideo 苛刻）。
    await transport.seek(const Duration(seconds: 3));
    expect(
      await _untilValue(
        () async => double.tryParse(await native.getProperty('playback-time')),
        (v) => v != null && (v - 3.0).abs() < 0.15,
        what: '定位到 3 s',
      ),
      closeTo(3.0, 0.15),
    );

    final dir = Directory.systemTemp.createTempSync('rossi-real-shot');
    final shot = '${dir.path}/real.png';
    expect(await transport.screenshot(shot), isNotNull);
    final bytes = File(shot).readAsBytesSync();
    expect(bytes.length, greaterThan(1024), reason: '真编码截图不该是空壳');

    final audio = await _untilValue(
      () async => transport.audioTracks.map((t) => t.id).toList(),
      (list) => list.any((i) => int.tryParse(i) != null),
      what: '音轨列表里有一条真轨',
    );
    expect(audio.length, 1, reason: '这条样本只有一条音轨：$audio');

    final drift = await transport.avDriftMs();
    expect(drift.isFinite, isTrue);

    await transport.close();
    await player.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('波形：symphonia 解真实容器里的 aac', () async {
    skipUnlessReady();
    if (samples == null) return;
    await RustLib.init();
    for (final key in <String>['mkv', if (samples!.containsKey('mp4')) 'mp4']) {
      final path = samples![key]!;
      final peaks = await localVideoWavePeaks(
        path: path,
        start: 0,
        end: 4,
        binSecs: 0.1,
      );
      expect(
        peaks.length,
        inInclusiveRange(30, 45),
        reason:
            '$key：4 s / 0.1 s 该有 40 格上下，拿到 ${peaks.length} 格。'
            '空列就意味着进度条对这个容器不会画波形',
      );
      expect(
        peaks.reduce((a, b) => a > b ? a : b),
        greaterThan(0.0),
        reason: '$key：RMS 全零？',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  /// mimage 的 `display_metadata.rs` 关心的是同一件事：**容器里写着画面要转 90°**。
  /// 这里验的是 Rossi 用户实际会看到的东西 —— `video-params` 给的是转好之后的尺寸，
  /// 所以信息卡上那行「尺寸」与画面对得上；顺带验「变速不变调」在 mpv 侧是开着的。
  test('容器转置与变速不变调：mpv 把转置折进尺寸、音高保住', () async {
    skipUnlessReady();
    final rotated = await _makeRotated();
    if (rotated == null) {
      return markTestSkipped('这个 ffmpeg 版本造不出带转置的样本');
    }
    final player = Player();
    final transport = MpvVideoTransport(player: player);
    expect(
      await _ready(transport, rotated),
      VideoEnginePhase.ready,
      reason: '转置样本解不出来：${transport.failureReason}',
    );
    final meta = await _untilValue(
      () async => transport.metadata,
      (m) => m.width > 0,
      what: 'video-params 到位',
    );
    // 判据是「画面按容器转置过来了」：mpv 的 autorotate 把转置**折进了几何**，
    // 所以 `video-params` 报的是竖过来的 120x160，而 `rotate` 反而是 0
    // （那个字段留的是额外旋转，比如 `--video-rotate`）。
    // mimage 要自己读 3x3 显示矩阵是因为它自己摆像素；Rossi 这边引擎已经做完了。
    expect(meta.width, 120, reason: '转置后宽该是 120，实际 ${meta.width}');
    expect(meta.height, 160, reason: '转置后高该是 160，实际 ${meta.height}');

    // 变速不变调（mimage `audio_stretch.rs` 的那件事）：mpv 侧的对应开关默认开着。
    final native = player.platform as NativePlayer;
    expect(
      (await native.getProperty('audio-pitch-correction')).toLowerCase(),
      contains('yes'),
      reason: '2x 播放该保住音高 —— mpv 的 audio-pitch-correction 不是 yes',
    );
    await transport.close();
    await player.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// 与 mpv 探针里同一个形状：读到满意为止，别猜时长。
Future<T> _untilValue<T>(
  Future<T> Function() read,
  bool Function(T) ok, {
  required String what,
  Duration within = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(within);
  while (true) {
    final value = await read();
    if (ok(value)) return value;
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('$what 在 ${within.inSeconds}s 内没到位（最后读到：$value）');
    }
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }
}
