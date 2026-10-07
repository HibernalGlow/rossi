import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/service/open_intent/open_intents.dart';

/// 外部递来的字符串能不能当作「要打开的本地路径」—— 这条判定决定了
/// 右键菜单点了到底有没有反应，所以每条守卫都要能被抓到。
void main() {
  group('OpenIntents.offer', () {
    // 队列是进程级单例，用例之间必须清干净，否则前一条的路径会算进后一条。
    setUp(() => OpenIntents.instance.takeAll());

    test('POSIX 绝对路径进队列', () {
      OpenIntents.instance.offer('/tmp/漫画卷1');
      expect(OpenIntents.instance.takeAll(), ['/tmp/漫画卷1']);
    });

    test('Windows 盘符路径进队列', () {
      OpenIntents.instance.offer(r'C:\Users\x\Downloads\book.cbz');
      expect(OpenIntents.instance.takeAll(), [r'C:\Users\x\Downloads\book.cbz']);
    });

    test('UNC 路径进队列', () {
      OpenIntents.instance.offer(r'\\nas\manga\vol1');
      expect(OpenIntents.instance.takeAll(), [r'\\nas\manga\vol1']);
    });

    test('网络地址不算路径', () {
      // 这条是证伪目标：`//img.cdn/a.cbz` 以 `/` 开头，只判「像不像绝对路径」
      // 就会把 URL 当成磁盘路径推进队列，然后开成一本打不开的书。
      OpenIntents.instance.offer('https://example.com/a.cbz');
      OpenIntents.instance.offer('//img.cdn/a.cbz');
      expect(OpenIntents.instance.takeAll(), isEmpty);
    });

    test('阳性对照：双斜杠但没有主机味的仍算路径', () {
      // 上一条如果把「以 `//` 开头」一律拒掉也能通过，所以必须有这一条：
      // POSIX 允许 `//foo/bar` 是实现定义的路径，它是合法输入，不该被网络判据吞掉。
      OpenIntents.instance.offer('//nas01/vol1');
      expect(OpenIntents.instance.takeAll(), isNotEmpty);
    });

    test('相对路径与空串不算', () {
      OpenIntents.instance.offer('relative/dir');
      OpenIntents.instance.offer('');
      expect(OpenIntents.instance.takeAll(), isEmpty);
    });

    test('同一批里重复的路径只记一次', () {
      OpenIntents.instance.offer('/tmp/a');
      OpenIntents.instance.offer('/tmp/a');
      expect(OpenIntents.instance.takeAll(), ['/tmp/a']);
    });

    test('尾随斜杠被归一，同一目录不占两个位置', () {
      OpenIntents.instance.offer('/tmp/a/');
      OpenIntents.instance.offer('/tmp/a');
      expect(OpenIntents.instance.takeAll(), ['/tmp/a']);
    });

    test('takeAll 取完即清', () {
      OpenIntents.instance.offer('/tmp/a');
      expect(OpenIntents.instance.takeAll(), hasLength(1));
      expect(OpenIntents.instance.takeAll(), isEmpty);
    });
  });

  test('arrivals 把新到的路径推给监听者', () async {
    OpenIntents.instance.takeAll();
    final received = <String>[];
    final subscription = OpenIntents.instance.arrivals.listen(
      received.addAll,
    );
    OpenIntents.instance.offer('/tmp/b');
    await Future<void>.delayed(Duration.zero);
    expect(received, ['/tmp/b']);
    await subscription.cancel();
    OpenIntents.instance.takeAll();
  });
}
