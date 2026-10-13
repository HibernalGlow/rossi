part of '../model.dart';

/// 单本漫画独立阅读设置（稀疏 patch，与全局共用一套 JSON 结构）。
///
/// [overridesJson] 只存用户显式改过的键（如 `{"readMode":2}`），键名与
/// `ReadSettingState.toJson()` 对齐；没有 key = 没设置 = 跟随全局。
/// 有记录且 [deleted] 为 false 表示启用了本漫特定设置；
/// 删除时清空 patch 并立 [deleted] 墓碑，靠 LWW 同步到其它设备。
/// 合并规则：unix 时间戳（[updatedAt]）更大的保留，与收藏/历史同一套 LWW。
@Entity()
@JsonSerializable()
class ComicReadPreference {
  @Id()
  int id;

  /// 复合唯一键：`$source:$comicId`，与历史/收藏保持一致。
  @Unique()
  String uniqueKey;

  String source;
  String comicId;

  /// 稀疏覆盖 JSON：只含显式设置的 `ReadSettingState` 键。
  String overridesJson;

  /// v12 前的单字段存储，已被 [overridesJson] 取代。
  ///
  /// 保留该列仅用于 v11→v12 存量迁移读取，读写一律走 [overridesJson]；
  /// 存量转完后的版本可删除此列。
  @Deprecated('由 overridesJson 取代，仅迁移读取使用')
  @JsonKey(includeToJson: false)
  int readMode;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  bool deleted;

  ComicReadPreference({
    this.id = 0,
    required this.uniqueKey,
    required this.source,
    required this.comicId,
    this.overridesJson = '{}',
    @Deprecated('由 overridesJson 取代，仅迁移读取使用') this.readMode = 0,
    required this.updatedAt,
    this.deleted = false,
  });

  /// 本漫独立设置：与全局共用一套 `ReadSettingState` 结构。
  ///
  /// 列里只存用户显式改过的键（稀疏，如 `{"readMode":2}`）；
  /// 返回 null 表示没有覆盖 = 跟随全局（含墓碑行）。
  /// record 的 `keys` 是精确的 key 集合：“有没有设置”看它，不看值。
  /// 脏数据兜底：解析失败返回 null。
  @Transient()
  @JsonKey(includeFromJson: false, includeToJson: false)
  ({ReadSettingState setting, Set<String> keys})? get overrideSetting {
    if (deleted) return null;
    final patch = _readOverridePatch();
    if (patch.isEmpty) return null;
    try {
      return (
        setting: ReadSettingState.fromJson(patch),
        keys: patch.keys.toSet(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 用 [updated] 相对 [current] 的变化更新本列，返回实际变化的 key。
  ///
  /// [includeKeys] 强制记录的键（即使值没变，如首次快照 readMode）。
  /// 只改列内容，不碰 `updatedAt`，落盘由调用方 `box.put`。
  Set<String> applyChanges(
    ReadSettingState current,
    ReadSettingState updated, {
    Set<String> includeKeys = const {},
  }) {
    final before = current.toJson();
    final after = updated.toJson();
    final delta = <String, dynamic>{};
    for (final key in after.keys) {
      if (before[key] != after[key]) delta[key] = after[key];
    }
    for (final key in includeKeys) {
      if (after.containsKey(key)) delta[key] = after[key];
    }
    if (delta.isEmpty) return const {};
    final patch = Map<String, dynamic>.of(_readOverridePatch())
      ..addAll(_sanitizeOverridePatch(delta));
    overridesJson = jsonEncode(patch);
    return delta.keys.toSet();
  }

  /// 解析并清洗后的 patch（内部用）。
  Map<String, dynamic> _readOverridePatch() {
    try {
      final decoded = jsonDecode(overridesJson);
      final map = decoded is Map<String, dynamic>
          ? decoded
          : decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : const <String, dynamic>{};
      return _sanitizeOverridePatch(map);
    } catch (_) {
      return const {};
    }
  }

  Map<String, dynamic> toJson() => _$ComicReadPreferenceToJson(this);

  /// 兼容 v11 及更早：老数据只有 `readMode` 整列，转成 `{"readMode":x}` patch。
  /// 缺 `readMode` 时（新版备份/同步）补 0，生成的 `fromJson` 才能安全解析。
  factory ComicReadPreference.fromJson(Map<String, dynamic> json) {
    json = Map.of(json);
    json.putIfAbsent('readMode', () => 0);
    if (!json.containsKey('overridesJson') && json['readMode'] is num) {
      json['overridesJson'] = jsonEncode({
        'readMode': (json['readMode'] as num).toInt().clamp(0, 2),
      });
    }
    return _$ComicReadPreferenceFromJson(json);
  }

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

/// 只保留 `ReadSettingState` 认识的 key，脏 key（旧版本残留/手改）直接丢弃。
///
/// 白名单与类型都从 `ReadSettingState` 自身派生：以后加字段零改动，
/// 类型按默认值的运行时类型校验（`readMode` 额外钳到 0~2）。
Map<String, dynamic> sanitizeReadSettingPatch(Map<String, dynamic> patch) {
  if (patch.isEmpty) return const {};
  final defaults = const ReadSettingState().toJson();
  final clean = <String, dynamic>{};
  for (final entry in patch.entries) {
    final key = entry.key;
    if (!defaults.containsKey(key)) continue;
    final value = entry.value;
    final fallback = defaults[key];
    if (fallback is bool && value is bool) {
      clean[key] = value;
    } else if (fallback is int && value is num) {
      clean[key] = key == 'readMode'
          ? value.toInt().clamp(0, 2)
          : value.toInt();
    } else if (fallback is double && value is num && value.isFinite) {
      clean[key] = value.toDouble();
    } else if (fallback is String && value is String) {
      clean[key] = value;
    }
  }
  return clean;
}

/// Entity 内部复用（同库私有）：与 [sanitizeReadSettingPatch] 同一实现。
Map<String, dynamic> _sanitizeOverridePatch(Map<String, dynamic> patch) =>
    sanitizeReadSettingPatch(patch);
