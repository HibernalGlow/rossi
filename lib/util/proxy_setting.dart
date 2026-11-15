import 'package:flutter_socks_proxy/socks_proxy.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/src/rust/api/qjs.dart';

/// 把代理设置应用到 Rust 侧 HTTP 客户端和 Dart 侧 `dart:io` HttpClient。
///
/// 幂等：可以随时调用。关闭代理或地址为空时会清空两种代理。
///
/// Rust 侧的配置变更会通过代际机制立刻同步到已加载的 QJS runtime，
/// 所以不需要重启应用。
void applyProxySetting(ProxySettingState setting) {
  final address = setting.address.trim();
  if (!setting.enabled || address.isEmpty) {
    try {
      setHttpProxy(proxy: '');
      setSocks5Proxy(proxy: '');
    } catch (_) {}
    SocksProxy.setProxy('DIRECT');
    return;
  }

  switch (setting.type) {
    case ProxyType.http:
      final proxyUrl =
          address.startsWith('http://') || address.startsWith('https://')
          ? address
          : 'http://$address';
      setHttpProxy(proxy: proxyUrl);
      // Dart 侧纯 dart:io HttpClient（如 minio / S3 同步）也走 HTTP 代理
      SocksProxy.initProxy(proxy: 'PROXY ${stripProxyScheme(proxyUrl)}');
    case ProxyType.socks5:
      SocksProxy.initProxy(proxy: 'SOCKS5 $address');
      setSocks5Proxy(proxy: address);
  }
}

/// 去掉代理地址的协议前缀，得到 `host:port`，供 Dart 侧 HttpClient 使用。
String stripProxyScheme(String url) {
  var value = url.trim();
  for (final prefix in const ['https://', 'http://']) {
    if (value.startsWith(prefix)) {
      value = value.substring(prefix.length);
      break;
    }
  }
  return value;
}
