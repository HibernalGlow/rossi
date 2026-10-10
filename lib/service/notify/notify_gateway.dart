import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:rxdart/rxdart.dart';

import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/service/notify/notify_topic.dart';
import 'package:zephyr/widgets/toast/toast_card.dart' show ToastType;
import 'package:zephyr/widgets/toast/toast_overlay.dart'
    show ToastOverlayController;

/// 一条待处置的应用内提示。
///
/// 不可变：[withMerged] 产新事件，被压掉的条数只在放行的那一条上挂一次。
class NotifyEvent {
  const NotifyEvent({
    required this.topic,
    required this.type,
    required this.message,
    this.title,
    this.duration,
    this.userInitiated = false,
    this.context,
    this.merged = 0,
  });

  final NotifyTopic topic;
  final ToastType type;
  final String? title;
  final String message;

  /// `null` 表示「用设置里的时长」。
  final Duration? duration;

  /// 用户在这一次交互里主动要的结果（点了「立即同步」、点了刷新追更）。
  ///
  /// 置 `true` 时**绕过逐事项开关与总闸**。刻意不绕过同文本合并：连点两次
  /// 「立即同步」不该出两条一模一样的提示，改造前那条 2 秒去重管的也是这个。
  /// 定时器和后台回调必须留 `false`。
  final bool userInitiated;

  /// 调用点手上的上下文；渲染时优先用它，它不可用时回落到根导航。
  final BuildContext? context;

  /// 同一条上累计的「被窗口压掉」的条数。
  final int merged;

  /// 节流键：事项 + 标题 + 正文。
  ///
  /// 带上正文是刻意的：「《A》下载完成」和「《B》下载完成」是**两件不同的事**，
  /// 合并成一条就是丢信息；而自动同步失败每次都是同一句，才是要被压下去的那个。
  String get dedupKey => '${topic.id}|$title|$message';

  NotifyEvent withMerged(int count) => NotifyEvent(
    topic: topic,
    type: type,
    title: title,
    message: message,
    duration: duration,
    userInitiated: userInitiated,
    context: context,
    merged: count,
  );

  /// 把累计条数写进正文尾部。
  String get displayMessage => merged <= 0
      ? message
      : '$message${t.settings.notifyMergedSuffix(count: merged)}';
}

typedef NotifyRenderer = void Function(NotifyEvent event);
typedef NotifySettingsReader = NotifySettingState Function();
typedef NotifyClock = DateTime Function();

/// 应用内提示的**唯一判定口**：谁能弹、弹几条算一条。
///
/// 三件事按顺序发生（[NotifyGateway.submit] → 门禁 → 节流 → 渲染器）：
///
/// 1. **门禁**（[_allows]）：`userInitiated` / 操作反馈 / 自管事项直接放行；
///    后台自动提示读 `NotifySettingState`（总开关 + 逐事项）。
/// 2. **节流**（[_admit]）：同 [NotifyEvent.dedupKey] 在事项自己的窗口里只留一条，
///    被压掉的条数不丢，挂到窗口过期后的下一条上（「另有 N 次同类提示」）。
///    这一步是「每 5 分钟敲一次」的真正解药——开关只能整类关掉，
///    节流才能留住「出事了」这条信息本身。
/// 3. **渲染**（[renderOnToastOverlay]）：默认出口就是提示条，构造时接好；
///    判据可以用 [attach] 把出口换成 recorder。
///
/// 出口**不需要宿主先挂什么东西**：没有「先 attach 才不丢」这条隐式前提。
/// 这条前提是踩出来的 —— 顶栏那五颗占位按钮的判据（「点了要给一句话，不能静默失效」）
/// 在只挂测试宿主的场景下会被它直接吃掉。
///
/// rxdart 在这一层只承担**传输**：`PublishSubject` 把「谁在什么时候提交」与
/// 「谁负责弹」解耦，`where` 让门禁写在管线上。逐键的窗口记账（[_admit] 里那两张
/// 表）是应用自己的语义——「什么算同一件事」「压掉的次数怎么告诉用户」库不知道。
class NotifyGateway {
  NotifyGateway({
    NotifySettingsReader? settings,
    NotifyClock? clock,
    void Function(String message)? onDropped,
  }) : _readSettings = settings ?? _currentNotifySetting,
       _now = clock ?? DateTime.now,
       _onDropped = onDropped ?? _logDropped {
    // 出口在构造时就接好，且**默认出口永远是提示条**：
    // 「还没挂渲染器就丢掉一条」这种分支既会在启动早期吞掉真提示，
    // 也会让任何没走 app 启动流程的宿主（判据、独立入口）静默失效。
    _subscription = _input.where(_allows).listen((event) {
      final resolved = _admit(event);
      if (resolved != null) {
        _renderer(resolved);
      }
    });
  }

