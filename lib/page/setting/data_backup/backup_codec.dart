import 'dart:convert';

import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/network/sync/sync_service.dart';
import 'package:zephyr/object_box/model.dart';

/// 接受上游旧 ZIP 格式，拒绝误选文件及无法理解的新格式。
void validateBackupManifest(Map<String, dynamic> manifest) {
  final format = manifest['format'];
  final version = manifest['formatVersion'];
  if ((format != null && format != 'rossi-data-backup') ||
      (version != null && version != 2) ||
      (format != null && version == null) ||
      (manifest['includeDownloads'] != null &&
          manifest['includeDownloads'] is! bool) ||
      manifest['version'] is! String) {
    throw const FormatException('不支持的应用备份格式');
  }
}

Map<String, dynamic> _globalJson(Map<String, dynamic> setting) {
  final decoded = setting['globalSetting'];
  if (decoded != null) return Map<String, dynamic>.from(decoded as Map);
  final encoded = setting['globalSettingData'];
  if (encoded == null || encoded == '') return {};
  return Map<String, dynamic>.from(jsonDecode(encoded as String) as Map);
}

/// ObjectBox 会同时输出字符串和解码后的设置，两份都必须过滤。
void sanitizeBackupSettings(Map<String, dynamic> data) {
  final settings = data['userSetting'] as List?;
  if (settings == null) return;
  for (var index = 0; index < settings.length; index++) {
    final setting = Map<String, dynamic>.from(settings[index] as Map);
    final portable = exportPortableGlobalSetting(
      importPortableGlobalSetting(
        const GlobalSettingState(),
        _globalJson(setting),
      ),
    );
    setting['globalSetting'] = portable;
    setting['globalSettingData'] = jsonEncode(portable);
    settings[index] = setting;
  }
}

/// 所有要恢复的实体先反序列化成功，再允许调用方清库。
/// 同时兼容旧全量设置与新可迁移设置，缺失的偏好保留目标设备的值。
Map<String, dynamic> prepareBackupData(
  Map<String, dynamic> data, {
  required GlobalSettingState currentSettings,
  required bool includeDownloads,
}) {
  final parsers = <String, Object Function(Map<String, dynamic>)>{
    'bikaComicHistory': BikaComicHistory.fromJson,
    'bikaComicDownload': BikaComicDownload.fromJson,
    'jmFavorite': JmFavorite.fromJson,
    'jmHistory': JmHistory.fromJson,
    'jmDownload': JmDownload.fromJson,
    'unifiedComicFavorite': UnifiedComicFavorite.fromJson,
    'unifiedComicHistory': UnifiedComicHistory.fromJson,
    'comicFollow': ComicFollow.fromJson,
    'unifiedComicDownload': UnifiedComicDownload.fromJson,
    'userSetting': UserSetting.fromJson,
    'pluginConfig': PluginConfig.fromJson,
    'pluginInfo': PluginInfo.fromJson,
    'comicFolder': ComicFolder.fromJson,
    'comicLink': ComicLink.fromJson,
    'comicReadPreference': ComicReadPreference.fromJson,
    'comicChapterReadMark': ComicChapterReadMark.fromJson,
  };
  if (!parsers.keys.any(data.containsKey)) {
    throw const FormatException('备份缺少应用数据');
  }
  const downloadKeys = {
    'bikaComicDownload',
    'jmDownload',
    'unifiedComicDownload',
  };
  final result = <String, dynamic>{};
  for (final entry in parsers.entries) {
    if (!includeDownloads && downloadKeys.contains(entry.key)) continue;
    final raw = data[entry.key];
    if (raw == null) continue;
    final items = <Map<String, dynamic>>[];
    for (final item in raw as List) {
      final json = Map<String, dynamic>.from(item as Map)..['id'] = 0;
      if (!includeDownloads &&
          (entry.key == 'comicFolder' || entry.key == 'comicLink') &&
          json['typeData'] == 'download') {
        continue;
      }
      if (entry.key == 'userSetting') {
        final merged = importPortableGlobalSetting(
          currentSettings,
          _globalJson(json),
        );
        json['globalSetting'] = merged.toJson();
        json['globalSettingData'] = jsonEncode(merged.toJson());
      }
      entry.value(json);
      items.add(json);
    }
    result[entry.key] = items;
  }
  return result;
}
