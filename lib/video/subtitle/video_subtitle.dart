/// 字幕：同名文件发现 + SRT/ASS/SSA → WebVTT 转换。
///
/// 发现规则照 neoview（同目录 / 同压缩包内、同主干、可带语言后缀
/// `video.zh-CN.srt`）；转换在 Rossi 侧做（mpv 能直接吃 srt/ass，
/// 但 vtt 轨要能被「自定义字幕层」渲染，而且转换本身要能测）。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:zephyr/video/model/video_media_kind.dart';

const List<String> subtitleExtensions = <String>[
  'srt',
  'ass',
  'ssa',
  'vtt',
  'sub',
];

class SubtitleCandidate {
  const SubtitleCandidate({
    required this.path,
    required this.label,
    this.language,
    this.format = 'srt',
  });

  /// 文件系统路径，或归档内条目标记（`archive:<source>#<entry>`）。
  final String path;
  final String label;
  final String? language;
  final String format;
}

/// 从一堆同目录条目名里挑出属于 [videoName] 的字幕。
///
/// 匹配口径与上游一致：**视频主干 startWith 字幕主干**，中间只允许
/// `.` / `_` / `-` / 空格 —— 于是 `movie.zh-CN.srt` 命中 `movie.mp4`，
/// 而 `movieost.srt` 不会。
List<SubtitleCandidate> matchSubtitleNames({
  required String videoName,
  required List<String> entryNames,
}) {
  final stem = p.basenameWithoutExtension(videoName);
  final out = <SubtitleCandidate>[];
  for (final name in entryNames) {
    final ext = extensionLower(name);
    if (ext == null || !subtitleExtensions.contains(ext)) continue;
    final subStem = p.basenameWithoutExtension(name);
    if (subStem == stem) {
      out.add(
        SubtitleCandidate(path: name, label: '默认', format: ext),
      );
      continue;
    }
    if (!subStem.startsWith(stem)) continue;
    final tail = subStem.substring(stem.length);
    if (!tail.startsWith('.') &&
        !tail.startsWith('_') &&
        !tail.startsWith('-') &&
        !tail.startsWith(' ')) {
      continue;
    }
    final language = tail.substring(1);
    out.add(
      SubtitleCandidate(
        path: name,
        label: language.isEmpty ? '字幕' : language,
        language: language.isEmpty ? null : language,
        format: ext,
      ),
    );
  }
  out.sort((a, b) => a.label.compareTo(b.label));
  return out;
}

/// 读一个目录里的外挂字幕（视频在文件夹里时的路径）。
Future<List<SubtitleCandidate>> discoverSidecarSubtitles(
  String videoPath,
) async {
  final dir = Directory(p.dirname(videoPath));
  if (!await dir.exists()) return const <SubtitleCandidate>[];
  final names = <String>[];
  await for (final entity in dir.list()) {
    if (entity is File) names.add(p.basename(entity.path));
  }
  return matchSubtitleNames(
    videoName: p.basename(videoPath),
    entryNames: names,
  ).map((c) => SubtitleCandidate(
    path: p.join(dir.path, c.path),
    label: c.label,
    language: c.language,
    format: c.format,
  )).toList();
}

String _vttTimestamp(Duration d) {
  final ms = d.inMilliseconds;
  String pad(int v, [int w = 2]) => v.toString().padLeft(w, '0');
  return '${pad(ms ~/ 3600000)}:${pad(ms ~/ 60000 % 60)}:'
      '${pad(ms ~/ 1000 % 60)}.${pad(ms % 1000, 3)}';
}

/// `00:00:01,500` / `0:01:02.50` / `1:02.5` → [Duration]。
///
/// 手写解析而不是 `DateTime.parse`：SRT/ASS 的时间戳都不是合法 ISO 8601，
/// 而且 ASS 用的是 `h:mm:ss.cs`（百分秒），SRT 用 `h:mm:ss,ms`。
Duration? _parseTime(String raw) {
  final text = raw.trim().replaceAll(',', '.');
  final parts = text.split(':');
  if (parts.isEmpty || parts.length > 3) return null;
  final fractions = <int>[];
  final seconds = <int>[];
  for (final part in parts) {
    final split = part.split('.');
    if (split.length > 2) return null;
    final head = int.tryParse(split[0].trim());
    if (head == null) return null;
    seconds.add(head);
    fractions.add(split.length == 1 ? 0 : _millisOf(split[1]));
  }
  final hours = parts.length == 3 ? seconds[0] : 0;
  final minutes = parts.length == 3 ? seconds[1] : (parts.length == 2 ? seconds[0] : 0);
  final secs = seconds.last;
  // 小数位挂在**最后一段**上（`01:02.500` 的 .500 属于秒），前面各段不会有。
  final millis = fractions.last;
  return Duration(
    hours: hours,
    minutes: minutes,
    seconds: secs,
    milliseconds: millis,
  );
}

