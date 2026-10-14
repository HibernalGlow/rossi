import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/setting/real_sr/service/denoise_model_download.dart';
import 'package:zephyr/page/setting/real_sr/widgets/image_processing/processing_settings_card.dart';
import 'package:zephyr/i18n/strings.g.dart';

class DenoiseModelCard extends StatelessWidget {
  const DenoiseModelCard({super.key, required this.download});
  final DenoiseModelDownload download;
  String _bytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: download,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final phase = download.phase;
      final status = switch (phase) {
        DenoiseDownloadPhase.checking => t.realSr.denoiseChecking,
        DenoiseDownloadPhase.missing => t.realSr.denoiseMissing,
        DenoiseDownloadPhase.downloading => '正在下载模型',
        DenoiseDownloadPhase.verifying => t.realSr.denoiseVerifying,
        DenoiseDownloadPhase.ready => t.realSr.denoiseInstalled(
          size: _bytes(download.installedBytes),
        ),
        DenoiseDownloadPhase.failed =>
          download.installedBytes > 0 ? t.realSr.denoiseUpdateFailed : '模型下载失败',
      };
      return Material(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.realSr.denoiseSubtitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Semantics(liveRegion: true, child: Text(status)),
              if (phase == DenoiseDownloadPhase.downloading ||
                  phase == DenoiseDownloadPhase.verifying) ...[
                const SizedBox(height: 12),
                Semantics(
                  label: phase == DenoiseDownloadPhase.verifying
                      ? t.realSr.denoiseVerifyTooltip
                      : t.realSr.denoiseProgressTooltip,
                  value: download.progress == null
                      ? _bytes(download.received)
                      : '${(download.progress! * 100).round()}%',
                  child: LinearProgressIndicator(
                    value: phase == DenoiseDownloadPhase.verifying
                        ? null
                        : download.progress,
                    borderRadius: BorderRadius.circular(12),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_bytes(download.received)}${download.total > 0 ? ' / ${_bytes(download.total)}' : ' · 总大小未知'}',
                ),
              ],
              if (download.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    download.error!,
                    style: TextStyle(color: colors.error),
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    style: processingActionStyle(),
                    onPressed: download.busy
                        ? null
                        : () {
                            HapticFeedback.lightImpact();
                            unawaited(download.download());
                          },
                    icon: Icon(
                      phase == DenoiseDownloadPhase.failed
                          ? Icons.refresh
                          : Icons.download,
                    ),
                    label: Text(
                      phase == DenoiseDownloadPhase.failed
                          ? t.realSr.retryDownload
                          : download.installedBytes > 0
                          ? '重新下载'
                          : t.realSr.downloadModel,
                    ),
                  ),
                  if (download.installedBytes > 0)
                    OutlinedButton.icon(
                      style: processingActionStyle(),
                      onPressed: download.busy
                          ? null
                          : () {
                              HapticFeedback.lightImpact();
                              unawaited(download.delete());
                            },
                      icon: const Icon(Icons.delete_outline),
                      label: Text(t.realSr.removeModel),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                t.realSr.denoiseAttribution,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    },
  );
}
