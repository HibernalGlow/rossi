import 'package:flutter/foundation.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/src/rust/api/qjs.dart';

/// 真正发起一次插件 `init` 的派发口。
typedef PluginInitRunner = Future<void> Function(String runtimeName);

Future<void> _invokeQjsInit(String runtimeName) => qjsTaskCall(
  runtimeName: runtimeName,
  taskGroupKey: '',
  isOnce: false,
  fnPath: 'init',
  argsJson: '{}',
);

/// 插件 `init` 的唯一登记处。
///
/// 宿主只能观察到「init 这个函数返回了」；探测型插件（先抓发布页再逐域名测速，把失败
/// 吞掉后正常返回）会让这个观察失真，所以这里不能用「调用过就算完成」：
/// - 用 `generation` 记录 bundle 被换过几次，在途 init 的结果只有在代际没变时才算数；
/// - 用 `inFlight` 让并发调用共用同一次 init，而不是各自发起一轮域名探测。
class PluginInitCoordinator {
  PluginInitCoordinator._() : _runInit = _invokeQjsInit;

  @visibleForTesting
  PluginInitCoordinator.withRunner(PluginInitRunner runner) : _runInit = runner;

  static final PluginInitCoordinator I = PluginInitCoordinator._();

  final PluginInitRunner _runInit;

  /// 插件没实现 init 时 Rust 侧报的标记，此时应当按「已完成」处理，
  /// 否则每次调用都会白跑一趟。
  static const _initMissingMarker = 'target is not function: init';

  /// 探测域名还没落地的报错特征。命中它才有必要重跑 init，
  /// 其它报错（404 / 解析失败）重跑 init 只会拖慢调用。
  static const _notReadyMarkers = ['未初始化', '请等待插件初始化', 'not initialized'];

  /// init 明确失败后的静默期：期间不再重复探测，让调用方拿到插件自己的报错。
  static const _failureCooldown = Duration(seconds: 5);

  final Map<String, int> _generation = {};
  final Set<String> _ready = {};
  final Map<String, _InitSlot> _inFlight = {};
  final Map<String, DateTime> _failedAt = {};

  bool isReady(String runtimeName) => _ready.contains(runtimeName);

  /// bundle 被替换、runtime 被释放、插件配置变更后都必须调用。
  /// 下一次 [ensureInitialized] 会真正重跑 init。
  void invalidate(String runtimeName) {
    _generation[runtimeName] = (_generation[runtimeName] ?? 0) + 1;
    _ready.remove(runtimeName);
    _inFlight.remove(runtimeName);
    _failedAt.remove(runtimeName);
  }

  /// 释放 Rust 侧 runtime 并作废 init 记录，两者不能拆开做。
  /// 先作废再释放：即使 drop 抛错，也不会留下「runtime 已经没了但记录说就绪」的状态。
  Future<void> resetRuntime(String runtimeName) async {
    invalidate(runtimeName);
    if (await isQjsRuntimeInitialized(name: runtimeName)) {
      await qjsDropRuntime(runtimeName: runtimeName);
    }
  }

  /// 等到插件真正可用。并发调用共用同一次 init；已经就绪时立即返回。
  ///
  /// 返回 false 表示因为刚失败过而跳过（静默期），调用方不要把它当成初始化成功。
  /// init 抛错时向上抛，与插件函数调用的错误一起呈现给使用者。
  Future<bool> ensureInitialized(String runtimeName) async {
    if (_ready.contains(runtimeName)) {
      return true;
    }
    final running = _inFlight[runtimeName];
    if (running != null) {
      await running.future;
      return _ready.contains(runtimeName);
    }
    if (_inFailureCooldown(runtimeName)) {
      return false;
    }
    final slot = _InitSlot();
    _inFlight[runtimeName] = slot;
    slot.future = _performInit(runtimeName, slot);
    await slot.future;
    return _ready.contains(runtimeName);
  }

  /// 调用方拿到「未初始化」报错后请求重跑一次 init（「重新加载」走的就是这里）。
  /// 返回 false 表示没有重跑成功，调用方应抛出原始报错。
  ///
  /// 这里只降级、不作废：在途的那次 init 属于当前 bundle，等它就够了，
  /// 再发一轮域名探测只会加重站点限流。
  Future<bool> retryAfterNotReady(String runtimeName) async {
    if (_inFailureCooldown(runtimeName)) {
      return false;
    }
    _ready.remove(runtimeName);
    _failedAt.remove(runtimeName);
    try {
      return await ensureInitialized(runtimeName);
    } catch (e) {
      logger.w('插件重跑 init 失败: $runtimeName', error: e);
      return false;
    }
  }

  bool _inFailureCooldown(String runtimeName) {
    final failedAt = _failedAt[runtimeName];
    if (failedAt == null) {
      return false;
    }
    if (DateTime.now().difference(failedAt) < _failureCooldown) {
      return true;
    }
    _failedAt.remove(runtimeName);
    return false;
  }

  Future<void> _performInit(String runtimeName, _InitSlot slot) async {
    final generation = _generation[runtimeName] ?? 0;
    try {
      try {
        await _runInit(runtimeName);
      } catch (e) {
        if (!e.toString().contains(_initMissingMarker)) {
          rethrow;
        }
        logger.w('插件未实现 init，已跳过: $runtimeName');
      }
      if ((_generation[runtimeName] ?? 0) != generation) {
        // 等回来时 bundle 已经被换掉，这次 init 属于旧模块，不算数。
        return;
      }
      _ready.add(runtimeName);
      _failedAt.remove(runtimeName);
    } catch (_) {
      _failedAt[runtimeName] = DateTime.now();
      rethrow;
    } finally {
      if (identical(_inFlight[runtimeName], slot)) {
        _inFlight.remove(runtimeName);
      }
    }
  }
}

bool isPluginNotReadyError(Object error) {
  final message = error.toString().toLowerCase();
  return PluginInitCoordinator._notReadyMarkers.any(
    (marker) => message.contains(marker),
  );
}

class _InitSlot {
  late final Future<void> future;
}
