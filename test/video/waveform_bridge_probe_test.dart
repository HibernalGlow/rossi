/// 波形进度条那条链的**过桥**验证：Dart → FRB → Rust(symphonia) → 回来。
///
/// 为什么值得单开一个文件：`wave_peaks.rs` 自己有 5 条 Rust 测试，
/// `VideoWaveformService` 的归一化与缓存是纯 Dart 逻辑，两边都绿也说明不了
/// 「桥那头接的是不是这个函数、参数顺序对不对、空列时 UI 拿到的还是不是 empty」。
/// 这条打通的是中间那一段 —— 之前只能靠真机看进度条底下有没有柱子（验收 B16）。
///
/// 需要原生库能在测试 VM 里加载；加载不了就 skip 并说明，不留永远红的测试。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:zephyr/src/rust/api/local.dart';
import 'package:zephyr/src/rust/frb_generated.dart';
import 'package:zephyr/video/service/video_waveform_service.dart';

/// 2 秒方波：前半响（±12000）、后半轻（±700）。
///
/// 用方波不用正弦：这里要的是**两段 RMS 有明显落差**，方波的均值平方根
/// 就是幅度本身，判据最干净，也不需要为了一个 sin 拖进 dart:math。
String _writeSquareWav() {
  const rate = 8000;
  const seconds = 2;
  final samples = rate * seconds;
  final data = ByteData(samples * 2);
  for (var i = 0; i < samples; i++) {
    final amp = i < samples ~/ 2 ? 12000 : 700;
    final sign = (i % 8) < 4 ? 1 : -1;
    data.setInt16(i * 2, amp * sign, Endian.little);
  }
  final out = BytesBuilder();
  void u32(int v) =>
      out.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
  void u16(int v) =>
      out.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));
  final bytes = data.buffer.asUint8List();
  out.add('RIFF'.codeUnits);
  u32(36 + bytes.length);
  out.add('WAVEfmt '.codeUnits);
  u32(16);
  u16(1); // PCM
  u16(1); // mono
  u32(rate);
  u32(rate * 2); // byte rate
  u16(2); // block align
  u16(16); // bits
  out.add('data'.codeUnits);
  u32(bytes.length);
  out.add(bytes);
  final dir = Directory.systemTemp.createTempSync('rossi-wave-bridge');
  final path = '${dir.path}/probe.wav';
  File(path).writeAsBytesSync(out.takeBytes());
  return path;
}

void main() {
  late final String wav;
  var nativeReady = false;
  // 加载失败的原因要能出现在 skip 的理由里：这条同时是「仓库根目录下那份
  // rust/target/release/libwindcore.dylib 与 frb_generated 的 content hash
  // 对得上吗」的守门人 —— 那个不一致已经咬过两次，症状是启动后一片黑且零线索。
  String? nativeError;

  setUpAll(() async {
    wav = _writeSquareWav();
    try {
      await RustLib.init();
      nativeReady = true;
    } catch (e) {
      nativeError = '$e';
    }
  });

  test('过桥本身：参数顺序与返回类型对得上', () async {
    if (!nativeReady) {
      return markTestSkipped('原生库加载不了（$nativeError）');
    }
    final peaks = await localVideoWavePeaks(
      path: wav,
      start: 0,
      end: 2,
      binSecs: 0.1,
    );
    // 2 s / 0.1 s = 20 格，允许末格不满。
    expect(
      peaks.length,
      inInclusiveRange(18, 22),
      reason: '拿到 ${peaks.length} 格',
    );
    // Rust 侧给的是**绝对** RMS（不归一），所以这里必须能看到量级差；
    // 归一化是 Dart 侧在拿到整条列之后做的 —— 两半各归一次就毁了跨窗口可比性。
    expect(
      peaks.reduce((a, b) => a > b ? a : b),
      greaterThan(0.1),
      reason: '响段 RMS 该有的量级没出来：$peaks',
    );
  });

  test('服务层：整条列一次取、归一化、缓存与清空', () async {
    if (!nativeReady) {
      return markTestSkipped('原生库加载不了（$nativeError）');
    }
    final service = VideoWaveformService.instance;
    service.clearCache();
    final strip = await service.stripFor(wav, const Duration(seconds: 2));
    expect(strip.isEmpty, isFalse, reason: '有音轨就该给出列');
    expect(strip.binSecs, greaterThanOrEqualTo(0.1));
    expect(
      strip.samples.reduce((a, b) => a > b ? a : b),
      closeTo(1.0, 0.001),
      reason: '归一化之后峰值该正好是 1',
    );
    final half = strip.samples.length ~/ 2;
    final first = strip.samples.take(half).reduce((a, b) => a + b) / half;
    final second =
        strip.samples.skip(half).reduce((a, b) => a + b) /
        (strip.samples.length - half);
    expect(
      first,
      greaterThan(second * 4),
      reason: '前半响后半轻要在列上看得出来：$first vs $second',
    );
    // 同一个文件第二次该命中缓存（同一实例，不重解）。
    final again = await service.stripFor(wav, const Duration(seconds: 2));
    expect(identical(again, strip), isTrue, reason: '缓存没命中就是每次滚动都重解码');

    service.clearCache();
    final afterClear = await service.stripFor(wav, const Duration(seconds: 2));
    expect(identical(afterClear, strip), isFalse, reason: 'clearCache 没生效');
  });

  test('没有音轨：退化成空列，不抛异常', () async {
    if (!nativeReady) {
      return markTestSkipped('原生库加载不了（$nativeError）');
    }
    final dir = Directory.systemTemp.createTempSync('rossi-wave-none');
    final bogus = '${dir.path}/not-audio.mp4';
    File(bogus).writeAsBytesSync('definitely not a media file'.codeUnits);
    final strip = await VideoWaveformService.instance.stripFor(
      bogus,
      const Duration(seconds: 10),
    );
    expect(strip.isEmpty, isTrue, reason: '解不出音轨时 UI 要拿得到「不画」这个信号');
  });
}
