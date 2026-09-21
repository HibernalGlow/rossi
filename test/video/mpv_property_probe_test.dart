/// mpv 那一层的证据，分两条腿、七探针。
///
/// **① 名字表（针对出厂引擎）**：`Mpv.framework` 里那份 mpv 才是用户机器上真正跑的，
/// 而它在 bundle 外面 dlopen 不了（依赖全是 `@rpath/...`，自己又没有 `LC_RPATH`）。
/// 所以这条不加载它 —— 直接把它的 `__cstring` 读出来，逐个核对我写进 mpv 的
/// 属性名/命令名。名字写错在 mpv 侧是**静默失败**（`set_property` 返回错误被吞掉），
/// 静态检查和出包都问不出来，只有这里问得出来。
///
/// **②～⑦ 取值与行为（针对任意可加载的 libmpv）**：`loop-file=inf` 是不是合法值、
/// `ab-loop-a` 回读长什么样、`frame-step` 走不走一帧、`screenshot-to-file` 落不落得到图、
/// 坏文件落不落得到 `failed`、`sub-add` 的字幕选不选得中、音轨与「只听声音」的往返 ——
/// 这些要活体才看得见。
/// 系统里装了 libmpv 就跑真断言，没装就 skip 并说明原因，绝不留一个永远红的测试。
/// 片源全是现场生成的（WAV / 未压缩 RGB24 的 AVI / 一段 SRT），不依赖任何外来素材。
///
/// 七条都过 = 「引擎语义」这一层能给的最好证据；它仍然不等于真机播放，
/// 画面/声音/字幕的实际观感只能在 `docs/video-playback-acceptance.md` 里靠人看。
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:zephyr/video/controller/mpv_video_transport.dart';
import 'package:zephyr/video/controller/video_transport.dart';
import 'package:zephyr/video/subtitle/video_subtitle.dart';

/// 出厂引擎的二进制：只在构建过 macOS 产物时存在。
File? _bundledMpv() {
  const relative = 'Contents/Frameworks/Mpv.framework/Versions/A/Mpv';
  final products = Directory('build/macos/Build/Products');
  if (!products.existsSync()) return null;
  for (final config in products.listSync().whereType<Directory>()) {
    for (final app in config.listSync().whereType<Directory>()) {
      if (!app.path.endsWith('.app')) continue;
      final binary = File('${app.path}/$relative');
      if (binary.existsSync()) return binary;
    }
  }
  return null;
}

/// 把 Mach-O 里的 C 字符串取出来（按 NUL 切，长度 ≥2 的都算）。
/// 不用 `strings`：那是外部工具，测试要能在任何开发机上自己跑。
Set<String> _cStrings(File binary) {
  final bytes = binary.readAsBytesSync();
  final out = <String>{};
  var start = 0;
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] != 0) continue;
    if (i - start >= 2) {
      var ascii = true;
      for (var j = start; j < i; j++) {
        final c = bytes[j];
        if (c < 0x20 || c > 0x7e) {
          ascii = false;
          break;
        }
      }
      if (ascii) out.add(String.fromCharCodes(bytes.sublist(start, i)));
    }
    start = i + 1;
  }
  return out;
}

/// 从传输层源码里把「我打算写给 mpv 的名字」抠出来。
///
/// 从源码取而不是在测试里抄一份名单：抄的那份会随时间失真，而失真成一个
/// **通过**的测试比失真成一个失败的测试糟得多。
List<String> _mpvNamesInUse() {
  final source = File('lib/video/controller/mpv_video_transport.dart');
  if (!source.existsSync()) return const [];
  final text = source.readAsStringSync();
  final names = <String>{};
  // `static const loopFile = 'loop-file';`
  for (final m in RegExp(
    r"static const \w+ = '([a-z][a-z0-9-]+)';",
  ).allMatches(text)) {
    names.add(m.group(1)!);
  }
  // `_get('chapter-list')`
  for (final m in RegExp(r"_get\('([a-z][a-z0-9-]+)'\)").allMatches(text)) {
    names.add(m.group(1)!);
  }
  // `_cmd(<String>['screenshot-to-file', path, 'video'])` —— 只有首位是命令名。
  for (final m in RegExp(
    r"_cmd\(<String>\[\s*'([a-z][a-z0-9-]+)'",
  ).allMatches(text)) {
    names.add(m.group(1)!);
  }
  return names.toList()..sort();
}

/// 2 秒 220 Hz 正弦，前半响后半轻（与 Rust 侧那个测试同一份形状）。
String _writeWav() {
  const rate = 44100;
  const seconds = 2.0;
  final frames = (seconds * rate).round();
  final data = Uint8List(frames * 2);
  for (var i = 0; i < frames; i++) {
    final t = i / rate;
    final amp = t < seconds / 2 ? 0.6 : 0.05;
    final sample = (amp * _sin(2 * 3.141592653589793 * 220 * t) * 32767)
        .toInt();
    final bytes = Int16List.fromList(<int>[sample]).buffer.asByteData();
    data[i * 2] = bytes.getUint8(0);
    data[i * 2 + 1] = bytes.getUint8(1);
  }
  final out = BytesBuilder();
  void u32(int v) =>
      out.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
  void u16(int v) =>
      out.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));
  out.add('RIFF'.codeUnits);
  u32(36 + data.length);
  out.add('WAVEfmt '.codeUnits);
  u32(16);
  u16(1);
  u16(1);
  u32(rate);
  u32(rate * 2);
  u16(2);
  u16(16);
  out.add('data'.codeUnits);
  u32(data.length);
  out.add(data);
  final dir = Directory.systemTemp.createTempSync('rossi-mpv-probe');
  final file = '${dir.path}/probe.wav';
  File(file).writeAsBytesSync(out.takeBytes());
  return file;
}

