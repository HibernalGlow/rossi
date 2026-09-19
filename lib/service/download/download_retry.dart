import 'package:zephyr/main.dart';
import 'package:zephyr/service/download/download_cancel_signal.dart';

/// 下载操作在首次尝试失败后，默认最多静默重试的次数。
const downloadSilentRetryCount = 3;

/// 判断是否为触发图源风控/限流的错误（如 HTTP 429 / 509 / 503 / Cloudflare 等）
bool isRateLimitedError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('429') ||
      message.contains('509') ||
      message.contains('503') ||
      message.contains('rate limit') ||
      message.contains('too many requests') ||
      message.contains('cloudflare');
}

Future<T> retryDownloadOperation<T>({
  required String operation,
  required Future<T> Function() action,
  required Future<void> Function() ensureTaskRunning,
  bool Function(Object error)? shouldRetry,
  bool Function()? shouldRetryUntilSuccess,
  Duration retryDelay = const Duration(seconds: 1),
}) async {
  Object? lastError;
  StackTrace? lastStackTrace;

  for (var attempt = 0;
      (shouldRetryUntilSuccess?.call() ?? false) ||
          attempt <= downloadSilentRetryCount;
      attempt++) {
    // 取消检查放在 try 外，取消不会被当成普通网络错误再次重试。
    await ensureTaskRunning();
    try {
      return await action();
    } catch (error, stackTrace) {
      final retryForever = shouldRetryUntilSuccess?.call() ?? false;
      if (_isDownloadCancellation(error) ||
          (!retryForever && attempt >= downloadSilentRetryCount) ||
          shouldRetry?.call(error) == false) {
        Error.throwWithStackTrace(error, stackTrace);
      }

      lastError = error;
      lastStackTrace = stackTrace;
      final retryNumber = attempt + 1;
      final isRateLimit = isRateLimitedError(error);

      // 测试或特殊调用传入 Duration.zero 时直接零等待；
      // 限流错误退避 3s, 5s, 7s...；普通网络错误指数退避 1s, 2s, 4s...
      final actualDelay = retryDelay == Duration.zero
          ? Duration.zero
          : (isRateLimit
              ? Duration(seconds: 3 + attempt * 2)
              : Duration(
                  milliseconds: (retryDelay.inMilliseconds * (1 << attempt))
                      .clamp(1000, 5000),
                ));

      logger.w(
        retryForever
            ? '$operation 失败${isRateLimit ? " [风控限流]" : ""}，准备持续重试 (第 $retryNumber 次，等待 ${actualDelay.inSeconds}s)'
            : '$operation 失败${isRateLimit ? " [风控限流]" : ""}，准备静默重试 ($retryNumber/$downloadSilentRetryCount，等待 ${actualDelay.inSeconds}s)',
        error: error,
        stackTrace: stackTrace,
      );
      if (actualDelay > Duration.zero) {
        await Future<void>.delayed(actualDelay);
      }
    }
  }

  // 逻辑上不会到达这里；保留栈信息，避免错误被意外吞掉。
  Error.throwWithStackTrace(lastError!, lastStackTrace!);
}

bool _isDownloadCancellation(Object error) {
  final message = error.toString();
  return message.contains(downloadTaskCancelledMessage) ||
      message.contains('__QJS_RUNTIME_CANCELLED__');
}

