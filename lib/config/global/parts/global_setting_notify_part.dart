part of '../global_setting.dart';

// 提示个性化（应用内提示的逐事项开关）

/// 应用内提示的个性化存储：**总开关 + 逐事项开关**。
///
/// 只管「要不要弹」，不管「长什么样」（外观见 [ToastSettingState]），
/// 也**不管系统通知栏那一路**（`flutter_local_notifications` 那条通道本轮不并进来，
/// 口径见 `docs/adr/0020-in-app-notification-personalization.md`）。
///
/// [topics] 的键用**稳定字符串 id**（见 `NotifyTopic.id`），不用枚举：
/// 这一份 JSON 会跟着设置块走云同步，而 `json_serializable` 对枚举键走
/// `$enumDecode`——碰到不认识的枚举名会**抛异常**，把那台设备上这一整块设置
/// 一起读失败（同一个坑的现场记录在 `ReadSettingState.readerBackgroundMode`）。
/// 字符串键则把「新版本新增了事项」降级成「本机没登记过该项」，
/// 由该事项自己的默认值（`NotifyTopic.defaultEnabled`）接住。
@freezed
abstract class NotifySettingState with _$NotifySettingState {
  const factory NotifySettingState({
    /// 「自动提示」总开关。关掉它只静音**后台自己冒出来**的那一类
    /// （同步结果、下载完成、追更、插件脚本报信……）。
    ///
    /// **不静音操作反馈**：点了收藏却一声不响，用户读到的是「按钮坏了」，
    /// 不是「安静」。这条口径的来由写在 ADR-0020。
    @Default(true) bool enabled,

    /// 逐事项**覆盖**。缺席 = 用该事项自己的默认（`NotifyTopic.defaultEnabled`）。
    ///
    /// 默认值不住在这里：否则「恢复默认」和「回落判断」会分成两个真源，互相打脸。
    @Default(<String, bool>{}) Map<String, bool> topics,
  }) = _NotifySettingState;

  factory NotifySettingState.fromJson(Map<String, dynamic> json) =>
      _$NotifySettingStateFromJson(json);
}

/// 提示个性化设置的读入口。
///
/// 与 [toastSetting] 同理：判定发生在**任意时刻**（后台定时器、下载队列、
/// 插件脚本），那些调用点多半拿不到 `BuildContext`/Cubit，所以直接读本地库；
/// 库还没起来或已关闭时回落到默认值——绝不让「读设置」本身把提示炸掉。
NotifySettingState get notifySetting {
  try {
    return objectbox.userSettingBox.get(1)?.globalSetting.notifySetting ??
        const NotifySettingState();
  } catch (_) {
    return const NotifySettingState();
  }
}
