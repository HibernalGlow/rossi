import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
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

  bool _notifyScheduled = false;

  /// 发一次「会话变了」的通知，但**绝不在 build 阶段发**。
  ///
  /// 这个中枢是全局单例，登记会话的时机在阅读器 `build` 里（`comic_read.dart` 的
  /// 尺寸回调那一处），于是 `notifyListeners()` 会打到「正在 build 的下游」上，
  /// 实测一次开书刷出 14 条 `setState() or markNeedsBuild() called during build`
  /// （11 个 `ListenableBuilder` + 3 个工作区信息卡）。
  ///
  /// 只把**通知**推到本帧之后；**状态本身照常同步写**，因为同一帧里就有代码直接读
  /// [comicId] / [docs] / [displayTitle]（顶栏书名那颗就是），把写入一起推迟会
  /// 读到上一本书的值。同一帧内多次调用合并成一次通知。
  void _notifySafely() {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      notifyListeners();
      return;
    }
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

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
    _notifySafely();
  }

  /// 更新阅读进度（当前槽位与总槽位）
  void updateProgress({required int currentSlot, required int totalSlots}) {
    if (_currentSlot == currentSlot && _totalSlots == totalSlots) return;
    _currentSlot = currentSlot;
    _totalSlots = totalSlots;
    _notifySafely();
  }

  /// 更新章节信息
  void updateEpInfo(NormalComicEpInfo epInfo) {
    _epInfo = epInfo;
    _notifySafely();
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
      _notifySafely();
    }
  }
}
