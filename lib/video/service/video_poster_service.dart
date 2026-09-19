/// 视频海报帧（缩略图）—— 上游对应 mImageViewer 的 `video/thumbnail.rs`
/// 与 neoview 的 `platform/video/FfmpegVideoThumbnailProvider.ts`。
///
/// 两条上游都用「独立解码器 + 磁盘缓存 + 按 (路径,修改时间,大小) 失效」的形状，
/// Rossi 侧的差别只在解码器：B4 边界不许 ffmpeg 进 `local_core`，
/// 所以取帧走**已经在依赖树里的 libmpv**（`Player.screenshot()` 直接回字节，
/// 不需要窗口、不需要落盘中转）。
///
/// 为什么不并发起多个播放器：mpv 实例不是免费的（每个十几 MB + 一条解码线程），
/// 而书群一次滚动就要二十张图。所以这里是**单槽位串行**（同 mimage 的
/// `seek_strip_thumbs` worker 与 neo 的 `VideoProcessScheduler`），
/// 队列里只保留最新一个待办。
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:zephyr/util/get_path.dart';

class VideoPoster {
  const VideoPoster({required this.bytes, required this.path});

  final Uint8List bytes;
  final String path;
}

class VideoPosterService {
  VideoPosterService({this.captureAt = const Duration(milliseconds: 500)});

  /// 单例：书群里几十个卡片共用一条串行队列才有意义。
  static final VideoPosterService instance = VideoPosterService();

  /// 取帧位置。不是 0：**很多容器/编码器第 0 帧是全黑或片头 logo**，
  /// 上游 `thumbnail=30`（选 motion 最少的帧）解决的是同一件事，
  /// 在没有滤镜可用的前提下，往后挪半秒是成本最低的等效做法。
  final Duration captureAt;

  static const int _memoryCacheEntries = 64;
  final LinkedHashMap<String, Uint8List> _memory =
      LinkedHashMap<String, Uint8List>();
  final Map<String, Future<Uint8List?>> _inFlight =
      <String, Future<Uint8List?>>{};

  Player? _player;
  bool _busy = false;
  Timer? _idleDispose;
  int _serial = 0;

  /// 磁盘缓存目录。放 `getCachePath()` 下：这是**可再生**的数据，
  /// 「设置→清缓存」把它一起清掉是正确行为（下次滚动会重新生成）。
  Future<String> _cacheDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'rossi-video-posters'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  /// 缓存键带 `(mtime, size)`：mimage 与 neo 都是这么做的，
  /// 因为**文件名会重复、内容会变**（重新下载、覆盖写）。
  static String cacheKeyFor(String path, int mtimeMs, int size) =>
      '${sha1ish('$path|$mtimeMs|$size')}.jpg';

  Future<Uint8List?> posterForFile(String videoPath) async {
    final file = File(videoPath);
    if (!await file.exists()) return null;
    final stat = await file.stat();
    final key = cacheKeyFor(videoPath, stat.modified.millisecondsSinceEpoch, stat.size);

    final mem = _memory[key];
    if (mem != null) return mem;

    final dir = await _cacheDir();
    final disk = File(p.join(dir, key));
    if (await disk.exists()) {
      try {
        final bytes = await disk.readAsBytes();
        if (bytes.isNotEmpty) {
          _remember(key, bytes);
          return bytes;
        }
      } on FileSystemException {
        // 半截文件：当没缓存，往下重新生成。
      }
    }

    final pending = _inFlight[key];
    if (pending != null) return pending;

    final work = _capture(videoPath, key, disk);
    _inFlight[key] = work;
    try {
      return await work;
    } finally {
      _inFlight.remove(key);
    }
  }

  /// 归档里的视频条目：先把字节物化（复用 `VideoMaterializer` 的调用方语义），
  /// 再走同一条取帧路。这里只接收一个已经落成磁盘的路径，避免依赖 FFI。
  Future<Uint8List?> posterForBytes({
    required String identityKey,
    required Future<Uint8List> Function() readBytes,
  }) async {
    if (_memory[identityKey] != null) return _memory[identityKey];
    final dir = await _cacheDir();
    final disk = File(p.join(dir, '$identityKey.jpg'));
    if (await disk.exists() && await disk.length() > 0) {
      final bytes = await disk.readAsBytes();
      _remember(identityKey, bytes);
      return bytes;
    }
    final work = _serialize(() async {
      final temp = File(p.join(dir, '.tmp_${_serial++}.bin'));
      try {
        await temp.writeAsBytes(await readBytes(), flush: true);
        final bytes = await _captureBytes(temp.path);
        if (bytes != null) await disk.writeAsBytes(bytes, flush: true);
        return bytes;
      } finally {
        try {
          await temp.delete();
        } catch (_) {}
      }
    });
    _inFlight[identityKey] = work;
    try {
      return await work;
    } finally {
      _inFlight.remove(identityKey);
    }
  }