/// 只用到一次，避免为了一个 sin 引 dart:math 之外的东西。
double _sin(double x) {
  // 归一到 [-pi, pi] 后用泰勒展开，精度对这个用途足够。
  const pi = 3.141592653589793;
  var v = x;
  while (v > pi) {
    v -= 2 * pi;
  }
  while (v < -pi) {
    v += 2 * pi;
  }
  final v2 = v * v;
  var term = v;
  var sum = v;
  for (var n = 1; n <= 8; n++) {
    term = -term * v2 / ((2 * n) * (2 * n + 1));
    sum += term;
  }
  return sum;
}

/// 找一个能 dlopen 的 libmpv，返回它的路径；找不到返回 null。
///
/// 显式把路径交给 `MediaKit.ensureInitialized(libmpv:)`，而不是靠
/// `LIBMPV_LIBRARY_PATH` 环境变量：那个变量在 `flutter test` 起的测试 VM 里读不到
/// （实测设置后 `Platform.environment` 为空），而 media_kit 在 macOS 上会把这个
/// 参数原样转发给 `NativeLibrary`，所以传参是这条路上唯一稳的口子。
String? _loadableLibmpv() {
  final env = Platform.environment['LIBMPV_LIBRARY_PATH'];
  final candidates = <String>[
    if (env != null && env.isNotEmpty) env,
    ...switch (Platform.operatingSystem) {
      'macos' => const [
        '/opt/homebrew/opt/mpv/lib/libmpv.2.dylib',
        '/opt/homebrew/lib/libmpv.2.dylib',
        '/usr/local/lib/libmpv.2.dylib',
      ],
      'linux' => const [
        '/usr/lib/x86_64-linux-gnu/libmpv.so.2',
        '/usr/lib/libmpv.so.2',
      ],
      'windows' => const ['libmpv-2.dll'],
      _ => const <String>[],
    },
  ];
  for (final path in candidates) {
    try {
      DynamicLibrary.open(path);
      return path;
    } catch (_) {
      // 换下一个候选：这里没有需要保留的失败信息，skip 时会把候选列表报出来。
    }
  }
  return null;
}

void _le(BytesBuilder o, int v, int bytes) {
  for (var i = 0; i < bytes; i++) {
    o.addByte((v >> (8 * i)) & 0xff);
  }
}

void _four(BytesBuilder o, String s) {
  assert(s.codeUnits.length == 4);
  o.add(s.codeUnits);
}

/// 一帧未压缩 RGB24，行倒序（正高度 DIB 的约定）。
Uint8List _frame(int width, int height, int index) {
  final px = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final o = ((height - 1 - y) * width + x) * 3;
      px[o] = (x * 4 + index * 8) & 0xff;
      px[o + 1] = (y * 4) & 0xff;
      px[o + 2] = 0x80;
    }
  }
  return px;
}

/// 一帧的 PCM s16le 音频块（单声道，40 ms）。
Uint8List _s16Block(int samples, int index) {
  final out = Uint8List(samples * 2);
  final bd = ByteData.sublistView(out);
  for (var i = 0; i < samples; i++) {
    // 不加 dart:math：一个三角波就够让解码器有事做。
    final v = (((index * 8 + i) % 32) - 16) * 800;
    bd.setInt16(i * 2, v, Endian.little);
  }
  return out;
}

