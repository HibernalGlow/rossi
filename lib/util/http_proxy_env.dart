import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:zephyr/network/http/wind_http.dart';
import 'package:zephyr/src/rust/api/qjs.dart';

/// 开发期从 `.env.proxy` 资源探测代理，探得到才套上去。
///
/// 判据用 `kReleaseMode` 而不是 `kDebugMode`：日常开发跑 `--profile` 时
/// `kDebugMode` 为 false，用它会连开发期代理一起关掉。
Future<void> tryApplyHttpProxyFromEnv() async {
  if (kReleaseMode) return;

  final rawProxy = await _readProxyFromEnvAsset();
  if (rawProxy == null || rawProxy.isEmpty) return;

  final proxyUrl =
      rawProxy.startsWith('http://') || rawProxy.startsWith('https://')
      ? rawProxy
      : 'http://$rawProxy';

  final reachable = await _probeProxyWithTimeout(proxyUrl);
  if (!reachable) return;

  setHttpProxy(proxy: proxyUrl);
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

Future<String?> _readProxyFromEnvAsset() async {
  try {
    final content = await rootBundle.loadString('.env.proxy');
    for (final rawLine in const LineSplitter().convert(content)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (!line.startsWith('proxy=')) continue;
      final value = line.substring('proxy='.length).trim();
      if (value.isNotEmpty) return value;
    }
  } catch (_) {
    return null;
  }
  return null;
}

Future<bool> _probeProxyWithTimeout(String proxyUrl) async {
  try {
    final response = await WindHttp(
      httpProxy: proxyUrl,
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
      followRedirects: false,
    ).fetch('http://www.gstatic.com/generate_204');
    return response.status >= 200 && response.status < 500;
  } catch (_) {
    return false;
  }
}
