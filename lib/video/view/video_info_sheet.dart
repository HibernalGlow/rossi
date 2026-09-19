/// 视频信息表 —— neoview `ImageInformationCard.tsx:48-83` 的等效物。
///
/// 字段口径与上游一致：**时长、帧率、码率、视频编码、音频编码**，
/// 拿不到的字段显示 `—` 而不是整行消失 —— 用户分不清「没有这条信息」和
/// 「探测失败」，而后者是要报出来的。
///
/// 多出来的一行 `av_drift_ms` 来自 mImageViewer：音画不同步时它是唯一能自证
/// 「不是渲染慢了，是同步丢了」的数字。
library;

import 'package:flutter/material.dart';

import 'package:zephyr/video/controller/reader_video_controller.dart';
import 'package:zephyr/video/subtitle/video_subtitle.dart';
import 'package:zephyr/video/view/video_control_overlay.dart';

Future<void> showVideoInfoSheet(
  BuildContext context, {
  required ReaderVideoController controller,
  required VideoLabels labels,
  List<SubtitleCandidate> sidecars = const <SubtitleCandidate>[],
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => _VideoInfoSheet(
      controller: controller,
      labels: labels,
      sidecars: sidecars,
    ),
  );
}

class _VideoInfoSheet extends StatefulWidget {
  const _VideoInfoSheet({
    required this.controller,
    required this.labels,
    required this.sidecars,
  });

  final ReaderVideoController controller;
  final VideoLabels labels;
  final List<SubtitleCandidate> sidecars;

  @override
  State<_VideoInfoSheet> createState() => _VideoInfoSheetState();
}

class _VideoInfoSheetState extends State<_VideoInfoSheet> {
  double? _drift;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _readDrift());
  }

  Future<void> _readDrift() async {
    final transport = widget.controller.transport;
    if (transport == null) return;
    final drift = await transport.avDriftMs();
    if (mounted) setState(() => _drift = drift);
  }

  String _orDash(String? value) =>
      (value == null || value.isEmpty) ? '—' : value;

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    final snapshot = widget.controller.snapshot;
    final metadata = widget.controller.transport?.metadata;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ListTile(
              title: Text(labels.info),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const Divider(height: 1),
            _row('时长', formatVideoTime(snapshot.duration)),
            _row('当前', formatVideoTime(snapshot.currentTime)),
            _row(
              '尺寸',
              metadata == null || metadata.width == 0
                  ? '—'
                  : '${metadata.width}×${metadata.height}',
            ),
            _row(
              '显示宽高比',
              metadata == null
                  ? '—'
                  : '${metadata.normalizedSar.$1}:${metadata.normalizedSar.$2}',
            ),
            _row(
              '帧率',
              metadata?.frameRate == null
                  ? '—'
                  : metadata!.frameRate!.toStringAsFixed(3),
            ),
            _row('码率', metadata?.bitrateKbps == null ? '—' : '${metadata!.bitrateKbps} kbps'),
            _row('视频编码', _orDash(metadata?.videoCodec)),
            _row('音频编码', _orDash(metadata?.audioCodec)),
            _row(
              '音画漂移',
              _drift == null ? '—' : '${_drift!.toStringAsFixed(1)} ms',
            ),
            _row('循环', widget.controller.snapshot.loopMode.name),
            _row('倍速', '${snapshot.playbackRate}x'),
            if (snapshot.abLoop != null)
              _row(
                'A–B',
                '${formatVideoTime(snapshot.abLoop!.a)} – '
                '${formatVideoTime(snapshot.abLoop!.b)}',
              ),
            if (widget.sidecars.isNotEmpty) ...<Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('外挂字幕', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              for (final sidecar in widget.sidecars)
                _row(sidecar.label, sidecar.format.toUpperCase()),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Row(
      children: <Widget>[
        SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.grey))),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