  Future<Uint8List?> _capture(
    String videoPath,
    String key,
    File disk,
  ) => _serialize(() async {
    final bytes = await _captureBytes(videoPath);
    if (bytes != null) {
      try {
        await disk.writeAsBytes(bytes, flush: true);
      } on FileSystemException {
        // 落盘失败不影响本次返回。
      }
      _remember(key, bytes);
    }
    return bytes;
  });

  Future<Uint8List?> _serialize(Future<Uint8List?> Function() work) async {
    while (_busy) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    _busy = true;
    try {
      return await work();
    } finally {
      _busy = false;
      _idleDispose?.cancel();
      // 空闲 60 s 再把 mpv 实例放掉：滚动列表是 bursts，逐张创建/销毁最浪费。
      _idleDispose = Timer(const Duration(seconds: 60), () async {
        final player = _player;
        _player = null;
        await player?.dispose();
      });
    }
  }

  Future<Uint8List?> _captureBytes(String videoPath) async {
    MediaKit.ensureInitialized();
    final player = _player ??= Player(
      configuration: const PlayerConfiguration(
        // 海报是给列表看的，不需要音频输出设备，也不需要缓存读满整个文件。
        title: 'rossi-video-poster',
      ),
    );
    try {
      await player.open(Media(_uri(videoPath)), play: false);
      // 等时长出现再定位：很多容器 `duration` 比第一帧晚到，
      // 直接 seek 到 500 ms 在时长未知的情况下会被吞掉。
      await player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 5));
      final target = captureAt < player.state.duration
          ? captureAt
          : player.state.duration ~/ 4;
      await player.seek(target);
      // 首帧真正解出来才能截到图：等 videoParams 出现，截不到退化成 10 帧间隔重试。
      await player.stream.videoParams
          .firstWhere((v) => (v.w ?? 0) > 0)
          .timeout(const Duration(seconds: 5));
      for (var attempt = 0; attempt < 4; attempt++) {
        final shot = await player.screenshot();
        if (shot != null && shot.isNotEmpty) return shot;
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      try {
        await player.stop();
      } catch (_) {}
    }
  }

  String _uri(String path) => 'file://${Uri.file(path).path}';

  void _remember(String key, Uint8List bytes) {
    _memory[key] = bytes;
    while (_memory.length > _memoryCacheEntries) {
      _memory.remove(_memory.keys.first);
    }
  }

  Future<void> shutdown() async {
    _idleDispose?.cancel();
    final player = _player;
    _player = null;
    await player?.dispose();
  }
}

/// 截图落盘的**下一个文件名**（含完整路径）。
///
/// 为什么不放在视频旁边：文件夹来源的视频就躺在用户的漫画库里，把
/// `screenshot_12-30-05.png` 写到它旁边等于往用户的内容目录里丢文件
/// （而且归档来源那条路会写进临时区，两种来源行为不一致）。
/// 统一落到应用自己的 documents 目录，与 neo 的「下载到用户目录」同构。
Future<String> nextVideoScreenshotPath({String ext = 'png'}) async {
  final base = await getFilePath();
  final dir = Directory(p.join(base, 'video_screenshots'));
  if (!await dir.exists()) await dir.create(recursive: true);
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return p.join(
    dir.path,
    'screenshot_${now.year}-${two(now.month)}-${two(now.day)}'
    '_${two(now.hour)}-${two(now.minute)}-${two(now.second)}.$ext',
  );
}

/// 没有引入 crypto 依赖也够用的短摘要：海报缓存键只要**稳定且唯一**，
/// 不承担安全语义。（同一份实现在 `VideoMaterializer` 里叫 sha1，那里已经带依赖。）
String sha1ish(String input) {
  var h1 = 0x67452301;
  var h2 = 0xefcdab89;
  for (final unit in input.codeUnits) {
    h1 = (h1 * 31 + unit) & 0x7FFFFFFF;
    h2 = (h2 * 37 + (unit ^ h1)) & 0x7FFFFFFF;
  }
  return '${h1.toRadixString(16).padLeft(8, '0')}${h2.toRadixString(16).padLeft(8, '0')}';
}
