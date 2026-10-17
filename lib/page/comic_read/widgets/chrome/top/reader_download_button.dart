import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart';

/// 阅读器顶栏的整本下载入口。
///
/// 下载任务和阅读缓存各走自己的路径；下载任务启动后会复用已有阅读缓存，
/// 阅读器再次取图时则优先读取已经落盘的下载文件。
class ReaderDownloadButton extends StatelessWidget {
  const ReaderDownloadButton({super.key, required this.onDownload});

  final Future<void> Function() onDownload;

  @override
  Widget build(BuildContext context) {
    return ReaderToolbarIconButton(
      icon: AppGlyphs.download,
      tooltip: t.comicInfo.download,
      onPressed: () => unawaited(onDownload()),
    );
  }
}
