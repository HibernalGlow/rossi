// 「切换提示」模板引擎 —— neoview
// `packages/nodes/neoview/src/application/switch-toast/ReaderSwitchToast.ts` 里
// `renderReaderSwitchToastTemplate` 的 Dart 翻译（T3 契约重建，非原文搬）。
//
// 逐条对照的语义：
// - `{{ path }}`（两侧可含空白）只解析 `book.` / `page.` 两种根；其它原样保留；
// - 未识别 / 取值为 null → 渲染成空串（不残留 `{{...}}`）；
// - 取值是对象 → JSON 序列化；其余 → 字符串化；
// - 空模板 → 空串。

import 'dart:convert';

/// 一次模板渲染能看到的全部上下文（两张扁平变量表）。
///
/// 上游按 `book` / `page` 两个对象逐段走属性；Rossi 的变量表是固定的两层
/// （`book.x` / `page.x`），用 `Map<String, Object?>` 等价承载。
/// `page` 为 `null` 表示当前没有页上下文（上游同款：整页取不到值 → 空串）。
class SwitchToastContext {
  const SwitchToastContext({required this.book, this.page});

  final Map<String, Object?>? book;
  final Map<String, Object?>? page;

  static const SwitchToastContext empty = SwitchToastContext(book: null);
}

final RegExp _placeholderPattern = RegExp(r'{{\s*([^}]+?)\s*}}');

String renderSwitchToastTemplate(String template, SwitchToastContext context) {
  if (template.isEmpty) return '';
  return template.replaceAllMapped(_placeholderPattern, (match) {
    final path = match.group(1) ?? '';
    if (!path.startsWith('book.') && !path.startsWith('page.')) {
      return match.group(0)!;
    }
    final segments = path.split('.');
    Object? value =
        switch (segments.first) {
          'book' => context.book,
          'page' => context.page,
          _ => null,
        };
    for (final segment in segments.skip(1)) {
      if (value is! Map) {
        value = null;
        break;
      }
      value = value[segment];
    }
    if (value == null) return '';
    if (value is Map || value is List) return _jsonStringify(value);
    return '$value';
  });
}

String _jsonStringify(Object value) {
  try {
    // 与上游 JSON.stringify 对齐的兜底：变量表里今天不会出现对象，
    // 但契约要求「对象不炸渲染、也不输出 [object Object]」。
    final encoded = jsonEncode(value);
    return encoded;
  } catch (_) {
    return '';
  }
}
