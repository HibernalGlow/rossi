// 文件管理器条目右键菜单的**纯 Dart** 判据。
//
//   dart run test/workspace/file_manager_entry_menu_check.dart
//
// 断言五件事，它们各自都曾经以「看起来没问题」的方式错过：
//
//   1. **菜单有哪些项** —— 十一个动作一个都不能少（用户要求「这几个操作都在右键里」）；
//   2. **哪一项是灰的、但必须在场** —— 多选时「重命名」没有定义，可它不能消失；
//   3. **危险组的位置** —— 破坏性动作必须在最后，且「永久删除」在「回收站」之后；
//   4. **确认只给不可撤销的那一个** —— 回收站的保护是撤销通道，不是确认框；
//   5. **二次确认问哪一句** —— 「可以撤销」与「删了就没了」必须问得不一样。
//
// 没有 package:test 依赖（跟 `shelf_entry_menu_check.dart` 同一套路：这个外壳里
// `dart run` 稳，`flutter test` 要拖起整套 binding）。失败抛 StateError 并以非零码退出。
//
// ignore_for_file: avoid_print

import 'package:zephyr/workspace/model/file_manager_entry_menu_spec.dart';

int _passed = 0;

void check(String label, bool condition, [String? detail]) {
  if (!condition) {
    throw StateError('FAIL: $label${detail == null ? '' : ' — $detail'}');
  }
  _passed++;
}

FileManagerEntryMenuItemSpec _item(
  List<FileManagerEntryMenuItemSpec> items,
  FileManagerEntryAction action,
) {
  final matched = items.where((item) => item.action == action).toList();
  if (matched.length != 1) {
    throw StateError('FAIL: ${action.name} 应恰好出现一次，实际 ${matched.length} 次');
  }
  return matched.first;
}

FileManagerEntryMenuInput _input({
  bool isDirectory = false,
  int selectionCount = 0,
  bool inSelection = false,
  bool canOpen = true,
  bool canCreateFolder = true,
  bool canPaste = false,
  bool trashRestoreSupported = false,
  bool canReveal = false,
}) => FileManagerEntryMenuInput(
  isDirectory: isDirectory,
  selectionCount: selectionCount,
  inSelection: inSelection,
  canOpen: canOpen,
  canCreateFolder: canCreateFolder,
  canPaste: canPaste,
  trashRestoreSupported: trashRestoreSupported,
  canReveal: canReveal,
);

void main() {
  _everyActionIsPresent();
  _revealNeedsADesktopHost();
  _batchGreysOutWhatHasNoMeaning();
  _pasteRequiresADirectory();
  _dangerousGroupIsLast();
  _exactlyOneNeedsConfirmation();
  _confirmationMatchesNeoviewDefaults();
  _deletePromptValues();
  _trashOutcomeHint();
  _tapGesturePrecedence();
  _menuTargetsOneWithoutTouchingSelection();

  print('file_manager_entry_menu_check: $_passed checks passed');
}

// ── 1. 十个动作一个都不能少 ────────────────────────────────────────────────

void _everyActionIsPresent() {
  for (final input in <FileManagerEntryMenuInput>[
    _input(),
    _input(isDirectory: true, canPaste: true),
    _input(selectionCount: 3, inSelection: true),
    _input(
      isDirectory: true,
      selectionCount: 3,
      inSelection: true,
      canPaste: true,
    ),
    _input(canOpen: false, canCreateFolder: false),
    _input(isDirectory: true, canReveal: true),
  ]) {
    final items = buildFileManagerEntryMenuItems(input);
    for (final action in FileManagerEntryAction.values) {
      check('每一种局面下都必须有 ${action.name}', items.any((i) => i.action == action));
    }
    check(
      '菜单里不出现重复项',
      items.map((i) => i.action).toSet().length == items.length,
    );
  }
}

// ── 1b. 「在系统文件管理器里显示」：只有桌面能点，移动端在场但灰 ────────────

