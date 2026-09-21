import 'package:zephyr/src/rust/api/file_manager.dart';

/// 跟随一本书存活：连按合并，旧阅读器销毁后忽略尚未完成的目录查找。
class LocalBookNavigationController {
  LocalBookNavigationController({
    required this.path,
    this.navigationJson,
    required this.open,
    required this.notify,
    this.resolve = localBookAdjacent,
  });

  static const contextKey = 'localBookNavigation';

  /// 松散图片被提升为「所在目录那一本书」后，点开的那一张的名字随路由一起带过去，
  /// 阅读器据此把初始位置落在这一页而不是同目录的上次阅读位置。
  static const entryHintKey = 'localEntryHint';
  final String path;
  final String? navigationJson;
  final Future<void> Function(LocalBookNavigationTarget target) open;
  final void Function(String message) notify;
  final Future<LocalBookNavigationTarget?> Function({
    required String path,
    String? navigationJson,
    required bool forward,
  })
  resolve;

  bool _busy = false;
  bool _disposed = false;
  bool _committed = false;

  Future<void> switchBook(bool forward) async {
    if (_disposed || _busy || _committed) return;
    _busy = true;
    try {
      final target = await resolve(
        path: path,
        navigationJson: navigationJson,
        forward: forward,
      );
      if (_disposed) return;
      if (target == null) {
        notify(forward ? '已经是最后一本书' : '已经是第一本书');
        return;
      }
      _committed = true;
      await open(target);
    } catch (error) {
      _committed = false;
      if (!_disposed) notify('切换书籍失败：$error');
    } finally {
      _busy = false;
    }
  }

  void dispose() => _disposed = true;
}
