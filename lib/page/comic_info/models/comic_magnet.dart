import 'package:zephyr/page/comic_info/json/normal/normal_comic_all_info.dart';

/// 图源插件给出的磁力链接（EH 系插件放在 `comicInfo.extern['magnet']`）。
///
/// 只认插件显式给的值：没有 magnet 的图源这里恒为空串，
/// 调用方据此决定按钮出不出现，不要按 `extern.containsKey` 判断。
String comicMagnetOf(NormalComicAllInfo? info) {
  if (info == null) {
    return '';
  }

  final direct = info.comicInfo.extern['magnet']?.toString().trim() ?? '';
  if (direct.isNotEmpty) {
    return direct;
  }

  // 兜底：磁力也可能只出现在 metadata 的「磁力 / 种子」分组里
  for (final group in info.comicInfo.metadata) {
    final type = group.type.trim().toLowerCase();
    if (type != 'magnet' && type != 'torrent') {
      continue;
    }
    for (final chip in group.value) {
      final magnet = chip.extern['magnet']?.toString().trim() ?? '';
      if (magnet.isNotEmpty) {
        return magnet;
      }
    }
  }

  return '';
}
