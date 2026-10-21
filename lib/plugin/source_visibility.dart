import 'package:zephyr/main.dart';
import 'package:zephyr/plugin/models/plugin_runtime_state.dart';
import 'package:zephyr/plugin/source_visibility_policy.dart';

/// 「完整来源列表」开关的**非 widget** 读法。
///
/// 只在拿不到 `BuildContext` 的回调 / 服务里用；widget 里一律
/// `context.watch<GlobalSettingCubit>()`，否则切换开关后列表不会重建。
///
/// 读失败按「关闭」处理：宁可少列来源，也不要因为读不到配置把受限来源放出来。
/// ObjectBox 未初始化时这里会抛，必须兜住。
bool get showRestrictedSourcesOrFalse {
  try {
    return objectbox.userSettingBox
            .get(1)
            ?.globalSetting
            .showRestrictedSources ??
        false;
  } catch (_) {
    return false;
  }
}

/// 按开关过滤插件列表，顺序保持不变。
Iterable<PluginRuntimeState> filterRestrictedPlugins(
  Iterable<PluginRuntimeState> plugins, {
  required bool showRestricted,
}) {
  if (showRestricted) return plugins;
  return plugins.where(
    (plugin) => !SourceVisibilityPolicy.isRestricted(uuid: plugin.uuid),
  );
}

/// 同上，按 uuid 集合过滤。
Iterable<String> filterRestrictedUuids(
  Iterable<String> uuids, {
  required bool showRestricted,
}) {
  if (showRestricted) return uuids;
  return uuids.where(
    (uuid) => !SourceVisibilityPolicy.isRestricted(uuid: uuid),
  );
}
