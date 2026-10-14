/// 对一次完整的传输做有限次重试。
///
/// 只用于「失败后从头再来也安全」的下载：Rust 侧失败时会删掉 `.part`，
/// 所以重试不会拼接出残缺文件；校验（大小 / SHA-256）仍在传输之外，不会被重试掩盖。
Future<T> retryTransfer<T>(
  Future<T> Function(int attempt) run, {
  int attempts = 3,
  Duration Function(int attempt) delay = _defaultDelay,
  void Function(int attempt, Object error)? onRetry,
}) async {
  assert(attempts >= 1);
  for (var attempt = 1; ; attempt++) {
    try {
      return await run(attempt);
    } catch (error) {
      if (attempt >= attempts) rethrow;
      onRetry?.call(attempt, error);
      await Future<void>.delayed(delay(attempt));
    }
  }
}

Duration _defaultDelay(int attempt) => Duration(seconds: attempt * 2);
