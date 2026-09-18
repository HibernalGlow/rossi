// 驻留计时（悬停聚焦 / 边缘揭示 / 揭示后恢复）的**纯 Dart** 判据。
//
//   dart run test/workspace/dwell_check.dart
//
// 时间由判据自己拨：`WorkspaceDwell` 不认识真实时钟，只认传进来的毫秒数。
// 于是「到点前不发、到点发一次、离开就取消」可以被**确定性地**钉住，
// 而不是靠 `await Future.delayed` 去赌调度 —— 那种判据在 CI 上会偶发变红，
// 而偶发变红的判据会被当成噪声忽略掉，等于没有。
//
// ignore_for_file: avoid_print
import 'package:zephyr/workspace/model/workspace_dwell.dart';

int _passed = 0;

void check(String label, bool condition, [String? detail]) {
  if (!condition) {
    throw StateError('FAIL: $label${detail == null ? '' : ' — $detail'}');
  }
  _passed++;
}

void main() {
  _firesOnlyAfterTheDelay();
  _firesExactlyOnce();
  _leaveOnlyCancelsItself();
  _switchingTargetRestartsTheClock();
  _suppressionCancelsAndBlocks();
  _nonPositiveDelayBecomesOneMillisecond();

  print('dwell_check: $_passed checks passed');
}

/// 到点之前绝不触发；恰好到点触发。
void _firesOnlyAfterTheDelay() {
  final dwell = WorkspaceDwell();
  dwell.enter('reader', nowMs: 1000, delayMs: 420);

  check('刚进入时还没到点', !dwell.isDue(1000));
  check('差 1ms 时还没到点', !dwell.isDue(1419));
  check('恰好在延时处到点', dwell.isDue(1420));
  check('剩余时间是延时本身', dwell.remainingMs(1000) == 420);

  final fresh = WorkspaceDwell();
  fresh.enter('r', nowMs: 0, delayMs: 10);
  check('没到点 takeDue 是 null', fresh.takeDue(9) == null);
  check('到点 takeDue 给出目标', fresh.takeDue(10) == 'r');
}

/// **只触发一次**：指针一直停在那儿不该反复激活（那会让画面持续横跳）。
void _firesExactlyOnce() {
  final dwell = WorkspaceDwell();
  dwell.enter('reader', nowMs: 0, delayMs: 300);

  check('到点发一次', dwell.takeDue(300) == 'reader');
  check('再问一次不再发', dwell.takeDue(300) == null);
  check('时间继续走也不发', dwell.takeDue(99999) == null);
  check('发完之后不再处于计时中', !dwell.isPending);
}

/// 离开只取消**自己**：从 A 移到 B 时事件顺序不保证，
/// 若无条件取消，B 的计时会被 A 的离开顺手抹掉。
void _leaveOnlyCancelsItself() {
  final dwell = WorkspaceDwell();
  dwell.enter('left', nowMs: 0, delayMs: 200);
  dwell.enter('right', nowMs: 50, delayMs: 200);

  dwell.leave('left'); // A 的离开事件迟到了
  check('迟到的离开不会抹掉新目标', dwell.pendingId == 'right');
  check('仍然按新目标的到点时间触发', dwell.takeDue(250) == 'right');

  final other = WorkspaceDwell();
  other.enter('right', nowMs: 0, delayMs: 200);
  other.leave('right');
  check('目标自己的离开会取消计时', !other.isPending);
  check('取消后到点也不发', other.takeDue(999) == null);
}

/// 换目标要**重新计时**：不能把在 A 攒的时间算给 B。
void _switchingTargetRestartsTheClock() {
  final dwell = WorkspaceDwell();
  dwell.enter('left', nowMs: 0, delayMs: 400);
  check('A 攒到差一点', dwell.remainingMs(390) == 10);

  dwell.enter('right', nowMs: 390, delayMs: 400);
  check('换到 B 之后剩余时间重新是 400', dwell.remainingMs(390) == 400);
  check('B 不继承 A 攒的时间', !dwell.isDue(400));
  check('B 按自己的到点时间触发', dwell.takeDue(790) == 'right');
}

/// 抑制期间：立刻作废待发项，且不触发（契约：指针捕获 / 拖动 / 输入法组合 /
/// 弹层 / 浮动菜单 期间既不许揭示也不许自动恢复）。
void _suppressionCancelsAndBlocks() {
  final dwell = WorkspaceDwell();
  dwell.enter('reader', nowMs: 0, delayMs: 100);
  dwell.setSuppressed(true);

  check('进入抑制立刻作废待发项', !dwell.isPending);
  check('抑制期间即使到点也不发', dwell.takeDue(5000) == null);
  check('isSuppressed 可读', dwell.isSuppressed);

  dwell.setSuppressed(false);
  check('解除抑制不会补发', dwell.takeDue(5001) == null);

  // 解除之后重新驻留仍然正常。
  dwell.enter('reader', nowMs: 6000, delayMs: 100);
  check('解除后新的驻留照常到点', dwell.takeDue(6100) == 'reader');

  // **抑制期间新进入的驻留也不许发。**
  //
  // 上面那条「抑制期间即使到点也不发」其实**验不到 `isDue` 里的 `_suppressed`**：
  // 进入抑制的瞬间就把待发项清掉了，`_pendingId` 已经是 null，就算 `isDue`
  // 完全不看 `_suppressed` 也照样返回 null（变异体 M35 就是这么活下来的）。
  // 要真的验到那一项，必须在**抑制状态里**新排一次驻留 —— `enter` 不做抑制检查
  // （抑制是 `isDue` 那一层的闸），于是这条才戳得到。
  final blocked = WorkspaceDwell()..setSuppressed(true);
  blocked.enter('reader', nowMs: 0, delayMs: 100);
  check('抑制期间新排的驻留到点也不发', blocked.takeDue(5000) == null);
  check('抑制期间新排的驻留仍留着待发项（是「不发」不是「被清掉」）', blocked.isPending);
  blocked.setSuppressed(false);
  check('解除抑制后那次被挡住的驻留可以发', blocked.takeDue(5001) == 'reader');
}

/// 延时小于等于 0 是非法值：按 1ms 处理，而不是「立刻」。
///
/// 区别在语义上：「立刻」意味着同一次事件里就触发（画面横跳），
/// 1ms 仍然过一次事件循环，用户扫过时不会误触发。
void _nonPositiveDelayBecomesOneMillisecond() {
  for (final delay in [0, -1, -1000]) {
    final dwell = WorkspaceDwell();
    dwell.enter('reader', nowMs: 0, delayMs: delay);
    check('delay=$delay 时 0ms 尚未到点', !dwell.isDue(0));
    check('delay=$delay 时 1ms 到点', dwell.isDue(1));
  }
}