/// 未压缩 AVI：hdrl / movi / idx1 三段，视频是 RGB24，音频是 PCM s16le。
///
/// 带一条音轨是为了让「音轨面板、`aid` 选择、`avsync`、`audio-codec-name`」
/// 这些**要有两条轨才看得见**的路径也能活体验证 —— 纯 WAV 探不到它们。
String _writeAvi({
  int width = 64,
  int height = 48,
  int frames = 25,
  bool withAudio = true,
  int sampleRate = 8000,
}) {
  const fps = 25;
  final frameBytes = width * height * 3;
  final blockSamples = sampleRate ~/ fps;
  final blockBytes = blockSamples * 2;

  final movi = BytesBuilder();
  final index = BytesBuilder();
  for (var i = 0; i < frames; i++) {
    final chunkStart = movi.length;
    _four(movi, '00dc');
    _le(movi, frameBytes, 4);
    movi.add(_frame(width, height, i));
    _four(index, '00dc');
    _le(index, 0x02, 4); // AVIIF_KEYFRAME
    _le(index, chunkStart + 4, 4); // 相对 movi LIST 的内容起点
    _le(index, frameBytes, 4);
    if (!withAudio) continue;
    final audioStart = movi.length;
    _four(movi, '01wb');
    _le(movi, blockBytes, 4);
    movi.add(_s16Block(blockSamples, i));
    _four(index, '01wb');
    _le(index, 0x10, 4); // AVIIF_NO_KEYFRAME
    _le(index, audioStart + 4, 4);
    _le(index, blockBytes, 4);
  }
  final moviBytes = movi.takeBytes();
  final indexBytes = index.takeBytes();

  final hdrl = BytesBuilder();
  final avih = BytesBuilder();
  _le(avih, 1000000 ~/ fps, 4); // dwMicroSecPerFrame
  _le(
    avih,
    (frameBytes + (withAudio ? blockBytes : 0)) * fps,
    4,
  ); // dwMaxBytesPerSec
  _le(avih, 0, 4); // dwPaddingGranularity
  _le(avih, 0x10 | 0x20, 4); // HAS_INDEX | IS_INTERLEAVED
  _le(avih, 0, 4); // dwTruncatedFrames
  _le(avih, 0, 4); // dwInitialFrames
  _le(avih, withAudio ? 2 : 1, 4); // dwStreams
  _le(avih, frameBytes, 4); // dwSuggestedBufferSize
  _le(avih, width, 4);
  _le(avih, height, 4);
  for (var i = 0; i < 4; i++) {
    _le(avih, 0, 4); // dwReserved
  }
  final avihBytes = avih.takeBytes();
  _four(hdrl, 'avih');
  _le(hdrl, avihBytes.length, 4);
  hdrl.add(avihBytes);

  final strh = BytesBuilder();
  _four(strh, 'vids');
  _four(strh, 'DIB ');
  _le(strh, 0, 4); // dwFlags
  _le(strh, 0, 2); // wPriority
  _le(strh, 0, 2); // wLanguage
  _le(strh, 0, 4); // dwInitialFrames
  _le(strh, 1, 4); // dwScale
  _le(strh, fps, 4); // dwRate  → fps = rate / scale
  _le(strh, 0, 4); // dwStart
  _le(strh, frames, 4); // dwLength
  _le(strh, frameBytes, 4); // dwSuggestedBufferSize
  _le(strh, 0xFFFFFFFF, 4); // dwQuality
  _le(strh, frameBytes, 4); // dwSampleSize
  _le(strh, 0, 4); // rcFrame left
  _le(strh, 0, 4); // rcFrame top
  _le(strh, width, 4); // rcFrame right
  _le(strh, height, 4); // rcFrame bottom
  final strhBytes = strh.takeBytes();

  final strf = BytesBuilder();
  _le(strf, 40, 4); // biSize
  _le(strf, width, 4);
  _le(strf, height, 4); // 正值 = 自下而上
  _le(strf, 1, 2); // biPlanes
  _le(strf, 24, 2); // biBitCount
  _le(strf, 0, 4); // biCompression = BI_RGB
  _le(strf, frameBytes, 4);
  _le(strf, 2835, 4); // 72 dpi
  _le(strf, 2835, 4);
  _le(strf, 0, 4);
  _le(strf, 0, 4);
  final strfBytes = strf.takeBytes();

  final strl = BytesBuilder();
  _four(strl, 'strh');
  _le(strl, strhBytes.length, 4);
  strl.add(strhBytes);
  _four(strl, 'strf');
  _le(strl, strfBytes.length, 4);
  strl.add(strfBytes);
  final strlBytes = strl.takeBytes();

  _four(hdrl, 'LIST');
  _le(hdrl, 4 + strlBytes.length, 4);
  _four(hdrl, 'strl');
  hdrl.add(strlBytes);

  if (withAudio) {
    final astrh = BytesBuilder();
    _four(astrh, 'auds'); // 音频流的 fccType 是 'auds'（写成 'audi' 会被认成未知流）
    _four(astrh, 'PCM ');
    _le(astrh, 0, 4); // dwFlags
    _le(astrh, 0, 2); // wPriority
    _le(astrh, 0, 2); // wLanguage
    _le(astrh, 0, 4); // dwInitialFrames
    _le(astrh, 2, 4); // dwScale = block align（字节/块）
    _le(astrh, sampleRate * 2, 4); // dwRate = 每秒字节数
    _le(astrh, 0, 4); // dwStart
    _le(astrh, frames * blockSamples, 4); // dwLength = 样本数
    _le(astrh, blockBytes, 4); // dwSuggestedBufferSize
    _le(astrh, 0xFFFFFFFF, 4); // dwQuality
    _le(astrh, 2, 4); // dwSampleSize = block align（ffmpeg 用它算样本数，填块大小会告警）
    for (var i = 0; i < 4; i++) {
      _le(astrh, 0, 4); // rcFrame（音频不用）
    }
    final astrhBytes = astrh.takeBytes();

    // strf = 18 字节 PCMWAVEFORMAT（真实工具写出来的 AVI 就是这个形状）。
    final afmt = BytesBuilder();
    _le(afmt, 1, 2); // wFormatTag = PCM
    _le(afmt, 1, 2); // nChannels
    _le(afmt, sampleRate, 4); // nSamplesPerSec
    _le(afmt, sampleRate * 2, 4); // nAvgBytesPerSec
    _le(afmt, 2, 2); // nBlockAlign
    _le(afmt, 16, 2); // wBitsPerSample
    _le(afmt, 0, 2); // cbSize
    final afmtBytes = afmt.takeBytes();

    final astrl = BytesBuilder();
    _four(astrl, 'strh');
    _le(astrl, astrhBytes.length, 4);
    astrl.add(astrhBytes);
    _four(astrl, 'strf');
    _le(astrl, afmtBytes.length, 4);
    astrl.add(afmtBytes);
    final astrlBytes = astrl.takeBytes();

    _four(hdrl, 'LIST');
    _le(hdrl, 4 + astrlBytes.length, 4);
    _four(hdrl, 'strl');
    hdrl.add(astrlBytes);
  }
  final hdrlBytes = hdrl.takeBytes();

  final body = BytesBuilder();
  _four(body, 'LIST');
  _le(body, 4 + hdrlBytes.length, 4);
  _four(body, 'hdrl');
  body.add(hdrlBytes);
  _four(body, 'LIST');
  _le(body, 4 + moviBytes.length, 4);
  _four(body, 'movi');
  body.add(moviBytes);
  _four(body, 'idx1');
  _le(body, indexBytes.length, 4);
  body.add(indexBytes);
  final bodyBytes = body.takeBytes();

  final file = BytesBuilder();
  _four(file, 'RIFF');
  _le(file, 4 + bodyBytes.length, 4);
  _four(file, 'AVI ');
  file.add(bodyBytes);

  final dir = Directory.systemTemp.createTempSync('rossi-avi');
  final path = '${dir.path}/probe.avi';
  File(path).writeAsBytesSync(file.takeBytes());
  return path;
}

