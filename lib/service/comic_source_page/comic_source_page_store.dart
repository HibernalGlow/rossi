import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:zephyr/util/get_path.dart';

/// 图源插件在**列表项**里交出来的原站页面链接，宿主按 `图源:漫画 id` 记下来。
///
/// 为什么要宿主记一份：插件的**详情** payload 里一般没有面向人的页面地址
/// （协议里那些 `url` 字段全是封面/图片资源），只有列表项的 `extern` 里偶尔带
/// （EH 给的是 `href`）。而详情页同时是收藏 / 历史 / 下载的入口，那会儿手上只有
/// `source + comicId`，链接只能趁解析列表的时候先存下来 —— 不改任何插件。
///
/// 存文件而不是 ObjectBox：这是**可重建的便利缓存**（记丢了下次浏览列表就补回来），
/// 不值得为它动库结构与迁移。
class ComicSourcePageStore {
  ComicSourcePageStore({Future<String> Function()? directory})
    : _directory = directory ?? getFilePath;

  static final ComicSourcePageStore instance = ComicSourcePageStore();

  static const String fileName = 'comic_source_pages.json';

  /// 最多记多少条。
  ///
  /// 落盘是**整份重写**，所以不设上限会变成「用得越久、每次写盘越慢」；
  /// Dart 的 Map 保持插入顺序，于是淘汰就是丢最早记的那批 —— 最早的那些通常也
  /// 是最早不再看的。
  static const int maxEntries = 5000;

  /// 认这些键 —— 它们在插件里都表示「这一本书在原站的页面」。
  ///
  /// **故意不认裸 `url`**：那个键在插件侧通常是封面或图片资源地址，
  /// 认它等于把「跳到原站」变成「跳到一张图」。
  static const List<String> externUrlKeys = <String>[
    'href',
    'webUrl',
    'pageUrl',
    'sourcePageUrl',
    'sourceUrl',
    'galleryUrl',
  ];

  final Future<String> Function() _directory;

  final Map<String, String> _urls = <String, String>{};

  /// 记一次「正在/已经读盘」的 Future，让并发调用**等同一次读完**。
  ///
  /// 不能只置一个 `bool`：那样 `flush` 会在读还没回来时先写盘，
  /// 把整份历史覆盖成只剩刚记的那几条。
  Future<void>? _loadFuture;
  bool _dirty = false;
  Timer? _debounce;

  static String keyOf(String source, String comicId) => '$source:$comicId';

  /// 从插件给的 `extern` 里挑出页面链接；没有就给空串（调用方据此决定按钮出不出现）。
  static String urlFromExtern(Map<String, dynamic>? extern) {
    if (extern == null) {
      return '';
    }
    for (final key in externUrlKeys) {
      final value = extern[key]?.toString().trim() ?? '';
      if (_looksLikePageUrl(value)) {
        return value;
      }
    }
    return '';
  }

  static bool _looksLikePageUrl(String value) =>
      value.startsWith('http://') || value.startsWith('https://');

  /// 已记下的链接；没有返回空串。
  ///
  /// 只读内存，所以调用方必须先 [load]（详情页在 `initState` 里 await 它）。
  String urlOf(String source, String comicId) =>
      _urls[keyOf(source, comicId)] ?? '';

  /// 读一次盘，幂等。
  ///
  /// 读不出来就当没记过：这份缓存只是便利，不该让详情页起不来。
  /// 磁盘上已有的链接**不会覆盖**内存里新记的值（先记后读的场景）。
  Future<void> load() => _loadFuture ??= _readFromDisk();

  Future<void> _readFromDisk() async {
    try {
      final file = File(p.join(await _directory(), fileName));
      if (!await file.exists()) {
        return;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        decoded.forEach((rawKey, rawValue) {
          final key = rawKey?.toString().trim() ?? '';
          final url = rawValue?.toString().trim() ?? '';
          if (key.isEmpty || !_looksLikePageUrl(url)) {
            return;
          }
          _urls.putIfAbsent(key, () => url);
        });
      }
    } on Object {
      // 手改坏的 JSON 抛 FormatException，路径不可用抛 IOException —— 都不该往上冒。
    }
  }

  /// 记住「这个 id 在原站是这一页」。
  ///
  /// 只有 `extern` 里确实有页面链接时才写；空写入直接返回，所以整页搜索结果
  /// 喂进来也不会产生一次落盘。
  void remember({
    required String source,
    required String comicId,
    required Map<String, dynamic>? extern,
  }) {
    rememberUrl(source: source, comicId: comicId, url: urlFromExtern(extern));
  }

  void rememberUrl({
    required String source,
    required String comicId,
    required String url,
  }) {
    final trimmedSource = source.trim();
    final trimmedId = comicId.trim();
    final trimmedUrl = url.trim();
    if (trimmedSource.isEmpty ||
        trimmedId.isEmpty ||
        !_looksLikePageUrl(trimmedUrl)) {
      return;
    }
    final key = keyOf(trimmedSource, trimmedId);
    if (_urls[key] == trimmedUrl) {
      return;
    }
    _urls[key] = trimmedUrl;
    while (_urls.length > maxEntries) {
      _urls.remove(_urls.keys.first);
    }
    _scheduleFlush();
  }

  /// 连续记只落一次盘：一页搜索结果几十个条目，逐条写盘没有意义。
  void _scheduleFlush() {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), flush);
  }

  Future<void> flush() async {
    _debounce?.cancel();
    _debounce = null;
    if (!_dirty) {
      return;
    }
    // 落盘前先把旧内容读齐，否则「启动后第一批列表」会把整份历史覆盖成只有新的几条。
    await load();
    _dirty = false;
    try {
      final dirPath = await _directory();
      final tempFile = File(p.join(dirPath, '$fileName.tmp'));
      await tempFile.writeAsString(jsonEncode(_urls), flush: true);
      await tempFile.rename(p.join(dirPath, fileName));
    } on Object {
      // 写失败＝这次没记住，下次浏览列表还会再记一遍。
    }
  }
}
