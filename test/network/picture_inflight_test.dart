import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/network/http/picture/picture_inflight.dart';

Uint8List _bytes(int marker) => Uint8List.fromList([marker]);

void main() {
  group('图片字节并发合并', () {
    test('同一指纹的并发调用只执行一次', () async {
      var calls = 0;
      Future<Uint8List> action() async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return _bytes(7);
      }

      final first = PictureInflightBytes.share('same', action);
      final second = PictureInflightBytes.share('same', action);

      expect(await first, await second);
      expect(calls, 1);
    });

    test('不同指纹各执行一次', () async {
      var calls = 0;
      Future<Uint8List> action() async {
        calls++;
        return _bytes(calls);
      }

      final a = PictureInflightBytes.share('k1', action);
      final b = PictureInflightBytes.share('k2', action);
      await Future.wait([a, b]);

      expect(calls, 2);
    });

    test('失败原样传播给等待方并释放该指纹', () async {
      var calls = 0;
      Future<Uint8List> failing() async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        throw StateError('boom');
      }

      Object? firstError;
      Object? secondError;
      // 创建时立刻挂上处理器，避免错误在监听前就被 zone 记成未捕获异常。
      final a = PictureInflightBytes.share('fail', failing).catchError(
        (Object e) {
          firstError = e;
          return Uint8List(0);
        },
      );
      final b = PictureInflightBytes.share('fail', failing).catchError(
        (Object e) {
          secondError = e;
          return Uint8List(0);
        },
      );
      await a;
      await b;

      expect(firstError, isStateError);
      expect(secondError, isStateError);
      expect(calls, 1);
      expect(PictureInflightBytes.pendingCount, 0);

      // 释放后主调方可以按自己的重试策略重新发起。
      await PictureInflightBytes.share('fail', failing).catchError(
        (Object _) => Uint8List(0),
      );
      expect(calls, 2);
    });

    test('完成后不残留登记', () async {
      await PictureInflightBytes.share('done', () async => _bytes(1));
      expect(PictureInflightBytes.pendingCount, 0);
    });

    test('指纹包含取消域与插件参数，跨请求域不会误合并', () {
      final base = <String, dynamic>{'referer': 'a'};
      String keyOf({
        String group = '',
        Map<String, dynamic> extern = const {},
      }) {
        return PictureInflightBytes.key(
          url: 'https://img/1.jpg',
          source: 'bika',
          runtimeName: 'bika',
          taskGroupKey: group,
          extern: extern,
        );
      }

      expect(
        keyOf(group: 'task-1', extern: base),
        isNot(keyOf(group: '', extern: base)),
      );
      expect(
        keyOf(extern: base),
        isNot(keyOf(extern: {'referer': 'b'})),
      );
      expect(
        keyOf(extern: base),
        keyOf(extern: {'referer': 'a'}),
      );
    });
  });
}
