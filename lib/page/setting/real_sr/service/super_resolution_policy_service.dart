import 'package:zephyr/page/setting/real_sr/model/super_resolution_condition.dart';

enum SuperResolutionPolicyTrigger {
  manual,
  auto,
  preload;

  static SuperResolutionPolicyTrigger fromString(String value) {
    return switch (value) {
      'manual' => SuperResolutionPolicyTrigger.manual,
      'preload' => SuperResolutionPolicyTrigger.preload,
      _ => SuperResolutionPolicyTrigger.auto,
    };
  }
}

class SuperResolutionPolicyInput {
  final SuperResolutionPolicyTrigger trigger;
  final double width;
  final double height;
  final String bookPath;
  final String imagePath;
  final String? innerPath;
  final int? createdAt;
  final int? modifiedAt;
  final Map<String, dynamic>? metadata;

  const SuperResolutionPolicyInput({
    this.trigger = SuperResolutionPolicyTrigger.auto,
    required this.width,
    required this.height,
    required this.bookPath,
    required this.imagePath,
    this.innerPath,
    this.createdAt,
    this.modifiedAt,
    this.metadata,
  });
}

class SuperResolutionPolicyDecision {
  final String kind; // 'run' | 'skip' | 'disabled'
  final String reason;
  final String? conditionId;
  final String? conditionName;
  final String? modelId;
  final int? scale;
  final int? noise;
  final int? tileSize;
  final bool? tileEnabled;
  final bool? tta;
  final String? gpuId;
  final bool useCache;

  const SuperResolutionPolicyDecision({
    required this.kind,
    required this.reason,
    this.conditionId,
    this.conditionName,
    this.modelId,
    this.scale,
    this.noise,
    this.tileSize,
    this.tileEnabled,
    this.tta,
    this.gpuId,
    this.useCache = true,
  });

  bool get shouldRun => kind == 'run';
  bool get isSkipped => kind == 'skip';
  bool get isDisabled => kind == 'disabled';

  @override
  String toString() =>
      'SuperResolutionPolicyDecision(kind: $kind, reason: $reason, condition: $conditionName)';
}

/// 超分全局与默认偏好设定（传递给策略服务）
class SuperResolutionPolicyPreferences {
  final bool autoUpscaleEnabled;
  final bool preUpscaleEnabled;
  final bool conditionalEnabled;
  final int? conditionalMinWidth;
  final int? conditionalMinHeight;
  final List<SuperResolutionCondition> conditions;
  final String? defaultModelId;
  final int? defaultScale;
  final int? defaultNoise;
  final int? defaultTileSize;
  final bool? defaultTileEnabled;
  final bool? defaultTta;
  final String? defaultGpuId;

  const SuperResolutionPolicyPreferences({
    this.autoUpscaleEnabled = true,
    this.preUpscaleEnabled = true,
    this.conditionalEnabled = false,
    this.conditionalMinWidth,
    this.conditionalMinHeight,
    this.conditions = const [],
    this.defaultModelId,
    this.defaultScale = 2,
    this.defaultNoise = 0,
    this.defaultTileSize = 512,
    this.defaultTileEnabled = true,
    this.defaultTta = false,
    this.defaultGpuId = '0',
  });
}

/// 条件超分策略裁决引擎（移植自 neo / Xiranite）
class SuperResolutionPolicyService {
  final SuperResolutionPolicyPreferences preferences;
  final Map<String, RegExp> _regexCache = {};
  late final List<SuperResolutionCondition> _activeConditions;

  SuperResolutionPolicyService(this.preferences) {
    _activeConditions = preferences.conditions
        .where((c) => c.enabled)
        .toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
  }

  SuperResolutionPolicyDecision decide(SuperResolutionPolicyInput input) {
    _validateInput(input);

    if (input.trigger != SuperResolutionPolicyTrigger.manual) {
      if (!preferences.autoUpscaleEnabled) {
        return const SuperResolutionPolicyDecision(
          kind: 'disabled',
          reason: 'automatic-upscale-disabled',
        );
      }
      if (input.trigger == SuperResolutionPolicyTrigger.preload &&
          !preferences.preUpscaleEnabled) {
        return const SuperResolutionPolicyDecision(
          kind: 'disabled',
          reason: 'preload-upscale-disabled',
        );
      }
      if (preferences.conditionalEnabled) {
        final minW = preferences.conditionalMinWidth ?? 0;
        final minH = preferences.conditionalMinHeight ?? 0;
        if (minW > input.width || minH > input.height) {
          return const SuperResolutionPolicyDecision(
            kind: 'skip',
            reason: 'below-conditional-minimum',
          );
        }
      }
    }

    final condition = preferences.conditionalEnabled
        ? _firstMatchingCondition(input)
        : null;

    if (condition?.action.skip == true) {
      return SuperResolutionPolicyDecision(
        kind: 'skip',
        reason: 'condition-skip',
        conditionId: condition!.id,
        conditionName: condition.name,
      );
    }

    if (condition?.match.excludeFromPreload == true &&
        input.trigger == SuperResolutionPolicyTrigger.preload) {
      return SuperResolutionPolicyDecision(
        kind: 'skip',
        reason: 'condition-excludes-preload',
        conditionId: condition!.id,
        conditionName: condition.name,
      );
    }

    final modelId =
        condition?.action.modelId ?? preferences.defaultModelId;
    final scale = condition?.action.scale ?? preferences.defaultScale;

    if (modelId == null || scale == null) {
      return SuperResolutionPolicyDecision(
        kind: 'disabled',
        reason: 'missing-model-defaults',
        conditionId: condition?.id,
        conditionName: condition?.name,
      );
    }

    final tileEnabled =
        condition?.action.tileEnabled ?? preferences.defaultTileEnabled;
    final tileSize = tileEnabled == false
        ? null
        : (condition?.action.tileSize ?? preferences.defaultTileSize);

    return SuperResolutionPolicyDecision(
      kind: 'run',
      reason: condition != null ? 'condition-match' : 'default-policy',
      conditionId: condition?.id,
      conditionName: condition?.name,
      modelId: modelId,
      scale: scale,
      noise: condition?.action.noise ?? preferences.defaultNoise,
      tileSize: tileSize,
      tileEnabled: tileEnabled,
      tta: condition?.action.tta ?? preferences.defaultTta,
      gpuId: condition?.action.gpuId ?? preferences.defaultGpuId,
      useCache: condition?.action.useCache ?? true,
    );
  }

