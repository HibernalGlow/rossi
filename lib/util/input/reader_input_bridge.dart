import 'package:flutter/widgets.dart';
import 'package:zephyr/util/input/reader_input_context.dart';
import 'package:zephyr/util/input/reader_input_guard.dart';

/// 应用级阅读器键盘宿主与现有绑定上下文的 adapter。
/// 工作台既可报告静态 contexts，也可登记实时目标 source。编辑/模态 UI
/// 拥有键盘时报告隔离上下文，阅读器自身入口与父层转发都遵守这条边界。
class ReaderInputBridge extends ChangeNotifier {
  ReaderInputBridge._();

  static final ReaderInputBridge instance = ReaderInputBridge._();

  KeyEventResult Function(KeyEvent event)? _readerHandler;

  /// 当前真实活跃的 context 集合。默认视为「在阅读器里」，
  /// 由 Dart adapter（工作台）在按键到达时按真实状态改写。
  Set<ReaderInputContext> _activeContexts = const <ReaderInputContext>{
    ReaderInputContext.reader,
  };

  bool get hasHandler => _readerHandler != null;

  Object? _contextOwner;
  Set<ReaderInputContext> Function()? _contextSource;
  bool _windowFocused = true;
  bool get windowFocused => _windowFocused;
  set windowFocused(bool value) {
    if (_windowFocused == value) return;
    _windowFocused = value;
    notifyListeners();
  }

  /// 当场读取宿主目标，避免子 Focus 比父层转发更早收到按键时读到旧上下文。
  Set<ReaderInputContext> get activeContexts {
    if (ReaderInputGuard.isEditing) return const {ReaderInputContext.editor};
    if (ReaderInputGuard.isModal) return const {ReaderInputContext.modal};
    return _contextSource?.call() ?? _activeContexts;
  }

  void attachContextSource(
    Object owner,
    Set<ReaderInputContext> Function() source,
  ) {
    final previousOwner = _contextOwner;
    if (previousOwner is Listenable) {
      previousOwner.removeListener(notifyListeners);
    }
    _contextOwner = owner;
    _contextSource = source;
    if (owner is Listenable) owner.addListener(notifyListeners);
    notifyListeners();
  }

  void detachContextSource(Object owner) {
    if (!identical(owner, _contextOwner)) return;
    if (owner is Listenable) owner.removeListener(notifyListeners);
    _contextOwner = null;
    _contextSource = null;
    _activeContexts = const {ReaderInputContext.reader};
    notifyListeners();
  }

  /// 阅读器挂载时登记。注销时必须传**同一个** tear-off（[detach] 用 `identical` 判定）。
  void attach(KeyEventResult Function(KeyEvent event) handler) {
    _readerHandler = handler;
  }

  void detach(KeyEventResult Function(KeyEvent event) handler) {
    if (identical(_readerHandler, handler)) _readerHandler = null;
  }

  /// **Dart 侧 adapter 入口**：报告当前真实活跃的 context 集合（neoview 的 7 个词汇）。
  void setActiveContexts(Set<ReaderInputContext> contexts) {
    _activeContexts = contexts;
    notifyListeners();
  }

  /// `reader` context 是否活跃 —— 只有它活跃、且已登记处理器时，阅读器才收按键。
  bool get readerContextActive =>
      _readerHandler != null && acceptsReaderKeyboard;

  bool get acceptsReaderKeyboard =>
      windowFocused &&
      !ReaderInputGuard.blocksKeyboard &&
      activeContexts.contains(ReaderInputContext.reader);

  /// 转交一次按键；阅读器上下文不活跃时返回 [KeyEventResult.ignored]（照常往下冒泡）。
  KeyEventResult dispatch(KeyEvent event) {
    if (!readerContextActive) return KeyEventResult.ignored;
    return _readerHandler!.call(event);
  }
}
