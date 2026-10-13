import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/navigation/navigation_shape.dart';
import 'package:zephyr/widgets/search/search_history_field.dart';
import 'package:zephyr/widgets/search/search_history_store.dart';

/// 书架内联搜索框。随工具栏展开直接挂载输入框，不等待浮层或路由动画。
class ShelfSearchField extends StatefulWidget {
  const ShelfSearchField({
    super.key,
    required this.query,
    this.historyScope = 'bookshelf',
    required this.focusNode,
    required this.hintText,
    required this.onChanged,
    required this.onSubmitted,
  });

  final String query;
  final String historyScope;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onChanged;
  final FutureOr<void> Function(String) onSubmitted;

  @override
  State<ShelfSearchField> createState() => _ShelfSearchFieldState();
}

class _ShelfSearchFieldState extends State<ShelfSearchField> {
  late final _controller = TextEditingController(text: widget.query);

  @override
  void didUpdateWidget(covariant ShelfSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query && _controller.text != widget.query) {
      _controller.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: AppShape.all(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 4),
        child: Row(
          children: [
            GlyphIcon(
              AppGlyphs.search,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SearchHistoryField(
                history: SearchHistoryStore.local(widget.historyScope),
                controller: _controller,
                focusNode: widget.focusNode,
                autofocus: true,
                minLines: 1,
                maxLines: 6,
                inputFormatters: [
                  FilteringTextInputFormatter.singleLineFormatter,
                ],
                onChanged: (value) {
                  setState(() {});
                  widget.onChanged(value);
                },
                // 默认 search 动作会先失焦；书架提交后继续输入。
                onSubmitted: (value) {
                  widget.onSubmitted(value.trim());
                  widget.focusNode.requestFocus();
                },
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            IconButton(
              tooltip: t.common.clear,
              onPressed: _controller.text.isEmpty
                  ? null
                  : () {
                      setState(_controller.clear);
                      widget.onChanged('');
                      widget.focusNode.requestFocus();
                    },
              icon: const GlyphIcon(AppGlyphs.close, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
