import 'dart:convert';

/// 条件超分的元数据单项表达式
class ConditionMetadataExpression {
  final String operator;
  final dynamic value;

  const ConditionMetadataExpression({
    required this.operator,
    required this.value,
  });

  Map<String, dynamic> toJson() => {'operator': operator, 'value': value};

  factory ConditionMetadataExpression.fromJson(Map<String, dynamic> json) {
    return ConditionMetadataExpression(
      operator: json['operator'] as String? ?? 'eq',
      value: json['value'],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConditionMetadataExpression &&
          runtimeType == other.runtimeType &&
          operator == other.operator &&
          value == other.value;

  @override
  int get hashCode => Object.hash(operator, value);
}

/// 超分条件的匹配规则
class ConditionMatch {
  final int? minWidth;
  final int? minHeight;
  final int? maxWidth;
  final int? maxHeight;
  final double? minMegapixels;
  final double? maxMegapixels;
  final String dimensionMode; // 'and' | 'or'
  final List<int>? createdBetween;
  final List<int>? modifiedBetween;
  final String? bookPathRegex;
  final String? imagePathRegex;
  final bool matchInnerPath;
  final bool excludeFromPreload;
  final Map<String, ConditionMetadataExpression>? metadata;

  const ConditionMatch({
    this.minWidth,
    this.minHeight,
    this.maxWidth,
    this.maxHeight,
    this.minMegapixels,
    this.maxMegapixels,
    this.dimensionMode = 'and',
    this.createdBetween,
    this.modifiedBetween,
    this.bookPathRegex,
    this.imagePathRegex,
    this.matchInnerPath = false,
    this.excludeFromPreload = false,
    this.metadata,
  });

  ConditionMatch copyWith({
    int? minWidth,
    int? minHeight,
    int? maxWidth,
    int? maxHeight,
    double? minMegapixels,
    double? maxMegapixels,
    String? dimensionMode,
    List<int>? createdBetween,
    List<int>? modifiedBetween,
    String? bookPathRegex,
    String? imagePathRegex,
    bool? matchInnerPath,
    bool? excludeFromPreload,
    Map<String, ConditionMetadataExpression>? metadata,
    bool clearMinWidth = false,
    bool clearMinHeight = false,
    bool clearMaxWidth = false,
    bool clearMaxHeight = false,
    bool clearMinMegapixels = false,
    bool clearMaxMegapixels = false,
    bool clearBookPathRegex = false,
    bool clearImagePathRegex = false,
  }) {
    return ConditionMatch(
      minWidth: clearMinWidth ? null : (minWidth ?? this.minWidth),
      minHeight: clearMinHeight ? null : (minHeight ?? this.minHeight),
      maxWidth: clearMaxWidth ? null : (maxWidth ?? this.maxWidth),
      maxHeight: clearMaxHeight ? null : (maxHeight ?? this.maxHeight),
      minMegapixels: clearMinMegapixels
          ? null
          : (minMegapixels ?? this.minMegapixels),
      maxMegapixels: clearMaxMegapixels
          ? null
          : (maxMegapixels ?? this.maxMegapixels),
      dimensionMode: dimensionMode ?? this.dimensionMode,
      createdBetween: createdBetween ?? this.createdBetween,
      modifiedBetween: modifiedBetween ?? this.modifiedBetween,
      bookPathRegex: clearBookPathRegex
          ? null
          : (bookPathRegex ?? this.bookPathRegex),
      imagePathRegex: clearImagePathRegex
          ? null
          : (imagePathRegex ?? this.imagePathRegex),
      matchInnerPath: matchInnerPath ?? this.matchInnerPath,
      excludeFromPreload: excludeFromPreload ?? this.excludeFromPreload,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
    if (minWidth != null) 'minWidth': minWidth,
    if (minHeight != null) 'minHeight': minHeight,
    if (maxWidth != null) 'maxWidth': maxWidth,
    if (maxHeight != null) 'maxHeight': maxHeight,
    if (minMegapixels != null) 'minMegapixels': minMegapixels,
    if (maxMegapixels != null) 'maxMegapixels': maxMegapixels,
    'dimensionMode': dimensionMode,
    if (createdBetween != null) 'createdBetween': createdBetween,
    if (modifiedBetween != null) 'modifiedBetween': modifiedBetween,
    if (bookPathRegex != null && bookPathRegex!.isNotEmpty)
      'bookPathRegex': bookPathRegex,
    if (imagePathRegex != null && imagePathRegex!.isNotEmpty)
      'imagePathRegex': imagePathRegex,
    'matchInnerPath': matchInnerPath,
    'excludeFromPreload': excludeFromPreload,
    if (metadata != null && metadata!.isNotEmpty)
      'metadata': metadata!.map((k, v) => MapEntry(k, v.toJson())),
  };

  factory ConditionMatch.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    double? parseDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    List<int>? parseRange(dynamic v) {
      if (v is List && v.length >= 2) {
        final start = parseInt(v[0]);
        final end = parseInt(v[1]);
        if (start != null && end != null) return [start, end];
      }
      return null;
    }

    Map<String, ConditionMetadataExpression>? parseMetadata(dynamic v) {
      if (v is Map) {
        final result = <String, ConditionMetadataExpression>{};
        v.forEach((key, val) {
          if (val is Map<String, dynamic>) {
            result[key.toString()] = ConditionMetadataExpression.fromJson(val);
          } else if (val is Map) {
            result[key.toString()] = ConditionMetadataExpression.fromJson(
              val.cast<String, dynamic>(),
            );
          }
        });
        return result;
      }
      return null;
    }

    return ConditionMatch(
      minWidth: parseInt(json['minWidth'] ?? json['min_width']),
      minHeight: parseInt(json['minHeight'] ?? json['min_height']),
      maxWidth: parseInt(json['maxWidth'] ?? json['max_width']),
      maxHeight: parseInt(json['maxHeight'] ?? json['max_height']),
      minMegapixels: parseDouble(
        json['minMegapixels'] ?? json['min_megapixels'] ?? json['minPixels'],
      ),
      maxMegapixels: parseDouble(
        json['maxMegapixels'] ?? json['max_megapixels'] ?? json['maxPixels'],
      ),
      dimensionMode:
          (json['dimensionMode'] ?? json['dimension_mode'] ?? 'and') == 'or'
          ? 'or'
          : 'and',
      createdBetween: parseRange(
        json['createdBetween'] ?? json['created_between'],
      ),
      modifiedBetween: parseRange(
        json['modifiedBetween'] ?? json['modified_between'],
      ),
      bookPathRegex:
          json['bookPathRegex'] as String? ??
          json['book_path_regex'] as String?,
      imagePathRegex:
          json['imagePathRegex'] as String? ??
          json['image_path_regex'] as String?,
      matchInnerPath:
          json['matchInnerPath'] as bool? ??
          json['match_inner_path'] as bool? ??
          false,
      excludeFromPreload:
          json['excludeFromPreload'] as bool? ??
          json['exclude_from_preload'] as bool? ??
          false,
      metadata: parseMetadata(json['metadata']),
    );
  }
}

/// 超分条件的触发动作
class ConditionAction {
  final bool skip;
  final String? modelId;
  final int? scale;
  final int? tileSize;
  final bool? tileEnabled;
  final int? noise;
  final String? gpuId;
  final bool? useCache;
  final bool? tta;

  const ConditionAction({
    this.skip = false,
    this.modelId,
    this.scale,
    this.tileSize,
    this.tileEnabled = true,
    this.noise,
    this.gpuId,
    this.useCache = true,
    this.tta = false,
  });

  ConditionAction copyWith({
    bool? skip,
    String? modelId,
    int? scale,
    int? tileSize,
    bool? tileEnabled,
    int? noise,
    String? gpuId,
    bool? useCache,
    bool? tta,
    bool clearModelId = false,
    bool clearScale = false,
  }) {
    return ConditionAction(
      skip: skip ?? this.skip,
      modelId: clearModelId ? null : (modelId ?? this.modelId),
      scale: clearScale ? null : (scale ?? this.scale),
      tileSize: tileSize ?? this.tileSize,
      tileEnabled: tileEnabled ?? this.tileEnabled,
      noise: noise ?? this.noise,
      gpuId: gpuId ?? this.gpuId,
      useCache: useCache ?? this.useCache,
      tta: tta ?? this.tta,
    );
  }

  Map<String, dynamic> toJson() => {
    'skip': skip,
    if (modelId != null && modelId!.isNotEmpty) 'modelId': modelId,
    if (scale != null) 'scale': scale,
    if (tileSize != null) 'tileSize': tileSize,
    if (tileEnabled != null) 'tileEnabled': tileEnabled,
    if (noise != null) 'noise': noise,
    if (gpuId != null && gpuId!.isNotEmpty) 'gpuId': gpuId,
    if (useCache != null) 'useCache': useCache,
    if (tta != null) 'tta': tta,
  };

  factory ConditionAction.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    final rawTile = parseInt(json['tileSize'] ?? json['tile_size']);
    final rawTileEnabled =
        json['tileEnabled'] as bool? ?? json['tile_enabled'] as bool?;

    return ConditionAction(
      skip: json['skip'] as bool? ?? false,
      modelId:
          json['modelId'] as String? ??
          json['model_id'] as String? ??
          json['model'] as String?,
      scale: parseInt(json['scale']),
      tileSize: rawTile,
      tileEnabled: rawTileEnabled ?? (rawTile != null && rawTile > 0),
      noise: parseInt(json['noise'] ?? json['noise_level']),
      gpuId: json['gpuId']?.toString() ?? json['gpu_id']?.toString(),
      useCache: json['useCache'] as bool? ?? json['use_cache'] as bool? ?? true,
      tta: json['tta'] as bool? ?? false,
    );
  }
}

/// 超分条件定义（源自 neo / Xiranite）
class SuperResolutionCondition {
  final String id;
  final String name;
  final bool enabled;
  final int priority;
  final ConditionMatch match;
  final ConditionAction action;

