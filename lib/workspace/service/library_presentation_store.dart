import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/workspace/model/library_presentation_preferences.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';

class LibraryPresentationChange {
  const LibraryPresentationChange(this.scope, this.presentation, {this.origin});

  final String scope;
  final LibraryPresentation presentation;
  final Object? origin;
}

/// 沿用各位置原来的键；所有写入共用队列，同步后通知在场的展墙。
class LibraryPresentationStore {
  LibraryPresentationStore({int Function()? now})
    : _now = now ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch);

  static final instance = LibraryPresentationStore();
  static const prefix = 'rossi.library.presentation.';
  static const _metaKey = 'rossi.library.presentationMeta.v1';

  final int Function() _now;
  final _changes = StreamController<LibraryPresentationChange>.broadcast(
    sync: true,
  );
  Future<void>? _pending;

  Stream<LibraryPresentationChange> get changes => _changes.stream;

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _pending?.then((_) => operation()) ?? operation();
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pending = tail;
    unawaited(
      tail.then((_) {
        if (identical(_pending, tail)) _pending = null;
      }),
    );
    return result;
  }

  Future<LibraryPresentation?> read(String scope) => _serial(() async {
    final prefs = await SharedPreferences.getInstance();
    return _read(prefs, scope);
  });

  LibraryPresentation? _read(SharedPreferences prefs, String scope) {
    try {
      final raw = prefs.get('$prefix$scope');
      return raw is String
          ? LibraryPresentationPreferences.parsePresentation(jsonDecode(raw))
          : null;
    } on Object {
      return null;
    }
  }

  Map<String, int> _timestamps(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_metaKey);
      final json = raw == null ? null : jsonDecode(raw);
      return {
        if (json is Map)
          for (final entry in json.entries)
            if (entry.key is String && entry.value is int && entry.value >= 0)
              entry.key as String: entry.value as int,
      };
    } on Object {
      return {};
    }
  }

  Future<void> _write(SharedPreferences prefs, String key, String value) async {
    if (!await prefs.setString(key, value)) {
      throw StateError('展墙设置写入失败: $key');
    }
  }

  Future<void> save(
    String scope,
    LibraryPresentation presentation, {
    Object? origin,
  }) => _serial(() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamps = _timestamps(prefs);
    final previous = _read(prefs, scope);
    final content = LibraryPresentationPreferences.content(presentation);
    if (previous != null &&
        LibraryPresentationPreferences.content(previous) == content &&
        timestamps.containsKey(scope)) {
      return;
    }
    final now = _now();
    final previousTime = timestamps[scope] ?? -1;
    timestamps[scope] = now > previousTime ? now : previousTime + 1;
    await _write(prefs, '$prefix$scope', content);
    await _write(prefs, _metaKey, jsonEncode(timestamps));
    _changes.add(
      LibraryPresentationChange(scope, presentation, origin: origin),
    );
  });

  Future<Map<String, LibraryPresentationPreference>> readAll() =>
      _serial(() async {
        final prefs = await SharedPreferences.getInstance();
        final timestamps = _timestamps(prefs);
        final result = <String, LibraryPresentationPreference>{};
        var migrated = false;
        for (final key in prefs.getKeys().where(
          (key) => key.startsWith(prefix),
        )) {
          final scope = key.substring(prefix.length);
          if (scope.isEmpty) continue;
          final presentation = _read(prefs, scope);
          if (presentation == null) continue;
          if (!timestamps.containsKey(scope)) {
            // 旧版只有设置没有时钟；迁移一次，后续同步不再刷新时间。
            timestamps[scope] = _now();
            migrated = true;
          }
          result[scope] = LibraryPresentationPreference(
            presentation,
            timestamps[scope]!,
          );
        }
        if (migrated) await _write(prefs, _metaKey, jsonEncode(timestamps));
        return result;
      });

  Future<void> apply(
    Map<String, LibraryPresentationPreference> incoming, {
    bool force = false,
  }) => _serial(() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamps = _timestamps(prefs);
    final changes = <LibraryPresentationChange>[];
    for (final entry in incoming.entries) {
      final scope = entry.key;
      final previous = _read(prefs, scope);
      final current = previous == null
          ? <String, LibraryPresentationPreference>{}
          : {
              scope: LibraryPresentationPreference(
                previous,
                timestamps[scope] ?? 0,
              ),
            };
      // 网络请求期间的新修改也参与比较，不被请求开始时的快照盖回去。
      final chosen = force
          ? entry.value
          : LibraryPresentationPreferences.merge(current, {
              scope: entry.value,
            })[scope]!;
      timestamps[scope] = chosen.updatedAt;
      final content = LibraryPresentationPreferences.content(
        chosen.presentation,
      );
      if (previous == null ||
          LibraryPresentationPreferences.content(previous) != content) {
        await _write(prefs, '$prefix$scope', content);
        changes.add(LibraryPresentationChange(scope, chosen.presentation));
      }
    }
    await _write(prefs, _metaKey, jsonEncode(timestamps));
    changes.forEach(_changes.add);
  });
}
