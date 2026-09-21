part of '../mpv_property_probe_test.dart';
// 现场生成分镜素材（WAV/AVI）



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
