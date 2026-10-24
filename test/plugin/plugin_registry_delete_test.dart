import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart' as log;
import 'package:path/path.dart' as p;
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';

import '../test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? pathProviderRoot;
  late final log.Level previousLoggerLevel;

  setUpAll(() async {
    // 开关打开的那条会触发未等待的磁盘清理；测试里没有 Rust，
    // 清理失败会被生产代码捕获，这里静音日志避免把预期噪音当成失败。
    previousLoggerLevel = log.Logger.level;
    log.Logger.level = log.Level.off;
    pathProviderRoot = await Directory.systemTemp.createTemp('breeze_paths_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => pathProviderRoot!.path,
        );
    await TestObjectBoxHelper.setUpTestObjectBox();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await TestObjectBoxHelper.tearDownTestObjectBox();
    log.Logger.level = previousLoggerLevel;
    final root = pathProviderRoot;
    if (root != null && await root.exists()) {
      await root.delete(recursive: true);
    }
    pathProviderRoot = null;
  });

  setUp(() async {
    objectbox.pluginInfoBox.removeAll();
    objectbox.pluginConfigBox.removeAll();
    objectbox.downloadTaskBox.removeAll();
    TestObjectBoxHelper.cleanComicFolderBoxes();
    await PluginRegistryService.I.init();
  });

  tearDown(() {
    PluginRegistryService.resetDownloadRootProviderForTests();
    TestObjectBoxHelper.cleanComicFolderBoxes();
  });

  PluginInfo pluginInfo(String uuid) => PluginInfo(
    uuid: uuid,
    version: '1.0.0',
    originScript: 'module.exports = {};',
    lastLoadSuccess: true,
    lastLoadError: null,
    insertedAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
    isEnabled: true,
    isDeleted: false,
    debug: false,
    getInfoJson: '{}',
  );

  void seedSource(String uuid) {
    objectbox.pluginInfoBox.put(pluginInfo(uuid));
    objectbox.pluginConfigBox.put(
      PluginConfig(name: uuid, config: '{"auth.account":"tester"}'),
    );
    objectbox.unifiedFavoriteBox.put(
      createTestFavorite('$uuid:1')..source = uuid,
    );
    objectbox.unifiedHistoryBox.put(
      createTestHistory('$uuid:1')..source = uuid,
    );
  }

  test('默认只删插件，保留该源的收藏、历史与下载记录', () async {
    const uuid = 'plugin-keep';
    seedSource(uuid);
    final download = createTestDownload('$uuid:1')..source = uuid;
    objectbox.unifiedDownloadBox.put(download);

    var downloadRootCalls = 0;
    PluginRegistryService.downloadRootProviderForTests = () async {
      downloadRootCalls += 1;
      return Directory.systemTemp.path;
    };

    await PluginRegistryService.I.deletePlugin(uuid);

    final stored = objectbox.pluginInfoBox
        .query(PluginInfo_.uuid.equals(uuid))
        .build()
        .findFirst();
    expect(stored, isNotNull);
    expect(stored!.isDeleted, isTrue);
    expect(stored.isEnabled, isFalse);
    expect(stored.originScript, isEmpty);
    expect(
      objectbox.pluginConfigBox
          .query(PluginConfig_.name.equals(uuid))
          .build()
          .findFirst(),
      isNull,
      reason: '插件配置与登录信息始终随插件一起删除',
    );
    expect(downloadRootCalls, 0, reason: '默认不碰下载目录');
    expect(
      objectbox.unifiedFavoriteBox
          .query(UnifiedComicFavorite_.source.equals(uuid))
          .build()
          .findFirst()!
          .deleted,
      isFalse,
    );
    expect(
      objectbox.unifiedHistoryBox
          .query(UnifiedComicHistory_.source.equals(uuid))
          .build()
          .findFirst()!
          .deleted,
      isFalse,
    );
    expect(objectbox.unifiedDownloadBox.get(download.id), isNotNull);
  });

  test('显式清理会删掉该源数据与下载目录', () async {
    const uuid = 'plugin-purge';
    final temp = await Directory.systemTemp.createTemp('breeze_plugin_delete_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final downloadRoot = p.join(temp.path, 'downloads');
    final sourceDir = Directory(p.join(downloadRoot, uuid));
    await sourceDir.create(recursive: true);
    await File(p.join(sourceDir.path, 'page.jpg')).writeAsString('x');

    seedSource(uuid);
    final download = createTestDownload('$uuid:1')..source = uuid;
    objectbox.unifiedDownloadBox.put(download);
    PluginRegistryService.downloadRootProviderForTests = () async =>
        downloadRoot;

    await PluginRegistryService.I.deletePlugin(uuid, deleteRelatedData: true);
    await Future<void>.delayed(Duration.zero);

    expect(sourceDir.existsSync(), isFalse);
    expect(
      objectbox.unifiedFavoriteBox
          .query(UnifiedComicFavorite_.source.equals(uuid))
          .build()
          .findFirst()!
          .deleted,
      isTrue,
    );
    expect(
      objectbox.unifiedHistoryBox
          .query(UnifiedComicHistory_.source.equals(uuid))
          .build()
          .findFirst()!
          .deleted,
      isTrue,
    );
    expect(objectbox.unifiedDownloadBox.get(download.id), isNull);
  });
}