/// 轮询到某个异步值满足条件为止（默认 12 s）。
///
/// 这套探针原先靠 `delay(120ms/400ms)` 猜 mpv 什么时候把值落下去，在同一台机器上
/// 和别的 mpv 实例抢 CPU 时会随机输 —— 一条时好时坏的探针比没有探针更糟。
/// 现在一律「读到满意为止」，超时就把最后一次读到的值报出来。
Future<T> _until<T>(
  Future<T> Function() read,
  bool Function(T) ok, {
  required String what,
  Duration within = const Duration(seconds: 12),
}) async {
  final deadline = DateTime.now().add(within);
  while (true) {
    final value = await read();
    if (ok(value)) return value;
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('$what 在 ${within.inSeconds}s 内没到位（最后一次读到：$value）');
    }
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }
}

/// 打开并等到「有结论」为止。
///
/// 这里**只等一次结论，不自己重试**：卡住时原地重开是传输层的职责
/// （`MpvVideoTransport._awaitFirstFrame` 的 allowRetry —— 同进程已经起过别的
/// mpv 实例时，第一次 load 偶尔什么都不上报，实测 5 次撞 2 次，第二次立刻成功）。
/// 超时给到 50 s > 内层的两次 20 s：内层那道重试要是失效了，这条就该红。
Future<VideoEnginePhase> _openAndAwait(
  MpvVideoTransport transport,
  String uri, {
  VideoOpenOptions options = const VideoOpenOptions(autoplay: false),
}) async {
  final seen = transport.phaseStream.firstWhere(
    (p) => p == VideoEnginePhase.ready || p == VideoEnginePhase.failed,
  );
  await transport.open(uri, options: options);
  return seen.timeout(const Duration(seconds: 50));
}

