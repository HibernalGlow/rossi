import 'package:flutter/widgets.dart';

/// 设置行的稳定身份。行没有 id 时，「跳到某一项」只能靠人肉数第几行 ——
/// 而条件行（`if (isDesktop)`）一改，位置就漂了。
///
/// 用独立的 key 类型而不是裸 [ValueKey]：本仓已有几处把 `ValueKey` 当 widget
/// 身份用的写法（如 `input_bindings_editor.dart` 的 `ValueKey('action:…')`），
/// 只认这个类型才不会把它们误当成可定位的设置项。
@immutable
class SettingEntryKey extends ValueKey<String> {
  const SettingEntryKey(super.value);

  String get id => value;
}

/// 给一行登记 id，并原样渲染它。
Widget settingEntry(String id, Widget child) {
  return KeyedSubtree(key: SettingEntryKey(id), child: child);
}

/// [children] 里已登记的 id，按渲染顺序。
List<String> settingEntryIds(List<Widget> children) {
  final ids = <String>[];
  for (final child in children) {
    final key = child.key;
    if (key is SettingEntryKey) ids.add(key.id);
  }
  return ids;
}

/// id 在整份 [children] 里的位置，没登记则返回 -1。
///
/// 返回值是**整份列表**的下标（含未登记的装饰行），因为滚动定位数的就是它。
int indexOfSettingEntry(List<Widget> children, String id) {
  for (var i = 0; i < children.length; i++) {
    final key = children[i].key;
    if (key is SettingEntryKey && key.id == id) return i;
  }
  return -1;
}
