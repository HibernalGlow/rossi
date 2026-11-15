import 'package:zephyr/src/rust/api/qjs.dart';

/// 把「内网拦截」开关应用到 Rust 侧 HTTP 客户端。
///
/// 开关关闭（默认）时放行内网 / 保留地址段，打开时拦截；域名前置的 IP 直连
/// 与普通请求共用这一个开关。配置变更会通过代际机制立刻同步到已加载的 QJS
/// runtime，不需要重启。
void applyPrivateNetworkPolicy({required bool blockPrivateNetwork}) {
  setAllowPrivateNetwork(enabled: !blockPrivateNetwork);
}
