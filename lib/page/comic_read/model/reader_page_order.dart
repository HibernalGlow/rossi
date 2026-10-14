/// 章节内页面显示顺序（页面排序）的纯逻辑。
///
/// 只做「源下标 → 显示位置」这一个映射，不碰状态、不碰 Widget：
/// 显示顺序是一层**间接**（口径照 mImageViewer 的 `display_order: &[usize]`），
/// 每一页仍然带着自己的 `chapterPageIndex`（源下标），所以尺寸缓存、
/// 历史记录、预取、按页撤销的 OCR 覆盖层都不必知道排序的存在。
/// 反过来，直接按「显示位置」重写 docs 列表的做法会让这些下游全部串位。
library;

/// 页面排序档位。
enum ReaderPageOrderMode {
  /// 图源给的顺序（插件/归档条目原样）。改造前的行为。
  source,

  /// 倒序：章节内页表整个反过来。
  reverse,

  /// 按文件名自然序：数字段按数值比，于是 `page2 < page10`。
  ///
  /// 图源把 `1.jpg 10.jpg 2.jpg` 这种码位序带进来时靠这一档纠正。
  natural,

  /// 手动顺序：用户在页面选择器里拖出来的那一份排列。
  custom,
}

/// 自然序排序键的一段：要么是数值，要么是去掉符号后的文本。
sealed class ReaderNaturalChunk {
  const ReaderNaturalChunk();
}

final class ReaderNaturalNum extends ReaderNaturalChunk {
  const ReaderNaturalNum(this.value);
  final int value;
}

final class ReaderNaturalText extends ReaderNaturalChunk {
  ReaderNaturalText(this.text);
  final String text;
}

/// 把文件名切成自然序键。
///
/// 逐条对齐 `vendor/mimageviewer/src/ui_helpers.rs` 的 `natural_sort_key`
/// （本仓 `rust/local_core/src/ui_helpers.rs` 用的是同一份函数体）：
/// 先转小写；连续数字当**一个数值**（溢出即饱和）；文本段丢掉非字母数字，
/// 全空则该段不产出 —— 于是 `#1.jpg` 与 `1.jpg` 的键相同，
/// 平局交给调用方按源下标定序。全角数字（`０-９`）也算数字。
///
/// 上游的枚举把 `Text` 排在 `Num` 前面，`local_core` 有意保留了 `Num` 在前
/// （见那份文件里的「Rossi 保留数字块先于文本块」注释），这里跟 `local_core` 一致。
List<ReaderNaturalChunk> readerNaturalSortKey(String name) {
  final lower = name.toLowerCase();
  final chunks = <ReaderNaturalChunk>[];
  var i = 0;
  while (i < lower.length) {
    final digit = _digitValue(lower[i]);
    if (digit != null) {
      var value = 0;
      while (i < lower.length) {
        final next = _digitValue(lower[i]);
        if (next == null) break;
        value = value > _maxDigitSafe ? _saturatedValue : value * 10 + next;
        i++;
      }
      chunks.add(ReaderNaturalNum(value));
      continue;
    }
    final buffer = StringBuffer();
    while (i < lower.length) {
      if (_digitValue(lower[i]) != null) break;
      final ch = lower[i];
      if (_isAlphanumeric(ch)) buffer.write(ch);
      i++;
    }
    if (buffer.isNotEmpty) chunks.add(ReaderNaturalText(buffer.toString()));
  }
  return chunks;
}

const int _maxDigitSafe = 922337203685477580;
final int _saturatedValue = 0x7fffffffffffffff;

int? _digitValue(String ch) {
  final code = ch.codeUnitAt(0);
  if (code >= 0x30 && code <= 0x39) return code - 0x30;
  // 全角数字 ０-９
  if (code >= 0xff10 && code <= 0xff19) return code - 0xff10;
  return null;
}

bool _isAlphanumeric(String ch) {
  final code = ch.codeUnitAt(0);
  if (code >= 0x30 && code <= 0x39) return true;
  if (code >= 0x41 && code <= 0x5a) return true;
  if (code >= 0x61 && code <= 0x7a) return true;
  // 非 ASCII 一律按「是不是空白/标点」反判：只有字母与数字（含 CJK）留下，
  // 与 Rust 侧 `char::is_alphanumeric` 同一口径。
  return !_isSeparatorOrSymbol(code);
}

