// 「切换提示」运行时 —— neoview `features/switch-toast/` 三件套
// （Store 的 show 去重语义 + Runtime 的 book/page 判定）在 Rossi 的合并形态。
//
// Rossi 里它只需要一个听 `ReaderSessionCoordinator` 的服务：
// - 上游 Runtime 用 `previousRef { bookId, pageIndex }` 对 session 变更做差分，
//   这里对同一份总线字段做同样的差分（`comicId` / `currentSlot`）；
// - 上游 Store 的 `show` 带「同文 500ms 去重」，语义原样保留；
// - 弹出不走自己那套按窗口坐标摆位的 Host，而是走应用统一的提示条
//   （`showInfoToast` → 无 context 时经 `eventBus` 由前台补弹），
//   位置 / 时长 / 外观全部沿用「设置 → 提示样式」（`ToastSettingState`）。
//
// 上游的 enableAction（按键操作提示）与 enableBoundaryToast（边界翻页提示）
// 需要按键执行 / 边界判定处的挂点，本轮未搬（口径登记在 docs/ROADMAP.md）。

import 'package:flutter/foundation.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/util/toast/switch_toast_template.dart';
import 'package:zephyr/widgets/toast.dart';

class SwitchToastService {
  SwitchToastService._();

  static final SwitchToastService instance = SwitchToastService._();

  /// 上游同款窗口：完全相同的一条提示在 500ms 内只弹一次。
  static const Duration _dedupWindow = Duration(milliseconds: 500);

  bool _started = false;

  String? _previousComicId;
  int? _previousSlot;

  String? _lastKey;
  DateTime? _lastShownAt;

  /// 判据里换成假设置源（应用路径不传，永远现读本地库）。
  @visibleForTesting
  SwitchToastSettingState Function()? settingsSourceOverride;

  SwitchToastSettingState get _settings =>
      (settingsSourceOverride ?? () => switchToastSetting)();

  /// 在 `GlobalSettingCubit` 就绪后调用一次；重复调用是幂等的。
  void start() {
    if (_started) return;
    _started = true;
    ReaderSessionCoordinator.instance.addListener(_onSessionChanged);
  }

  /// 只在判据里用：回到「没听见过任何会话」的初态。
  void resetForTest() {
    ReaderSessionCoordinator.instance.removeListener(_onSessionChanged);
    _started = false;
    _previousComicId = null;
    _previousSlot = null;
    _lastKey = null;
    _lastShownAt = null;
  }

  void _onSessionChanged() {
    final coordinator = ReaderSessionCoordinator.instance;
    final settings = _settings;

    final comicId = coordinator.comicId;
    final slot = coordinator.currentSlot;
    if (comicId == null) {
      _previousComicId = null;
      _previousSlot = null;
      return;
    }

    if (comicId != _previousComicId) {
      _previousComicId = comicId;
      _previousSlot = slot;
      if (settings.enableBook) {
        _publish(
          titleTemplate: settings.bookTitleTemplate,
          descriptionTemplate: settings.bookDescriptionTemplate,
          context: _contextOf(coordinator, slot),
          fallbackTitle: coordinator.displayTitle ?? '',
        );
      }
      return;
    }
    if (slot != _previousSlot) {
      _previousSlot = slot;
      if (settings.enablePage) {
        _publish(
          titleTemplate: settings.pageTitleTemplate,
          descriptionTemplate: settings.pageDescriptionTemplate,
          context: _contextOf(coordinator, slot),
          fallbackTitle: '第 ${slot + 1} 页',
        );
      }
    }
  }

  void _publish({
    required String titleTemplate,
    required String descriptionTemplate,
    required SwitchToastContext context,
    required String fallbackTitle,
  }) {
    final title = renderSwitchToastTemplate(titleTemplate, context).trim();
    final description = renderSwitchToastTemplate(
      descriptionTemplate,
      context,
    ).trim();
    if (title.isEmpty && description.isEmpty) return;

    final key = '$title\n$description';
    final now = DateTime.now();
    if (key == _lastKey &&
        _lastShownAt != null &&
        now.difference(_lastShownAt!) < _dedupWindow) {
      return;
    }
    _lastKey = key;
    _lastShownAt = now;

    final resolvedTitle = title.isEmpty ? fallbackTitle : title;
    // 上游把 title 加粗、description 跟在下面；Rossi 的 ToastCard 同款两行。
    // 只剩一条时不占用标题位 —— 提示条对空正文会直接丢弃（见 ToastOverlayController）。
    if (description.isEmpty) {
      showInfoToast(resolvedTitle);
    } else {
      showInfoToast(description, title: resolvedTitle);
    }
  }

  /// 变量表与上游 `switchToastContext` 对齐；Rossi 拿不到的键
  /// （页分辨率 / 字节大小、emm 系列）不进表，模板引用它们时渲染为空串。
  SwitchToastContext _contextOf(ReaderSessionCoordinator c, int slot) {
    final total = c.totalSlots;
    final currentPageDisplay = total > 0 ? (slot + 1).clamp(1, total) : 0;
    final path = c.localSource?.path ?? '';
    final doc = slot < c.docs.length ? c.docs[slot] : null;
    return SwitchToastContext(
      book: <String, Object?>{
        'name': c.displayTitle,
        'displayName': c.displayTitle,
        'path': path,
        'type': _sourceType(c),
        'totalPages': total,
        'currentPageIndex': slot,
        'currentPageDisplay': currentPageDisplay,
        'progressPercent': total > 0
            ? double.parse(
                (currentPageDisplay / total * 100).toStringAsFixed(1),
              )
            : null,
      },
      page: doc == null
          ? null
          : <String, Object?>{
              'name': doc.originalName,
              'displayName': doc.originalName.isEmpty
                  ? '第 ${slot + 1} 页'
                  : doc.originalName,
              'path': doc.path,
              'index': slot,
              'indexDisplay': slot + 1,
            },
    );
  }

  String _sourceType(ReaderSessionCoordinator c) {
    final local = c.localSource;
    if (local == null) return '在线';
    final file = local.path.split(RegExp(r'[/\\]')).last;
    final dot = file.lastIndexOf('.');
    if (dot > 0 && dot < file.length - 1)
      return file.substring(dot + 1).toUpperCase();
    return '目录';
  }
}
