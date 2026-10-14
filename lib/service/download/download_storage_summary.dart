/// 下载占用统计的纯部分：一本漫画的落盘量怎么表达、多本怎么合计、字节怎么写成人话。
///
/// 与 `download_storage_layout.dart` 分开，是因为「目录在哪、占多少」要碰文件系统与
/// 数据库，而那一条闭包会拖着整个 app；判据留在这里才测得动。
library;

/// 一本漫画的落盘统计。
class DownloadStorageStat {
  const DownloadStorageStat({
    required this.bytes,
    required this.measured,
    required this.rootCount,
  });

  final int bytes;

  /// 有没有真的找到目录。没找到时 [bytes] 是 0，但**不能**显示成「0 B」——
  /// 那句假话会被读成「这本漫画没占地方」，而真实情况可能是目录换了布局、
  /// 或者压根还没统计过。
  final bool measured;

  /// 命中了几个兼容目录（同一本可能留下历史布局的多份）。
  final int rootCount;

  static const unmeasured = DownloadStorageStat(
    bytes: 0,
    measured: false,
    rootCount: 0,
  );
}

/// 多本漫画的合计占用；没量到的那些不掺数（它们不是 0，是不知道）。
int totalDownloadStorageBytes(Iterable<DownloadStorageStat> stats) {
  var total = 0;
  for (final stat in stats) {
    if (!stat.measured) continue;
    total += stat.bytes;
  }
  return total;
}

/// 有没有任何一本真的量到过 —— 决定那句「共占用」能不能说出口。
bool hasMeasuredStorage(Iterable<DownloadStorageStat> stats) {
  return stats.any((stat) => stat.measured);
}

/// 字节数的可读形式：B / KB / MB / GB，KB 起保留一位小数。
String formatDownloadBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
