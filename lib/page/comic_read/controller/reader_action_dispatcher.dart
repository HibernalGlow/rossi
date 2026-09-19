import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_controller.dart';
import 'package:zephyr/page/comic_read/cubit/reader_presentation_cubit.dart';
import 'package:zephyr/page/comic_read/model/reader_presentation.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';
import 'package:zephyr/util/input/reader_input_bridge.dart';
import 'package:zephyr/video/controller/video_action_dispatch.dart';

/// 把引擎解析出的 **action id 落到执行体**（ADR-0015 §5 的第 ③ 件事）。
///
/// 这三件事的分界就是「换外壳能不能用」：解析框架无关（在 Rust），执行必然框架绑定
/// （在这里）。所以这个类的职责边界很清楚 —— **它不判断任何输入对应什么动作**，
/// 只回答「这个动作 id 在本仓怎么执行」。将来换 Tauri / egui 时要重写的就是这一个文件，
/// 机械、可枚举。
///
/// 动作 id 的清单与「哪些已实现」归注册表（Rust `ACTION_CATALOG`）。这里没实现的
/// （上一个 / 下一个书籍）一律 no-op：设置页把它们标灰，导入的表里出现也不会
/// 误触发什么。
class ReaderActionDispatcher {
  ReaderActionDispatcher({
    required this.context,
    required this.actions,
    required this.onToggleMenu,
    required this.onToggleFullscreen,
    required this.onOpenSettings,
    required this.onResetView,
    required this.onOpenRadialMenu,
    this.onBeforePageTurn,
  });

  final BuildContext context;
  final ReaderActionController actions;
  final VoidCallback onToggleMenu;
  final Future<void> Function() onToggleFullscreen;
  final VoidCallback onOpenSettings;
  final VoidCallback onResetView;

  /// 唤出轮盘。执行体在阅读器那边（浮层要挂在阅读器的 Overlay 上、要落在指针当前位置），
  /// 这里只负责「这个动作 id 在本仓就是开轮盘」。
  final VoidCallback onOpenRadialMenu;

  /// 翻页前先归位缩放。只有**点击**路径要在外层补这一刀：横翻时 `_turnPage` 自己会先问
  /// `onBeforeTurnPage`（两条路都覆盖到了），但条漫的百分比滚动绕不过那条钩子 ——
  /// 改造前的点击路径因此在外面多调了一次。键盘的竖向小幅滚动是「平滑微调」，
  /// 本来就不该被归位打断，所以它不补。
  final VoidCallback? onBeforePageTurn;

  ReadSettingState get _readSetting =>
      context.read<GlobalSettingCubit>().state.readSetting;

  /// 采集一次按键 → 解析 → 派发。
  ///
  /// 返回 `false` = 这张表里没人认这个键（事件继续往下冒泡，例如让焦点遍历接管方向键）。
  bool dispatchKeyEvent(KeyEvent event, String bindingsArrayJson) {
    final inputJson = keyboardInputJsonOf(event);
    if (inputJson == null) return false;
    return _dispatchInput(
      inputJson,
      bindingsArrayJson,
      fromKeyboard: true,
    );
  }

  /// 采集一次按下（鼠标键 / 触控笔）→ 解析 → 派发。返回 `false` = 没人认这一按。
  ///
  /// 与点击分区那条路**分开**是有意的：`area` 说的是「落在画面哪一格」，而轮盘的
  /// 唤出只看「按了哪个键」，与位置无关（neoview 的出厂绑法就是右键按下）。
  bool dispatchPointerPress({
    required int button,
    required String bindingsArrayJson,
  }) => _dispatchInput(
    mouseInputJson(button: button),
    bindingsArrayJson,
    fromKeyboard: false,
  );

  /// 采集一次落在某格的点击 → 解析 → 派发。
  bool dispatchTapArea({
    required String area,
    required String bindingsArrayJson,
  }) => _dispatchInput(
    areaInputJson(area: area),
    bindingsArrayJson,
    fromKeyboard: false,
  );

  bool _dispatchInput(
    String inputJson,
    String bindingsArrayJson, {
    required bool fromKeyboard,
  }) {
    final actionId = OperationBindingStore.resolveAction(
      bindingsArrayJson: bindingsArrayJson,
      inputJson: inputJson,
      // 用**当下真实的 context 集合**，不能用写死的 `readerContexts`：
      // 那样 `video.*` 那 24 条动作在解析阶段就永远不会命中（它们的 context 是
      // `video`，优先级 150 高于 `reader` 的 100），注册表里再全也只是摆设。
      contexts: ReaderInputBridge.instance.activeContexts
          .map((context) => context.name)
          .toList(growable: false),
    );
    if (actionId == null) return false;
    return dispatch(actionId, fromKeyboard: fromKeyboard);
  }

