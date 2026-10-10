// 「在系统文件管理器里显示」那条命令的**纯 Dart** 判据。
//
//   dart run test/workspace/reveal_in_file_manager_check.dart
//
// 钉四件事，每一件都对应一种「在界面上看不出来」的错法：
//
//   1. **参数是数组，不是拼好的 shell 字符串** —— 文件名里本来就能有单引号、
//      反引号、`$`、分号；一旦拼成 `sh -c "open -R '$path'"`，用户的一个畸形
//      文件名就变成一次命令执行。这里断言 argv 里那个元素**逐字等于**原路径。
//   2. **Windows 必须是单个 `/select,<路径>` 参数** —— 拆成 `['/select,', path]`
//      两个参数资源管理器不认（那恰好是最顺手会写错的样子）。
//   3. **Linux 只能打开所在目录**，`selectsEntry` 必须为假，文案不许吹成「已选中」。
//   4. **三家的措辞互不相同** —— 同一条措辞盖住三种不同的实际行为就是骗人。
//
// 平台是按参数传进来的，所以本机（macOS）一份代码就能把三家分支全跑到。
//
// ignore_for_file: avoid_print

import 'package:zephyr/platform/desktop/reveal_in_file_manager.dart';

int _passed = 0;

void check(String label, bool condition, [String? detail]) {
  if (!condition) {
    throw StateError('FAIL: $label${detail == null ? '' : ' — $detail'}');
  }
  _passed++;
}

/// 一个「故意让 shell 拼接写法当场出事」的文件名。
const nasty = "/tmp/它 有'引号`和\$美元;分号/a b.txt";

void main() {
  _macosShape();
  _windowsShape();
  _linuxShape();
  _unsupportedAndEmpty();
  _argsAreVerbatimNotEscaped();
  _labelsDifferPerHost();

  print('reveal_in_file_manager_check: $_passed checks passed');
}

void _macosShape() {
  final command = buildRevealCommand(
    path: '/tmp/漫画/01.jpg',
    host: RevealHost.macos,
  )!;
  check('访达用 open', command.binary == 'open', command.binary);
  check(
    '访达是 -R（定位并选中），不是裸 open（那只会打开它自己）',
    command.args.first == '-R',
    '${command.args}',
  );
  check('访达这一档算「选中了」', command.selectsEntry);
}

void _windowsShape() {
  final command = buildRevealCommand(
    path: r'C:\漫画\第01话',
    host: RevealHost.windows,
  )!;
  check(
    '资源管理器用 explorer.exe',
    command.binary == 'explorer.exe',
    command.binary,
  );
  check(
    '必须是**一个**参数（拆成两个参数资源管理器不认）',
    command.args.length == 1,
    '${command.args}',
  );
  check(
    '形状是 /select,<完整路径>',
    command.args.single == r'/select,C:\漫画\第01话',
    command.args.single,
  );
  check('资源管理器这一档算「选中了」', command.selectsEntry);
}

void _linuxShape() {
  final command = buildRevealCommand(
    path: '/data/comics/01.cbz',
    host: RevealHost.linux,
  )!;
  check('Linux 用 xdg-open', command.binary == 'xdg-open', command.binary);
  check('只能给所在目录', command.args.single == '/data/comics', command.args.single);
  check(
    'Linux 那档必须承认自己选不中',
    !command.selectsEntry,
    'selectsEntry=true 会让文案吹成「已选中这一项」',
  );
}

void _unsupportedAndEmpty() {
  for (final host in RevealHost.values) {
    check(
      '${host.name} 拿到空白路径时不出命令',
      buildRevealCommand(path: '   ', host: host) == null,
    );
  }
  check(
    '不支持的平台不出命令',
    buildRevealCommand(path: '/tmp/a', host: RevealHost.unsupported) == null,
  );
}

/// 关键的一条：路径**逐字**进 argv，没被转义、拆分，也没落进一条 shell 命令里。
void _argsAreVerbatimNotEscaped() {
  for (final host in <RevealHost>[
    RevealHost.macos,
    RevealHost.windows,
    RevealHost.linux,
  ]) {
    final command = buildRevealCommand(path: nasty, host: host)!;
    check(
      '${host.name} 不经过 sh',
      command.binary != 'sh' && command.binary != 'bash',
      command.binary,
    );
    check('${host.name} 没有 -c 那种整串命令参数', !command.args.contains('-c'));
  }

  final mac = buildRevealCommand(path: nasty, host: RevealHost.macos)!;
  check('访达：argv 里就是原路径本身', mac.args.last == nasty, mac.args.last);

  final win = buildRevealCommand(path: nasty, host: RevealHost.windows)!;
  check(
    '资源管理器：只有 /select, 前缀是加的，其余逐字',
    win.args.single == '/select,$nasty',
    win.args.single,
  );

  final linux = buildRevealCommand(path: nasty, host: RevealHost.linux)!;
  check(
    'xdg-open：给的是父目录，且它是原路径的前缀',
    nasty.startsWith(linux.args.single) && linux.args.single != nasty,
    linux.args.single,
  );
}

void _labelsDifferPerHost() {
  final mac = revealMenuLabel(RevealHost.macos);
  final win = revealMenuLabel(RevealHost.windows);
  final lin = revealMenuLabel(RevealHost.linux);
  check(
    '三家措辞互不相同',
    mac != win && win != lin && mac != lin,
    '$mac / $win / $lin',
  );
  check('访达那一档说「访达」', mac.contains('访达'), mac);
  check('Windows 那一档说「资源管理器」', win.contains('资源管理器'), win);
  check('Linux 那一档说清是「所在目录」', lin.contains('目录'), lin);

  final outcome = revealOutcome(
    host: RevealHost.linux,
    path: '/data/comics/01.cbz',
  );
  check(
    'Linux 的结果文案不许声称选中了文件',
    !outcome.contains('已选中') && outcome.contains('所在的目录'),
    outcome,
  );
}
