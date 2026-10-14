import 'package:flutter/widgets.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/reader/page_trim_layout.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';

class CurrentPageImageRef {
  const CurrentPageImageRef.local(
    this.owner,
    this.source,
    this.index, {
    this.trimLayout,
    this.trimIndex,
    this.trimEnabled = false,
    this.halfPage = false,
    this.presenter,
  }) : filePath = null,
       originalPath = null,
       bookKey = null;

  const CurrentPageImageRef.file(
    this.owner,
    this.filePath, {
    this.originalPath,
    this.trimLayout,
    this.trimIndex,
    this.trimEnabled = false,
    this.halfPage = false,
    this.bookKey,
  }) : source = null,
       index = null,
       presenter = null;

  final Object owner;
  final PageSource? source;
  final int? index;

  /// 画面此刻使用的文件；开了降噪或超分时是处理后的缓存产物。
  final String? filePath;

  /// 处理之前的原图。没有处理、或来源不清楚时为 null，调用方按 [filePath] 即原图处理。
  final String? originalPath;
  final PageTrimLayout? trimLayout;
  final int? trimIndex;
  final bool trimEnabled;
  final bool halfPage;
  final GpuPresentController? presenter;
  final String? bookKey;
}

/// Only the active page reports here; inspection performs IO when opened.
class CurrentPageImageInfo extends ChangeNotifier {
  CurrentPageImageInfo._();

  static final CurrentPageImageInfo instance = CurrentPageImageInfo._();
  CurrentPageImageRef? _current;
  final Map<Object, int> _pending = {};
  int _nextRevision = 0;
  CurrentPageImageRef? get current => _current;

  void reportLocalAfterFrame(
    Object owner,
    PageSource source,
    int index,
    bool Function() isCurrent, {
    PageTrimLayout? trimLayout,
    int? trimIndex,
    bool trimEnabled = false,
    bool halfPage = false,
    GpuPresentController? presenter,
  }) {
    _schedule(
      owner,
      isCurrent,
      () => reportLocal(
        owner,
        source,
        index,
        trimLayout: trimLayout,
        trimIndex: trimIndex,
        trimEnabled: trimEnabled,
        halfPage: halfPage,
        presenter: presenter,
      ),
    );
  }

  void reportFileAfterFrame(
    Object owner,
    String path,
    bool Function() isCurrent, {
    String? originalPath,
    PageTrimLayout? trimLayout,
    int? trimIndex,
    bool trimEnabled = false,
    bool halfPage = false,
    String? bookKey,
  }) {
    _schedule(
      owner,
      isCurrent,
      () => reportFile(
        owner,
        path,
        originalPath: originalPath,
        trimLayout: trimLayout,
        trimIndex: trimIndex,
        trimEnabled: trimEnabled,
        halfPage: halfPage,
        bookKey: bookKey,
      ),
    );
  }

  void _schedule(Object owner, bool Function() isCurrent, VoidCallback report) {
    final revision = ++_nextRevision;
    _pending[owner] = revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pending[owner] != revision || !isCurrent()) return;
      _pending.remove(owner);
      report();
    });
  }

  void reportLocal(
    Object owner,
    PageSource source,
    int index, {
    PageTrimLayout? trimLayout,
    int? trimIndex,
    bool trimEnabled = false,
    bool halfPage = false,
    GpuPresentController? presenter,
  }) {
    final previous = _current;
    if (previous?.owner == owner &&
        identical(previous?.source, source) &&
        previous?.index == index &&
        previous?.filePath == null &&
        previous?.trimLayout == trimLayout &&
        previous?.trimIndex == trimIndex &&
        previous?.trimEnabled == trimEnabled &&
        previous?.halfPage == halfPage &&
        previous?.presenter == presenter) {
      return;
    }
    _replace(
      CurrentPageImageRef.local(
        owner,
        source,
        index,
        trimLayout: trimLayout,
        trimIndex: trimIndex,
        trimEnabled: trimEnabled,
        halfPage: halfPage,
        presenter: presenter,
      ),
    );
  }

  void reportFile(
    Object owner,
    String path, {
    String? originalPath,
    PageTrimLayout? trimLayout,
    int? trimIndex,
    bool trimEnabled = false,
    bool halfPage = false,
    String? bookKey,
  }) {
    final previous = _current;
    if (previous?.owner == owner &&
        previous?.filePath == path &&
        previous?.originalPath == originalPath &&
        previous?.trimLayout == trimLayout &&
        previous?.trimIndex == trimIndex &&
        previous?.trimEnabled == trimEnabled &&
        previous?.halfPage == halfPage &&
        previous?.bookKey == bookKey) {
      return;
    }
    _replace(
      CurrentPageImageRef.file(
        owner,
        path,
        originalPath: originalPath,
        trimLayout: trimLayout,
        trimIndex: trimIndex,
        trimEnabled: trimEnabled,
        halfPage: halfPage,
        bookKey: bookKey,
      ),
    );
  }

  void _replace(CurrentPageImageRef? next) {
    _current?.trimLayout?.removeListener(notifyListeners);
    _current?.presenter?.removeListener(notifyListeners);
    _current = next;
    next?.trimLayout?.addListener(notifyListeners);
    next?.presenter?.addListener(notifyListeners);
    notifyListeners();
  }

  void clear(Object owner) {
    _pending.remove(owner);
    if (_current?.owner != owner) return;
    _replace(null);
  }
}
