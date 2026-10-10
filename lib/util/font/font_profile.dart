import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/src/rust/api/font.dart' as rust_font;
import 'package:zephyr/util/get_path.dart';

/// 默认字体（整个字体家族共用一个文件）。
const _fontDefaultKey = 'font_profile_default';

/// 默认字体来源模式：system = 应用默认字体栈（零配置）；
/// family = 系统已安装字体（按家族名引用）；file = 导入的字体文件。
const _fontModeKey = 'font_profile_mode';

/// 系统已安装字体的家族名（mode = family 时生效）。
const _fontFamilyKey = 'font_profile_family';

/// 字重覆盖键（可选；沿用旧版逐字重键名，老数据无需迁移即成为覆盖项）。
const _fontOverrideKeys = <int, String>{
  100: 'font_profile_w100',
  200: 'font_profile_w200',
  300: 'font_profile_w300',
  400: 'font_profile_w400',
  500: 'font_profile_w500',
  600: 'font_profile_w600',
  700: 'font_profile_w700',
  800: 'font_profile_w800',
  900: 'font_profile_w900',
};

const fontWeightLabels = <int, String>{
  100: 'Thin',
  200: 'ExtraLight',
  300: 'Light',
  400: 'Regular',
  500: 'Medium',
  600: 'SemiBold',
  700: 'Bold',
  800: 'ExtraBold',
  900: 'Black',
};

/// 纯函数：从已配置的字重里挑离 [target] 最近的；同距取较小字重。
/// 没有任何候选时返回 null。
int? nearestConfiguredWeight(int target, Iterable<int> configured) {
  int? best;
  int bestDistance = 0;
  for (final weight in configured) {
    final distance = (weight - target).abs();
    if (best == null ||
        distance < bestDistance ||
        (distance == bestDistance && weight < best)) {
      best = weight;
      bestDistance = distance;
    }
  }
  return best;
}

/// 纯函数：字重 → 字体家族名的解析规则。
/// 优先精确命中的覆盖项，其次最近的覆盖项，最后回落到默认字体。
/// 都没有时返回空串（调用方保持原 TextStyle 不动）。
String resolveFontFamily({
  required String? defaultFamily,
  required Map<int, String> overrideFamilies,
  FontWeight? weight,
}) {
  if (overrideFamilies.isNotEmpty) {
    final normalized = _normalizeWeightStatic(weight);
    final exact = overrideFamilies[normalized];
    if (exact != null) return exact;
    final nearest = nearestConfiguredWeight(normalized, overrideFamilies.keys);
    if (nearest != null) return overrideFamilies[nearest]!;
  }
  return defaultFamily ?? '';
}

int _normalizeWeightStatic(FontWeight? weight) {
  if (weight == null) return 400;
  return weight.value.clamp(100, 900) ~/ 100 * 100;
}

class FontProfileController extends ChangeNotifier {
  FontProfileController._();

  static final FontProfileController instance = FontProfileController._();

  static const modeSystem = 'system';
  static const modeFamily = 'family';
  static const modeFile = 'file';

  SharedPreferences? _prefs;
  String _mode = modeSystem;
  String _systemFamily = '';
  String? _defaultPath;
  String? _defaultFamily;
  Map<int, String> _paths = const {};
  Map<int, String> _families = const {};

  /// 默认字体来源模式。
  String get mode => _mode;

  /// 系统已安装字体的家族名（mode = family 时生效）。
  String get systemFamily => _systemFamily;

  /// 默认字体文件路径（null = 未设置）。
  String? get defaultPath => _defaultPath;

  /// 字重覆盖文件路径（键为字重值）。
  Map<int, String> get paths => _paths;

  bool get hasOverrides => _paths.isNotEmpty;

  /// 当前模式下默认字体对应的家族名（空串 = 用应用默认字体栈）。
  String get _effectiveDefaultFamily {
    switch (_mode) {
      case modeFamily:
        return _systemFamily;
      case modeFile:
        return _defaultFamily ?? '';
      default:
        return '';
    }
  }

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    final nextPaths = <int, String>{};
    final nextFamilies = <int, String>{};

