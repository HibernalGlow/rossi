import 'dart:io';

import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;

/// 把 cargo 的 target 目录从「输入哈希工作区内部」重定向到一个稳定目录，
/// 让 native-assets 构建能跨哈希增量复用。
///
/// 为什么要重定向：`native_toolchain_rust` 用 `input.outputDirectory` 拼
/// `--target-dir`，而 `outputDirectory` 的目录名是整个 HookInput 的 checksum，
/// 其中含 `package_root` 绝对路径与全部 config 字段。于是搬一次仓、升一次
/// SDK 就翻一次哈希，hooks_runner 新建整份 cargo 缓存且**永不回收旧目录**
/// （上游 `build_runner.dart` 里 `TODO dartbug.com/50565 Purge old or unused
/// folders` 至今未实现）。本仓实测：一次搬仓 + 一次 config 变更堆出 4 份
/// 2-5G 缓存，共 15.8G。
///
/// 为什么只能走软链：`--target-dir` 重复传会被 cargo 直接拒绝（实测报
/// "the argument '--target-dir' cannot be used multiple times"），而产物路径
/// 又由同一个 `outputDirectory` 回读，所以改传参或设 `CARGO_TARGET_DIR` 都不
/// 成立 —— 只能让这个路径本身指向稳定目录。
///
/// 稳定目录默认 `packageRoot/rust/target/native-assets`（被 `rust/.gitignore`
/// 的 `/target` 覆盖，不脏工作区；也刻意不与 `rust/gpu_present/target` 混用，
/// 见 `windows/runner/CMakeLists.txt` 的隔离说明）。构建环境可用
/// `ROSSI_NATIVE_ASSETS_TARGET_DIR` 覆写 —— Windows 上产物要留 D 盘时就设它。
Future<void> useSharedCargoTargetDirectory(HookInput input) async {
  final override = Platform.environment['ROSSI_NATIVE_ASSETS_TARGET_DIR'];
  final stableDir = Directory(
    override != null && override.isNotEmpty
        ? override
        : p.join(
            input.packageRoot.toFilePath(),
            'rust',
            'target',
            'native-assets',
          ),
  );
  final linkPath = p.join(input.outputDirectory.toFilePath(), 'target');
  final link = Link(linkPath);

  if (await link.exists()) {
    if (p.equals(link.targetSync(), stableDir.absolute.path)) return;
    await link.delete();
  } else if (await Directory(linkPath).exists()) {
    // 已有一份真实目录＝上一次独立构建的缓存，不静默删别人的产物。
    if (!await Directory(linkPath).list().isEmpty) {
      stderr.writeln(
        '[rossi-hook] $linkPath 已是真实目录，保持原行为（不共享、不清理）',
      );
      return;
    }
    await Directory(linkPath).delete();
  }

  try {
    await stableDir.create(recursive: true);
    await link.create(stableDir.absolute.path);
  } on Object catch (error) {
    // Windows 上没有符号链接权限时退回上游原行为：能编，只是不共享缓存。
    stderr.writeln('[rossi-hook] 稳定 target 软链创建失败，退回原行为: $error');
    await Directory(linkPath).create(recursive: true);
  }
}
