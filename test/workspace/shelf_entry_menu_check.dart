// 收藏 / 历史卡片右键菜单的**纯 Dart** 判据。
//
//   dart run test/workspace/shelf_entry_menu_check.dart
//
// 断言三件事，它们各自都曾经以「看起来没问题」的方式错过：
//
//   1. **菜单有哪些项** —— 收藏卡上不该出现给自己「收藏」，历史卡上必须有；
//   2. **哪一项是灰的** —— 不能点、但**必须在场**（隐藏等于让人以为没这功能）；
//   3. **这一项真的能落地吗** —— 「在文件管理新页签打开」靠的是把漫画 id
//      解析成磁盘目录，插件漫画没有目录。解析错了不会报错，只会打开一个
//      空目录或者根目录。
//
// 没有 package:test 依赖（跟 `board_layout_check.dart` 同一套路：这个外壳里
// `dart run` 稳，`flutter test` 要拖起整套 binding）。失败抛 StateError 并以
// 非零码退出。
//
// ignore_for_file: avoid_print

import 'package:zephyr/workspace/model/shelf_entry_menu_spec.dart';

int _passed = 0;

void check(String label, bool condition, [String? detail]) {
  if (!condition) {
    throw StateError('FAIL: $label${detail == null ? '' : ' — $detail'}');
  }
  _passed++;
}

ShelfEntryMenuItemSpec _item(
  List<ShelfEntryMenuItemSpec> items,
  ShelfEntryAction action,
) {
  final matched = items.where((item) => item.action == action).toList();
  if (matched.length != 1) {
    throw StateError('FAIL: ${action.name} 应恰好出现一次，实际 ${matched.length} 次');
  }
  return matched.first;
}

bool _has(List<ShelfEntryMenuItemSpec> items, ShelfEntryAction action) =>
    items.any((item) => item.action == action);

void main() {
  _alwaysPresent();
  _unavailableIsDisabledNotHidden();
  _kindDecidesActions();
  _onlyRemoveIsDestructive();
  _orderPutsDestructiveLast();
  _pathResolution();
  _linkResolution();
  _confirmKind();

  print('shelf_entry_menu_check: $_passed checks passed');
}

// ── 1. 必备项 ──────────────────────────────────────────────────────────────

void _alwaysPresent() {
  for (final kind in ShelfEntryKind.values) {
    final items = buildShelfEntryMenuItems(ShelfEntryMenuInput(kind: kind));
    for (final action in <ShelfEntryAction>[
      ShelfEntryAction.open,
      ShelfEntryAction.openInFileManagerTab,
      ShelfEntryAction.copyTitle,
      ShelfEntryAction.copyLink,
      ShelfEntryAction.remove,
    ]) {
      check('$kind 的菜单必须有 ${action.name}', _has(items, action));
    }
  }
}

// ── 2. 不可用的项：置灰、但在场 ────────────────────────────────────────────

void _unavailableIsDisabledNotHidden() {
  final blocked = buildShelfEntryMenuItems(
    const ShelfEntryMenuInput(
      kind: ShelfEntryKind.history,
      canOpenInFileManagerTab: false,
    ),
  );
  check(
    '没有本地目录时「在文件管理新页签打开」仍在场',
    _has(blocked, ShelfEntryAction.openInFileManagerTab),
  );
  check(
    '没有本地目录时它是灰的',
    !_item(blocked, ShelfEntryAction.openInFileManagerTab).enabled,
  );

  final allowed = buildShelfEntryMenuItems(
    const ShelfEntryMenuInput(
      kind: ShelfEntryKind.history,
      canOpenInFileManagerTab: true,
    ),
  );
  check(
    '有本地目录时它可以点',
    _item(allowed, ShelfEntryAction.openInFileManagerTab).enabled,
  );

  final cannotOpen = buildShelfEntryMenuItems(
    const ShelfEntryMenuInput(kind: ShelfEntryKind.history, canOpen: false),
  );
  check(
    'canOpen=false 时「打开」是灰的',
    !_item(cannotOpen, ShelfEntryAction.open).enabled,
  );
}

// ── 3. 条目类型决定动作集合 ────────────────────────────────────────────────

void _kindDecidesActions() {
  final favorite = buildShelfEntryMenuItems(
    const ShelfEntryMenuInput(kind: ShelfEntryKind.favorite),
  );
  check(
    '收藏卡上不出现「收藏 / 取消收藏」这一项',
    !_has(favorite, ShelfEntryAction.toggleFavorite),
  );

  final history = buildShelfEntryMenuItems(
    const ShelfEntryMenuInput(kind: ShelfEntryKind.history),
  );
  check('历史卡上必须有「收藏」', _item(history, ShelfEntryAction.toggleFavorite).enabled);
  check(
    '「收藏」不是破坏性动作',
    !_item(history, ShelfEntryAction.toggleFavorite).destructive,
  );

  final already = buildShelfEntryMenuItems(
    const ShelfEntryMenuInput(kind: ShelfEntryKind.history, isFavorite: true),
  );
  check(
    '已在收藏里时「收藏」置灰',
    !_item(already, ShelfEntryAction.toggleFavorite).enabled,
  );
}

