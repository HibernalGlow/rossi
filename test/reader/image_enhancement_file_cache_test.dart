import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/setting/real_sr/service/image_enhancement_file_cache.dart';

void main() {
  late Directory root;
  late File source;
  late Directory cache;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('reader_processing_');
    source = File('${root.path}/source.jpg');
    await source.writeAsString('original pixels');
    cache = Directory('${root.path}/cache');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'ordered stages publish a new result while original remains untouched',
    () async {
      final engine = ImageEnhancementFileCache();
      final inputs = <String>[];
      Future<bool> stage(String input, String output) async {
        final text = await File(input).readAsString();
        inputs.add(text);
        await File(output).writeAsString('$text processed');
        return true;
      }

      final result = await engine.process(
        sourcePath: source.path,
        cacheDirectory: cache,
        pipelineKey: 'denoise-then-upscale',
        stages: [stage, stage],
      );
      expect(inputs, ['original pixels', 'original pixels processed']);
      expect(await source.readAsString(), 'original pixels');
      expect(result, isNot(source.path));
      expect(
        await File(result!).readAsString(),
        'original pixels processed processed',
      );
      final second = await engine.process(
        sourcePath: source.path,
        cacheDirectory: cache,
        pipelineKey: 'denoise-then-upscale',
        stages: [stage, stage],
      );
      expect(second, result);
      expect(inputs.length, 2);
    },
  );

  test(
    'parallel consumers share one inference and parameter changes miss cache',
    () async {
      final engine = ImageEnhancementFileCache();
      var count = 0;
      final started = Completer<void>();
      final release = Completer<void>();
      Future<bool> stage(String input, String output) async {
        count++;
        if (!started.isCompleted) started.complete();
        await release.future;
        await File(output).writeAsString('processed');
        return true;
      }

      final first = engine.process(
        sourcePath: source.path,
        cacheDirectory: cache,
        pipelineKey: 'tile128',
        stages: [stage],
      );
      await started.future;
      final second = engine.process(
        sourcePath: source.path,
        cacheDirectory: cache,
        pipelineKey: 'tile128',
        stages: [stage],
      );
      release.complete();
      final paths = await Future.wait([first, second]);
      expect(paths[0], paths[1]);
      expect(count, 1);
      final changed = await engine.process(
        sourcePath: source.path,
        cacheDirectory: cache,
        pipelineKey: 'tile256',
        stages: [stage],
      );
      expect(changed, isNot(paths[0]));
      expect(count, 2);
    },
  );

  test('failure cleans temporary outputs and remains retryable', () async {
    final engine = ImageEnhancementFileCache();
    var succeeds = false;
    Future<bool> stage(String input, String output) async {
      await File(output).writeAsString('partial');
      return succeeds;
    }

    expect(
      await engine.process(
        sourcePath: source.path,
        cacheDirectory: cache,
        pipelineKey: 'denoise',
        stages: [stage],
      ),
      isNull,
    );
    expect(await cache.list().toList(), isEmpty);
    succeeds = true;
    expect(
      await engine.process(
        sourcePath: source.path,
        cacheDirectory: cache,
        pipelineKey: 'denoise',
        stages: [stage],
      ),
      isNotNull,
    );
    expect(await source.readAsString(), 'original pixels');
  });

  test('source changed during inference cannot publish stale output', () async {
    final engine = ImageEnhancementFileCache();
    final result = await engine.process(
      sourcePath: source.path,
      cacheDirectory: cache,
      pipelineKey: 'denoise',
      stages: [
        (input, output) async {
          await File(output).writeAsString('old pixels');
          await source.writeAsString('new original pixels');
          return true;
        },
      ],
    );
    expect(result, isNull);
    expect(await cache.list().toList(), isEmpty);
    expect(await source.readAsString(), 'new original pixels');
  });
}
