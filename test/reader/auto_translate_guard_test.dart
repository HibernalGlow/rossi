import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_read/widgets/reader_auto_translate_page.dart';

/// 「翻到新的一页自动译」的守卫矩阵。
///
/// 验的是判据，不是链路：`presenter` 与真呈现器在单测里拿不到，
/// 「真的翻出一张译文页」要真机判（同仓 `local_read_session_translation_gate_test.dart`
/// 对这种装配也是这么交代的）。这里守的是**抢用户**那一类错。
void main() {
  bool should({
    bool auto = true,
    bool supported = true,
    bool running = false,
    bool owned = false,
    bool building = false,
    bool alreadyTried = false,
    int index = 3,
  }) {
    return readerAutoTranslateShouldRun(
      auto: auto,
      supported: supported,
      running: running,
      owned: owned,
      building: building,
      alreadyTried: alreadyTried,
      index: index,
    );
  }

  test('阳性对照：翻到没译过的一页，且没在飞 —— 必须动手', () {
    expect(should(), isTrue, reason: '这一格判 false，自动档就整条是死的');
  });

  test('开关关着 / 这台机器不做翻译 —— 不动', () {
    expect(should(auto: false), isFalse);
    expect(should(supported: false), isFalse);
  });

  test('这一页已经有译文 —— 不动', () {
    // `toggle` 在已归属时是**关掉**：少了这一判，自动档会把用户刚手动关掉的
    // 那一页又点成译文页。
    expect(should(owned: true), isFalse);
  });

  test('上一张还在飞 / 这一页已经试过 —— 不动', () {
    // 增强图轨一页只有一份，并发塞第二张只会互相覆盖；
    // 失败后 owned 仍是 false，没有 alreadyTried 每次重建都会重烧十几秒。
    expect(should(running: true), isFalse);
    expect(should(building: true), isFalse);
    expect(should(alreadyTried: true), isFalse);
  });

  test('没有有效页号 —— 不动', () {
    expect(should(index: -1), isFalse);
    expect(should(index: 0), isTrue, reason: '第一页是合法目标，别把 0 当无值');
  });
}
