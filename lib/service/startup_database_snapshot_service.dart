import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:zephyr/main.dart' as app;
import 'package:zephyr/object_box/object_box.dart';
import 'package:zephyr/src/rust/api/simple.dart';
import 'package:zephyr/util/get_path.dart';
import 'package:zephyr/util/rust_loader.dart';

const _startupDatabaseSnapshotFileName = 'database_snapshot.br';

/// 现在是 2026年8月20日23:07:18
/// 目标为一年后删除Objectbox依赖改为sqlite，目前为迁移期
/// 先将数据保存至本地，以便后续迁移
/// 启动时异步生成数据库快照。
///
/// 读取数据库、序列化、Brotli 压缩和写文件都交给 ObjectBox 的后台
/// isolate，UI isolate 只传递目标路径。
Future<void> saveStartupDatabaseSnapshot() async {
  try {
    final snapshotPath = p.join(
      await getFilePath(),
      _startupDatabaseSnapshotFileName,
    );

    await app.objectbox.store.runAsync<String, void>((store, path) async {
      await initRustLib(silent: true);
      final backgroundObjectBox = ObjectBox.fromStore(store);
      final json = backgroundObjectBox.collectAllDataJson();
      final compressed = await compressExtreme(data: utf8.encode(json));

      // FileMode.write 会截断旧文件，确保每次启动都覆盖上一次快照。
      await File(path).writeAsBytes(compressed, flush: true);
    }, snapshotPath);
    app.logger.i('数据库启动快照已更新：$snapshotPath');
  } catch (error, stackTrace) {
    // 快照属于辅助功能，失败时不能影响应用启动。
    app.logger.e('更新数据库启动快照失败', error: error, stackTrace: stackTrace);
  }
}