// ── 4. 破坏性动作只该有一个 ────────────────────────────────────────────────

void _onlyRemoveIsDestructive() {
  for (final kind in ShelfEntryKind.values) {
    final items = buildShelfEntryMenuItems(ShelfEntryMenuInput(kind: kind));
    final destructive = items.where((item) => item.destructive).toList();
    check(
      '$kind 的菜单里破坏性项恰好只有「移除」',
      destructive.length == 1 &&
          destructive.single.action == ShelfEntryAction.remove,
      '${destructive.map((item) => item.action.name).toList()}',
    );
    check(
      '$kind 的「移除」可以点（灰掉的删除按钮等于功能不存在）',
      _item(items, ShelfEntryAction.remove).enabled,
    );
  }
}

// ── 5. 次序：破坏性永远在最后 ──────────────────────────────────────────────

void _orderPutsDestructiveLast() {
  for (final kind in ShelfEntryKind.values) {
    final items = buildShelfEntryMenuItems(ShelfEntryMenuInput(kind: kind));
    check('$kind 的「移除」排在最后', items.last.action == ShelfEntryAction.remove);
    final copyTitle = items.indexWhere(
      (item) => item.action == ShelfEntryAction.copyTitle,
    );
    check('$kind 的复制组在移除之前', copyTitle < items.length - 1);
    check(
      '$kind 的复制标题在复制链接之前',
      copyTitle <
          items.indexWhere((item) => item.action == ShelfEntryAction.copyLink),
    );
  }
}

// ── 6. 「新页签」落点解析 ──────────────────────────────────────────────────

void _pathResolution() {
  const cases = <String, String?>{
    // 归档：开它**所在目录**，不是归档文件本身。
    '/Users/glow/comics/a.cbz': '/Users/glow/comics',
    '/Users/glow/comics/a.zip': '/Users/glow/comics',
    '/Users/glow/comics/a.7z': '/Users/glow/comics',
    // 单张图：同上。
    '/Users/glow/pics/001.jpg': '/Users/glow/pics',
    // 目录：原样。
    '/Users/glow/comics/series': '/Users/glow/comics/series',
    // Windows 盘符：与 POSIX 同样处理。
    r'D:\library\a.cbz': r'D:\library',
    // 插件漫画 id：没有本地位置。
    'bika': null,
    '12345': null,
    // 网络地址不是磁盘路径。
    'https://cdn.example.com/a.cbz': null,
    // 空串不该爆炸。
    '   ': null,
  };
  cases.forEach((input, expected) {
    final actual = resolveFileManagerTabPath(input);
    check(
      'resolveFileManagerTabPath($input) == $expected',
      actual == expected,
      'actual: $actual',
    );
  });

  // 归档就在根目录：退到根目录是对的，但**绝不能把归档文件自己当目录**送进去
  // —— 那会打开一个不存在的位置，而且不报错。
  check(
    '根目录下的归档退到根目录，而不是它自己',
    resolveFileManagerTabPath('/a.cbz') == '/',
    'actual: ${resolveFileManagerTabPath('/a.cbz')}',
  );
  check('没有扩展名的相对路径不是磁盘位置', resolveFileManagerTabPath('comics/series') == null);
}

// ── 7. 复制链接的取值 ──────────────────────────────────────────────────────

void _linkResolution() {
  check(
    '本地漫画复制出来的是路径本身',
    resolveShelfEntryLink(
          source: 'local',
          comicId: '/Users/glow/comics/series',
        ) ==
        '/Users/glow/comics/series',
  );
  check(
    '插件漫画复制出来的是 来源:漫画id',
    resolveShelfEntryLink(source: 'bika', comicId: '12345') == 'bika:12345',
  );
  check(
    '来源为空时退化成漫画 id',
    resolveShelfEntryLink(source: '  ', comicId: ' 12345 ') == '12345',
  );
}

// ── 8. 二次确认问哪一句 ────────────────────────────────────────────────────

void _confirmKind() {
  for (final kind in ShelfEntryKind.values) {
    check(
      '$kind 的「移除」要二次确认',
      confirmKindFor(ShelfEntryAction.remove, kind) == kind,
    );
  }
  for (final action in ShelfEntryAction.values) {
    if (action == ShelfEntryAction.remove) continue;
    check(
      '${action.name} 不弹二次确认',
      confirmKindFor(action, ShelfEntryKind.favorite) == null,
    );
  }
}
