import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/search/search_history_field.dart';
import 'package:zephyr/widgets/search/search_history_store.dart';

/// 保留 Material SearchBar 的外观与实时筛选，历史交给官方 Autocomplete。
class BindingSearchField extends StatelessWidget {
  const BindingSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.trailing,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final List<Widget> trailing;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SearchHistoryAutocomplete(
    history: SearchHistoryStore.local('input-bindings'),
    controller: controller,
    onChanged: onChanged,
    fieldBuilder:
        (context, controller, focus, changed, submitted, historyButton) =>
            SearchBar(
              controller: controller,
              focusNode: focus,
              hintText: hintText,
              leading: const GlyphIcon(AppGlyphs.search),
              elevation: const WidgetStatePropertyAll(0),
              backgroundColor: WidgetStatePropertyAll(
                Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              trailing: [historyButton, ...trailing],
              onChanged: changed,
              onSubmitted: submitted,
            ),
  );
}