  SuperResolutionCondition? _firstMatchingCondition(
    SuperResolutionPolicyInput input,
  ) {
    for (final condition in _activeConditions) {
      if (_matches(condition, input)) {
        return condition;
      }
    }
    return null;
  }

  bool _matches(
    SuperResolutionCondition condition,
    SuperResolutionPolicyInput input,
  ) {
    final match = condition.match;
    final hasWidthRule = match.minWidth != null || match.maxWidth != null;
    final hasHeightRule = match.minHeight != null || match.maxHeight != null;
    final widthMatches = _within(input.width, match.minWidth, match.maxWidth);
    final heightMatches = _within(input.height, match.minHeight, match.maxHeight);

    if (match.dimensionMode == 'or' && hasWidthRule && hasHeightRule) {
      if (!widthMatches && !heightMatches) return false;
    } else if ((hasWidthRule && !widthMatches) || (hasHeightRule && !heightMatches)) {
      return false;
    }

    final megapixels = input.width * input.height / 1000000.0;
    if (!_within(megapixels, match.minMegapixels, match.maxMegapixels)) {
      return false;
    }

    if (!_withinRange(input.createdAt, match.createdBetween)) return false;
    if (!_withinRange(input.modifiedAt, match.modifiedBetween)) return false;

    if (match.bookPathRegex != null && match.bookPathRegex!.isNotEmpty) {
      final reg = _getRegex(match.bookPathRegex!);
      if (!reg.hasMatch(_normalizePath(input.bookPath))) return false;
    }

    if (match.imagePathRegex != null && match.imagePathRegex!.isNotEmpty) {
      final imageTarget = match.matchInnerPath && input.innerPath != null
          ? input.innerPath!
          : input.imagePath;
      final reg = _getRegex(match.imagePathRegex!);
      if (!reg.hasMatch(_normalizePath(imageTarget))) return false;
    }

    if (match.metadata != null && match.metadata!.isNotEmpty) {
      for (final entry in match.metadata!.entries) {
        final actual = input.metadata?[entry.key];
        if (!_evaluateExpression(entry.value, actual)) {
          return false;
        }
      }
    }

    return true;
  }

  RegExp _getRegex(String pattern) {
    return _regexCache.putIfAbsent(pattern, () {
      try {
        return RegExp(pattern, unicode: true);
      } catch (_) {
        return RegExp(pattern);
      }
    });
  }

  bool _evaluateExpression(
    ConditionMetadataExpression expression,
    dynamic actual,
  ) {
    switch (expression.operator) {
      case 'eq':
        return actual == expression.value;
      case 'ne':
        return actual != expression.value;
      case 'gt':
        final a = _comparableNumber(actual);
        final b = _comparableNumber(expression.value);
        return a != null && b != null && a > b;
      case 'gte':
        final a = _comparableNumber(actual);
        final b = _comparableNumber(expression.value);
        return a != null && b != null && a >= b;
      case 'lt':
        final a = _comparableNumber(actual);
        final b = _comparableNumber(expression.value);
        return a != null && b != null && a < b;
      case 'lte':
        final a = _comparableNumber(actual);
        final b = _comparableNumber(expression.value);
        return a != null && b != null && a <= b;
      case 'regex':
        final reg = _getRegex(expression.value.toString());
        return reg.hasMatch(actual?.toString() ?? '');
      case 'contains':
        return (actual?.toString() ?? '').contains(expression.value.toString());
      default:
        return false;
    }
  }

  static void _validateInput(SuperResolutionPolicyInput input) {
    if (!input.width.isFinite || input.width <= 0) {
      throw RangeError('Super-resolution policy width must be positive.');
    }
    if (!input.height.isFinite || input.height <= 0) {
      throw RangeError('Super-resolution policy height must be positive.');
    }
    if (input.bookPath.trim().isEmpty) {
      throw ArgumentError('Super-resolution policy book path is required.');
    }
    if (input.imagePath.trim().isEmpty) {
      throw ArgumentError('Super-resolution policy image path is required.');
    }
  }

  static bool _within(num value, num? min, num? max) {
    if (min != null && value < min) return false;
    if (max != null && value > max) return false;
    return true;
  }

  static bool _withinRange(int? value, List<int>? range) {
    if (range == null || range.length < 2) return true;
    if (value == null) return false;
    return value >= range[0] && value <= range[1];
  }

  static double? _comparableNumber(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      return double.tryParse(value);
    }
    return null;
  }

  static String _normalizePath(String path) {
    return path.replaceAll(r'\', '/');
  }
}
