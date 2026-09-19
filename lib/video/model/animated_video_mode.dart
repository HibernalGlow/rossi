/// 「动图当视频播」的判定 —— 逐行翻译自 neoview
/// `packages/nodes/neoview/src/application/animated-video/ReaderAnimatedVideoMode.ts:3-59`
/// 与 `features/reader/animated-image-video-mode.ts:5-18`。
///
/// 语义：GIF / APNG / 动图 WebP 平时是「一页静态内容」，但打开这条开关后，
/// 命中关键字（默认 `[#dyna]`）或命中动图后缀的页改走视频控制器 ——
/// 于是它们获得暂停 / 逐帧 / 循环 / 进度拖动，也就是「运动页」。
/// 上游默认关闭，这里同样默认关闭：不改设置时行为与改造前逐字一致。
library;

import 'package:zephyr/video/model/video_media_kind.dart';

/// 归一化关键字：去空白、去方括号、小写。
///
/// 上游做归一化是因为关键字**既可以写成 `[#dyna]` 也可以写成 `#dyna`**，
/// 而文件名里通常只剩后者；不归一化的话用户按设置页的写法填进去就永远命不中。
String normalizeAnimatedVideoKeyword(String raw) {
  var text = raw.trim().toLowerCase();
  if (text.startsWith('[') && text.endsWith(']')) {
    text = text.substring(1, text.length - 1).trim();
  }
  return text;
}

/// 这个条目名是否要「当视频播」。
///
/// 命中条件（与上游一致，顺序也一致）：
/// 1. 开关关闭 ⇒ 一律 false；
/// 2. 名字里含任一关键字 ⇒ true（不看后缀，因为 `[#dyna]` 标记的就是「这页会动」）；
/// 3. 后缀是动图（gif / apng）⇒ true；
/// 4. 其余 ⇒ false。**webp 不在自动命中里**：静图 webp 远比动图多，
///    自动接管会把整本的正常页换成播放器，上游同样只让它走关键字。
bool shouldOpenAnimatedImageAsVideo(
  String name, {
  required bool enabled,
  List<String> keywords = const <String>['[#dyna]'],
  List<String> extraExtensions = const <String>[],
}) {
  if (!enabled) return false;
  final lower = name.toLowerCase();
  for (final raw in keywords) {
    final keyword = normalizeAnimatedVideoKeyword(raw);
    if (keyword.isEmpty) continue;
    if (lower.contains(keyword)) return true;
  }
  final ext = extensionLower(name);
  if (ext == null) return false;
  final resolved = disguisedExtensions[ext] ?? ext;
  if (animatedImageExtensions.contains(resolved)) return true;
  return extraExtensions.map((e) => e.trim().toLowerCase()).contains(resolved);
}

/// 动图当视频播时的页种类标签（信息卡与调试要看得出它不是真视频文件）。
RossiMediaKind motionPageKindOf(String name) =>
    mediaKindOf(name) ?? RossiMediaKind.image;
