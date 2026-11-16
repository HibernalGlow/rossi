import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const appIdentity = 'com.hibernalglow.rossi';
const legacyAppIdentity = 'com.zephyr.breeze';

/// 只复制应用自己的持久数据；不搬缓存、可执行文件或数据库锁文件。
class LegacyAppData {
  const LegacyAppData(this.root, {this.extraEntries = const {}});

  final String root;
  final Map<String, String> extraEntries;

  Map<String, String> get entries => {
    for (final name in ['db', 'files', 'zephyr', 'shared_preferences.json'])
      name: p.join(root, name),
    ...extraEntries,
  };
}

/// 首启复制的事务边界是整个新数据根目录。失败时旧数据、新的半成品均保留。
/// 发布前再次读取源清单及摘要，拒绝复制期间仍在写入的旧数据库。
class AppDataMigration {
  AppDataMigration(this.destination);

  final Directory destination;
  static const markerName = '.rossi-identity-v1.json';

  File get marker => File(p.join(destination.path, markerName));

  Future<Map<String, dynamic>?> readMarker() async {
    if (!await marker.exists()) return null;
    return jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> run(
    List<LegacyAppData> candidates, {
    Future<void> Function(Directory stage)? validateCopy,
  }) async {
    await destination.parent.create(recursive: true);
    final lock = await File('${destination.path}.identity-migration.lock')
        .open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.blockingExclusive);
      return await _run(candidates, validateCopy: validateCopy);
    } finally {
      await lock.close();
    }
  }

  Future<Map<String, dynamic>> _run(
    List<LegacyAppData> candidates, {
    Future<void> Function(Directory stage)? validateCopy,
  }) async {
    final previous = await readMarker();
    if (previous != null) return previous;
    // 绝不覆盖已经使用中的新库，即便用户手工删掉了迁移记录。
    if (await File(p.join(destination.path, 'db', 'breeze_db', 'data.mdb'))
        .exists()) {
      return _record('existing');
    }
    LegacyAppData? source;
    for (final candidate in candidates) {
      if (p.equals(
        p.normalize(candidate.root),
        p.normalize(destination.path),
      )) {
        continue;
      }
      if (await File(p.join(candidate.root, 'db', 'breeze_db', 'data.mdb'))
          .exists()) {
        source = candidate;
        break;
      }
    }
    if (source == null) return _record('fresh');

    final before = await _manifest(source.entries);
    await destination.parent.create(recursive: true);
    final stage = await destination.parent.createTemp(
      '${p.basename(destination.path)}.migrating-',
    );
    for (final item in before.entries) {
      final relative = item.key;
      final input = File(_sourcePath(source.entries, relative));
      final output = File(p.join(stage.path, relative));
      await output.parent.create(recursive: true);
      await input.copy(output.path);
      if (await _digest(output) != item.value) {
        throw FileSystemException('迁移副本校验失败，原数据保留', input.path);
      }
    }
    final after = await _manifest(source.entries);
    if (jsonEncode(before) != jsonEncode(after)) {
      throw FileSystemException('旧应用仍在写入数据，请关闭 Breeze 后重试；原数据保留', source.root);
    }
    await validateCopy?.call(stage);
    final record = <String, dynamic>{
      'status': 'copied',
      'source': source.root,
      'sourcePreserved': true,
      'fileCount': before.length,
      'completedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await File(p.join(stage.path, markerName))
        .writeAsString(jsonEncode(record), flush: true);
    // path_provider 可能已经创建空目录。若其中有内容，先改名保留而非删除。
    if (await destination.exists()) {
      final saved = await destination.parent.createTemp(
        '${p.basename(destination.path)}.before-migration-',
      );
      await saved.delete(); // 这里只删除本次创建的空占位目录。
      await destination.rename(saved.path);
    }
    await stage.rename(destination.path);
    return record;
  }

  Future<Map<String, dynamic>> _record(String status) async {
    final record = <String, dynamic>{'status': status};
    await destination.create(recursive: true);
    await marker.writeAsString(jsonEncode(record), flush: true);
    return record;
  }

  static String _sourcePath(Map<String, String> roots, String relative) {
    final parts = p.split(relative);
    return p.joinAll([roots[parts.first]!, ...parts.skip(1)]);
  }

  static Future<String> _digest(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static Future<Map<String, String>> _manifest(
    Map<String, String> roots,
  ) async {
    final files = <String, String>{};
    Future<void> visit(String source, String relative) async {
      final type = await FileSystemEntity.type(source, followLinks: false);
      if (type == FileSystemEntityType.notFound) return;
      if (type == FileSystemEntityType.link) {
        throw FileSystemException('自动迁移不跟随符号链接，请使用备份导入', source);
      }
      if (type == FileSystemEntityType.directory) {
        final children = await Directory(source)
            .list(followLinks: false)
            .toList();
        children.sort((a, b) => a.path.compareTo(b.path));
        for (final child in children) {
          if (p.basename(child.path) == 'lock.mdb') continue;
          await visit(child.path, p.join(relative, p.basename(child.path)));
        }
      } else if (type == FileSystemEntityType.file) {
        files[relative] = await _digest(File(source));
      } else {
        throw FileSystemException('不支持的迁移文件类型', source);
      }
    }

    for (final entry in roots.entries) {
      await visit(entry.value, entry.key);
    }
    return files;
  }
}