  const SuperResolutionCondition({
    required this.id,
    required this.name,
    this.enabled = true,
    required this.priority,
    required this.match,
    required this.action,
  });

  SuperResolutionCondition copyWith({
    String? id,
    String? name,
    bool? enabled,
    int? priority,
    ConditionMatch? match,
    ConditionAction? action,
  }) {
    return SuperResolutionCondition(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      priority: priority ?? this.priority,
      match: match ?? this.match,
      action: action ?? this.action,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'enabled': enabled,
    'priority': priority,
    'match': match.toJson(),
    'action': action.toJson(),
  };

  factory SuperResolutionCondition.fromJson(Map<String, dynamic> json) {
    return SuperResolutionCondition(
      id:
          json['id'] as String? ??
          'condition-${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? '未命名条件',
      enabled: json['enabled'] as bool? ?? true,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      match: json['match'] is Map
          ? ConditionMatch.fromJson(
              (json['match'] as Map).cast<String, dynamic>(),
            )
          : const ConditionMatch(),
      action: json['action'] is Map
          ? ConditionAction.fromJson(
              (json['action'] as Map).cast<String, dynamic>(),
            )
          : const ConditionAction(),
    );
  }

  /// 默认出厂初始条件
  static SuperResolutionCondition createDefault({
    String id = 'condition-default',
    String name = '默认条件',
    int priority = 0,
  }) {
    return SuperResolutionCondition(
      id: id,
      name: name,
      enabled: true,
      priority: priority,
      match: const ConditionMatch(dimensionMode: 'and'),
      action: const ConditionAction(
        skip: false,
        scale: 2,
        tileEnabled: true,
        tileSize: 512,
        noise: 0,
        gpuId: '0',
        useCache: true,
        tta: false,
      ),
    );
  }

  static List<SuperResolutionCondition> decodeList(String? jsonString) {
    if (jsonString == null || jsonString.trim().isEmpty) {
      return [createDefault()];
    }
    try {
      final dynamic decoded = jsonDecode(jsonString);
      if (decoded is List) {
        final list = <SuperResolutionCondition>[];
        for (var i = 0; i < decoded.length; i++) {
          final item = decoded[i];
          if (item is Map) {
            list.add(
              SuperResolutionCondition.fromJson(
                item.cast<String, dynamic>(),
              ).copyWith(priority: i),
            );
          }
        }
        return list.isNotEmpty ? list : [createDefault()];
      }
    } catch (_) {}
    return [createDefault()];
  }

  static String encodeList(List<SuperResolutionCondition> conditions) {
    final list = conditions.asMap().entries.map((e) {
      return e.value.copyWith(priority: e.key).toJson();
    }).toList();
    return jsonEncode(list);
  }
}