/// `.5` = 500 ms、`.50` = 500 ms、`.500` = 500 ms。
int _millisOf(String fraction) {
  if (fraction.isEmpty) return 0;
  final padded = fraction.padRight(3, '0').substring(0, 3);
  return int.tryParse(padded) ?? 0;
}

/// ASS 的 `\N` 是换行，VTT 用字面换行。
String _assToVttText(String text) => text
    .replaceAll(RegExp(r'\\N'), '\n')
    .replaceAll(RegExp(r'\\n'), '\n')
    .replaceAll(RegExp(r'\{[^}]*\}'), '');

/// SRT / ASS / SSA → WebVTT。
///
/// 已经是 VTT 的原样返回（只补表头）。SRT 的 `-->` 用逗号分隔毫秒，
/// ASS 要从 `Dialogue:` 行里按逗号切字段 —— 两者都是**逐行状态机**，
/// 不做「整篇正则替换」，因为字幕文本里出现 `[]`、`{}`、数字行都很常见。
String convertSubtitlesToWebVtt(String source, {required String format}) {
  if (format == 'vtt') {
    return source.trimLeft().startsWith('WEBVTT')
        ? source
        : 'WEBVTT\n\n$source';
  }
  if (format == 'ass' || format == 'ssa') {
    return _convertAss(source);
  }
  return _convertSrt(source);
}

String _convertSrt(String source) {
  final out = StringBuffer('WEBVTT\n\n');
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  var i = 0;
  final cuePattern = RegExp(
    r'(\d{1,2}:\d{2}:\d{2}[,.]\d{1,3})\s*-->\s*(\d{1,2}:\d{2}:\d{2}[,.]\d{1,3})',
  );
  while (i < lines.length) {
    final match = cuePattern.firstMatch(lines[i].trim());
    if (match == null) {
      i++;
      continue;
    }
    final start = _parseTime(match.group(1)!);
    final end = _parseTime(match.group(2)!);
    if (start != null && end != null) {
      out.write('${_vttTimestamp(start)} --> ${_vttTimestamp(end)}\n');
    }
    i++;
    final text = <String>[];
    while (i < lines.length && lines[i].trim().isNotEmpty) {
      text.add(lines[i].trim());
      i++;
    }
    if (text.isNotEmpty) out.write('${text.join('\n')}\n\n');
  }
  return out.toString();
}

String _convertAss(String source) {
  final out = StringBuffer('WEBVTT\n\n');
  for (final raw in source.replaceAll('\r\n', '\n').split('\n')) {
    if (!raw.startsWith('Dialogue:')) continue;
    // ASS 的 `Dialogue:` 固定 **10 个字段**，第 10 个（下标 9）才是正文，
    // 且正文里可以有逗号 —— 所以按 `,` 全切之后用 sublist(9) 拼回，
    // 长度判据也必须是 10：判成 11 会把所有「正文不含逗号」的正常字幕行整行丢掉。
    final parts = raw.substring('Dialogue:'.length).split(',');
    if (parts.length < 10) continue;
    final start = _parseTime(parts[1]);
    final end = _parseTime(parts[2]);
    if (start == null || end == null) continue;
    final text = parts.sublist(9).join(',');
    final cleaned = _assToVttText(text).trim();
    if (cleaned.isEmpty) continue;
    out
      ..write('${_vttTimestamp(start)} --> ${_vttTimestamp(end)}\n')
      ..write('$cleaned\n\n');
  }
  return out.toString();
}

/// 字幕样式（neo 的字号 0.5–3 em、底色 0–100%、底部 0–30%）→ 一条 VTT `::::cue`。
String buildVttCueStyleCss({
  double sizeEm = 1.0,
  String colorHex = 'ffffff',
  int backgroundOpacityPercent = 70,
  int bottomPercent = 5,
}) {
  final size = sizeEm.clamp(0.5, 3.0);
  final bg = backgroundOpacityPercent.clamp(0, 100) / 100.0;
  final color = colorHex.replaceAll('#', '');
  return '::::cue\n'
      '{\n'
      '  font-size: ${size.toStringAsFixed(2)}em;\n'
      '  color: #$color;\n'
      '  background-color: rgba(0,0,0,${bg.toStringAsFixed(2)});\n'
      '  vertical-align: bottom;\n'
      '}\n';
}