void _revealNeedsADesktopHost() {
  final desktop = buildFileManagerEntryMenuItems(
    _input(isDirectory: false, canReveal: true),
  );
  final mobile = buildFileManagerEntryMenuItems(_input(isDirectory: false));

  check(
    '桌面宿主上这一项可以点（右键一个文件也该够得着）',
    _item(desktop, FileManagerEntryAction.revealInFileManager).enabled,
  );
  check(
    '这个平台做不到时它仍在场',
    mobile.any((item) => item.action == FileManagerEntryAction.revealInFileManager),
    '隐藏等于让人以为没这功能',
  );
  check(
    '这个平台做不到时它是灰的',
    !_item(mobile, FileManagerEntryAction.revealInFileManager).enabled,
  );
  check(
    '显示这一项不弹二次确认（它不动盘）',
    !requiresConfirmation(FileManagerEntryAction.revealInFileManager),
  );

  final order = desktop.map((item) => item.action).toList();
  check(
    '它排在「打开」那一组里、危险组之前',
    order.indexOf(FileManagerEntryAction.open) <
        order.indexOf(FileManagerEntryAction.revealInFileManager),
    '$order',
  );
  check(
    '它在回收站之前',
    order.indexOf(FileManagerEntryAction.revealInFileManager) <
        order.indexOf(FileManagerEntryAction.trash),
    '$order',
  );
}

// ── 2. 多选：没有定义的动作置灰、但在场 ────────────────────────────────────

void _batchGreysOutWhatHasNoMeaning() {
  // 单选那一侧必须把 canPaste 打开，否则「粘贴可点」这条断言测的是剪贴板为空的情形。
  final single = buildFileManagerEntryMenuItems(
    _input(isDirectory: true, canPaste: true, canReveal: true),
  );
  final batch = buildFileManagerEntryMenuItems(
    _input(
      isDirectory: true,
      selectionCount: 3,
      inSelection: true,
      canPaste: true,
      canReveal: true,
    ),
  );

  for (final action in <FileManagerEntryAction>[
    FileManagerEntryAction.open,
    FileManagerEntryAction.openInNewTab,
    FileManagerEntryAction.revealInFileManager,
    FileManagerEntryAction.rename,
    FileManagerEntryAction.createFolder,
    FileManagerEntryAction.paste,
  ]) {
    check(
      '单选时 ${action.name} 可以点',
      _item(single, action).enabled,
      '${_item(single, action)}',
    );
    check(
      '多选时 ${action.name} 仍在场',
      batch.any((i) => i.action == action),
      '隐藏等于让人以为没这功能',
    );
    check('多选时 ${action.name} 置灰', !_item(batch, action).enabled);
  }

  // 批量动作在多选时必须可用 —— 否则「多选」这个模式就没有出口。
  for (final action in <FileManagerEntryAction>[
    FileManagerEntryAction.copy,
    FileManagerEntryAction.cut,
    FileManagerEntryAction.copyPath,
    FileManagerEntryAction.trash,
    FileManagerEntryAction.deletePermanently,
  ]) {
    check('多选时 ${action.name} 可以点', _item(batch, action).enabled);
  }

  // 右键的那一项**不在**选中集合里 ⇒ 菜单是对「这一个」的，不是对整批。
  final outside = buildFileManagerEntryMenuItems(
    _input(isDirectory: true, selectionCount: 3, inSelection: false),
  );
  check(
    '在选中集合外右键时按单选处理',
    _item(outside, FileManagerEntryAction.rename).enabled,
  );
  check('在选中集合外右键时「打开」可用', _item(outside, FileManagerEntryAction.open).enabled);
}

// ── 3. 粘贴只落在目录上 ────────────────────────────────────────────────────

