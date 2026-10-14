import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

typedef FileEnhancementStage =
    Future<bool> Function(String input, String output);

/// 两条处理链共用的缓存约束：独立结果、按源版本与有序参数去重、完整产物才发布。
class ImageEnhancementFileCache {
  final Map<String, Future<String?>> _pending = {};

  Future<String?> process({
    required String sourcePath,
    required Directory cacheDirectory,
    required String pipelineKey,
    required List<FileEnhancementStage> stages,
  }) async {
    if (stages.isEmpty) return null;
    final source = File(sourcePath);
    final stat = await source.stat();
    if (stat.type != FileSystemEntityType.file || stat.size == 0) return null;
    final sourceVersion = (stat.size, stat.modified, stat.changed);
    final key = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              source.absolute.path,
              stat.size,
              stat.modified.microsecondsSinceEpoch,
              stat.changed.microsecondsSinceEpoch,
              pipelineKey,
            ]),
          ),
        )
        .toString();
    final output = File(p.join(cacheDirectory.path, '$key.png'));
    if (await output.exists() && await output.length() > 0) return output.path;
    final pending = _pending[output.path];
    if (pending != null) return pending;
    final work = _produce(source, sourceVersion, output, stages);
    _pending[output.path] = work;
    try {
      return await work;
    } finally {
      if (identical(_pending[output.path], work)) _pending.remove(output.path);
    }
  }

  Future<String?> _produce(
    File source,
    (int, DateTime, DateTime) version,
    File output,
    List<FileEnhancementStage> stages,
  ) async {
    await output.parent.create(recursive: true);
    final temporary = <File>[];
    var input = source.path;
    try {
      for (final stage in stages) {
        final file = File(
          p.join(output.parent.path, 'pending_${const Uuid().v4()}.png'),
        );
        temporary.add(file);
        if (!await stage(input, file.path) ||
            !await file.exists() ||
            await file.length() == 0) {
          return null;
        }
        input = file.path;
      }
      final current = await source.stat();
      if ((current.size, current.modified, current.changed) != version) {
        return null;
      }
      // 源在处理期间改变时丢弃结果，旧版缓存不能成为新版源的画面。
      await temporary.last.rename(output.path);
      return output.path;
    } finally {
      for (final file in temporary) {
        if (await file.exists()) await file.delete();
      }
    }
  }
}