  /// 全局那一个。调用点用 `showInfoToast` 系列与本文件里的 `notifyAmbient`，
  /// 不要直接摸 [instance]。
  static final NotifyGateway instance = NotifyGateway();

  final NotifySettingsReader _readSettings;
  final NotifyClock _now;
  final void Function(String message) _onDropped;

  final PublishSubject<NotifyEvent> _input = PublishSubject<NotifyEvent>();
  late final StreamSubscription<NotifyEvent> _subscription;

  /// 「上次放行」与「窗口内被压掉的条数」，按 [NotifyEvent.dedupKey] 分键。
  final Map<String, DateTime> _lastShownAt = {};
  final Map<String, int> _suppressed = {};

  NotifyRenderer _renderer = renderOnToastOverlay;

  /// 换出口。判据用它换成 recorder；传回 [renderOnToastOverlay] 即恢复默认。
  void attach(NotifyRenderer renderer) {
    _renderer = renderer;
  }

  /// 只清节流记账并恢复默认出口，**不拆管线**。
  void detach() {
    _renderer = renderOnToastOverlay;
    _resetThrottleState();
  }

  /// 提交一条提示。
  void submit(NotifyEvent event) {
    if (event.message.trim().isEmpty) {
      return;
    }
    _input.add(event);
  }

  /// 只清节流记账。测试用。
  void _resetThrottleState() {
    _lastShownAt.clear();
    _suppressed.clear();
  }

  @visibleForTesting
  void resetForTest() {
    _resetThrottleState();
  }

  // ── 3. 渲染：默认出口 ────────────────────────────────────────────────

  /// 弹到提示条上。外观由 `ToastSettingState` 决定，这里只管挂哪儿。
  ///
  /// 一律走提示条：以前「正文 ≥ 30 字就退化成 commonDialog」，结果下载完成
  /// 这种长文件名会弹一个「成功 + 取消/确定」的对话框拦住用户。
  /// 长文本现在由提示条自己换行（见 ToastCard），不再有对话框那条分支。
  static void renderOnToastOverlay(NotifyEvent event) {
    final context = _usableContext(event.context);
    if (context == null) {
      logger.w('toast: 没有可用的根上下文，丢弃提示「${event.message}」');
      return;
    }
    ToastOverlayController.instance.show(
      context,
      type: event.type,
      title: event.title,
      // 累计条数在节流那步就已经拼进正文，渲染器不做文案加工。
      message: event.displayMessage,
      duration: event.duration,
    );
  }

  /// 优先用调用点手上的上下文（对话框里的提示希望挂在那一层），
  /// 它不可用再回落到根导航 —— 与改造前「没 context 就走总线补弹」等价，
  /// 只是这一跳不再需要事件总线。
  static BuildContext? _usableContext(BuildContext? preferred) {
    if (preferred != null && preferred.mounted) {
      return preferred;
    }
    final root = navigatorKey.currentContext;
    if (root != null && root.mounted) {
      return root;
    }
    return null;
  }

  // ── 1. 门禁 ──────────────────────────────────────────────────────────

  bool _allows(NotifyEvent event) {
    if (event.userInitiated) {
      return true;
    }
    switch (event.topic.policy) {
      case NotifyPolicy.actionFeedback:
        return true;
      case NotifyPolicy.selfManaged:
        return true;
      case NotifyPolicy.ambient:
        return event.topic.enabledIn(_readSettings());
    }
  }

  // ── 2. 节流 ──────────────────────────────────────────────────────────

  /// 同一条在窗口内只放行一次；被压掉的条数不丢，挂到窗口过后的那一条上。
  ///
  /// 返回 `null` 表示这一条被压掉。刻意写成**同步**的一步，而不是
  /// `StreamTransformer.bind` + `async*` 生成器：生成器里那层 `await for`
  /// 是延迟订阅的，`attach()` 之后同步 `add` 进来的第一条会被不缓冲的
  /// `PublishSubject` 直接吞掉 —— 这是探针实测出来的，不是推测。
  NotifyEvent? _admit(NotifyEvent event) {
    final window = event.topic.throttle;
    if (window == null || window <= Duration.zero) {
      return event;
    }
    final key = event.dedupKey;
    final last = _lastShownAt[key];
    if (last != null && _now().difference(last) < window) {
      _suppressed[key] = (_suppressed[key] ?? 0) + 1;
      _onDropped(event.message);
      return null;
    }
    _lastShownAt[key] = _now();
    final merged = _suppressed.remove(key) ?? 0;
    return merged == 0 ? event : event.withMerged(merged);
  }

  static NotifySettingState _currentNotifySetting() => notifySetting;

  static void _logDropped(String message) {
    logger.d('notify: 节流窗口内合并一条「$message」');
  }
}
