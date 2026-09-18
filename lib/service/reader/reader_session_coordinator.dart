import 'package:flutter/foundation.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/model/normal_comic_ep_info.dart';
import 'package:zephyr/reader/page_source.dart';

/// 全局阅读器会话中枢。
///
/// 负责在 Reader 运行时向外部发布状态（当前阅读书本、章节信息、页数、当前槽位），
/// 并提供解耦的页面跳转控制通道。适用于工作区侧面板卡片（如 [PageListCard]）、
/// 悬浮窗、底栏缩略图预览等。
class ReaderSessionCoordinator extends ChangeNotifier {
  ReaderSessionCoordinator._();

  static final ReaderSessionCoordinator instance = ReaderSessionCoordinator._();

  String? _comicId;
  String? _from;
  String? _title;
  NormalComicEpInfo? _epInfo;
  PageSource? _localSource;
  int _currentSlot = 0;
  int _totalSlots = 0;
  Future<void> Function(int targetGlobalSlot)? _jumpToSlot;

  String? get comicId => _comicId;
  String? get from => _from;
  String? get displayTitle => _title;
  NormalComicEpInfo? get epInfo => _epInfo;
  PageSource? get localSource => _localSource;
  int get currentSlot => _currentSlot;
  int get totalSlots => _totalSlots;

  /// 是否存在活跃的阅读会话
  bool get hasActiveSession =>
      _comicId != null && (_epInfo != null || _localSource != null);

  /// 当前章节所含有的所有页面列表条目
  List<Doc> get docs => _epInfo?.docs ?? const <Doc>[];

  /// 关联并登记当前阅读会话
  void attachSession({
    required String comicId,
    required String from,
    required String title,
    required NormalComicEpInfo epInfo,
    PageSource? localSource,
    required int currentSlot,
    required int totalSlots,
    required Future<void> Function(int target) jumpToSlot,
  }) {
    _comicId = comicId;
    _from = from;
    _title = title;
    _epInfo = epInfo;
    _localSource = localSource;
    _currentSlot = currentSlot;
    _totalSlots = totalSlots;
    _jumpToSlot = jumpToSlot;
    notifyListeners();
  }

  /// 更新阅读进度（当前槽位与总槽位）
  void updateProgress({required int currentSlot, required int totalSlots}) {
    if (_currentSlot == currentSlot && _totalSlots == totalSlots) return;
    _currentSlot = currentSlot;
    _totalSlots = totalSlots;
    notifyListeners();
  }

  /// 更新章节信息
  void updateEpInfo(NormalComicEpInfo epInfo) {
    _epInfo = epInfo;
    notifyListeners();
  }

  /// 请求阅读器跳转到目标槽位
  Future<void> jumpTo(int slot) async {
    final callback = _jumpToSlot;
    if (callback != null) {
      await callback(slot);
    }
  }

  /// 解除阅读会话登记
  void detachSession(String comicId) {
    if (_comicId == comicId) {
      _comicId = null;
      _from = null;
      _title = null;
      _epInfo = null;
      _localSource = null;
      _currentSlot = 0;
      _totalSlots = 0;
      _jumpToSlot = null;
      notifyListeners();
    }
  }
}
