import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/src/rust/api/margin_fit.dart';

/// 每页内容矩形的缓存：同一页只分析一次，不在每帧重数几百万像素。
///
/// 键是 `(来源对象, 页序, 像素宽高, 容差)`。四样都在，所以
/// - 换书 / 换源 / 换章必然换键，**不会把上一页的裁切套到下一页**；
/// - 源图变了（重新下载、超分换尺寸、降采样宽度不同）换键，旧值自然失效；
/// - 同一页同一尺寸的重复请求直接命中，翻页来回不重算。
///
/// 键里用的是 `identityHashCode(source)`，而这个 map **强引用着 source 本身**
/// （见 [_Entry.source]）：对象还活着，它的身份哈希就不可能被别人复用。
/// 少了这条强引用，「GC 回收后哈希被新来源复用」会让键撞上另一本书的同页同尺寸，
/// 表现就是**这一页被按别人的内容矩形裁了** —— 那是切掉画面的事故，不是缓存未命中。
///
/// 上限 512 条是刻意的：一条记录 16 字节加一个来源对象引用，而一次阅读会话理论上
/// 无界，所以给硬上限按 LRU 淘汰，而不是无限增长。
class MarginFitCache {
  static const int maxEntries = 512;

  static final MarginFitCache instance = MarginFitCache._();

  MarginFitCache._();

  final LinkedHashMap<String, _Entry> _entries = LinkedHashMap();

  /// 已发起、还没回来的分析（按缓存键）。
  ///
  /// 没有这张表，同一页会被位图路与纹理路各问一次，或在 widget 重建时反复排队 ——
  /// 检测一次几十毫秒，重复排队纯粹浪费。
  final Map<String, Future<Rect?>> _inFlight = {};

  /// 取这一页的内容矩形；没缓存就现算一次。
  ///
  /// 返回 `null` 表示**这一页不要裁**（满版出血、灰色背景、检测自己说不可靠）。
  /// 调用方必须按原样显示，不许回退成任何猜测的矩形。
  Future<Rect?> bboxFor({
    required PageSource source,
    required int pageIndex,
    required Uint8List rgba,
    required int width,
    required int height,
    int? tolerance,
  }) {
    final String key = _keyFor(source, pageIndex, width, height, tolerance);
    final _Entry? hit = _entries[key];
    if (hit != null) {
      // 触碰一下，维持 LRU 顺序。
      _entries.remove(key);
      _entries[key] = hit;
      return Future<Rect?>.value(hit.rect);
    }
    final Future<Rect?>? pending = _inFlight[key];
    if (pending != null) return pending;

    final Future<Rect?> work = _detect(
      key,
      source,
      rgba,
      width,
      height,
      tolerance,
    );
    _inFlight[key] = work;
    return work;
  }

  Future<Rect?> _detect(
    String key,
    PageSource source,
    Uint8List rgba,
    int width,
    int height,
    int? tolerance,
  ) async {
    try {
      final ContentBBox? box = await detectPageContentBbox(
        rgba: rgba,
        width: width,
        height: height,
        tolerance: tolerance,
      );
      final Rect? rect = box == null
          ? null
          : Rect.fromLTRB(box.left, box.top, box.right, box.bottom);
      _put(key, _Entry(source, rect));
      return rect;
    } finally {
      _inFlight.remove(key);
    }
  }

  void _put(String key, _Entry entry) {
    _entries[key] = entry;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  static String _keyFor(
    PageSource source,
    int pageIndex,
    int width,
    int height,
    int? tolerance,
  ) =>
      '${identityHashCode(source)}|$pageIndex|$width x $height|tol=${tolerance ?? 'd'}';

  /// 换源、重开这一本时清掉整份（不必须，只是别让上一本的记录占着上限）。
  void clear() {
    _entries.clear();
    _inFlight.clear();
  }

  int get length => _entries.length;
}

class _Entry {
  /// 强引用来源，保住它的身份哈希不被复用（见类注释）。
  final PageSource source;

  /// `null` = 这一页检测过了，答案是「不裁」。
  final Rect? rect;

  const _Entry(this.source, this.rect);
}
