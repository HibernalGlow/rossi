import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/setting/real_sr/service/denoise_model_download.dart';

void main() {
  test(
    'all panels share one transfer, indeterminate progress, verify and ready',
    () async {
      final release = Completer<void>();
      var size = 0;
      var calls = 0;
      final phases = <DenoiseDownloadPhase>[];
      final model = DenoiseModelDownload(
        inspect: () async => size,
        transfer: (progress, verifying) async {
          calls++;
          progress(42, -1);
          await release.future;
          progress(100, 100);
          verifying();
          size = 100;
        },
        remove: () async {
          size = 0;
        },
      );
      addTearDown(model.dispose);
      model.addListener(() => phases.add(model.phase));
      await model.refresh();
      expect(model.phase, DenoiseDownloadPhase.missing);
      final first = model.download();
      final second = model.download();
      expect(identical(first, second), isTrue);
      expect(calls, 1);
      expect(model.progress, isNull);
      expect(model.busy, isTrue);
      release.complete();
      await first;
      expect(model.phase, DenoiseDownloadPhase.ready);
      expect(model.installedBytes, 100);
      expect(phases, contains(DenoiseDownloadPhase.verifying));
      expect(model.busy, isFalse);
      await model.delete();
      expect(model.phase, DenoiseDownloadPhase.missing);
    },
  );

  test(
    'failed update preserves installed status and retry clears the error',
    () async {
      var fail = true;
      final model = DenoiseModelDownload(
        inspect: () async => 100,
        transfer: (_, _) async {
          if (fail) throw StateError('network disconnected');
        },
        remove: () async {},
      );
      addTearDown(model.dispose);
      await model.refresh();
      await model.download();
      expect(model.phase, DenoiseDownloadPhase.failed);
      expect(model.installedBytes, 100);
      expect(model.error, contains('network disconnected'));
      fail = false;
      await model.download();
      expect(model.phase, DenoiseDownloadPhase.ready);
      expect(model.error, isNull);
    },
  );

  test(
    'completed download is failed unless installation inspection confirms it',
    () async {
      final model = DenoiseModelDownload(
        inspect: () async => 0,
        transfer: (_, verify) async {
          verify();
        },
        remove: () async {},
      );
      addTearDown(model.dispose);
      await model.download();
      expect(model.phase, DenoiseDownloadPhase.failed);
      expect(model.installedBytes, 0);
    },
  );
}
