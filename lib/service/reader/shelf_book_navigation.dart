import 'package:zephyr/type/enum.dart';

/// 书签、历史、下载列表共用的阅读顺序上下文。
class ShelfBookNavigationEntry {
  const ShelfBookNavigationEntry({
    required this.key,
    required this.comicId,
    required this.from,
    required this.type,
  });

  final String key;
  final String comicId;
  final String from;
  final ComicEntryType type;

  String get identity => shelfBookNavigationIdentity(from, comicId);
}

String shelfBookNavigationIdentity(String from, String comicId) =>
    '${from.trim()}:${comicId.trim()}';

class ShelfBookNavigationRegistry {
  ShelfBookNavigationRegistry._();

  static final instance = ShelfBookNavigationRegistry._();
  static const contextKey = 'shelfBookNavigationToken';

  final _byScope = <String, String>{};
  final _entries = <String, List<ShelfBookNavigationEntry>>{};
  var _serial = 0;

  String register({
    required String scope,
    required List<ShelfBookNavigationEntry> entries,
  }) {
    final old = _byScope[scope];
    if (old != null) _entries.remove(old);
    final token = '$scope:${++_serial}';
    _byScope[scope] = token;
    _entries[token] = List.unmodifiable(entries);
    return token;
  }

  List<ShelfBookNavigationEntry>? lookup(String? token) {
    if (token == null || token.isEmpty) return null;
    return _entries[token];
  }
}

/// 阅读器中的“上一本 / 下一本”控制器。
class ShelfBookNavigationController {
  ShelfBookNavigationController({
    required this.entries,
    required this.currentKey,
    required this.open,
    required this.notify,
  });

  final List<ShelfBookNavigationEntry> entries;
  final String currentKey;
  final Future<void> Function(ShelfBookNavigationEntry entry) open;
  final void Function(String message) notify;

  bool _busy = false;
  bool _disposed = false;

  int get _index => entries.indexWhere((entry) => entry.key == currentKey);

  bool get canGoPrevious => _index > 0;

  bool get canGoNext => _index >= 0 && _index < entries.length - 1;

  Future<void> switchBook(bool forward) async {
    if (_busy || _disposed) return;
    final index = _index;
    if (index < 0) return;
    final targetIndex = forward ? index + 1 : index - 1;
    if (targetIndex < 0 || targetIndex >= entries.length) {
      notify(forward ? '已经是最后一本书' : '已经是第一本书');
      return;
    }
    _busy = true;
    try {
      await open(entries[targetIndex]);
    } finally {
      _busy = false;
    }
  }

  void dispose() => _disposed = true;
}
