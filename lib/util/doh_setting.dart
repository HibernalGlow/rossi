import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/src/rust/api/qjs.dart';

/// 把 DoH 设置应用到 Rust 侧 HTTP 客户端。
///
/// 幂等：可以随时调用。开启且有端点时，Rust 侧所有 HTTP 请求（含 ECH 引导）
/// 都会优先走 DoH，与是否开启代理无关；配置变更通过代际机制立刻生效。
void applyDohSetting(DohSettingState setting) {
  try {
    setDohConfig(
      enabled: setting.enabled,
      providers: setting.providers
          .map((url) => url.trim())
          .where((url) => url.isNotEmpty)
          .toList(growable: false),
    );
  } catch (_) {}
}