void _pasteRequiresADirectory() {
  check(
    '剪贴板为空时「粘贴」置灰',
    !_item(
      buildFileManagerEntryMenuItems(_input(isDirectory: true)),
      FileManagerEntryAction.paste,
    ).enabled,
  );
  check(
    '剪贴板非空 + 目标是目录时「粘贴」可用',
    _item(
      buildFileManagerEntryMenuItems(_input(isDirectory: true, canPaste: true)),
      FileManagerEntryAction.paste,
    ).enabled,
  );
  check(
    '剪贴板非空但目标是文件时「粘贴」置灰',
    !_item(
      buildFileManagerEntryMenuItems(_input(canPaste: true)),
      FileManagerEntryAction.paste,
    ).enabled,
  );

  // 只读目录里不能新建文件夹，但这一项仍在场。
  final readOnly = buildFileManagerEntryMenuItems(
    _input(isDirectory: true, canCreateFolder: false),
  );
  check(
    '只读目录里「新建文件夹」仍在场',
    readOnly.any((i) => i.action == FileManagerEntryAction.createFolder),
  );
  check(
    '只读目录里「新建文件夹」置灰',
    !_item(readOnly, FileManagerEntryAction.createFolder).enabled,
  );

  check(
    '打不开的文件「打开」置灰但仍在场',
    !_item(
      buildFileManagerEntryMenuItems(_input(canOpen: false)),
      FileManagerEntryAction.open,
    ).enabled,
  );
}

// ── 4. 危险组的位置 ────────────────────────────────────────────────────────

void _dangerousGroupIsLast() {
  for (final input in <FileManagerEntryMenuInput>[
    _input(),
    _input(isDirectory: true, canPaste: true),
    _input(selectionCount: 5, inSelection: true),
  ]) {
    final items = buildFileManagerEntryMenuItems(input);
    final dangerous = items.where((item) => item.dangerous).toList();
    check(
      '危险项恰好是「回收站 + 永久删除」两个',
      dangerous.length == 2 &&
          dangerous.first.action == FileManagerEntryAction.trash &&
          dangerous.last.action == FileManagerEntryAction.deletePermanently,
      '${dangerous.map((i) => i.action.name).toList()}',
    );
    check(
      '永久删除排在最后',
      items.last.action == FileManagerEntryAction.deletePermanently,
    );
    check(
      '回收站紧挨在永久删除之前',
      items[items.length - 2].action == FileManagerEntryAction.trash,
    );
    // 「复制路径」这类无害动作不许混进危险组后面 —— 那会让它被误当成安全的。
    check(
      '危险组之后没有别的项',
      items
          .skipWhile((item) => !item.dangerous)
          .every((item) => item.dangerous),
    );
  }
}

// ── 5. 确认只给不可撤销的那一个 ────────────────────────────────────────────

void _exactlyOneNeedsConfirmation() {
  final items = buildFileManagerEntryMenuItems(
    _input(
      isDirectory: true,
      selectionCount: 2,
      inSelection: true,
      canPaste: true,
    ),
  );
  final destructive = items.where((item) => item.destructive).toList();
  check(
    '需要二次确认的恰好只有「永久删除」',
    destructive.length == 1 &&
        destructive.single.action == FileManagerEntryAction.deletePermanently,
    '${destructive.map((i) => i.action.name).toList()}',
  );

  // 不变式：要确认的动作必须同时是危险色（否则「点下去才知道是删」）。
  for (final item in items) {
    check(
      '${item.action.name} 的 destructive 蕴含 dangerous',
      !item.destructive || item.dangerous,
      '$item',
    );
  }

  // 回收站**不是**靠确认保护的：它的保护是撤销通道。
  check('「移到回收站」不弹确认', !_item(items, FileManagerEntryAction.trash).destructive);
  check('「移到回收站」仍然是危险色', _item(items, FileManagerEntryAction.trash).dangerous);
}

// ── 6. 与 neoview 的默认确认配置一致 ───────────────────────────────────────

void _confirmationMatchesNeoviewDefaults() {
  // neo: ReaderFolderConfirmationConfig{trash:false, permanentDelete:true,
  //      batchTrash:false, batchPermanentDelete:true}
  for (final count in <int>[1, 7]) {
    check(
      'requiresConfirmation(trash) 恒为 false（count=$count）',
      !requiresConfirmation(FileManagerEntryAction.trash),
    );
    check(
      'requiresConfirmation(deletePermanently) 恒为 true（count=$count）',
      requiresConfirmation(FileManagerEntryAction.deletePermanently),
    );
  }
  for (final action in FileManagerEntryAction.values) {
    if (action == FileManagerEntryAction.deletePermanently) continue;
    check('${action.name} 不弹确认', !requiresConfirmation(action));
  }
}

