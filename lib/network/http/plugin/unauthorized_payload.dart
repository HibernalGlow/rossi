import 'dart:convert';

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:zephyr/util/json/json_value.dart';

class UnauthorizedPayload {
  const UnauthorizedPayload({
    required this.pluginId,
    required this.message,
    this.scheme,
    this.data,
  });

  final String pluginId;
  final String message;
  final Map<String, dynamic>? scheme;
  final Map<String, dynamic>? data;
}

/// 从插件调用抛出的错误里嗅探「登录态失效」载荷。
///
/// # 为什么这里**不能**写 `(error as AnyhowException)`
///
/// 只有**跨过 FRB 回来的**插件错误才是 [AnyhowException]；Dart 侧自己抛的
/// 一律不是 —— `StateError`（插件/runtime 不可用、bundle 缺失）、
/// `FormatException`（插件返回值不是 JSON map）、`DownloadTaskCancelledException`
/// 都可能出现在这里。
///
/// 硬转会抛 `TypeError`，而这个 `TypeError` 是在调用方
/// （[callUnifiedComicPlugin] 的 `catch`）里抛出来的 → **真实错误被顶替**：
/// 界面上只剩一句
/// 「type 'StateError' is not a subtype of type 'AnyhowException' in type cast」，
/// 真正的原因（例如 `plugin_not_found:bika`）一个字都不剩，连日志都跟着失真。
/// 嗅探函数是**旁路判断**：它没资格改写错误本身，拿不准就该安静地返回 null，
/// 让调用方 `rethrow` 把原错误原样交出去。
///
/// 非 [AnyhowException] 的错误里不会出现这段载荷（载荷由插件 JS 抛出、经 Rust
/// `anyhow` 回来），所以只认 [AnyhowException] 既不会漏判，也避免把普通错误的
/// 文本误判成「登录过期」而弹一次假的重新登录。
UnauthorizedPayload? parseUnauthorizedPayload(
  Object error, {
  required String fallbackPluginId,
}) {
  if (error is! AnyhowException) {
    return null;
  }
  final text = error.message.trim().split('\n').first;
  final regExp = RegExp(
    r'(?:bundle:.*?cjs\]|source:.*?cjs\])\s*(\{.*\})',
    dotAll: true,
  );
  final match = regExp.firstMatch(text);
  final jsonText = match != null ? match.group(1)! : text;
  try {
    final parsed = requireJsonMap(jsonDecode(jsonText));
    if (parsed['type']?.toString() != 'unauthorized') {
      return null;
    }
    final pluginId = parsed['source']?.toString().trim();
    return UnauthorizedPayload(
      pluginId: pluginId?.isNotEmpty == true ? pluginId! : fallbackPluginId,
      message: parsed['message']?.toString().trim().isNotEmpty == true
          ? parsed['message'].toString().trim()
          : '登录过期，请重新登录',
      scheme: asJsonMap(parsed['scheme']),
      data: asJsonMap(parsed['data']),
    );
  } catch (_) {
    return null;
  }
}
