import 'dart:convert';
import 'package:zephyr/page/setting/real_sr/model/super_resolution_condition.dart';

class UpscaleConditionImportResult {
  final List<SuperResolutionCondition> conditions;
  final List<String> warnings;

  const UpscaleConditionImportResult({
    required this.conditions,
    this.warnings = const [],
  });
}

/// 解析导入的条件 JSON 文本（支持当前规范格式与旧版格式）
UpscaleConditionImportResult parseUpscaleConditionImport(String text) {
  if (text.trim().isEmpty) {
    throw const FormatException('导入内容不能为空');
  }

  dynamic parsed;
  try {
    parsed = jsonDecode(text);
  } catch (e) {
    throw FormatException('JSON 格式无效: $e');
  }

  final unwrapped = _unwrapConditions(parsed);
  if (unwrapped is! List || unwrapped.isEmpty) {
    throw const FormatException('备份数据必须包含非空的条件数组');
  }

  final warnings = <String>[];
  final conditions = <SuperResolutionCondition>[];

  for (var i = 0; i < unwrapped.length; i++) {
    final item = unwrapped[i];
    if (item is! Map) {
      warnings.add('跳过第 ${i + 1} 项：数据不是对象');
      continue;
    }

    try {
      final map = item.cast<String, dynamic>();
      final normalized = _normalizeConditionMap(map, i, warnings);
      if (normalized != null) {
        conditions.add(SuperResolutionCondition.fromJson(normalized));
      }
    } catch (e) {
      warnings.add('第 ${i + 1} 项解析失败: $e');
    }
  }

  if (conditions.isEmpty) {
    throw FormatException(
      warnings.isNotEmpty ? warnings.first : '未在备份中解析到有效条件',
    );
  }

  return UpscaleConditionImportResult(
    conditions: conditions,
    warnings: warnings,
  );
}

dynamic _unwrapConditions(dynamic value) {
  if (value is List) return value;
  if (value is Map) {
    if (value['conditions'] is List) return value['conditions'];
    if (value['conditionsList'] is List) return value['conditionsList'];
    if (value['preferences'] is Map &&
        (value['preferences'] as Map)['conditions'] is List) {
      return (value['preferences'] as Map)['conditions'];
    }
    if (value['superResolution'] is Map) {
      final sr = value['superResolution'] as Map;
      if (sr['preferences'] is Map &&
          (sr['preferences'] as Map)['conditions'] is List) {
        return (sr['preferences'] as Map)['conditions'];
      }
    }
  }
  return value;
}

Map<String, dynamic>? _normalizeConditionMap(
  Map<String, dynamic> raw,
  int priority,
  List<String> warnings,
) {
  final id = raw['id']?.toString() ?? 'condition-${DateTime.now().millisecondsSinceEpoch}-$priority';
  final name = raw['name']?.toString() ?? '条件 ${priority + 1}';
  final enabled = raw['enabled'] is bool ? raw['enabled'] as bool : true;

  final rawMatch = raw['match'] is Map ? (raw['match'] as Map).cast<String, dynamic>() : <String, dynamic>{};
  final rawAction = raw['action'] is Map ? (raw['action'] as Map).cast<String, dynamic>() : <String, dynamic>{};

  // 兼容旧字段：regexBookPath / regexImagePath / minPixels / maxPixels
  final match = Map<String, dynamic>.from(rawMatch);
  if (match.containsKey('regexBookPath') && !match.containsKey('bookPathRegex')) {
    match['bookPathRegex'] = match['regexBookPath'];
  }
  if (match.containsKey('regexImagePath') && !match.containsKey('imagePathRegex')) {
    match['imagePathRegex'] = match['regexImagePath'];
  }
  if (match.containsKey('minPixels') && !match.containsKey('minMegapixels')) {
    match['minMegapixels'] = match['minPixels'];
  }
  if (match.containsKey('maxPixels') && !match.containsKey('maxMegapixels')) {
    match['maxMegapixels'] = match['maxPixels'];
  }
  match['dimensionMode'] = (match['dimensionMode'] ?? match['dimension_mode']) == 'or' ? 'or' : 'and';

  // 兼容旧 action 字段：modelName / noiseLevel
  final action = Map<String, dynamic>.from(rawAction);
  if (action.containsKey('modelName') && !action.containsKey('modelId')) {
    action['modelId'] = action['modelName'];
  }
  if (action.containsKey('noiseLevel') && !action.containsKey('noise')) {
    action['noise'] = action['noiseLevel'];
  }
  // 旧版 MODEL_REALESRGAN_ANIMAVIDEOV3_UP2X 等模型映射
  final rawModel = action['modelId']?.toString() ?? action['model']?.toString();
  if (rawModel != null && rawModel.startsWith('MODEL_')) {
    action['modelId'] = _mapLegacyModelName(rawModel);
  }

  return {
    'id': id,
    'name': name,
    'enabled': enabled,
    'priority': priority,
    'match': match,
    'action': action,
  };
}

String _mapLegacyModelName(String name) {
  final upper = name.toUpperCase();
  if (upper.contains('ANIMAVIDEO') || upper.contains('ANIMEVIDEO')) {
    return 'realesr-animevideov3';
  }
  if (upper.contains('REALCUGAN') || upper.contains('CUGAN')) {
    return 'realcugan';
  }
  if (upper.contains('REALESRGAN') || upper.contains('ESRGAN')) {
    return 'realesrgan-x4plus-anime';
  }
  if (upper.contains('WAIFU2X')) {
    return 'waifu2x';
  }
  return name.toLowerCase().replaceAll('_', '-');
}
