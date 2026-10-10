import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 提示的处置口径 —— 决定「这一类消息归不归逐事项开关管、要不要节流」。
enum NotifyPolicy {
  /// 用户动作的回应（点了收藏、点了保存、点了手动同步）。
  ///
  /// **永不静音**：这类提示是「按钮有反应」的唯一证据，静音了用户读到的是坏了。
  actionFeedback,

  /// 后台自己冒出来的提示（定时器、队列回调、流监听、插件脚本）。
  ///
  /// 归「自动提示」总开关与逐事项开关管，并按 [NotifyTopic.throttle] 节流。
  /// 这一类才是「没过一会儿弹一次」的来源。
  ambient,

  /// 开关住在它自己的设置块里，不归本表管。
  ///
  /// 阅读器切书/翻页/触边界提示就是这个情况（`SwitchToastSettingState` 的
  /// `enableBook`/`enablePage`/`enableBoundaryToast`，并且服务内部已自带 500 ms
  /// 去重）。再造一份同名开关只会多出第二个真源，两边会互相打脸。
  selfManaged,
}

/// 应用内提示的**事项**登记表。
///
/// 新增事项就往这里加一个值，然后调用点带上它即可；设置页遍历
/// [ambientTopics] 自动长出来，不用改页面代码。
///
/// [id] 是存进 `NotifySettingState.topics` 的稳定键，**一旦发布不要改名**：
/// 改名等于把用户已有的逐项开关全部读成「没登记过」→ 悄悄回到默认值。
enum NotifyTopic {
  /// 默认档：现有三百多处 `showInfoToast` / `showSuccessToast` …… 调用点。
  ///
  /// 它们全是操作反馈，所以 [NotifyPolicy.actionFeedback]；节流窗口沿用改造前
  /// 根页面那条手写去重的 2 秒同文本合并（`navigation_bar` 里的老实现）。
  action(
    id: 'action',
    policy: NotifyPolicy.actionFeedback,
    throttle: Duration(seconds: 2),
  ),

  /// 阅读器切换提示（切书 / 翻页 / 触到最后一页）。
  readerSwitch(id: 'reader.switch', policy: NotifyPolicy.selfManaged),

  syncAutoSuccess(
    id: 'sync.autoSuccess',
    policy: NotifyPolicy.ambient,
    throttle: Duration(minutes: 10),
  ),

  syncAutoFailure(
    id: 'sync.autoFailure',
    policy: NotifyPolicy.ambient,
    throttle: Duration(minutes: 10),
  ),

  downloadComplete(
    id: 'download.complete',
    policy: NotifyPolicy.ambient,
    throttle: Duration(seconds: 60),
  ),

  downloadFailed(
    id: 'download.failed',
    policy: NotifyPolicy.ambient,
    throttle: Duration(seconds: 60),
  ),

  followUpdate(
    id: 'follow.update',
    policy: NotifyPolicy.ambient,
    throttle: Duration(minutes: 5),
  ),

  /// 插件脚本自己调 `flutter.showToast`。
  ///
  /// 节流必须留着：脚本可以在一次抓取的循环里逐章连发，改造前那条通道
  /// **一条去重都没有**（`dart_tools_bridge`）。
  pluginMessage(
    id: 'plugin.message',
    policy: NotifyPolicy.ambient,
    throttle: Duration(seconds: 3),
  ),

  /// 外部调起 / 深链落点提示（`open_intent_consumer`）。
  intentOpen(
    id: 'intent.open',
    policy: NotifyPolicy.ambient,
    throttle: Duration(minutes: 5),
  ),

  /// 通知权限被拒等系统层提示（启动路径上每次都发，`notification_service`）。
  systemPermission(
    id: 'system.permission',
    policy: NotifyPolicy.ambient,
    throttle: Duration(minutes: 30),
  );

  const NotifyTopic({required this.id, required this.policy, this.throttle});

  /// 存进设置里的稳定键。
  final String id;

  final NotifyPolicy policy;

  /// 出厂默认：**现在所有事项都默认开**，所以它是一个 getter，不是每个值都要传的
  /// 参数（没人传的参数就是个死口子）。将来要改某一项的默认，在这里按事项分叉。
  ///
  /// 默认值住在这里、不住在存储里：存储只放用户的**偏离**，于是「恢复默认」与
  /// 「未登记时回落」用的是同一个数，不会长成两个互相打脸的真源。
  bool get defaultEnabled => true;

  /// 同一件事（同 [id] + 同标题 + 同正文）在这个窗口内最多弹一次；
  /// 被压掉的条数不丢，挂在窗口过期后的**下一条**上（见 `NotifyGateway`）。
  ///
  /// `null` 表示本表不节流（`selfManaged` 的事项自己管）。
  final Duration? throttle;

  /// 归逐事项开关管的那些。设置页就列这一组。
  static List<NotifyTopic> get ambientTopics =>
      values.where((topic) => topic.policy == NotifyPolicy.ambient).toList();

  /// 现在到底让不让弹：总闸优先 → 逐事项覆盖 → 本事项出厂默认。
  ///
  /// 层叠顺序要显示在设置页上（总闸关掉时逐事项会「灰着但仍是开」，
  /// 不说明会被读成矛盾），见 `notify_setting_page.dart`。
  bool enabledIn(NotifySettingState setting) =>
      setting.enabled && (setting.topics[id] ?? defaultEnabled);

  String get label => switch (this) {
    NotifyTopic.action => t.settings.notifyTopicAction,
    NotifyTopic.readerSwitch => t.settings.notifyTopicReaderSwitch,
    NotifyTopic.syncAutoSuccess => t.settings.notifyTopicSyncAutoSuccess,
    NotifyTopic.syncAutoFailure => t.settings.notifyTopicSyncAutoFailure,
    NotifyTopic.downloadComplete => t.settings.notifyTopicDownloadComplete,
    NotifyTopic.downloadFailed => t.settings.notifyTopicDownloadFailed,
    NotifyTopic.followUpdate => t.settings.notifyTopicFollowUpdate,
    NotifyTopic.pluginMessage => t.settings.notifyTopicPluginMessage,
    NotifyTopic.intentOpen => t.settings.notifyTopicIntentOpen,
    NotifyTopic.systemPermission => t.settings.notifyTopicSystemPermission,
  };

  String get hint => switch (this) {
    NotifyTopic.action => t.settings.notifyTopicActionHint,
    NotifyTopic.readerSwitch => t.settings.notifyTopicReaderSwitchHint,
    NotifyTopic.syncAutoSuccess => t.settings.notifyTopicSyncAutoSuccessHint,
    NotifyTopic.syncAutoFailure => t.settings.notifyTopicSyncAutoFailureHint,
    NotifyTopic.downloadComplete => t.settings.notifyTopicDownloadCompleteHint,
    NotifyTopic.downloadFailed => t.settings.notifyTopicDownloadFailedHint,
    NotifyTopic.followUpdate => t.settings.notifyTopicFollowUpdateHint,
    NotifyTopic.pluginMessage => t.settings.notifyTopicPluginMessageHint,
    NotifyTopic.intentOpen => t.settings.notifyTopicIntentOpenHint,
    NotifyTopic.systemPermission => t.settings.notifyTopicSystemPermissionHint,
  };
}