// ── 7. 二次确认问哪一句 ────────────────────────────────────────────────────

void _deletePromptValues() {
  final cases = <FileManagerEntryAction, FileManagerDeletePrompt?>{
    FileManagerEntryAction.trash: FileManagerDeletePrompt.trash(
      count: 3,
      restoreSupported: true,
    ),
    FileManagerEntryAction.deletePermanently: FileManagerDeletePrompt.permanent(
      count: 3,
    ),
    FileManagerEntryAction.rename: null,
    FileManagerEntryAction.copy: null,
    FileManagerEntryAction.cut: null,
    FileManagerEntryAction.paste: null,
    FileManagerEntryAction.copyPath: null,
    FileManagerEntryAction.open: null,
    FileManagerEntryAction.openInNewTab: null,
    FileManagerEntryAction.revealInFileManager: null,
    FileManagerEntryAction.createFolder: null,
  };
  cases.forEach((action, expected) {
    final actual = deletePromptFor(action, count: 3, restoreSupported: true);
    check(
      'deletePromptFor(${action.name}) == $expected',
      actual == expected,
      'actual: $actual',
    );
  });

  // 同一个动作、不同的平台能力，问出来的话必须不一样 —— 否则用户在 macOS 上
  // 会以为还能撤销。
  final macTrash = deletePromptFor(
    FileManagerEntryAction.trash,
    count: 1,
    restoreSupported: false,
  );
  final winTrash = deletePromptFor(
    FileManagerEntryAction.trash,
    count: 1,
    restoreSupported: true,
  );
  check('macOS 与 Windows 的回收站提示不相同', macTrash != winTrash);
  check('macOS 的回收站提示标为不可撤销', macTrash!.restoreSupported == false);
  check(
    '永久删除的提示与回收站不同',
    macTrash !=
        deletePromptFor(
          FileManagerEntryAction.deletePermanently,
          count: 1,
          restoreSupported: false,
        ),
  );
}

// ── 8. 「能不能撤销」只有一个判断入口 ──────────────────────────────────────

void _trashOutcomeHint() {
  check('支持撤销时文案说可以撤销', trashOutcomeHint(restoreSupported: true) == '可以撤销');
  check('不支持撤销时文案说无法撤销', trashOutcomeHint(restoreSupported: false) == '无法撤销');
  check('单选主语是「这一项」', selectionSubject(1) == '这一项');
  check('多选主语带条数', selectionSubject(3) == '这 3 项');
}

// ── 9. 单击的三种含义与它们的优先级 ────────────────────────────────────────

FileManagerEntryTapGesture _tap({
  bool ctrl = false,
  bool shift = false,
  bool mode = false,
}) => resolveFileManagerEntryTapGesture(
  toggleModifier: ctrl,
  extendModifier: shift,
  selectionMode: mode,
);