  /// 派发一条已解析的动作。返回 `false` = 本仓还没有这一条的执行体（或它被设置关着）。
  bool dispatch(String actionId, {required bool fromKeyboard}) {
    // 视频动作先走：`InputContext::Video` 的优先级（150）高于 `reader`（100），
    // 所以「快进档开着时翻页变跳转」这类重映射，判定处只能在视频分支里面，
    // 不能散到下面的翻页分支去 —— 否则同一个动作 id 会有两处解释。
    if (dispatchVideoAction(actionId)) return true;
    // 快进档：翻页输入改成跳转（必须在视频分支之后、翻页分支之前）。
    if (remapPageTurnToSeekWhenSeekMode(actionId)) return true;

    switch (actionId) {
      case BindingAction.pageLeft:
      case BindingAction.pageRight:
        // 空间动作：**方向在这里交给引擎解释**（左右开下「往右翻」是前进还是退回
        // 由 Rust 决定），本文件不许出现第二种方向判断。
        final turn = OperationBindingStore.resolvePageTurn(
          actionId: actionId,
          readMode: _readSetting.readMode,
        );
        return switch (turn) {
          'next' => _turnPage(next: true, fromKeyboard: fromKeyboard),
          'previous' => _turnPage(next: false, fromKeyboard: fromKeyboard),
          _ => false,
        };

      case BindingAction.nextPage:
        // 语义动作与方向无关，但**与输入种类有关**：键盘的「前进」在条漫里是小幅
        // 平滑滚动（200px），点击的「前进」是一整屏的 70% —— 改造前就是这两种手感，
        // 这里照抄，不为「统一」去动它。
        if (fromKeyboard) {
          actions.onKeyScrollNext();
        } else {
          onBeforePageTurn?.call();
          actions.onPageActionNext();
        }
        return true;

      case BindingAction.previousPage:
        if (fromKeyboard) {
          actions.onKeyScrollPrev();
        } else {
          onBeforePageTurn?.call();
          actions.onPageActionPrev();
        }
        return true;

      case BindingAction.firstPage:
        onBeforePageTurn?.call();
        actions.onGoToFirstPage();
        return true;
      case BindingAction.lastPage:
        onBeforePageTurn?.call();
        actions.onGoToLastPage();
        return true;

      case BindingAction.fullscreen:
        unawaited(onToggleFullscreen());
        return true;

      case BindingAction.toggleReadingDirection:
        return _toggleReadingDirection();

      case BindingAction.toggleBookMode:
        context.read<GlobalSettingCubit>().updateReadSetting(
          (current) => current.copyWith(doublePageMode: !current.doublePageMode),
        );
        return true;

      case BindingAction.resetView:
        // 两件事一起做：清掉顶栏那一份呈现状态（缩放模式 / 手动倍率 / 旋转 /
        // 宽页策略），再清掉手势层那份自由变换（双指放大、双击放大）。
        // 只清后者是改造前的行为 —— 顶栏面板当时还不存在。
        context.read<ReaderPresentationCubit>().resetView();
        onResetView();
        return true;

      // ── 缩放与旋转 ──────────────────────────────────────────────────────
      // 语义逐条照 neoview 的 `ReaderInputActionExecutor`：倍率是 fit 之上的乘数，
      // 换模式一律把倍率打回 100%。
      case BindingAction.zoomIn:
        context.read<ReaderPresentationCubit>().stepScale(1);
        return true;
      case BindingAction.zoomOut:
        context.read<ReaderPresentationCubit>().stepScale(-1);
        return true;
      case BindingAction.fitWindow:
        context.read<ReaderPresentationCubit>().setFitMode(
          ReaderFitMode.fit,
        );
        onResetView();
        return true;
      case BindingAction.actualSize:
        context.read<ReaderPresentationCubit>().setFitMode(
          ReaderFitMode.original,
        );
        onResetView();
        return true;
      case BindingAction.rotateClockwise:
        context.read<ReaderPresentationCubit>().rotate(1);
        return true;
      case BindingAction.rotate180:
        context.read<ReaderPresentationCubit>().rotate(2);
        return true;

      case BindingAction.toggleControls:
        // 「点击唤出/收起上下栏」这个开关管的是**单击**：绑到键盘上的同一动作不受它影响
        // （否则关掉点击就把键盘一起关了）。
        if (!fromKeyboard && !_readSetting.centerTapToggleBars) return false;
        onToggleMenu();
        return true;

      case BindingAction.openSettings:
        onOpenSettings();
        return true;

      case BindingAction.openRadialMenu:
        // 「怎么打开轮盘」与「轮盘里每一格干什么」同一套机制：一条输入 → 一个动作 id。
        // 差别只在前者的输入是键盘/点击，后者的输入是 `device: radial`。
        onOpenRadialMenu();
        return true;

      default:
        return false;
    }
  }

  bool _turnPage({required bool next, required bool fromKeyboard}) {
    // 键盘的空间动作与改造前同一出口（`onSpatialPageRight` → `onPageAction*`）：条漫下
    // 是一整屏的百分比滚动，而不是 200px 微调 —— 微调属于「向下滚动」那一族。
    if (!fromKeyboard) onBeforePageTurn?.call();
    if (next) {
      actions.onPageActionNext();
    } else {
      actions.onPageActionPrev();
    }
    return true;
  }

  /// 左开 ⇄ 右开。条漫（readMode 0）没有左右可言 —— 与顶栏那颗按钮同一判定：
  /// 置灰 / 不动，而不是「切到某个横翻模式」。
  bool _toggleReadingDirection() {
    final mode = _readSetting.readMode;
    if (mode != 1 && mode != 2) return false;
    context.read<GlobalSettingCubit>().updateReadSetting(
      (current) => current.copyWith(readMode: current.readMode == 2 ? 1 : 2),
    );
    return true;
  }
}
