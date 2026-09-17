import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/model/normal_comic_ep_info.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/local_page_source.dart';
import 'package:zephyr/reader/page_source.dart';

/// 管理当前活跃的本地 GPU 呈现阅读会话。
class LocalReadSession {
  LocalReadSession._();

  static final LocalReadSession instance = LocalReadSession._();

  PageSource? _currentSource;
  GpuPresentController? _presenter;

  PageSource? get currentSource => _currentSource;
  GpuPresentController? get presenter => _presenter;

  /// 初始化或获取当前 GPU 呈现控制器
  GpuPresentController getOrCreatePresenter() {
    if (_presenter == null) {
      final presenter = GpuPresentController();
      presenter.start();
      _presenter = presenter;
    }
    return _presenter!;
  }

  /// 设置当前打开的来源
  void setSource(PageSource source) {
    if (!identical(_currentSource, source)) {
      unawaited(_currentSource?.close());
      _currentSource = source;
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    await _currentSource?.close();
    _currentSource = null;
    _presenter?.dispose();
    _presenter = null;
  }
}

/// 判断是否为本地漫画来源
bool isLocalComicSource(String from, String comicId) {
  if (from == 'local' || from == 'local_source') {
    return true;
  }
  final lower = comicId.toLowerCase();
  return lower.startsWith('/') ||
      lower.contains(':\\') ||
      lower.contains(':/') ||
      lower.endsWith('.zip') ||
      lower.endsWith('.cbz') ||
      lower.endsWith('.rar') ||
      lower.endsWith('.cbr');
}

/// 将本地漫画归档/文件夹解析为 Breeze 阅读器所需的 [NormalComicEpInfo]
Future<NormalComicEpInfo> getLocalComicEpInfo(String path) async {
  final PageSourceOpen result = await LocalPageSource.open(path);

  switch (result) {
    case PageSourceRejected(:final message):
      throw StateError('无法打开本地漫画: $message');

    case PageSourceOpened(:final source):
      LocalReadSession.instance.setSource(source);
      LocalReadSession.instance.getOrCreatePresenter();

      final String name = p.basename(path);
      final docs = <Doc>[];

      for (int i = 0; i < source.pageCount; i++) {
        final pageRef = source.pages[i];
        docs.add(
          Doc(
            originalName: pageRef.name,
            path: i.toString(),
            fileServer: path,
            id: i.toString(),
            storageChapterId: path,
            extern: <String, dynamic>{
              'localIndex': i,
              'localPath': path,
              'isLocalGpu': true,
            },
          ),
        );
      }

      return NormalComicEpInfo(
        length: docs.length,
        epPages: docs.length.toString(),
        docs: docs,
        epId: path,
        epName: name,
      );
  }
}