    _systemFamily = _prefs!.getString(_fontFamilyKey)?.trim() ?? '';
    final storedMode = _prefs!.getString(_fontModeKey)?.trim() ?? '';
    final storedDefault = _prefs!.getString(_fontDefaultKey)?.trim() ?? '';
    if (storedDefault.isNotEmpty) {
      final family = await _registerFont(storedDefault, tag: 'default');
      if (family != null) {
        _defaultPath = storedDefault;
        _defaultFamily = family;
      }
    }
    // 旧数据没有模式键：有默认文件即视为 file，否则出厂 system（零操作）。
    _mode = switch (storedMode) {
      modeFamily => modeFamily,
      modeFile => modeFile,
      modeSystem => modeSystem,
      _ => storedDefault.isNotEmpty ? modeFile : modeSystem,
    };

    for (final entry in _fontOverrideKeys.entries) {
      final path = _prefs!.getString(entry.value)?.trim() ?? '';
      if (path.isEmpty) continue;
      final family = await _registerFont(path, tag: 'w${entry.key}');
      if (family == null) continue;
      nextPaths[entry.key] = path;
      nextFamilies[entry.key] = family;
    }
    _paths = nextPaths;
    _families = nextFamilies;
    notifyListeners();
  }

  String? pathForWeight(int weight) => _paths[weight];

  String familyForWeight(FontWeight? weight) {
    return resolveFontFamily(
      defaultFamily: _effectiveDefaultFamily,
      overrideFamilies: _families,
      weight: weight,
    );
  }

  /// 切换默认字体来源模式（文件与家族名都保留，可随时切回）。
  Future<void> setMode(String mode) async {
    _prefs ??= await SharedPreferences.getInstance();
    _mode = mode;
    await _prefs!.setString(_fontModeKey, mode);
    notifyListeners();
  }

  /// 设置系统已安装字体的家族名（空串 = 清除，回退系统默认）。
  Future<void> setSystemFamily(String name) async {
    _prefs ??= await SharedPreferences.getInstance();
    final normalized = name.trim();
    _systemFamily = normalized;
    if (normalized.isEmpty) {
      await _prefs!.remove(_fontFamilyKey);
    } else {
      await _prefs!.setString(_fontFamilyKey, normalized);
    }
    notifyListeners();
  }

  /// 枚举系统已安装字体的家族名（桥到 Rust font-kit：
  /// macOS/iOS = CoreText，Windows = DirectWrite，Linux = fontconfig）。
  /// 失败回空表，由调用方给出「手动输入」兜底。
  Future<List<String>> listSystemFontFamilies() async {
    try {
      final families = await rust_font.listSystemFontFamilies();
      return families;
    } catch (_) {
      return const [];
    }
  }

  /// 设置默认字体（传空串清除）。整个家族共用这一个文件；
  /// 引擎会对粗体字重做模拟加粗。
  Future<bool> setDefaultPath(String path) async {
    _prefs ??= await SharedPreferences.getInstance();
    final normalizedPath = path.trim();
    final previousPath = _defaultPath;

    if (normalizedPath.isEmpty) {
      await _prefs!.remove(_fontDefaultKey);
      await _deleteIfManaged(previousPath);
      _defaultPath = null;
      _defaultFamily = null;
      notifyListeners();
      return true;
    }

    final storedPath = await _copyToManagedFonts('default', normalizedPath);
    final family = await _registerFont(storedPath, tag: 'default');
    if (family == null) {
      await _deleteIfManaged(storedPath);
      return false;
    }
    await _prefs!.setString(_fontDefaultKey, storedPath);
    if (previousPath != null && previousPath != storedPath) {
      await _deleteIfManaged(previousPath);
    }
    _defaultPath = storedPath;
    _defaultFamily = family;
    notifyListeners();
    return true;
  }

  /// 设置某字重的覆盖文件（传空串清除该字重的覆盖）。
  Future<bool> setOverridePath(int weight, String path) async {
    _prefs ??= await SharedPreferences.getInstance();
    final normalizedPath = path.trim();
    final key = _fontOverrideKeys[weight]!;
    final previousPath = _paths[weight];

    if (normalizedPath.isEmpty) {
      final nextPaths = Map<int, String>.from(_paths);
      final nextFamilies = Map<int, String>.from(_families);
      nextPaths.remove(weight);
      nextFamilies.remove(weight);
      await _prefs!.remove(key);
      await _deleteIfManaged(previousPath);
      _paths = nextPaths;
      _families = nextFamilies;
      notifyListeners();
      return true;
    }

    final storedPath = await _copyToManagedFonts('w$weight', normalizedPath);
    final family = await _registerFont(storedPath, tag: 'w$weight');
    if (family == null) {
      await _deleteIfManaged(storedPath);
      return false;
    }

    final nextPaths = Map<int, String>.from(_paths);
    final nextFamilies = Map<int, String>.from(_families);
    nextPaths[weight] = storedPath;
    nextFamilies[weight] = family;
    await _prefs!.setString(key, storedPath);
    if (previousPath != null && previousPath != storedPath) {
      await _deleteIfManaged(previousPath);
    }
    _paths = nextPaths;
    _families = nextFamilies;
    notifyListeners();
    return true;
  }

  Future<void> clearAll() async {
    _prefs ??= await SharedPreferences.getInstance();
    final managedPaths = <String>[
      ?_defaultPath,
      ..._paths.values,
    ];
    await _prefs!.remove(_fontDefaultKey);
    await _prefs!.remove(_fontModeKey);
    await _prefs!.remove(_fontFamilyKey);
    for (final key in _fontOverrideKeys.values) {
      await _prefs!.remove(key);
    }
    _mode = modeSystem;
    _systemFamily = '';
    _defaultPath = null;
    _defaultFamily = null;
    _paths = {};
    _families = {};
    for (final path in managedPaths) {
      await _deleteIfManaged(path);
    }
    notifyListeners();
  }

  TextTheme applyToTextTheme(TextTheme base) {
    return TextTheme(
      displayLarge: _apply(base.displayLarge),
      displayMedium: _apply(base.displayMedium),
      displaySmall: _apply(base.displaySmall),
      headlineLarge: _apply(base.headlineLarge),
      headlineMedium: _apply(base.headlineMedium),
      headlineSmall: _apply(base.headlineSmall),
      titleLarge: _apply(base.titleLarge),
      titleMedium: _apply(base.titleMedium),
      titleSmall: _apply(base.titleSmall),
      bodyLarge: _apply(base.bodyLarge),
      bodyMedium: _apply(base.bodyMedium),
      bodySmall: _apply(base.bodySmall),
      labelLarge: _apply(base.labelLarge),
      labelMedium: _apply(base.labelMedium),
      labelSmall: _apply(base.labelSmall),
    );
  }

  TextStyle? applyStyleForWeight(TextStyle? style, int weight) {
    if (style == null) return null;
    final family = resolveFontFamily(
      defaultFamily: _effectiveDefaultFamily,
      overrideFamilies: _families,
      weight: FontWeight.values
          .where((w) => w.value == weight)
          .firstOrNull,
    );
    if (family.isEmpty) return style;
    return style.copyWith(fontFamily: family);
  }

  TextStyle? _apply(TextStyle? style) {
    if (style == null) return null;
    final family = familyForWeight(style.fontWeight);
    if (family.isEmpty) return style;
    return style.copyWith(fontFamily: family);
  }

  Future<String?> _registerFont(String path, {required String tag}) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final family = 'user-font-$tag-${path.hashCode}';
      final loader = FontLoader(family);
      loader.addFont(
        Future.value(
          ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes),
        ),
      );
      await loader.load();
      return family;
    } catch (_) {
      return null;
    }
  }

  Future<String> _copyToManagedFonts(String tag, String sourcePath) async {
    final fileRoot = await getFilePath();
    final fontsDir = Directory(p.join(fileRoot, 'fonts'));
    if (!await fontsDir.exists()) {
      await fontsDir.create(recursive: true);
    }

    final originalName = p.basename(sourcePath);
    final sanitizedName = originalName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final targetPath = p.join(fontsDir.path, '${tag}_$sanitizedName');
    final sourceFile = File(sourcePath);
    final targetFile = File(targetPath);

    if (p.equals(sourceFile.path, targetFile.path)) {
      return targetFile.path;
    }

    await sourceFile.copy(targetFile.path);
    return targetFile.path;
  }

  Future<void> _deleteIfManaged(String? targetPath) async {
    if (targetPath == null || targetPath.isEmpty) return;
    final fontsDir = Directory(p.join(await getFilePath(), 'fonts'));
    final normalizedFontsDir = p.normalize(fontsDir.path);
    final normalizedTarget = p.normalize(targetPath);
    if (!p.isWithin(normalizedFontsDir, normalizedTarget) &&
        normalizedFontsDir != normalizedTarget) {
      return;
    }

    final file = File(targetPath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
