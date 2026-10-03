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
  _motionPushesTheDeadlineBack();
  _sweepNeverFires();
  _armedIsTheSettleBoundary();
  _nonPositiveDelayBecomesOneMillisecond();

  print('dwell_check: $_passed checks passed');
}

/// 到点之前绝不触发；恰好到点触发。
///
/// 到期点 = 进入时刻 + `settleMs`（先静够，「确实停住了」）+ `delayMs`
/// （停住之后再看一会儿）。两段都要验到位：只验总和，就看不出「静置」这一段
/// 到底是并进延时里了还是根本没参与。
void _firesOnlyAfterTheDelay() {
  const settle = WorkspaceDwell.settleMs;
  final dwell = WorkspaceDwell();
  dwell.enter('reader', nowMs: 1000, delayMs: 420);

  check('刚进入时还没到点', !dwell.isDue(1000));
  check('静置窗口里还没到点', !dwell.isDue(1000 + settle));
  check('差 1ms 时还没到点', !dwell.isDue(1000 + settle + 419));
  check('恰好在 settle+delay 处到点', dwell.isDue(1000 + settle + 420));
  check('剩余时间是 settle+delay 的全部', dwell.remainingMs(1000) == settle + 420);

  final fresh = WorkspaceDwell();
  fresh.enter('r', nowMs: 0, delayMs: 10);
  check('没到点 takeDue 是 null', fresh.takeDue(settle + 9) == null);
  check('到点 takeDue 给出目标', fresh.takeDue(settle + 10) == 'r');
}

/// **只触发一次**：指针一直停在那儿不该反复激活（那会让画面持续横跳）。
void _firesExactlyOnce() {
  final dwell = WorkspaceDwell();
  dwell.enter('reader', nowMs: 0, delayMs: 300);

  check('到点发一次', dwell.takeDue(WorkspaceDwell.settleMs + 300) == 'reader');
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
  check(
    '仍然按新目标的到点时间触发',
    dwell.takeDue(50 + WorkspaceDwell.settleMs + 200) == 'right',
  );

  final other = WorkspaceDwell();
  other.enter('right', nowMs: 0, delayMs: 200);
  other.leave('right');
  check('目标自己的离开会取消计时', !other.isPending);
  check('取消后到点也不发', other.takeDue(999) == null);
}

/// 换目标要**重新计时**：不能把在 A 攒的时间算给 B。
void _switchingTargetRestartsTheClock() {
  const settle = WorkspaceDwell.settleMs;
  final dwell = WorkspaceDwell();
  dwell.enter('left', nowMs: 0, delayMs: 400);
  check('A 攒到只剩 delay 的尾巴', dwell.remainingMs(390) == 70);

  dwell.enter('right', nowMs: 390, delayMs: 400);
  check(
    '换到 B 之后剩余时间重新是 settle+400',
    dwell.remainingMs(390) == settle + 400,
  );
  check('B 不继承 A 攒的时间', !dwell.isDue(400));
  check('B 按自己的到点时间触发', dwell.takeDue(390 + settle + 400) == 'right');
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
  check(
    '解除后新的驻留照常到点',
    dwell.takeDue(6000 + WorkspaceDwell.settleMs + 100) == 'reader',
  );

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

/// 指针**又动了**：到期点整体推后，攒下的静置时间不作废重来。
///
/// 这条是「停住才计时」的另一半：没有它，「路过时不打扰」就只能靠把延时
/// 拉到很大去挡，而真停下来的人也得一起等满。
void _motionPushesTheDeadlineBack() {
  const settle = WorkspaceDwell.settleMs;
  final dwell = WorkspaceDwell();
  dwell.enter('left', nowMs: 0, delayMs: 150);

  dwell.noteMotion(100);
  check('动了之后 100+settle 之前不算停住', !dwell.isArmed(100 + settle - 1));
  check('原来的到期点不再算到点', !dwell.isDue(0 + settle + 150));
  check('新的到期点是最后一次运动 + settle + delay', dwell.isDue(100 + settle + 150));

  // 对照：没有那次运动的话，本应在这里到点（证明推后真的发生了）。
  final still = WorkspaceDwell()..enter('left', nowMs: 0, delayMs: 150);
  check('对照：不动的那条按原时刻到点', still.isDue(settle + 150));

  // 没有待发项时 noteMotion 什么都不做（不该凭空造出一个计时目标）。
  final idle = WorkspaceDwell()..noteMotion(500);
  check('没在计时时 noteMotion 不造目标', !idle.isPending && !idle.isDue(99999));
}

/// **路过**不算驻留：指针在几条泳道之间移动、每一下都动，就谁都不该激活。
void _sweepNeverFires() {
  final dwell = WorkspaceDwell();
  dwell.enter('left', nowMs: 0, delayMs: 150);
  for (final t in [40, 80, 120]) {
    dwell.noteMotion(t);
    check('运动到 $t 时还没到点', !dwell.isDue(t));
    check('运动到 $t 时也没进入预备态', !dwell.isArmed(t));
  }
  dwell.leave('left'); // 从这条泳道走了
  check('走了之后彻底没有待发项', !dwell.isPending);
  check('走了之后到点也不发', dwell.takeDue(999999) == null);
}

/// 预备态（[WorkspaceDwell.isArmed]）的边界：**静够就算停住**，此时交互还没交出。
///
/// 它是界面上那道「已经看见我停在这儿了」的边框的唯一出处，所以既不能早于
/// 静置窗口（那样路过仍然会闪），也不能晚于到点（那样它就永远看不到）。
void _armedIsTheSettleBoundary() {
  const settle = WorkspaceDwell.settleMs;
  final dwell = WorkspaceDwell();
  dwell.enter('right', nowMs: 1000, delayMs: 150);

  check('刚进入还不算停住', !dwell.isArmed(1000));
  check('静置窗口差 1ms 仍不算', !dwell.isArmed(1000 + settle - 1));
  check('静够 settle 之后进入预备态', dwell.isArmed(1000 + settle));
  check('预备态时交互还没交出去', !dwell.isDue(1000 + settle));
  check('delay 走完才交出去', dwell.isDue(1000 + settle + 150));

  check('取走到点项之后不再处于预备态', dwell.takeDue(1000 + settle + 150) == 'right');
  check('发过之后 isArmed 归位', !dwell.isArmed(1000 + settle + 200));

  // 抑制期间既不发也不该亮预备态（否则弹层上还闪一道边框）。
  final blocked = WorkspaceDwell()..enter('right', nowMs: 0, delayMs: 150);
  blocked.setSuppressed(true);
  check('被抑制时不亮预备态', !blocked.isArmed(9999));
}

/// 延时小于等于 0 是非法值：按 1ms 处理，而不是「立刻」。
///
/// 区别在语义上：「立刻」意味着同一次事件里就触发（画面横跳），
/// 1ms 仍然过一次事件循环，用户扫过时不会误触发。
void _nonPositiveDelayBecomesOneMillisecond() {
  for (final delay in [0, -1, -1000]) {
    final dwell = WorkspaceDwell();
    dwell.enter('reader', nowMs: 0, delayMs: delay);
    const settle = WorkspaceDwell.settleMs;
    check('delay=$delay 时静置窗口里尚未到点', !dwell.isDue(settle));
    check('delay=$delay 时 settle+1ms 到点', dwell.isDue(settle + 1));
  }
}
