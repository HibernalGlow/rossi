import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/service/reader/reader_history_service.dart';

/// 「页码只能来自这本自己」的结构前提。
///
/// 早先 `ReaderHistoryService` 是进程级单例，`_history` 装的是**最后一次
/// 读过/写过的那本**；而读写都是异步的，于是上一本在途的写入会落在下一本的
/// `loadHistory` 之后，把上一本的页码交给下一本 —— 症状就是换书后停在中间 /
/// 最后一页（再被 `clamp(0, totalSlots-1)` 变成"最后一页"）。
///
/// 现在的口径是**一个阅读会话一份实例**。这组用例钉的就是这条：谁再把它改回
/// 共享实例（哪怕换成 `factory` 返回同一个对象），这里会红。
void main() {
  test('历史服务每个阅读会话一份，不是共享单例', () {
    final first = ReaderHistoryService();
    final second = ReaderHistoryService();

    expect(
      identical(first, second),
      isFalse,
      reason: '共享实例 = 上一本的页码会漏给下一本',
    );
  });

  test('新建的实例没有页码：读不到任何"上一本残留"', () {
    expect(ReaderHistoryService().lastPageIndex, 0);
  });
}