bool _isSeparatorOrSymbol(int code) {
  if (code <= 0x20) return true; // C0 控制符与空格
  if (code >= 0x21 && code <= 0x2f)
    return true; // ! " # $ % & ' ( ) * + , - . /
  if (code >= 0x3a && code <= 0x40) return true; // : ; < = > ? @
  if (code >= 0x5b && code <= 0x60) return true; // [ \ ] ^ _ `
  if (code >= 0x7b && code <= 0x7e) return true; // { | } ~
  if (code == 0xa0 || code == 0x3000) return true; // 不换行空格 / 全角空格
  return code >= 0x2000 && code <= 0x206f; // Unicode 分隔符区
}

/// 比较两个自然序键；返回负数表示 [a] 在前。
int compareReaderNaturalKeys(
  List<ReaderNaturalChunk> a,
  List<ReaderNaturalChunk> b,
) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final left = a[i];
    final right = b[i];
    if (left is ReaderNaturalNum && right is ReaderNaturalNum) {
      final c = left.value.compareTo(right.value);
      if (c != 0) return c;
      continue;
    }
    if (left is ReaderNaturalText && right is ReaderNaturalText) {
      final c = left.text.compareTo(right.text);
      if (c != 0) return c;
      continue;
    }
    // 类型不同：数字块在前（与 local_core 的枚举顺序一致）。
    return left is ReaderNaturalNum ? -1 : 1;
  }
  return a.length.compareTo(b.length);
}

/// 原样顺序：`[0, 1, …, pageCount - 1]`。
List<int> readerSourceOrder(int pageCount) =>
    List<int>.generate(pageCount, (index) => index, growable: false);

/// 把 `[0..pageCount)` 排成 `order[position] = 源下标` 的形式。
///
/// 空数组或页数不一致时返回 `null`，由调用方退回原样顺序 ——
/// 云端同步来的、或上一个会话留下的排列都可能对不上新的页数。
List<int>? normalizeReaderPageOrder(List<int>? order, int pageCount) {
  if (order == null || order.length != pageCount || pageCount <= 0) {
    return null;
  }
  final seen = <int>{};
  for (final index in order) {
    if (index < 0 || index >= pageCount || !seen.add(index)) return null;
  }
  return List<int>.unmodifiable(order);
}

/// 自然序：返回「显示位置 → 源下标」的排列。
///
/// 平局（同一自然键，例如 `1.jpg` 与 `#1.jpg`）按源下标定序，
/// 于是这一档在任何一次重排里都稳定，翻页时不会出现同一页反复换位。
List<int> readerNaturalOrder(List<String> names) {
  final order = List<int>.generate(names.length, (index) => index);
  final keys = names.map(readerNaturalSortKey).toList(growable: false);
  order.sort((a, b) {
    final c = compareReaderNaturalKeys(keys[a], keys[b]);
    return c != 0 ? c : a.compareTo(b);
  });
  return List<int>.unmodifiable(order);
}

/// 某个源下标在当前排列里的显示位置；不在表内时返回 `null`。
///
/// 排序档位变了之后要把「正在看的那一页」对齐回去，用的就是这一条。
int? readerPositionOfSource(List<int> order, int sourceIndex) {
  final index = order.indexOf(sourceIndex);
  return index < 0 ? null : index;
}

/// 在 [order] 上做一次「把位置 [oldIndex] 的内容搬到 [newIndex]」。
///
/// 与 `ReorderableListView` 的语义一致：先移除再插入，所以往下拖时
/// [newIndex] 会比最终位置大 1，这里按同一套规则处理，调用方直接把
/// `onReorder` 的两个参数传进来即可。
List<int> readerMoveInOrder(List<int> order, int oldIndex, int newIndex) {
  final next = List<int>.of(order);
  final moved = next.removeAt(oldIndex);
  final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
  next.insert(target.clamp(0, next.length), moved);
  return List<int>.unmodifiable(next);
}

/// 手动排列的初始值：当前显示顺序被「固化」成可编辑的起点。
List<int> readerCustomOrderFrom(
  List<int> currentOrder, {
  ReaderPageOrderMode? seedMode,
  List<String> names = const <String>[],
}) {
  switch (seedMode) {
    case ReaderPageOrderMode.reverse:
      return List<int>.unmodifiable(
        currentOrder.reversed.toList(growable: false),
      );
    case ReaderPageOrderMode.natural:
      return readerNaturalOrder(names);
    case ReaderPageOrderMode.source:
    case ReaderPageOrderMode.custom:
    case null:
      return List<int>.unmodifiable(currentOrder);
  }
}
