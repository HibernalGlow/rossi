import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/network/sync/sync_device_id.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/service/app_identity/data_migration.dart';
import 'package:zephyr/service/app_identity/desktop_preferences.dart';
import 'package:zephyr/service/app_identity/identity_paths.dart';

Map<String, dynamic>? identityMigrationNotice;

/// 在打开 ObjectBox、生成设备 ID、加载全局设置之前完成首启迁移。
Future<void> prepareAppIdentity() async {
  final root = await applicationDataRoot();
  final migration = AppDataMigration(Directory(root));
  final previous = await migration.readMarker();
  final isMobile = Platform.isAndroid || Platform.isIOS;
  String? legacyWindowsSupport;
  if (Platform.isWindows) {
    final roaming = Platform.environment['APPDATA'];
    if (roaming != null) {
      legacyWindowsSupport = p.join(roaming, 'com.example', 'Rossi');
    }
  }
  var quarantinedNow = false;
  var result = <String, dynamic>{};
  try {
    result = await migration.run(
      isMobile
          ? const []
          : legacyDesktopData(
              target: root,
              operatingSystem: Platform.operatingSystem,
              environment: Platform.environment,
              legacyWindowsSupport: legacyWindowsSupport,
            ),
      validateCopy: (stage) async {
        final store = await openStore(
          directory: p.join(stage.path, 'db', 'breeze_db'),
        );
        store.close();
      },
    );
  } catch (error, stackTrace) {
    // 迁移失败时继续启动；旧目录、临时副本和重试机会都保留。
    debugPrint('Rossi 首启数据迁移失败，旧数据保持不动：$error\n$stackTrace');
    result = <String, dynamic>{'status': 'error', 'error': '$error'};
  }
  if (result['status'] == 'copied') {
    final quarantined = await _quarantineIfModelTooNew(migration, result);
    if (quarantined != null) {
      result = quarantined;
      quarantinedNow = true;
    }
  }
  if (result['status'] == 'copied' && result['preferencesImported'] != true) {
    // 只有真导进去了才记账：写失败时保持 marker 里的「未导入」，下次启动重试。
    if (await _importDesktopPreferences(root)) {
      result['preferencesImported'] = true;
      await migration.marker.writeAsString(jsonEncode(result), flush: true);
    }
  }
  if (previous == null || quarantinedNow) {
    var legacyMobileApp = Platform.isIOS;
    if (Platform.isAndroid) {
      try {
        legacyMobileApp =
            await const MethodChannel('com.zephyr.breeze/file_picker')
                .invokeMethod<bool>('isLegacyAppInstalled') ??
            false;
      } catch (error) {
        // 通道没注册（旧包、纯 Dart 测试宿主）时按「没装旧版」处理即可，
        // 这条探测只决定要不要弹迁移提示。
        debugPrint('检测旧版安卓应用失败，按未安装处理：$error');
      }
    }
    if (result['status'] == 'copied' ||
        result['status'] == 'incompatible' ||
        result['status'] == 'error' ||
        legacyMobileApp ||
        (Platform.isLinux && result['status'] == 'fresh')) {
      identityMigrationNotice = result;
    }
  }
  try {
    await ensureSyncDeviceId();
  } catch (error, stackTrace) {
    // 设备 ID 只影响同步端的身份（拿不到时是占位值），同样不该挡住启动。
    debugPrint('生成同步设备 ID 失败，本次按占位值启动：$error\n$stackTrace');
  }
}

/// 迁移过来的库若打不开（旧版 Breeze 的模型比本仓新），就地让开。
///
/// 判据只认「DB 的 entity ID 比模型高」这一条：那说明这份副本是本仓读不了的新
/// 结构，留着只会让启动停在「数据库不兼容」页。其它失败（被别的进程占着、磁盘
/// 错误）**不能**动库，否则会把还能用的数据改名藏起来。
///
/// 探过一次就在 marker 里记 `dbOpened`，之后不再重复开库 —— 这条只是给
/// 「迁移时没做校验的老副本」补一次体检，不是每次启动都要多开一次 Store。
Future<Map<String, dynamic>?> _quarantineIfModelTooNew(
  AppDataMigration migration,
  Map<String, dynamic> record,
) async {
  if (record['dbOpened'] == true) return null;
  final db = Directory(p.join(migration.destination.path, 'db', 'breeze_db'));
  if (!await db.exists()) return null;
  try {
    final store = await openStore(directory: db.path);
    store.close();
    record['dbOpened'] = true;
    await migration.marker.writeAsString(jsonEncode(record), flush: true);
    return null;
  } catch (error) {
    final message = '$error';
    if (!message.contains('higher than') || !message.contains('from model')) {
      return null;
    }
    debugPrint('迁移副本的模型比本仓新，改名保留并全新开始：$error');
    return migration.quarantineDatabase(record, error);
  }
}

Future<bool> _importDesktopPreferences(String root) async {
  try {
    await _applyDesktopPreferences(root);
    return true;
  } catch (error, stackTrace) {
    // 偏好导入是「锦上添花」：整段（读文件 + 写偏好）都不许把启动带崩。
    // 这里曾经把 plutil 的失败抛给调用方，结果是**老用户直接看不到界面**
    // （`_initServices` 抛到启动失败页），而真正失败的原因只是旧 plist 里
    // 混着 AppKit 写的 `<data>` —— `plutil -convert json` 见到它就整份放弃。
    debugPrint('旧版偏好设置导入失败，已跳过（原文件保留）：$error\n$stackTrace');
    return false;
  }
}

Future<void> _applyDesktopPreferences(String root) async {
  final preferences = await SharedPreferences.getInstance();
  // 旧应用写过同步端身份：已经随数据目录复制过来了，这里先摘掉，两个并存
  // 应用各用各的设备 ID（下面按 key 过滤时也会跳过同一个键）。
  await preferences.remove('sync.device_id');
  final data = await _readLegacyPreferences(root);
  if (data == null) return;
  for (final entry in data.entries) {
    if (!entry.key.startsWith('flutter.')) continue;
    final key = entry.key.substring('flutter.'.length);
    // 两个并存应用是两个同步端，不复用旧应用的设备 ID。
    if (key == 'sync.device_id' || preferences.containsKey(key)) continue;
    final value = entry.value;
    final bool saved;
    if (value is bool) {
      saved = await preferences.setBool(key, value);
    } else if (value is int) {
      saved = await preferences.setInt(key, value);
    } else if (value is double) {
      saved = await preferences.setDouble(key, value);
    } else if (value is String) {
      saved = await preferences.setString(key, value);
    } else if (value is List && value.every((item) => item is String)) {
      saved = await preferences.setStringList(key, value.cast<String>());
    } else {
      continue;
    }
    if (!saved) throw FileSystemException('写入迁移偏好设置失败', key);
  }
}

Future<Map<String, dynamic>?> _readLegacyPreferences(String root) async {
  if (!Platform.isMacOS) {
    return readJsonPreferences(File(p.join(root, 'shared_preferences.json')));
  }
  final home = Platform.environment['HOME'];
  if (home == null) return null;
  return readMacPreferencesPlist(
    File(p.join(home, 'Library', 'Preferences', '$legacyAppIdentity.plist')),
  );
}
