import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zephyr/video/controller/mpv_video_transport.dart';
import 'package:zephyr/video/controller/video_transport.dart';
import 'package:zephyr/video/service/video_frame_preview.dart';

String? _library() {
  // flutter_tester 的 @rpath 与应用不同，先加载应用内的框架依赖。
  for (final mode in ['Release', 'Debug']) {
    final directory = Directory(
      '${Directory.current.path}/build/macos/Build/Products/$mode/Rossi.app/Contents/Frameworks',
    );
    if (!directory.existsSync()) continue;
    final frameworks = directory
        .listSync()
        .whereType<Directory>()
        .where(
          (entry) =>
              entry.path.endsWith('.framework') &&
              !entry.path.contains('ObjectBox') &&
              !entry.path.contains('FlutterMacOS'),
        )
        .toList();
    for (var pass = 0; pass < 4; pass++) {
      for (final framework in frameworks) {
        final name = framework.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last
            .replaceFirst('.framework', '');
        try {
          DynamicLibrary.open('${framework.path}/Versions/A/$name');
        } catch (_) {}
      }
    }
    break;
  }
  for (final path in [
    '${Directory.current.path}/build/macos/Build/Products/Release/Rossi.app/Contents/Frameworks/Mpv.framework/Versions/A/Mpv',
    '${Directory.current.path}/build/macos/Build/Products/Debug/Rossi.app/Contents/Frameworks/Mpv.framework/Versions/A/Mpv',
    '/opt/homebrew/opt/mpv/lib/libmpv.2.dylib',
    '/usr/local/lib/libmpv.2.dylib',
  ]) {
    try {
      DynamicLibrary.open(path);
      return path;
    } catch (_) {}
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = _library();
  test(
    '真实 H264：原截图路径与预览均能生成可解码图片，不强制缩放滤镜',
    () async {
      MediaKit.ensureInitialized(libmpv: library);
      // ignore: avoid_print
      print('preview backend: $library');
      final directory = await Directory.systemTemp.createTemp(
        'preview-native-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final input = '${directory.path}/sample.mp4';
      final generated = await Process.run('ffmpeg', [
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-f',
        'lavfi',
        '-i',
        'testsrc2=size=1920x1080:rate=8:duration=3',
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=440:duration=3',
        '-c:v',
        'libx264',
        '-preset',
        'ultrafast',
        '-c:a',
        'aac',
        '-shortest',
        input,
      ]);
      expect(generated.exitCode, 0, reason: '${generated.stderr}');
      for (final preview in [false, true]) {
        final player = Player();
        final transport = MpvVideoTransport(player: player);

        try {
          await transport.open(
            input,
            options: const VideoOpenOptions(autoplay: false),
          );
          final ready = Stopwatch()..start();
          while (transport.duration == Duration.zero &&
              ready.elapsedMilliseconds < 5000) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
          }
          expect(transport.duration, greaterThan(Duration.zero));
          await transport.seek(const Duration(seconds: 1));
          await Future<void>.delayed(const Duration(milliseconds: 200));
          final watch = Stopwatch()..start();
          final path = '${directory.path}/${preview ? 'preview' : 'full'}.jpg';
          String? shot;
          while (shot == null && watch.elapsedMilliseconds < 2000) {
            shot = await transport.screenshot(path);
            if (shot == null) {
              await Future<void>.delayed(const Duration(milliseconds: 120));
            }
          }
          expect(shot, path);
          watch.stop();
          final bytes = await File(path).readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          try {
            expect(frame.image.width, 1920);
            expect(frame.image.height, 1080);
            if (preview) {
              final native = player.platform as NativePlayer;
              expect(
                await native.getProperty('vf'),
                isNot(contains('lavfi-scale')),
              );
            }
            // 两条路径使用同一合成源；记录耗时方便本地评估，不设机器相关速度门槛。
            // ignore: avoid_print
            print(
              '${preview ? 'preview' : 'full'}: ${watch.elapsedMilliseconds}ms, '
              '${bytes.length} bytes, ${frame.image.width}x${frame.image.height}',
            );
          } finally {
            frame.image.dispose();
            codec.dispose();
          }
          if (preview) {
            // 与正式界面相同：主播放器存在时，独立的懒加载预览解码器取帧。
            final provider = VideoFramePreviewProvider(
              createPreviewTransport: () => MpvVideoTransport(),
              cacheDirOverride: directory.path,
            )..setSource(input);
            try {
              const target = Duration(seconds: 2);
              await provider.request(target);
              final wait = Stopwatch()..start();
              while (provider.peek(target) == null &&
                  wait.elapsedMilliseconds < 10000) {
                await Future<void>.delayed(const Duration(milliseconds: 40));
              }
              final captured = provider.peek(target);
              expect(
                captured,
                isNotNull,
                reason: '验证实际 provider 开流、定位、缓存和完成通知',
              );
              final codec = await ui.instantiateImageCodec(
                await File(captured!.filePath).readAsBytes(),
              );
              final decoded = await codec.getNextFrame();
              expect(decoded.image.width, 1920);
              decoded.image.dispose();
              codec.dispose();
              expect(await provider.request(target), same(captured));
            } finally {
              await provider.dispose();
            }
          }
        } finally {
          await transport.close();
          await player.dispose();
        }
      }
    },
    skip: library == null || !File('/opt/homebrew/bin/ffmpeg').existsSync(),
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
