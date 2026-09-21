/// 媒体身份判定：一个条目名到底是静态图、动图还是视频。
///
/// 逐条翻译自 neoview `packages/nodes/neoview/src/domain/page/media.ts`
/// （扩展名 / MIME 注册表、`resolve` / `supports`、伪装后缀）。
/// 纯逻辑，不带 Flutter 依赖，因此可在 `flutter test` 里逐条对照上游。
library;

/// 一页（一个条目）的媒体种类。
///
/// 与 neoview `PageMediaKind`（`domain/page/page.ts:5`）同名同集合，
/// 差别只有 `documentPage` 在本项目里还没接入 —— 保留它是因为
/// `mediaKindOf` 的返回值要能区分「不认识」与「是文档页」。
enum RossiMediaKind { image, animatedImage, video, documentPage }

/// 静态图扩展名（不含点、小写）。
///
/// `gif` 不在这里：上游把动图单列一档（`media.ts:78`），因为「一页 = 一段循环画面」
/// 与「一页 = 一张静态图」在阅读路径上是两回事。
const Set<String> imageExtensions = <String>{
  'jpg',
  'jpeg',
  'png',
  'webp',
  'bmp',
  'tif',
  'tiff',
  'avif',
  'jxl',
  'heic',
  'heif',
};

/// 动图扩展名：走 `animated-image` 档，可以被「动图当视频播」那条开关接管。
const Set<String> animatedImageExtensions = <String>{'gif', 'apng'};

/// 视频扩展名。
///
/// 并集口径：**neoview `media.ts:17-33` 为主**，再补 mImageViewer
/// `folder_tree.rs:81` 的 `SUPPORTED_VIDEO_EXTENSIONS`（那份表里独有 `wmv` 已在、
/// 缺 `webm/m4v/ogv/3gp/3g2/flv/mpeg/mpg` —— 上游那份是「扫到就列」的白名单，
/// 本表是「列出来就要能播」的白名单，所以取并集后要逐条验能播才留下）。
const Set<String> videoExtensions = <String>{
  '3g2',
  '3gp',
  'avi',
  'flv',
  'm4v',
  'mkv',
  'mov',
  'mp4',
  'mpeg',
  'mpg',
  'nov',
  'ogg',
  'ogv',
  'webm',
  'wmv',
};

/// MIME 猜测表，与 neoview 一样只在「需要给外部一个类型」时用。
String mimeTypeForExtension(String ext) => switch (ext) {
  'mp4' || 'm4v' || 'nov' => 'video/mp4',
  'mkv' => 'video/x-matroska',
  'webm' => 'video/webm',
  'mov' => 'video/quicktime',
  'avi' => 'video/x-msvideo',
  'wmv' => 'video/x-ms-wmv',
  'flv' => 'video/x-flv',
  'ogv' || 'ogg' => 'video/ogg',
  'mpg' || 'mpeg' => 'video/mpeg',
  '3gp' || '3g2' => 'video/3gpp',
  'gif' => 'image/gif',
  'apng' => 'image/apng',
  'webp' || 'wbp' => 'image/webp',
  'png' => 'image/png',
  'jpg' || 'jpeg' => 'image/jpeg',
  _ => 'application/octet-stream',
};

/// **伪装后缀**：扩展名写着 A、内容其实是 B。
///
/// 上游 `media.ts:35,144-152` 的规则是「**先按原始后缀解析**」——
/// 因为图源会把 mp4 改名成 `.nov` 以躲开平台限制，反过来 `.wbp` 其实是 webp。
const Map<String, String> disguisedExtensions = <String, String>{
  'nov': 'mp4',
  'wbp': 'webp',
};

/// 用户自定义「额外视频后缀」的登记表。
///
/// 为什么是登记表而不是逐处传参：同一条判定有 **5 个使用点**（页序、封面、
/// 页列表缩略图、文件管理器、播放页）。把设置签名传到每一个调用点，
/// 漏掉一处的后果不是「别名不生效」这么轻 —— 而是封面会把那个 mp4 的
/// 头几十字节当图片字节写进按路径哈希的封面缓存，症状是封面永久白图。
/// 形态与仓里既有的 `LocalReadSession.instance` / `ActiveVideoScope.instance` 一致。
class VideoAliasRegistry {
  VideoAliasRegistry._();

  static final VideoAliasRegistry instance = VideoAliasRegistry._();

  List<String> _extra = const <String>[];

  List<String> get extraVideoExtensions => _extra;