void main() {
  test('默认视频样式保持原色，字幕颜色和透明度被 mpv 接受', () async {
    final lib = _loadableLibmpv();
    if (lib == null) {
      markTestSkipped('系统里没有可加载的 libmpv');
      return;
    }
    MediaKit.ensureInitialized(libmpv: lib);
    final player = Player();
    final transport = MpvVideoTransport(player: player);
    final errors = <String>[];
    final phases = <VideoEnginePhase>[];
    final errorSub = player.stream.error.listen(errors.add);
    final phaseSub = transport.phaseStream.listen(phases.add);
    final media = File(_writeWav());
    final native = player.platform as NativePlayer;
    Future<void> expectProperty(String key, String expected) async {
      expect(
        await _until(
          () async => (await native.getProperty(key)).toLowerCase(),
          (value) => value == expected,
          what: '$key=$expected',
        ),
        expected,
      );
    }

    try {
      expect(
        await _openAndAwait(transport, media.path),
        VideoEnginePhase.ready,
      );
      await transport.setFilter(VideoFilterState.neutral);
      for (final key in ['brightness', 'contrast', 'saturation']) {
        expect(double.parse(await native.getProperty(key)), 0);
      }
      await transport.setSubtitleStyle(const VideoSubtitleStyle());
      await expectProperty('sub-color', '#ffffffff');
      await expectProperty('sub-back-color', '#b3000000');
      expect(double.parse(await native.getProperty('sub-pos')), 95);

      await transport.setSubtitleStyle(
        const VideoSubtitleStyle(
          colorHex: '#12a4f0',
          backgroundOpacityPercent: 0,
        ),
      );
      await expectProperty('sub-color', '#ff12a4f0');
      await expectProperty('sub-back-color', '#00000000');
      await transport.setSubtitleStyle(
        const VideoSubtitleStyle(
          colorHex: 'invalid',
          backgroundOpacityPercent: 100,
        ),
      );
      await expectProperty('sub-color', '#ffffffff');
      await expectProperty('sub-back-color', '#ff000000');
      // 错误来自异步日志流，等事件送达后再确认不会把画面切到失败页。
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(errors, isEmpty);
      expect(phases, isNot(contains(VideoEnginePhase.failed)));
    } finally {
      await errorSub.cancel();
      await phaseSub.cancel();
      await transport.close();
      await transport.close(); // 幂等关闭；借用的 Player 仍由调用方释放。
      expect((player.platform as NativePlayer).disposed, isFalse);
      await player.dispose();
      await media.parent.delete(recursive: true);
    }
  });

  test('出厂那台 mpv 认得我写的每一个名字', () {
    final names = _mpvNamesInUse();
    // 名单本身为空 = 源码解析失效，这时候"全过"是假的通过。
    expect(names, isNotEmpty, reason: '没解析出任何 mpv 名字，正则失配了');
    expect(names, contains('loop-file'), reason: '解析结果不像话');

    final mpv = _bundledMpv();
    if (mpv == null) {
      markTestSkipped('没有 macOS 产物（先 flutter build macos --debug 再跑）');
      return;
    }
    final strings = _cStrings(mpv);
    final unknown = names.where((n) => !strings.contains(n)).toList();
    expect(
      unknown,
      isEmpty,
      reason: '这些名字在 ${mpv.path} 里没有，mpv 会静默拒绝：$unknown',
    );
  });

  test('mpv 属性逐项生效（引擎语义的主干）', () async {
    final lib = _loadableLibmpv();
    if (lib == null) {
      markTestSkipped('系统里没有可加载的 libmpv（brew install mpv 即可跑真断言）');
      return;
    }
    late final Player player;
    try {
      MediaKit.ensureInitialized(libmpv: lib);
      player = Player();
    } catch (e) {
      markTestSkipped('libmpv 加载不了（$lib）：$e');
      return;
    }
    final transport = MpvVideoTransport(player: player);
    var loaded = false;
    try {
      // 先挂订阅再 open：phaseStream 是广播流，open 里推进的相位可能在这行之前就发完了。
      final phaseSeen = transport.phaseStream.firstWhere(
        (p) => p == VideoEnginePhase.ready || p == VideoEnginePhase.failed,
      );
      await transport
          .open(
            'file://${_writeWav()}',
            options: const VideoOpenOptions(autoplay: false),
          )
          .timeout(const Duration(seconds: 20));
      await phaseSeen.timeout(const Duration(seconds: 20));
      loaded = player.state.duration > Duration.zero;
    } on TimeoutException {
      // 落下面 skip。
    }
    if (!loaded) {
      await transport.close();
      await player.dispose();
      markTestSkipped('没有打开成功（时长仍为 0）：多半是 native 库不可用');
      return;
    }

    Future<String> property(String key) async {
      final platform = player.platform;
      if (platform is! NativePlayer) return '';
      return platform.getProperty(key);
    }

    expect(player.state.duration > Duration.zero, isTrue, reason: '时长要解得出来');

    // 每个属性都「读到满意为止」：mpv 落值是异步的，猜时长会在同机有多个
    // 实例抢 CPU 时随机输（这条套件以前就因此时绿时红）。
    await transport.setRate(1.75);
    expect(
      await _until(
        () async => player.state.rate,
        (v) => (v - 1.75).abs() < 0.01,
        what: 'speed=1.75 生效',
      ),
      closeTo(1.75, 0.01),
    );

    await transport.setVolume(40);
    expect(
      await _until(
        () async => player.state.volume,
        (v) => (v - 40).abs() <= 0.5,
        what: 'volume=40 生效',
      ),
      closeTo(40, 0.5),
    );

    await transport.setMuted(true);
    expect(
      await _until(
        () => property('mute'),
        (v) => v.contains('yes'),
        what: 'mute=yes 生效',
      ),
      contains('yes'),
    );

    await transport.setLoopFile(true);
    expect(
      await _until(
        () => property('loop-file'),
        (v) => v == 'inf',
        what: 'mimage 的单条循环档 loop-file=inf',
      ),
      'inf',
    );

    await transport.setAbLoop(
      const VideoAbLoop(a: Duration(seconds: 1), b: Duration(seconds: 2)),
    );
    // mpv 对 double 属性按 `%f` 回读（写 '12' 回 '12.000000'），且 `ab-loop-*`
    // 未设时回 'no' —— 所以这里一律解析成数值比，别比字符串。
    expect(
      await _until(
        () async => double.tryParse(await property('ab-loop-a')),
        (v) => v != null && (v - 1).abs() <= 0.05,
        what: 'A 点写进去了',
      ),
      closeTo(1, 0.05),
    );
    expect(
      await _until(
        () async => double.tryParse(await property('ab-loop-b')),
        (v) => v != null && (v - 2).abs() <= 0.05,
        what: 'B 点写进去了',
      ),
      closeTo(2, 0.05),
    );
    await transport.setAbLoop(null);
    expect(
      await _until(
        () => property('ab-loop-a'),
        (v) => v == 'no',
        what: 'A-B 清掉之后回 no',
      ),
      'no',
    );

    await transport.setFilter(
      const VideoFilterState(brightness: 150, contrast: 100, saturation: 60),
    );
    // UI 的 100% 对应 mpv 的 0，降低饱和度必须落到负值。
    expect(
      await _until(
        () async => double.tryParse(await property('brightness')),
        (v) => v != null && (v - 50).abs() <= 1.0,
        what: 'brightness 150% 对应 +50',
      ),
      closeTo(50, 1.0),
    );
    expect(
      await _until(
        () async => double.tryParse(await property('saturation')),
        (v) => v != null && (v + 40).abs() <= 1.0,
        what: 'saturation 60% 对应 -40',
      ),
      closeTo(-40, 1.0),
    );

    await transport.setSubtitleStyle(
      const VideoSubtitleStyle(sizeEm: 1.6, bottomPercent: 12),
    );
    expect(
      await _until(
        () async => double.tryParse(await property('sub-scale')),
        (v) => v != null && (v - 1.6).abs() <= 0.01,
        what: 'sub-scale 生效',
      ),
      closeTo(1.6, 0.01),
    );
    expect(
      await _until(
        () async => double.tryParse(await property('sub-pos')),
        (v) => v != null && (v - 88).abs() <= 0.01,
        what: '字幕离底部 12% 对应 sub-pos=88',
      ),
      closeTo(88, 0.01),
    );

    await transport.setVideoEnabled(false);
    expect(
      await _until(
        () => property('video'),
        (v) => v == 'no',
        what: '只听声音模式该把画面关掉',
      ),
      'no',
    );

    final drift = await transport.avDriftMs();
    expect(drift.isFinite, isTrue);

    await transport.seek(const Duration(milliseconds: 500));
    // 问 mpv 自己要时间：暂停态里 media_kit 的 position 流是不发的
    // （控制器靠乐观回填让标签跟着走，见 `seekRelative` 那段）。
    await _until(
      () async => double.tryParse(await property('playback-time')),
      (v) => v != null && (v - 0.5).abs() < 0.12,
      what: 'mpv 侧定位落到 500 ms 附近',
    );
    expect(transport.isPlaying, isFalse, reason: '暂停态定位不该顺手开播');

    await transport.close();
    await player.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  /// 视频侧的三条：元数据、逐帧、截图落盘。
  ///
  /// WAV 只能证声音，所以这里手写一个未压缩 RGB24 的 AVI（231 KB）当片源 ——
  /// mpv 认它（`rawvideo 64x48 25 fps`），于是 `container-fps`/`video-params`、
  /// `frame-step` 是不是真的走一帧、`screenshot-to-file` 落不落得到图，
  /// 全都能在不开 App 的情况下拿到凭据。
  ///
  /// 需要 `NativePlayer.test = true`：media_kit 起来就带 `--vid=no`，只有
  /// `VideoController` 附着时才改回 auto，而测试里没有 platform view。
  /// 顺带说，这同一个默认值也是海报那条路的坑（那里根本没有渲染面），
  /// 已在 `VideoPosterService._captureBytes` 里显式 `vid=auto` 补上。
  test('视频侧语义：元数据、逐帧、截图', () async {
    final lib = _loadableLibmpv();
    if (lib == null) {
      markTestSkipped('系统里没有可加载的 libmpv（brew install mpv）');
      return;
    }
    MediaKit.ensureInitialized(libmpv: lib);
    NativePlayer.test = true;
    final path = _writeAvi();
    final player = Player();
    final transport = MpvVideoTransport(player: player);
    expect(
      await _openAndAwait(transport, 'file://$path'),
      VideoEnginePhase.ready,
      reason: '合成 AVI 该解得出来',
    );

    // 信息表那三列全靠这些：宽高、帧率、编码名。
    final meta = await _until(
      () async => transport.metadata,
      (m) => m.width == 64 && m.height == 48 && m.frameRate != null,
      what: 'metadata 解出宽高与帧率',
    );
    expect(meta.frameRate ?? 0, closeTo(25, 0.5));
    expect(meta.videoCodec ?? '', contains('raw'));
    expect(
      player.state.duration.inMilliseconds,
      inInclusiveRange(900, 1100),
      reason: '25 帧 @25fps 该是 1 s 上下，实际 ${player.state.duration}',
    );

    // 逐帧：25 fps 走一帧就是 40 ms，而且期间必须还是暂停。
    await player.pause();
    final before = player.state.position;
    await transport.stepFrame(1);
    // 等位置真的动，别猜 400 ms：同机多个 mpv 实例抢 CPU 时固定时长会随机输。
    final stepped = await _until(
      () async => player.state.position,
      (d) => d != before,
      what: 'frame-step 该推进位置',
    );
    final advanced = stepped - before;
    expect(
      advanced.inMilliseconds,
      inInclusiveRange(20, 120),
      reason: '一帧该是 40 ms 上下，实际走了 $advanced',
    );
    expect(transport.isPlaying, isFalse, reason: '逐帧期间必须还是暂停');

    // 回退一帧：`frame-back-step` 是 mimage 与 neo 都有的「上一帧」，
    // 走的是另一条命令，不能靠正着走的那条推定它成立。
    await transport.stepFrame(-1);
    final back = await _until(
      () async => player.state.position,
      (d) => d.inMilliseconds < 20,
      what: '退一帧该回到起点附近',
    );
    expect(back.inMilliseconds, lessThan(20));

    // 截图：mpv 的 screenshot-to-file 真的落一个图像文件（海报/预览帧同源）。
    final dir = Directory.systemTemp.createTempSync('rossi-shot');
    final shot = '${dir.path}/probe-shot.png';
    expect(await transport.screenshot(shot), isNotNull, reason: '该返回落盘路径');
    final bytes = File(shot).readAsBytesSync();
    expect(bytes, isNotEmpty);
    // PNG(89 50 4E 47) 或 JPEG(FF D8 FF)：扩展名是我给的，实际格式由 mpv 决定。
    final isPng = bytes[0] == 0x89 && bytes[1] == 0x50;
    final isJpeg = bytes[0] == 0xff && bytes[1] == 0xd8;
    expect(isPng || isJpeg, isTrue, reason: '落盘的不是图像文件');

    await transport.close();
    await player.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  /// 打不开的文件必须落到 `failed`。
  ///
  /// 这是「视频整条功能都是装饰，绝不该让一页读不下去」那句承诺的兑现点：
  /// 相位停在 `prerolling` 的话，页面上就是一个永远转不完的圈（曾经就是这样，
  /// 因为 media_kit 的 error 是广播流，晚一帧订阅就再也收不到）。
  test('打不开的文件要落到 failed，不许卡在 prerolling', () async {
    final lib = _loadableLibmpv();
    if (lib == null) {
      markTestSkipped('系统里没有可加载的 libmpv（brew install mpv）');
      return;
    }
    MediaKit.ensureInitialized(libmpv: lib);
    final player = Player();
    final transport = MpvVideoTransport(player: player);
    final phaseSeen = transport.phaseStream.firstWhere(
      (p) => p == VideoEnginePhase.ready || p == VideoEnginePhase.failed,
    );
    final dir = Directory.systemTemp.createTempSync('rossi-missing');
    await transport.open('file://${dir.path}/not-here.mp4');
    final phase = await phaseSeen.timeout(const Duration(seconds: 15));
    expect(phase, VideoEnginePhase.failed);
    expect(
      transport.failureReason,
      isNotNull,
      reason: 'failed 得带得上面的话，页面才有的可显示',
    );
    await transport.close();
    await player.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  /// 海报那条路的机制：没有渲染面时，显式 `vid=auto` 就足够让画面解出来。
  ///
  /// `VideoPosterService` 用的是裸 `Player()`（页面树里没有 `Video` 组件），
  /// 而 media_kit 给裸 Player 的默认是 `--vid=no` ⇒ 不显式打开视频轨的话，
  /// 它等 `videoParams` 一定超时、截图一定 null，表现为「视频卡片从来没有封面」。
  /// 这条不测海报函数本身（那要 mock path_provider），只测它依赖的那一句是否成立。
  test('裸 Player 显式 vid=auto 后能解出画面并截图', () async {
    final lib = _loadableLibmpv();
    if (lib == null) {
      markTestSkipped('系统里没有可加载的 libmpv（brew install mpv）');
      return;
    }
    MediaKit.ensureInitialized(libmpv: lib);
    // 上面的测试为了自己能用而开了这个静态开关；这里必须关掉，
    // 否则「裸 Player 默认 vid=no」这个前提就不成立了。
    NativePlayer.test = false;
    final player = Player();
    final native = player.platform;
    if (native is! NativePlayer) {
      await player.dispose();
      markTestSkipped('不是 NativePlayer，测不到 vid 这一层');
      return;
    }
    final path = _writeAvi();
    final paramsSeen = player.stream.videoParams
        .firstWhere((v) => (v.w ?? 0) > 0)
        .timeout(const Duration(seconds: 8));
    await native.setProperty('vid', 'auto');
    await player.open(Media('file://$path'), play: false);
    await paramsSeen;
    final shot = await player.screenshot();
    expect(shot, isNotNull, reason: '海报取的就是这个字节串');
    expect(shot!, isNotEmpty);
    await player.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  /// 外挂字幕这条链的活体一半：`sub-add` 之后轨列表里有它、认得出是外挂、能选中。
  ///
  /// 侧挂字幕是两个上游共有的一条主功能。Rossi 侧的名字匹配与 SRT/ASS/MicroDVD
  /// 转换在纯逻辑测试里已经钉过，剩下「mpv 收不收、tracks 流里长什么样、按号选选不选得中」
  /// 只有活体能答 —— 而最后这半恰好抓到过一次真错（见 `selectSubtitleTrack` 的轨号判别）。
  test('外挂字幕：sub-add 之后能进轨列表并被选中', () async {
    final lib = _loadableLibmpv();
    if (lib == null) {
      markTestSkipped('系统里没有可加载的 libmpv（brew install mpv）');
      return;
    }
    MediaKit.ensureInitialized(libmpv: lib);
    NativePlayer.test = true;
    final player = Player();
    final transport = MpvVideoTransport(player: player);
    expect(
      await _openAndAwait(transport, 'file://${_writeAvi()}'),
      VideoEnginePhase.ready,
      reason: '合成 AVI 没解出来：${transport.failureReason}',
    );

    final dir = Directory.systemTemp.createTempSync('rossi-sub');
    final srt = '${dir.path}/probe.srt';
    File(srt).writeAsStringSync('1\n00:00:00,500 --> 00:00:01,000\nrossi\n\n');
    await transport.addSubtitleFile(srt);
    // 先问 mpv 自己收没收下（`_cmd` 是吞异常的，光看 transport 那边分不出来），
    // 再等 media_kit 的 tracks 流把这条轨送到 `subtitleTracks`。
    final native = player.platform as NativePlayer;
    final list = await native.getProperty('track-list');
    // mpv 的轨道类型串是 `sub`，不是 `subtitle`（这条断言第一次就写错了）。
    expect(list, contains('"type":"sub"'), reason: 'mpv 就没收下这个字幕文件');
    final ids = await _until(
      () async => transport.subtitleTracks.map((t) => t.id).toList(),
      (list) => list.any((i) => int.tryParse(i) != null),
      what: 'sub-add 之后该有一条数字轨号的字幕轨',
    );
    // media_kit 的轨表里混着它自己造的伪轨（auto / no）：列给用户看就是两条点不动的假轨。
    expect(ids, isNot(contains('auto')), reason: '伪轨不该出现在轨列表：$ids');
    expect(ids, isNot(contains('no')), reason: '伪轨不该出现在轨列表：$ids');
    final sidecar = transport.subtitleTracks
        .where((t) => int.tryParse(t.id) != null)
        .toList(growable: false);
    expect(sidecar, isNotEmpty, reason: 'sub-add 之后该有一条数字轨号的字幕轨：$ids');

    // 选择状态要问 mpv：media_kit 的 state.track 只记**它自己**最后一次设的值
    // （刚 sub-add 完时它还是 auto），而面板上「哪条是选中的」看的是 mpv 那边。
    Future<String> sid() async => native.getProperty('sid');
    expect(
      await sid(),
      anyOf('auto', sidecar.first.id),
      reason: '只有一条外挂字幕时 mpv 该自动选中它，实际 sid=${await sid()}',
    );

    // 关掉再选回来：数字轨号必须按号选 —— 走 URI 分支的话 mpv 会去开一个叫 "1" 的文件。
    await transport.selectSubtitleTrack(null);
    expect(await _until(sid, (v) => v == 'no', what: '关闭字幕该回到 sid=no'), 'no');
    await transport.selectSubtitleTrack(sidecar.first.id);
    expect(
      await _until(sid, (v) => v == sidecar.first.id, what: '数字轨号的外挂字幕要按号选中'),
      sidecar.first.id,
    );

    // MicroDVD `.sub`：mpv 对它的解码不可靠，所以 Rossi 侧先转成 WebVTT 再挂
    // （`convertSubtitleFileForEngine`）。转出来的东西 mpv 认不认，只有活体能答。
    final sub = '${dir.path}/probe.sub';
    File(sub).writeAsStringSync('{0}{100}第一句|换行\\n{120}{200}第二句\\n');
    final converted = await convertSubtitleFileForEngine(sub, format: 'sub');
    expect(converted, isNotNull, reason: '.sub 该被转成临时 .vtt');
    expect(
      File(converted!).readAsStringSync(),
      startsWith('WEBVTT'),
      reason: '转出来的得是合法 WebVTT 头',
    );
    await transport.addSubtitleFile(converted);
    final subs2 = await _until(
      () async => transport.subtitleTracks.map((e) => e.id).toList(),
      (list) => list.where((i) => int.tryParse(i) != null).length >= 2,
      what: '转换后的 .vtt 该成为第二条字幕轨',
    );
    final vttId = subs2.firstWhere(
      (i) => int.tryParse(i) != null && i != sidecar.first.id,
    );
    await transport.selectSubtitleTrack(vttId);
    expect(
      await _until(sid, (v) => v == vttId, what: '转换出来的 WebVTT 要选得中'),
      vttId,
    );

    await transport.close();
    await player.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  /// 要有**两条轨**才看得见的那半：音轨面板、`aid` 选择、音画漂移、码率。
  ///
  /// 合成的 AVI 现在带一条 PCM s16le（8 kHz 单声道，与视频帧按 40 ms 对齐交错），
  /// mpv 报 `Audio --aid=1 (pcm_s16le 1ch 8000 Hz 128 kbps)`。
  /// 音轨面板与「只听声音」是 mimage 与 neo 都有的功能，此前只验过代码存在。
  test('音轨与同步：PCM 轨进得了列表也选得中', () async {
    final lib = _loadableLibmpv();
    if (lib == null) {
      markTestSkipped('系统里没有可加载的 libmpv（brew install mpv）');
      return;
    }
    MediaKit.ensureInitialized(libmpv: lib);
    NativePlayer.test = true;
    final player = Player();
    final transport = MpvVideoTransport(player: player);
    expect(
      await _openAndAwait(transport, 'file://${_writeAvi()}'),
      VideoEnginePhase.ready,
    );
    final native = player.platform as NativePlayer;

    // 音频编解码名要进信息卡（`audio-codec-name`）。
    final ameta = await _until(
      () async => transport.metadata,
      (m) => (m.audioCodec ?? '').contains('pcm'),
      what: 'audio-codec-name 解出 pcm',
    );
    expect(ameta.audioCodec ?? '', contains('pcm'));

    // 音轨列表：media_kit 的 auto/no 伪轨不能混进来。
    final audioIds = await _until(
      () async => transport.audioTracks.map((t) => t.id).toList(),
      (list) => list.any((i) => int.tryParse(i) != null),
      what: '音轨列表里该有一条真轨',
    );
    expect(
      audioIds,
      isNot(anyOf(contains('auto'), contains('no'))),
      reason: '伪轨混进音轨面板：$audioIds',
    );
    expect(audioIds.length, 1, reason: '这条合成源只有一条音轨：$audioIds');

    // 关掉再选回：走 aid 属性，面板上的选中态以此为准。
    await transport.selectAudioTrack(null);
    expect(
      await _until(
        () => native.getProperty('aid'),
        (v) => v == 'no',
        what: '关音轨该是 aid=no',
      ),
      'no',
    );
    await transport.selectAudioTrack(audioIds.first);
    expect(
      await _until(
        () => native.getProperty('aid'),
        (v) => v == audioIds.first,
        what: '按号选音轨要选得回',
      ),
      audioIds.first,
    );

    // 音画漂移：两条流都在的时候 `avsync` 才是个有意义的数。
    final drift = await transport.avDriftMs();
    expect(drift.isFinite, isTrue);

    // 纯音频档（neo 的 audio-only）：**开与关都要验** —— 只验「关」是假绿，
    // 真正的缺陷在「关得掉、开不回来」（见 spec §5 缺陷 ⑰）。
    await transport.setVideoEnabled(false);
    expect(
      await _until(
        () => native.getProperty('video'),
        (v) => v == 'no',
        what: '只听声音该把画面关掉',
      ),
      'no',
    );
    final whilePaused = await native.getProperty('video');
    await transport.setVideoEnabled(true);
    await player.play();
    final whilePlaying = await _until(
      () => native.getProperty('video'),
      (v) => v != 'no',
      what: '退出「只听声音」后画面必须回来',
    );
    // mpv 的 `video` 回读的不是 yes/no 而是**当前轨号**（关掉时才是 'no'），
    // 所以判据是「不再是 no」，并且 `vid` 必须是选中的那条轨。
    expect(
      whilePlaying,
      isNot('no'),
      reason: '退出「只听声音」后播放态必须有画面（暂停态读回 $whilePaused）',
    );
    expect(
      await native.getProperty('vid'),
      isNot(anyOf('no', 'auto')),
      reason: 'vid 要落回真轨号，否则画面回不来',
    );

    await transport.close();
    await player.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
