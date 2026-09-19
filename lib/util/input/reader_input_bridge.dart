import 'package:flutter/widgets.dart';
import 'package:zephyr/util/input/reader_input_context.dart';

/// 应用级的「活跃阅读器按键处理器」+ **真实 context 集合**。
///
/// **为什么需要它**：阅读器的按键处理挂在**阅读器子树自己的 `Focus`** 上
/// （`reader_input_controller.dart`）。焦点一旦离开那棵子树 —— 例如打开阅读设置面板
/// （`showModalBottomSheet` 推入一条模态路由、把主焦点拿走）—— 它就再也收不到按键，
/// 左右键转而落到 `WidgetsApp` 默认的 `DirectionalFocusIntent`（方向焦点遍历）上，
/// 用户看到的是「左右键被设置面板吃掉、翻不动页」。
///
/// 于是把**同一个处理器**登记到这里，由工作台在按键冒泡经过时转交
/// （见 `breeze_workspace_page.dart`）。键盘逻辑仍然只有一处（`key.dart`）。
///
/// **context 判定与 neoview 一致**（见 [ReaderInputContext]）：阅读器只在 `reader`
/// context **活跃**时接收按键。「活跃」由 Dart 侧的 adapter 报告 —— 只有应用自己知道
/// 现在在场的是哪块内容，核心不可能知道。设置面板之所以不该抢走按键，也由同一套语义
/// 解释：它是**阅读器自己的 UI**，不引入任何与 `reader` 竞争的绑定，于是
/// `arrowLeft` / `arrowRight` 仍由 `reader` context 解析（neoview 里高优先级 context
/// 只有在**自己也有匹配绑定**时才赢）。
class ReaderInputBridge {
  ReaderInputBridge._();

  static final ReaderInputBridge instance = ReaderInputBridge._();

  KeyEventResult Function(KeyEvent event)? _readerHandler;

  /// 当前真实活跃的 context 集合。默认视为「在阅读器里」，
  /// 由 Dart adapter（工作台）在按键到达时按真实状态改写。
  Set<ReaderInputContext> _activeContexts = const <ReaderInputContext>{
    ReaderInputContext.reader,
  };

  bool get hasHandler => _readerHandler != null;

  Set<ReaderInputContext> get activeContexts => _activeContexts;

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
  }

  /// `reader` context 是否活跃 —— 只有它活跃、且已登记处理器时，阅读器才收按键。
  bool get readerContextActive =>
      _readerHandler != null &&
      _activeContexts.contains(ReaderInputContext.reader);

  /// 转交一次按键；阅读器上下文不活跃时返回 [KeyEventResult.ignored]（照常往下冒泡）。
  KeyEventResult dispatch(KeyEvent event) {
    if (!readerContextActive) return KeyEventResult.ignored;
    return _readerHandler!.call(event);
  }
}
