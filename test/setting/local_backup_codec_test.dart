import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/setting/data_backup/backup_codec.dart';

void main() {
  Map<String, dynamic> record(GlobalSettingState state) =>
      (UserSetting()..globalSetting = state).toJson();

  test('导出的两份全局设置均排除本机事实，覆盖每条设置记录', () {
    const source = GlobalSettingState(
      customExportPath: '/desktop/export',
      socks5Proxy: '127.0.0.1:7890',
      windowWidth: 1920,
      downloadConcurrency: 7,
    );
    final data = <String, dynamic>{
      'userSetting': [record(source), record(source)],
    };
    sanitizeBackupSettings(data);
    for (final item in data['userSetting'] as List) {
      for (final raw in [
        item['globalSetting'],
        jsonDecode(item['globalSettingData'] as String),
      ]) {
        expect(raw['downloadConcurrency'], 7);
        expect(raw.containsKey('customExportPath'), isFalse);
        expect(raw.containsKey('socks5Proxy'), isFalse);
        expect(raw.containsKey('windowWidth'), isFalse);
        expect(raw.containsKey('syncSetting'), isFalse);
        expect(raw.containsKey('appLockSetting'), isFalse);
      }
    }
  });

  for (final serializedOnly in [false, true]) {
    test('旧备份保留目标设备的本机配置及未提供偏好 $serializedOnly', () {
      final item = record(const GlobalSettingState());
      final sparse = {'downloadConcurrency': 7, 'windowWidth': '损坏但不迁移'};
      item['globalSettingData'] = jsonEncode(sparse);
      if (serializedOnly) {
        item.remove('globalSetting');
      } else {
        item['globalSetting'] = sparse;
      }
      final result = prepareBackupData(
        {
          'userSetting': [item],
        },
        currentSettings: const GlobalSettingState(
          customExportPath: '/mobile/export',
          windowWidth: 412,
          socks5Proxy: '10.0.0.2:1080',
          downloadTaskConcurrency: 5,
        ),
        includeDownloads: false,
      );
      final setting = UserSetting.fromJson(
        (result['userSetting'] as List).first,
      ).globalSetting;
      expect(setting.downloadConcurrency, 7);
      expect(setting.customExportPath, '/mobile/export');
      expect(setting.windowWidth, 412);
      expect(setting.socks5Proxy, '10.0.0.2:1080');
      expect(setting.downloadTaskConcurrency, 5);
    });
  }

  test('设置 JSON 损坏时导出失败，不能输出未过滤的设置', () {
    expect(
      () => sanitizeBackupSettings({
        'userSetting': [
          {'globalSettingData': 'invalid json'},
        ],
      }),
      throwsFormatException,
    );
  });

  test('损坏的实体在清库之前校验失败', () {
    expect(
      () => prepareBackupData(
        {
          'unifiedComicHistory': [{}],
        },
        currentSettings: const GlobalSettingState(),
        includeDownloads: false,
      ),
      throwsA(isA<TypeError>()),
    );
    expect(
      () => prepareBackupData(
        {},
        currentSettings: const GlobalSettingState(),
        includeDownloads: false,
      ),
      throwsFormatException,
    );
  });

  test('不含下载文件的备份不会引入异机下载记录或目录', () {
    final result = prepareBackupData(
      {
        'unifiedComicDownload': [{}],
        'comicFolder': [
          {'typeData': 'download'},
        ],
        'comicLink': [
          {'typeData': 'download'},
        ],
        'userSetting': [],
      },
      currentSettings: const GlobalSettingState(),
      includeDownloads: false,
    );
    expect(result.containsKey('unifiedComicDownload'), isFalse);
    expect(result['comicFolder'], isEmpty);
    expect(result['comicLink'], isEmpty);
  });

  test('支持旧备份，拒绝其他格式或未知新版本', () {
    validateBackupManifest({'version': '1.0.0', 'includeDownloads': false});
    validateBackupManifest({
      'format': 'rossi-data-backup',
      'formatVersion': 2,
      'version': '1.0.0',
    });
    expect(
      () => validateBackupManifest({'format': 'other', 'version': '1.0.0'}),
      throwsFormatException,
    );
    expect(
      () => validateBackupManifest({
        'format': 'rossi-data-backup',
        'formatVersion': 3,
        'version': '1.0.0',
      }),
      throwsFormatException,
    );
  });
}
