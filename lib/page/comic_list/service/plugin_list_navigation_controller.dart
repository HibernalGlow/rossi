import 'package:flutter/foundation.dart';

/// 通用菜单只观察轻量导航信息，滚动不会重建列表正文。
class PluginListNavigationController extends ChangeNotifier {
  Object? _owner;
  int currentPage = 1;
  int? totalPages;
  int? savedPage;
  bool busy = false;
  Future<void> Function(int)? _jump;
  Future<void> Function()? _restore;
  bool get attached => _owner != null;
  bool get canRestore => attached && savedPage != null && !busy;

  void attach(
    Object owner, {
    required Future<void> Function(int) jump,
    required Future<void> Function() restore,
  }) {
    _owner = owner;
    _jump = jump;
    _restore = restore;
  }

  void update(
    Object owner, {
    required int page,
    required int? total,
    required int? saved,
    required bool loading,
  }) {
    if (!identical(owner, _owner)) return;
    if (currentPage == page &&
        totalPages == total &&
        savedPage == saved &&
        busy == loading) {
      return;
    }
    currentPage = page;
    totalPages = total;
    savedPage = saved;
    busy = loading;
    notifyListeners();
  }

  void detach(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _jump = null;
    _restore = null;
  }

  Future<void> jumpToPage(int page) async {
    if (!busy && page >= 1 && (totalPages == null || page <= totalPages!)) {
      await _jump?.call(page);
    }
  }

  Future<void> restore() async {
    if (canRestore) await _restore?.call();
  }
}
