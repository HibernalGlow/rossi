/// 「这一页会不会动」的判定 —— 纯逻辑，不 import Flutter。
///
/// 容器嗅探移植自 mImageViewer 的
/// `canonical_image_loader.rs::probe_static_animation`
/// （`apng_has_multiple_frames` / `webp_has_animation`），与 Rust 侧
/// `rust/local_core/src/animation.rs` 是同一条规则的**两份实现**：
/// 一份在拍平之前拦住在 Rust 里跑的那条（禁漫反混淆），一份拦住在 Dart 里跑的那条
/// （RealSR 超分、以及本地页的渲染路径选择）。改一处必须改另一处 ——
/// Rust 侧 `page_order::animated_name_table_matches_the_dart_side` 已经钉住后缀表，
/// 容器扫描这部分靠 `test/reader/page_animation_test.dart` 与
/// `animation.rs` 的同名夹具对拍。
library;

import 'dart:io';

import 'package:zephyr/video/model/video_media_kind.dart';

/// 嗅探需要读多少字节。
///
/// `acTL` 在 `IDAT` 之前、`ANIM`/`ANMF` 在帧数据之前，4 KiB 覆盖这两种排布。
/// 不够时一律答「不是动图」：宁可漏判一条动图（回到今天的行为 —— 画第一帧），
/// 也不能把一本静图误判成动图换掉整条渲染路径。
const int sniffHeadBytes = 4096;

/// 后缀本身就意味着「这一页是一段循环画面」。
///
/// 只有 `gif` 与 `apng`：neoview 的 `ANIMATED_IMAGE_EXTENSIONS` 就是这一对
/// （`features/reader/animated-image-video-mode.ts:11`）。
/// **`.wbp` 不在这里** —— 上游把它映射成 `image/webp`（`media.ts:13`），也就是
/// 「一颗改名的 WebP」而不是「一颗动图 WebP」；动图信号在上游是文件名里的
/// `[#dyna]` 关键字与 MIME，不是后缀。按后缀接管会把静图 webp 改名成 `.wbp`
/// 的条目也一并抬出 GPU 那条路。
const Set<String> animatedNameSuffixes = <String>{'gif', 'apng'};

/// 后缀就说得出「这一页会不会动」。
bool animatedByExtensionName(String name) {
  final ext = extensionLower(name);
  return ext != null && animatedNameSuffixes.contains(ext);
}

/// 后缀看不出静/动、必须查容器的档。
///
/// webp（含伪装后缀 wbp）与 png 的**静图远多于动图**：按名字接管等于把一整本的
/// 正常页从 GPU 上屏那条路挪走，那是回归而不是修复。
bool needsContainerProbe(String name) {
  final ext = extensionLower(name);
  if (ext == null) return false;
  const ambiguous = <String>{'webp', 'png'};
  return ambiguous.contains(disguisedExtensions[ext] ?? ext);
}

/// 只看容器结构判断「这是一段动图」；[head] 不必是完整文件。
bool animatedContainerHead(List<int> head) =>
    _apngHasMultipleFrames(head) || _webpHasAnimation(head);

/// 读文件头部并判定。读不到（文件没了 / 权限）答「不是动图」。
Future<bool> animatedFileHead(File file, [int bytes = sniffHeadBytes]) async {
  try {
    final raf = await file.open();
    try {
      return animatedContainerHead(await raf.read(bytes));
    } finally {
      await raf.close();
    }
  } catch (_) {
    return false;
  }
}

/// 本地的一页要不要走动图渲染路径。
///
/// [directPath] 是「这一页在磁盘上的直接路径」，归档内返回 `null`。
/// 归档**不做容器嗅探**：要查头部就得整条 inflate 再过桥，而这条判定服务的是
/// 翻页关键路径，代价比它买的东西大。归档里的动图因此只有按后缀认得出的
/// （gif / apng / wbp），动图 webp 与改名成 `.png` 的 APNG 会停在第一帧 ——
/// 取舍与影响面见 `docs/animated-image.md`。
Future<bool> localPageIsAnimated({
  required String name,
  required Future<String?> Function() directPath,
}) async {
  if (animatedByExtensionName(name)) return true;
  if (!needsContainerProbe(name)) return false;
  final path = await directPath();
  if (path == null) return false;
  return animatedFileHead(File(path));
}

bool _apngHasMultipleFrames(List<int> head) {
  const signature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (head.length < signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (head[i] != signature[i]) return false;
  }
  var rest = head.sublist(signature.length);
  int be32(List<int> b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  while (true) {
    // 块头 = 4 字节长度 + 4 字节类型。
    if (rest.length < 8) return false;
    final length = be32(rest, 0);
    final kind = rest.sublist(4, 8);
    var payload = rest.sublist(8);
    if (_fourcc(kind, 'acTL')) {
      // num_frames 是 acTL 的前 4 字节；单帧 acTL 与静图无异。
      if (length < 8 || payload.length < 4) return false;
      return be32(payload, 0) > 1;
    }
    // 走到这里 acTL 已经不可能出现（规范允许它的位置只在图像数据之前）。
    if (_fourcc(kind, 'IDAT') || _fourcc(kind, 'IEND')) return false;
    final skipped = length + 4; // + CRC
    if (payload.length < skipped) return false;
    payload = payload.sublist(skipped);
    rest = payload;
  }
}

bool _webpHasAnimation(List<int> head) {
  if (head.length < 12) return false;
  if (!_fourcc(head, 'RIFF', 0) || !_fourcc(head, 'WEBP', 8)) return false;
  int le32(List<int> b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
  var rest = head.sublist(12);
  while (rest.length >= 8) {
    final kind = rest.sublist(0, 4);
    final length = le32(rest, 4);
    final payload = rest.sublist(8);
    if (_fourcc(kind, 'ANIM') || _fourcc(kind, 'ANMF')) return true;
    // VP8X 的 flags 里 bit1 = animation。查标志位而不是只查块名，是因为
    // **ANIM 永远不在偏移 12**（仓库里原有那条判定即如此）：动图 WebP 的第一个
    // 块必须是 VP8X，而 ANMF 可能排在 4 KiB 头部之外。
    if (_fourcc(kind, 'VP8X')) {
      return payload.isNotEmpty && (payload[0] & 0x02) != 0;
    }
    final padded = length + (length & 1); // RIFF 块奇数长度补一字节
    if (payload.length < padded) return false;
    rest = payload.sublist(padded);
  }
  return false;
}

bool _fourcc(List<int> bytes, String fourcc, [int offset = 0]) {
  if (bytes.length < offset + 4) return false;
  for (var i = 0; i < 4; i++) {
    if (bytes[offset + i] != fourcc.codeUnitAt(i)) return false;
  }
  return true;
}