void _tapGesturePrecedence() {
  // 四个按键组合一个不落 —— 少一个就会出现「某种按键组合点上去没反应」。
  check(
    '什么都不按、也不在多选模式 = 打开',
    _tap() == FileManagerEntryTapGesture.open,
  );
  check(
    '按修饰键 = 切换选中',
    _tap(ctrl: true) == FileManagerEntryTapGesture.toggle,
  );
  check(
    '按 Shift = 连选',
    _tap(shift: true) == FileManagerEntryTapGesture.extend,
  );
  // 「两个键一起按听谁的」必须钉住。连选需要一个起点，而切换会把起点改掉，
  // 所以连选优先 —— 反过来会让 Shift 变成「把锚点挪到这一项」。
  check(
    'Ctrl 与 Shift 同时按，连选优先',
    _tap(ctrl: true, shift: true) == FileManagerEntryTapGesture.extend,
  );

  // 这两格是用户报的那个 bug 的两面：「长按把选中态立起来了，点第二下却进了文件夹」。
  // 模式位本身由界面层算（`_selectionModeOn` = 摁下了开关 **或** 手里正拿着东西），
  // 所以「空着集合进模式、点第一下」在这里就是 mode:true —— 它必须算加选。
  check(
    '多选模式内 + 直点 = 切换选中（点得上第二项，不分设备）',
    _tap(mode: true) == FileManagerEntryTapGesture.toggle,
  );
  check(
    '不在模式内 + 直点 = 打开（第一下仍然进得去文件夹）',
    _tap() == FileManagerEntryTapGesture.open,
  );
  // 新规则不能反过来把修饰键盖掉：按住 Shift 要的仍然是**范围**。
  check(
    '模式内 + Shift = 连选优先',
    _tap(shift: true, mode: true) == FileManagerEntryTapGesture.extend,
  );
  check(
    '模式内 + Ctrl = 切换选中',
    _tap(ctrl: true, mode: true) == FileManagerEntryTapGesture.toggle,
  );

  // 穷举 8 格（4 个按键组合 ×「在不在模式里」）。三档的计数各自钉死，
  // 加起来必须正好 8 —— 说明没有任何一格「点了没反应」；
  // `open` 只剩 1 格：退出模式是「摁回那颗开关 / 操作条的取消选择」，
  // 不靠双击（`canDoubleTap` 仍然只对压缩包为真）。
  final tally = <FileManagerEntryTapGesture, List<String>>{};
  for (final ctrl in [false, true]) {
    for (final shift in [false, true]) {
      for (final mode in [false, true]) {
        final gesture = _tap(ctrl: ctrl, shift: shift, mode: mode);
        (tally[gesture] ??= []).add('$ctrl/$shift/$mode: $gesture');
      }
    }
  }
  final opens = tally[FileManagerEntryTapGesture.open] ?? const [];
  final toggles = tally[FileManagerEntryTapGesture.toggle] ?? const [];
  final extends_ = tally[FileManagerEntryTapGesture.extend] ?? const [];
  check(
    '只有「不按键且不在模式里」这一格才打开',
    opens.length == 1 && opens.single.contains('false/false/false'),
    'actual: $opens',
  );
  check(
    '切换选中恰好 3 格',
    toggles.length == 3,
    'actual ${toggles.length}: $toggles',
  );
  check(
    '连选恰好 4 格（按 Shift 的全部）',
    extends_.length == 4,
    'actual ${extends_.length}: $extends_',
  );
  check(
    '8 格全部有归属',
    opens.length + toggles.length + extends_.length == 8,
    'open=${opens.length} toggle=${toggles.length} extend=${extends_.length}',
  );
}

// ── 10. 右键不动选中集合：目标口径只由 effectiveCount 算 ────────────────────

void _menuTargetsOneWithoutTouchingSelection() {
  // 「在选中集合里右键 = 对整批，在集合外右键 = 对这一个」这条规则取自 neoview，
  // 它以前是**先收敛选中态**再弹菜单来实现的 —— 于是右键一个没选中的文件会顺手
  // 把那一行画成选中、操作条跟着出现。现在它只算数、不改状态：
  // 下面三条缺任何一条，要么整批操作缩成一项，要么右键变成选中。
  check(
    '右键没选中的项（别处已经选了 3 项）→ 只作用这一个',
    _input(selectionCount: 3, inSelection: false).effectiveCount == 1,
  );
  check(
    '右键已选中的项 → 作用整批（不能被算成 1）',
    _input(selectionCount: 3, inSelection: true).effectiveCount == 3,
  );
  // 阳性对照：一个都没选、也不在集合里，计数必须是 1 而不是 0 ——
  // 0 会让「对这一个」的动作变成「对空集合」。
  check('空集合 + 集合外 → 仍然算 1 项', _input().effectiveCount == 1);
  check(
    '集合外那一项不该被当成批量（批量会把打开/重命名灰掉）',
    !_input(selectionCount: 3, inSelection: false).batch &&
        _input(selectionCount: 3, inSelection: true).batch,
  );
}
