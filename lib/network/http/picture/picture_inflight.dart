import 'dart:convert';
import 'dart:typed_data';

/// 同一进程内、**完全相同请求**的图片字节共享表。
///
/// 阅读器预取下一页与用户真正翻到该页时，会各自发起一次参数完全一致的插件
/// 取字节请求；两个请求都在本地落盘之前出发，于是同一页下载两遍。这里按请求
/// 指纹合并成一次网络往返，另一个调用方等待同一份字节。
///
/// 指纹必须包含插件 id、QuickJS runtime、下载任务的取消域以及插件 `extern`：
/// 少了任何一项，等待方就可能继承别人的取消状态或插件请求参数（例如二次
/// `getChapter` 后 referer/token 已变），拿到的字节也可能不属于这一页。
/// 因此阅读请求与下载任务请求之间**不会**互相合并。
class PictureInflightBytes {
  PictureInflightBytes._();

  static final Map<String, Future<Uint8List>> _pending = {};

  static String key({
    required String url,
    required String source,
    required String runtimeName,
    required String taskGroupKey,
    required Map<String, dynamic> extern,
  }) {
    return jsonEncode(<String, dynamic>{
      'url': url,
      'source': source,
      'runtime': runtimeName,
      'group': taskGroupKey,
      'extern': extern,
    });
  }

  /// 执行 [action]，并把同一 [key] 的并发调用合并到第一次执行上。
  ///
  /// 失败与取消都会原样传播给等待方：各自主调方本来就会按自己的重试策略再试，
  /// 重试期间 key 已从表中移除，第二次尝试会独立发起请求。
  static Future<Uint8List> share(
    String key,
    Future<Uint8List> Function() action,
  ) async {
    final running = _pending[key];
    if (running != null) return running;

    final started = action();
    _pending[key] = started;
    try {
      return await started;
    } finally {
      // 只清理自己登记的那一条，避免旧条目被后续调用覆盖后误删。
      if (identical(_pending[key], started)) _pending.remove(key);
    }
  }

  /// 当前登记数量，仅用于测试与调试观察。
  static int get pendingCount => _pending.length;
}
