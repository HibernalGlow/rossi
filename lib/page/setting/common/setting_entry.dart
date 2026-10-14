import 'package:flutter/widgets.dart';
import 'package:scroll_spy/scroll_spy.dart';
import 'package:zephyr/page/setting/common/setting_group.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';

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

/// 给一行登记 id，同时将其挂入 `scroll_spy` 的 [ScrollSpyItem] 以支持滚动感知与锚点跳转。
Widget settingEntry(String id, Widget child) {
  return KeyedSubtree(
    key: SettingEntryKey(id),
    child: ScrollSpyItem<String>(id: id, child: child),
  );
}

/// 分组卡把若干行收进同一个列表下标里，所以按 id 找行要能穿进卡内。
List<Widget> _rowsOf(Widget child) => switch (child) {
  SettingSectionCard(:final children) => children,
  SettingGroup(:final children) => children,
  _ => const <Widget>[],
};

/// [children] 里已登记的 id，按渲染顺序（分组卡内同样计入）。
List<String> settingEntryIds(List<Widget> children) {
  final ids = <String>[];
  for (final child in children) {
    final key = child.key;
    if (key is SettingEntryKey) ids.add(key.id);
    ids.addAll(settingEntryIds(_rowsOf(child)));
  }
  return ids;
}

/// 这一项（或它所在的分组卡）在 [children] 里。
bool containsSettingEntry(Widget child, String id) {
  final key = child.key;
  if (key is SettingEntryKey && key.id == id) return true;
  return _rowsOf(child).any((row) => containsSettingEntry(row, id));
}

/// 这一页真正的行序列：分组卡拆成它内部的行，其余原样保留。
///
/// 「有没有行没登记 id」这类尺要数的是**行**，不是列表下标 —— 分组卡是一个下标，
/// 把它当一行看会同时漏掉卡里的行与卡本身。
List<Widget> flattenSettingEntries(List<Widget> children) {
  final rows = <Widget>[];
  for (final child in children) {
    final inner = _rowsOf(child);
    if (inner.isEmpty) {
      rows.add(child);
      continue;
    }
    rows.addAll(flattenSettingEntries(inner));
  }
  return rows;
}

/// id 在整份 [children] 里的位置，没登记则返回 -1。
///
/// 返回值是**整份列表**的下标（含未登记的装饰行），因为滚动定位数的就是它。
/// 行被收进分组卡时，返回的是那张卡的下标 —— 卡本身只是一个下标，
/// 卡里第几行由 `SettingEntryList` 在落到卡之后再挪进视口。
int indexOfSettingEntry(List<Widget> children, String id) {
  for (var i = 0; i < children.length; i++) {
    if (containsSettingEntry(children[i], id)) return i;
  }
  return -1;
}
