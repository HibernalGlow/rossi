import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/service/reader/local_book_navigation_controller.dart';
import 'package:zephyr/src/rust/api/file_manager.dart';

void main() {
  test('上下本切换会把游标交给下一本，并合并并发输入', () async {
    var calls = 0;
    final opened = <String>[];
    final messages = <String>[];
    final target = const LocalBookNavigationTarget(
      path: '/books/next.cbz',
      navigationJson: '{}',
    );
    final controller = LocalBookNavigationController(
      path: '/books/current.cbz',
      navigationJson: '{"cursor":1}',
      notify: messages.add,
      resolve: ({
        required String path,
        String? navigationJson,
        required bool forward,
      }) async {
        calls += 1;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        expect(path, '/books/current.cbz');
        expect(navigationJson, '{"cursor":1}');
        expect(forward, isTrue);
        return target;
      },
      open: (value) async => opened.add(value.path),
    );

    await Future.wait([controller.switchBook(true), controller.switchBook(true)]);
    expect(calls, 1);
    expect(opened, ['/books/next.cbz']);
    expect(messages, isEmpty);
  });

  test('到达上下本边界时提示用户，释放后不再提交迟到的结果', () async {
    final messages = <String>[];
    final controller = LocalBookNavigationController(
      path: '/books/current.cbz',
      notify: messages.add,
      resolve: ({
        required String path,
        String? navigationJson,
        required bool forward,
      }) async => null,
      open: (_) async {},
    );

    await controller.switchBook(false);
    expect(messages, ['已经是第一本书']);
    controller.dispose();
    await controller.switchBook(true);
    expect(messages, ['已经是第一本书']);
  });
}
