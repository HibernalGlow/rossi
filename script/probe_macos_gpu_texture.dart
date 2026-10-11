// 由 probe_macos_gpu_texture.swift 在真实 Flutter/Metal 窗口中运行。
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zephyr/gpu/gpu_present_bridge.dart';

const MethodChannel _host = MethodChannel('rossi/gpu_texture_probe');
const GpuPresentBridge _bridge = GpuPresentBridge();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Directory? fixture;
  try {
    final Map<Object?, Object?> config = (await _host
        .invokeMapMethod<Object?, Object?>('config'))!;
    final int width = config['width']! as int;
    final int height = config['height']! as int;
    final int samples = config['samples']! as int;
    fixture = await Directory.systemTemp.createTemp('rossi-texture-probe-');
    await _createPages(
      fixture,
      config['sourceWidth']! as int,
      config['sourceHeight']! as int,
    );
    runApp(const _ProbeView());
    await WidgetsBinding.instance.endOfFrame;
    final GpuPresentStatus initial = await _bridge.tryInit(
      width: width,
      height: height,
    );
    GpuPresentStatus status = initial;
    final Stopwatch readyWait = Stopwatch()..start();
    while (status.state == GpuPresentState.loading &&
        readyWait.elapsed < const Duration(seconds: 15)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      status = await _bridge.status();
    }
    _check(
      status.state == GpuPresentState.ready,
      'Presenter failed to become ready: ${status.error}',
    );
    _check(
      await _bridge.open(fixture.path) == 2,
      'Expected two generated pages',
    );
    _check(
      await _bridge.setPrefetchEnabled(false),
      'Prefetch could not be disabled',
    );

    // 没挂 Texture 时发通知不应伪造引擎取帧；此处的主动延迟不计入性能样本。
    await _bridge.show(0);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final GpuPresentStats unmounted = await _bridge.stats();
    _check(unmounted.framesMarked > 0, 'No texture notification was sent');
    _check(
      unmounted.handleOpened == 0,
      'A notification falsely counted as acquisition without a Texture',
    );

    runApp(_ProbeView(textureId: status.textureId));
    await WidgetsBinding.instance.endOfFrame;
    final GpuPresentStats mounted = await _awaitAcquisition(
      unmounted.probeInt('frameSerial'),
    );
    final List<Map<String, Object?>> cold = <Map<String, Object?>>[];
    final List<Map<String, Object?>> cached = <Map<String, Object?>>[];
    // 页 0 已用于挂载验证；页 1 是本次来源中尚未解码的页。
    cold.add(await _showAndMeasure(1));
    for (int i = 0; i < samples; i++) {
      cached.add(await _showAndMeasure(i % 2));
    }
    await fixture.delete(recursive: true);
    fixture = null;
    await _host.invokeMethod<void>('report', <String, Object?>{
      'ok': true,
      'mode': 'Flutter debug engine with Release native presenter',
      'sourceWidth': config['sourceWidth'],
      'sourceHeight': config['sourceHeight'],
      'targetWidth': width,
      'targetHeight': height,
      'withoutTexture': <String, Object?>{
        'framesMarked': unmounted.framesMarked,
        'framesAcquired': unmounted.handleOpened,
        'probe': unmounted.probe,
      },
      'afterMount': mounted.probe,
      'cold': cold,
      'cached': cached,
      'boundary':
          'Native method receipt to first copyPixelBuffer return; excludes physical screen presentation. Dart method round trip is separate. Debug engine, synthetic images, uncontrolled system load.',
    });
  } catch (error, stack) {
    await _host.invokeMethod<void>('report', <String, Object?>{
      'ok': false,
      'error': error.toString(),
      'stack': stack.toString(),
    });
  } finally {
    await fixture?.delete(recursive: true);
  }
}

void _check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<GpuPresentStats> _awaitAcquisition(int serial) async {
  final Stopwatch timeout = Stopwatch()..start();
  while (timeout.elapsed < const Duration(seconds: 10)) {
    final GpuPresentStats stats = await _bridge.stats();
    _check(
      stats.probeInt('frameSerial') == serial,
      'The measured frame was replaced',
    );
    if (stats.probe['frameAcquired'] == true) {
      _check(
        stats.probeInt('lastAcquiredFrameSerial') == serial,
        'Acquisition belongs to another frame',
      );
      return stats;
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  throw StateError('Flutter did not acquire frame $serial');
}

Future<Map<String, Object?>> _showAndMeasure(int index) async {
  final GpuPresentStats before = await _bridge.stats();
  final Stopwatch roundTrip = Stopwatch()..start();
  await _bridge.show(index);
  roundTrip.stop();
  final GpuPresentStats after = await _bridge.stats();
  final int serial = after.probeInt('frameSerial');
  _check(serial > before.probeInt('frameSerial'), 'No new frame was published');
  final GpuPresentStats acquired = await _awaitAcquisition(serial);
  _check(acquired.probeInt('framePageIndex') == index, 'Wrong page acquired');
  _check(
    acquired.handleOpened > before.handleOpened,
    'No distinct frame acquisition',
  );
  return <String, Object?>{
    'index': index,
    'dartShowRoundTripMs': roundTrip.elapsedMicroseconds / 1000,
    'probe': acquired.probe,
  };
}

Future<void> _createPages(Directory dir, int width, int height) async {
  for (int page = 0; page < 2; page++) {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    canvas.drawColor(
      page == 0 ? const Color(0xff1258ab) : const Color(0xffba6421),
      BlendMode.src,
    );
    final Paint paint = Paint()..color = const Color(0xffeaeaea);
    for (int x = 0; x < width; x += 37) {
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), 0, 11, height.toDouble()),
        paint,
      );
    }
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(width, height);
    try {
      final ByteData bytes = (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!;
      await File('${dir.path}/$page.png').writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image.dispose();
      picture.dispose();
    }
  }
}

class _ProbeView extends StatelessWidget {
  const _ProbeView({this.textureId});
  final int? textureId;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: const Color(0xff141414),
      child: textureId == null
          ? const SizedBox.expand()
          : Texture(textureId: textureId!, filterQuality: FilterQuality.none),
    ),
  );
}
