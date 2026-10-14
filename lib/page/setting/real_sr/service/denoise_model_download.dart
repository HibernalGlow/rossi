import 'dart:async';

import 'package:flutter/foundation.dart';

enum DenoiseDownloadPhase {
  checking,
  missing,
  downloading,
  verifying,
  ready,
  failed,
}

/// 下载状态与面板寿命无关。关闭面板再打开仍观察同一传输，所有入口合并为一次下载。
class DenoiseModelDownload extends ChangeNotifier {
  DenoiseModelDownload({
    required this.inspect,
    required this.transfer,
    required this.remove,
  });

  final Future<int> Function() inspect;
  final Future<void> Function(
    void Function(int, int) progress,
    VoidCallback verifying,
  )
  transfer;
  final Future<void> Function() remove;
  DenoiseDownloadPhase phase = DenoiseDownloadPhase.checking;
  int received = 0;
  int total = 0;
  int installedBytes = 0;
  String? error;
  Future<void>? _operation;
  bool _disposed = false;

  bool get busy => _operation != null;
  double? get progress => total > 0 ? (received / total).clamp(0, 1) : null;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() => _operation ?? _start(_refresh);

  Future<void> _refresh() async {
    try {
      installedBytes = await inspect();
      phase = installedBytes > 0
          ? DenoiseDownloadPhase.ready
          : DenoiseDownloadPhase.missing;
      error = null;
    } catch (e) {
      phase = DenoiseDownloadPhase.failed;
      error = e.toString();
    }
    _changed();
  }

  Future<void> download() {
    final pending = _operation;
    if (pending != null) return pending;
    phase = DenoiseDownloadPhase.downloading;
    received = total = 0;
    error = null;
    // 先登记 future 再通知；另一面板的重入点击不能启动第二次传输。
    final work = _start(_download);
    _changed();
    return work;
  }

  Future<void> _download() async {
    try {
      await transfer(
        (bytes, length) {
          received = bytes;
          total = length;
          _changed();
        },
        () {
          phase = DenoiseDownloadPhase.verifying;
          _changed();
        },
      );
      installedBytes = await inspect();
      if (installedBytes <= 0) throw StateError('下载完成，但模型校验未通过');
      phase = DenoiseDownloadPhase.ready;
    } catch (e) {
      // 失败保留可用的旧模型，界面同时披露本次更新失败。
      phase = DenoiseDownloadPhase.failed;
      error = e.toString();
    }
    _changed();
  }

  Future<void> delete() {
    if (_operation != null) return _operation!;
    final work = _start(_delete);
    _changed();
    return work;
  }

  Future<void> _delete() async {
    try {
      await remove();
      installedBytes = 0;
      error = null;
      phase = DenoiseDownloadPhase.missing;
    } catch (e) {
      phase = DenoiseDownloadPhase.failed;
      error = e.toString();
    }
    _changed();
  }

  Future<void> _start(Future<void> Function() action) {
    final completer = Completer<void>();
    _operation = completer.future;
    unawaited(
      Future<void>.sync(action).then(
        (_) {
          _operation = null;
          completer.complete();
          _changed();
        },
        onError: (Object e, StackTrace s) {
          _operation = null;
          completer.completeError(e, s);
          _changed();
        },
      ),
    );
    return completer.future;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
