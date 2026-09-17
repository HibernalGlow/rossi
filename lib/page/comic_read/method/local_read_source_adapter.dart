import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/model/normal_comic_ep_info.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/local_page_source.dart';
import 'package:zephyr/reader/page_source.dart';

/// 管理当前活跃的本地 GPU 呈现阅读会话。
///
/// 它同时是 HDR 设置的**唯一真相源**：界面上的开关改这里，渲染时读这里，
/// 两者之间不再各存一份（否则“开关看着开了、画面还是 SDR”这种不一致会很难查）。
class LocalReadSession extends ChangeNotifier {
  LocalReadSession._();

  static final LocalReadSession instance = LocalReadSession._();

  PageSource? _currentSource;
  GpuPresentController? _presenter;

  int _hdrMode = 0; // 0: 关闭, 1: 扩展线性 HDR, 2: SDR 增强
  double _hdrBoost = 2.0;
  double _hdrPeak = 0.0;
  bool _prefsLoaded = false;

  PageSource? get currentSource => _currentSource;
  GpuPresentController? get presenter => _presenter;
  int get hdrMode => _hdrMode;
  double get hdrBoost => _hdrBoost;
  double get hdrPeak => _hdrPeak;

  /// 是否启用了色调映射（真 HDR 或 SDR 增强）。
  /// 关闭时整条链路回落到原来的 Flutter 纹理通路，行为与从前一致。
  bool get hdrEnabled => _hdrMode != 0;

  /// 真 HDR（扩展线性 + 浮点输出）是否启用。
  bool get extendedLinearHdr => _hdrMode == 1;

  Future<void> ensurePrefsLoaded() async {
    if (_prefsLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final int mode = prefs.getInt('rossi_gpu_hdr_mode') ?? 0;
      final double boost = prefs.getDouble('rossi_gpu_hdr_boost') ?? 2.0;
      _prefsLoaded = true;
      if (mode != _hdrMode || boost != _hdrBoost) {
        _hdrMode = mode;
        _hdrBoost = boost;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// 配置 HDR 模式与参数，并立即同步到当前呈现器与本地存储。
  Future<bool> setHdr({
    required int mode,
    double boost = 2.0,
    double peak = 0.0,
  }) async {
    _hdrMode = mode;
    _hdrBoost = boost;
    _hdrPeak = peak;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('rossi_gpu_hdr_mode', mode);
      await prefs.setDouble('rossi_gpu_hdr_boost', boost);
    } catch (_) {}
    // 先通知界面重挂显示节点（开关 HDR 会换掉整个画面节点），
    // 再去推底层参数 —— 反过来会让旧节点多渲染一帧旧参数。
    notifyListeners();

    if (_presenter != null) {
      return await _presenter!.setHdr(mode: mode, boost: boost, peak: peak);
    }
    return true;
  }

  /// 初始化或获取当前 GPU 呈现控制器
  GpuPresentController getOrCreatePresenter() {
    if (_presenter == null) {
      final presenter = GpuPresentController();
      presenter.start();
      unawaited(() async {
        await ensurePrefsLoaded();
        if (_hdrMode != 0) {
          await presenter.setHdr(mode: _hdrMode, boost: _hdrBoost, peak: _hdrPeak);
        }
      }());
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

  /// 释放资源。
  ///
  /// 命名成 `release` 而不是覆写 `ChangeNotifier.dispose`：这会话是单例，
  /// 生命周期跟进程走，并不是“销毁后不可再用”——它只释放来源与呈现器，
  /// 下次进阅读器还会重建。把语义写准比省一个名字重要。
  Future<void> release() async {
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
