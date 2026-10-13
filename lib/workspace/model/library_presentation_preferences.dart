import 'dart:convert';

import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';

/// 每个展示位置独立记时，避免在两端调整不同面板时互相覆盖。
class LibraryPresentationPreference {
  const LibraryPresentationPreference(this.presentation, this.updatedAt);

  final LibraryPresentation presentation;
  final int updatedAt;

  Map<String, dynamic> toJson() => {
    'updatedAt': updatedAt,
    'presentation': LibraryPresentationPreferences.presentationJson(
      presentation,
    ),
  };
}

abstract final class LibraryPresentationPreferences {
  static LibraryPresentation? parsePresentation(Object? raw) {
    if (raw is! Map || raw.keys.any((key) => key is! String)) return null;
    final json = Map<String, dynamic>.from(raw);
    final defaults = const LibraryPresentation().toJson();
    // 全是未知键或损坏值的记录不能变成一份默认设置覆盖本机。
    final usable =
        LibraryCoverTapAction.values.any(
          (action) => action.name == json['coverTapAction'],
        ) ||
        defaults.entries.any((entry) {
          final value = json[entry.key];
          return switch (entry.value) {
            bool _ => value is bool,
            num _ => value is num && value.isFinite,
            String _ => LibraryWeight.values.any(
              (weight) => weight.name == value,
            ),
            Map _ =>
              value is Map &&
                  value.entries.any(
                    (signal) =>
                        signal.key is String &&
                        signal.value is num &&
                        (signal.value as num).isFinite,
                  ),
            _ => false,
          };
        });
    return usable ? LibraryPresentation.fromJson(json) : null;
  }

  static Map<String, LibraryPresentationPreference> decode(Object? raw) {
    if (raw is! Map || raw['scopes'] is! Map) return {};
    final result = <String, LibraryPresentationPreference>{};
    for (final entry in (raw['scopes'] as Map).entries) {
      if (entry.key is! String || (entry.key as String).isEmpty) continue;
      final record = entry.value;
      if (record is! Map) continue;
      final timestamp = record['updatedAt'];
      if (timestamp is! int || timestamp < 0) continue;
      final presentation = parsePresentation(record['presentation']);
      if (presentation == null) continue;
      result[entry.key as String] = LibraryPresentationPreference(
        presentation,
        timestamp,
      );
    }
    return result;
  }

  static Map<String, dynamic> encode(
    Map<String, LibraryPresentationPreference> preferences,
  ) => {
    'scopes': {
      for (final scope in preferences.keys.toList()..sort())
        scope: preferences[scope]!.toJson(),
    },
  };

  static Map<String, LibraryPresentationPreference> merge(
    Map<String, LibraryPresentationPreference> local,
    Map<String, LibraryPresentationPreference> remote,
  ) {
    final merged = {...local};
    for (final entry in remote.entries) {
      final previous = merged[entry.key];
      final incoming = entry.value;
      if (previous == null ||
          incoming.updatedAt > previous.updatedAt ||
          (incoming.updatedAt == previous.updatedAt &&
              content(
                    incoming.presentation,
                  ).compareTo(content(previous.presentation)) >
                  0)) {
        merged[entry.key] = incoming;
      }
    }
    return merged;
  }

  /// 信号 Map 的插入顺序不能改变相同时间戳时的合并结果。
  static Map<String, Object> presentationJson(
    LibraryPresentation presentation,
  ) {
    final json = presentation.toJson();
    json['signalWeights'] = {
      for (final key in presentation.signalWeights.keys.toList()..sort())
        key: presentation.signalWeights[key]!,
    };
    return json;
  }

  static String content(LibraryPresentation presentation) =>
      jsonEncode(presentationJson(presentation));
}
