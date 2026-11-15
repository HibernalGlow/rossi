import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_list/scene_filter/plugin_list_filter_schema.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';

/// 筛选面板里的下拉选择，复用设置页同款 [FluentDropdown]。
///
/// 选项树会按层级展开成缩进列表：children 直接渲染在父项下方，
/// 父项本身也可选。这样长列表、自动定位、滚动关闭、Fluent UI 选中条
/// 都复用同一套实现。
class PluginChoiceDropdown extends StatelessWidget {
  const PluginChoiceDropdown({
    super.key,
    required this.field,
    required this.selectedValue,
    required this.onSelected,
  });

  final PluginChoiceField field;
  final String selectedValue;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = field.findOptionByValue(selectedValue);

    return FluentDropdown<String>(
      value: selectedValue,
      displayValue: selected?.label ?? field.label,
      items: _flattenOptions(field.options),
      onChanged: (value) {
        if (value == selectedValue) {
          return;
        }
        onSelected(value);
      },
      indicator: FluentDropdownIndicator.bar,
      panelColor: colorScheme.surfaceContainerLow,
      selectedColor: colorScheme.surfaceContainerHighest,
      hoverColor: colorScheme.surfaceContainerHigh,
      panelBorderRadius: 12,
      itemBorderRadius: 8,
    );
  }

  Map<String, String> _flattenOptions(
    List<PluginChoiceOption> options, [
    int depth = 0,
  ]) {
    final result = <String, String>{};
    final indent = List.filled(depth, '\u00A0\u00A0').join();
    for (final option in options) {
      result[option.value] = '$indent${option.label}';
      if (option.children.isNotEmpty) {
        result.addAll(_flattenOptions(option.children, depth + 1));
      }
    }
    return result;
  }
}
