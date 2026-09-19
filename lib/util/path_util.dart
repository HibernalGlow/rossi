import 'package:path/path.dart' as p;

/// 将任意字符串清理为可作为文件/路径段的安全名称。
///
/// 只保留字母、数字、下划线、连字符和点号，其余字符替换为下划线，
/// 并压缩连续下划线、去除首尾下划线。若结果为空则返回 [fallback]。
String sanitizePathSegment(String input, {String fallback = 'cover'}) {
  final sanitized = input
      .replaceAll(RegExp(r'[^a-zA-Z0-9_\-.]'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return sanitized.isEmpty ? fallback : sanitized;
}

/// 从图片 URL 中提取扩展名。
///
/// 只返回由字母数字组成、长度 1-8 的扩展名，否则返回 'jpg'。
String extractImageExtension(String url) {
  try {
    final uri = Uri.parse(url);
    final ext = p.extension(uri.path).replaceFirst('.', '').toLowerCase();
    if (RegExp(r'^[a-z0-9]{1,8}$').hasMatch(ext)) {
      return ext;
    }
  } catch (_) {}
  return 'jpg';
}

/// Windows 盘符路径：`C:\...` / `C:/...`（必须锚定在**串首**）。
///
/// 旧实现用 `contains(':/')`，于是任何含 `://` 的网络地址都被当成盘符路径。
final RegExp _windowsDrivePath = RegExp(r'^[a-z]:[\\/]');

/// 协议相对地址 `//host/...` 里跟在 `//` 后面的这一段是否像主机名。
///
/// 只有含 `.`（域名）或 `:`（端口）时才认定是网络地址；否则
/// `//foo/bar` 视为 POSIX 双斜杠路径，仍按本地路径处理。
bool _hostLooksLikeNetworkHost(String rest) {
  final end = rest.indexOf(RegExp(r'[/?#]'));
  final host = end < 0 ? rest : rest.substring(0, end);
  return host.contains('.') || host.contains(':');
}

/// 是否为网络地址（`http://…` / `https://…` / 协议相对 `//host/…`）。
///
/// 网络地址永远不是磁盘路径，必须在盘符与分隔符判定**之前**排除：
/// `http://img.cdn/a.jpg` 含 `:/`、`//img.cdn/a.jpg` 以 `/` 开头，
/// 两者都会被非锚定的旧判据认成"本地来源"。而 `getCachePicture` 一旦走本地分支，
/// 因为目标既不是真文件、`ensureLocalComicCover` 也返回 null，就会返回哨兵串
/// `'404'` —— 请求根本没发出去，界面上显示为 404 占位图。
bool isNetworkAddress(String value) {
  final lower = value.trim().toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return true;
  }
  if (lower.startsWith('//')) {
    return _hostLooksLikeNetworkHost(lower.substring(2));
  }
  return false;
}

/// 判断是否为本地漫画来源
///
/// 第二个参数在不同调用点语义不同：多数是 comicId（插件 id 或本地路径），
/// 而 `getCachePicture` / `downloadImageWithRetry` 传的是图片 url，
/// 所以这里必须同时容忍"路径"与"URL"两种输入 —— 见 [isNetworkAddress]。
bool isLocalComicSource(String from, String comicId) {
  if (from == 'local' || from == 'local_source') {
    return true;
  }
  final lower = comicId.trim().toLowerCase();
  if (isNetworkAddress(lower)) {
    return false;
  }
  return lower.startsWith('/') ||
      _windowsDrivePath.hasMatch(lower) ||
      lower.endsWith('.zip') ||
      lower.endsWith('.cbz') ||
      lower.endsWith('.rar') ||
      lower.endsWith('.cbr') ||
      lower.endsWith('.7z') ||
      lower.endsWith('.tar');
}
