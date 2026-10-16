import 'package:path/path.dart' as p;
import 'package:zephyr/util/path_util.dart';

const Set<String> _archiveExtensions = <String>{
  '.zip',
  '.cbz',
  '.rar',
  '.cbr',
  '.7z',
  '.tar',
};

/// 单张图 / 单文件形态的本地漫画：文件管理该开它**所在目录**，
/// 而不是拿这个文件当目录去列。
const Set<String> _singleFileExtensions = <String>{
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.avif',
  '.gif',
  '.bmp',
  '.tif',
  '.tiff',
};

final RegExp _windowsDrivePath = RegExp(r'^[a-z]:[\\/]');

/// 这条漫画在**文件管理**里应该打开的目录；没有本地目录时返回 `null`
/// （= 菜单里那一项置灰）。
///
/// 三种输入，三条分支：
///
/// - **归档**（`.zip`/`.cbz`/…）：开它所在的目录 —— 文件管理列的是目录，
///   把归档文件本身送进去只会得到一个错误；
/// - **单张图**：同上，开它所在目录；
/// - **目录**：原样打开。
///
/// 已知文件类型时由 [isDirectory] 指定，避免把带扩展名的目录当成文件。
/// 网络地址与插件漫画 id（`bika` 之类）一律 `null`：它们没有磁盘位置。
String? resolveFileManagerTabPath(String comicId, {bool? isDirectory}) {
  final raw = comicId.trim();
  if (raw.isEmpty) return null;
  if (isNetworkAddress(raw)) return null;

  final lower = raw.toLowerCase();
  // 路径风格决定用哪套分隔符：`package:path` 的默认 context 跟着**跑判据的
  // 那台机器**走，于是 macOS 上 `p.dirname(r'D:\library\a.cbz')` 会返回 `.`
  // ——「Windows 盘符路径」这条分支在开发机上永远解析不出来，只有 CI/Windows
  // 上才碰巧对。所以按输入自身的形状选 context。
  final looksWindows = _windowsDrivePath.hasMatch(lower);
  if (!looksWindows && !lower.startsWith('/')) return null;
  final ctx = looksWindows ? p.windows : p.posix;

  if (isDirectory == true) return raw;
  final ext = ctx.extension(lower);
  if (isDirectory == false ||
      _archiveExtensions.contains(ext) ||
      _singleFileExtensions.contains(ext)) {
    final dir = ctx.dirname(raw);
    return (dir.isEmpty || dir == '.' || dir == raw) ? null : dir;
  }
  return raw;
}
