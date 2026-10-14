import 'package:flutter/widgets.dart';
import 'package:zephyr/reader/page_source.dart';

class CurrentPageImageRef {
  const CurrentPageImageRef.local(this.owner, this.source, this.index)
    : filePath = null;

  const CurrentPageImageRef.file(this.owner, this.filePath)
    : source = null,
      index = null;

  final Object owner;
  final PageSource? source;
  final int? index;
  final String? filePath;
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
    bool Function() isCurrent,
  ) {
    _schedule(owner, isCurrent, () => reportLocal(owner, source, index));
  }

  void reportFileAfterFrame(
    Object owner,
    String path,
    bool Function() isCurrent,
  ) {
    _schedule(owner, isCurrent, () => reportFile(owner, path));
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

  void reportLocal(Object owner, PageSource source, int index) {
    final previous = _current;
    if (previous?.owner == owner &&
        identical(previous?.source, source) &&
        previous?.index == index &&
        previous?.filePath == null) {
      return;
    }
    _current = CurrentPageImageRef.local(owner, source, index);
    notifyListeners();
  }

  void reportFile(Object owner, String path) {
    final previous = _current;
    if (previous?.owner == owner && previous?.filePath == path) return;
    _current = CurrentPageImageRef.file(owner, path);
    notifyListeners();
  }

  void clear(Object owner) {
    _pending.remove(owner);
    if (_current?.owner != owner) return;
    _current = null;
    notifyListeners();
  }
}
