import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/network/http/plugin/plugin_init_coordinator.dart';

/// 插件 init 登记处的并发口径。
///
/// 背景（真实故障）：wnacg 这类探测型插件的 `init` 要先抓发布页、再逐域名测速，
/// 并且把探测失败吞掉后正常返回。宿主旧口径是「调过 init 就算完成」，于是
/// 一次探测失败会把插件钉死整个会话，界面上就是「尚未初始化，请等待插件初始化完成」，
/// 点「重新加载」也不会重跑 init。这里锁住新的四条口径。
void main() {
  group('PluginInitCoordinator', () {
    test('并发 ensureInitialized 只派发一次 init，并且都等到它完成', () async {
      final gate = Completer<void>();
      var calls = 0;
      final coordinator = PluginInitCoordinator.withRunner((runtime) async {
        calls++;
        await gate.future;
      });

      final first = coordinator.ensureInitialized('r');
      final second = coordinator.ensureInitialized('r');
      expect(calls, 1, reason: '第二个调用方必须复用同一次 init');

      gate.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(coordinator.isReady('r'), isTrue);
      expect(calls, 1);
    });

    test('init 抛错后进入静默期：不再重复探测，且 ensure 返回 false', () async {
      var calls = 0;
      final coordinator = PluginInitCoordinator.withRunner((runtime) async {
        calls++;
        throw Exception('域名探测超时');
      });

      await expectLater(
        coordinator.ensureInitialized('r'),
        throwsA(isA<Exception>()),
      );
      expect(coordinator.isReady('r'), isFalse);

      expect(await coordinator.ensureInitialized('r'), isFalse);
      expect(calls, 1, reason: '静默期内不该再打一轮站点');
    });

    test('换 bundle 后重新探测；在途的旧 init 结果不算数', () async {
      final staleGate = Completer<void>();
      final calls = <String>[];
      final coordinator = PluginInitCoordinator.withRunner((runtime) async {
        calls.add(runtime);
        if (calls.length == 1) {
          await staleGate.future;
        }
      });

      final stale = coordinator.ensureInitialized('r');
      expect(calls, ['r']);

      // 模拟云端静默更新：bundle 被换掉，JS 模块状态全新。
      coordinator.invalidate('r');
      staleGate.complete();
      expect(await stale, isFalse, reason: '旧模块的 init 结论必须作废');
      expect(coordinator.isReady('r'), isFalse);

      expect(await coordinator.ensureInitialized('r'), isTrue);
      expect(calls, ['r', 'r'], reason: '新 bundle 要真正重跑一次 init');
    });

    test('未初始化报错走 retryAfterNotReady 时复用同一次在途 init', () async {
      final firstGate = Completer<void>();
      final retryGate = Completer<void>();
      var calls = 0;
      final coordinator = PluginInitCoordinator.withRunner((runtime) async {
        calls++;
        await (calls == 1 ? firstGate.future : retryGate.future);
      });

      final ready = coordinator.ensureInitialized('r');
      firstGate.complete();
      expect(await ready, isTrue);
      expect(calls, 1);

      final first = coordinator.retryAfterNotReady('r');
      final second = coordinator.retryAfterNotReady('r');
      expect(calls, 2, reason: '降级就绪后只补发一次探测');

      retryGate.complete();
      expect(await first, isTrue);
      expect(await second, isTrue, reason: '第二个调用方等的是同一次 init');
      expect(calls, 2);
    });

    test('插件没实现 init 时按就绪处理，不每次白跑', () async {
      var calls = 0;
      final coordinator = PluginInitCoordinator.withRunner((runtime) async {
        calls++;
        throw Exception(
          'target is not function: init; targetType=undefined; rootKeys=["getInfo"]',
        );
      });

      expect(await coordinator.ensureInitialized('r'), isTrue);
      expect(await coordinator.ensureInitialized('r'), isTrue);
      expect(calls, 1);
    });
  });

  group('isPluginNotReadyError', () {
    test('认得出探测未就绪的报错', () {
      expect(
        isPluginNotReadyError(
          Exception('[bundle:7166a5fc fn:getComicDetail] 尚未初始化，请等待插件初始化完成'),
        ),
        isTrue,
      );
      expect(
        isPluginNotReadyError(Exception('plugin is not initialized')),
        isTrue,
      );
    });

    test('不误伤其它报错：重跑 init 对它们没有意义', () {
      expect(isPluginNotReadyError(Exception('HTTP 404 Not Found')), isFalse);
      expect(isPluginNotReadyError(Exception('解析列表页失败')), isFalse);
    });
  });
}