  /// 由 `VideoSettingsStore` 在每次读到设置时刷新。
  void update(List<String> extra) {
    _extra = extra
        .map((e) => e.trim().toLowerCase())
        .where(
          (e) => e.isNotEmpty && e.length <= MediaKindOverrides._maxAliasLength,
        )
        .toList(growable: false);
  }
}

/// 用户自定义扩展名别名（neoview 的 `formatAlias` 设置）的上位约束。
class MediaKindOverrides {
  const MediaKindOverrides({this.extraVideoExtensions = const <String>[]});

  static const MediaKindOverrides none = MediaKindOverrides();

  final List<String> extraVideoExtensions;

  /// 生效的别名 = 显式传入的 ∪ 登记表里的。
  ///
  /// 取并集而不是覆盖：测试与调用方显式传参时要优先它自己的值，
  /// 但生产路径上那 5 个调用点大多不传，得靠登记表兜住。
  Set<String> effective() => <String>{
    ...extraVideoExtensions.map((e) => e.trim().toLowerCase()),
    ...VideoAliasRegistry.instance.extraVideoExtensions,
  }..removeWhere((e) => e.isEmpty);

  /// 校验规则照抄 neoview `media.ts:80-85`：
  /// 最多 128 条、每条最长 16 字符、**不许与图片档重叠**。
  ///
  /// 「不许重叠」不是为了好看：一个后缀同时命中两档，页序里它就会被随机路由，
  /// 而「同一本书每次打开页数不一样」是最难查的那类 bug。
  List<String> get invalidEntries {
    final problems = <String>[];
    if (extraVideoExtensions.length > _maxAliasCount) {
      problems.add('视频后缀最多 $_maxAliasCount 条');
    }
    // 按去重后的集合报错：列表里写了两遍 `png` 不该在设置页刷两条同样的提示。
    for (final raw in extraVideoExtensions.toSet()) {
      final ext = raw.trim().toLowerCase();
      if (ext.isEmpty) {
        problems.add('存在空后缀');
        continue;
      }
      if (ext.length > _maxAliasLength) {
        problems.add('$ext 超过 $_maxAliasLength 个字符');
      }
      if (imageExtensions.contains(ext) ||
          animatedImageExtensions.contains(ext)) {
        problems.add('$ext 已经是图片后缀');
      }
    }
    return problems;
  }

  static const int _maxAliasCount = 128;
  static const int _maxAliasLength = 16;
}

/// 取小写后缀（不含点）。目录名里的点不能当成后缀，所以要求最后一个 `.`
/// 在最后一个路径分隔符之后 —— 与 Rust 侧 `page_order.rs:111 extension_lower` 同一条判断。
String? extensionLower(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return null;
  final lastSep = name.lastIndexOf(RegExp(r'[/\\]'));
  if (dot < lastSep) return null;
  final ext = name.substring(dot + 1).toLowerCase();
  return ext.isEmpty ? null : ext;
}

/// 是否为视频条目（含伪装后缀与用户别名）。
bool isVideoName(
  String name, [
  MediaKindOverrides overrides = MediaKindOverrides.none,
]) => mediaKindOf(name, overrides) == RossiMediaKind.video;

bool isImageName(
  String name, [
  MediaKindOverrides overrides = MediaKindOverrides.none,
]) {
  final ext = extensionLower(name);
  if (ext == null) return false;
  final resolved = disguisedExtensions[ext] ?? ext;
  // 别名优先于图片表：用户把一个后缀明确声明成视频时，
  // 「它看起来像图片」不该赢 —— 否则别名功能在最常见的一处（页序）就失效了。
  if (overrides.effective().contains(resolved)) return false;
  return imageExtensions.contains(resolved);
}

/// 条目名 → 媒体种类。认不出来返回 `null`（**不算一页**）。
RossiMediaKind? mediaKindOf(
  String name, [
  MediaKindOverrides overrides = MediaKindOverrides.none,
]) {
  final ext = extensionLower(name);
  if (ext == null) return null;
  final resolved = disguisedExtensions[ext] ?? ext;
  if (animatedImageExtensions.contains(resolved) || resolved == 'webp') {
    // webp 可能是动图也可能是静图。上游同样按「动图档」处理它：
    // 静图 webp 走动图路径只是白拿一帧，反过来的错误是「动图只画第一帧」。
    return resolved == 'gif' || resolved == 'apng'
        ? RossiMediaKind.animatedImage
        : RossiMediaKind.image;
  }
  if (imageExtensions.contains(resolved)) return RossiMediaKind.image;
  if (videoExtensions.contains(resolved)) return RossiMediaKind.video;
  if (overrides.effective().contains(resolved)) {
    return RossiMediaKind.video;
  }
  return null;
}
