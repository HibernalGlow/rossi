import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_list/scene_filter/plugin_list_filter_schema.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/widgets/popup_panel.dart';

class PluginListFilterDialog extends StatefulWidget {
  const PluginListFilterDialog({
    super.key,
    required this.scheme,
    required this.initialSelections,
  });

  final PluginListFilterSchema scheme;
  final Map<String, String> initialSelections;

  @override
  State<PluginListFilterDialog> createState() => _PluginListFilterDialogState();
}

class _PluginListFilterDialogState extends State<PluginListFilterDialog> {
  late final Map<String, String> _selections;

  @override
  void initState() {
    super.initState();
    _selections = Map<String, String>.from(widget.initialSelections);
  }

  @override
  Widget build(BuildContext context) {
    // 形态（宽屏托盘卡片 / 窄屏全屏）由推出它的那条路由决定，
    // 这里只是同一份内容结构 —— 见 `popup_panel.dart` 文件头。
    return PopupPanel(
      title: Text(
        widget.scheme.title.isNotEmpty
            ? widget.scheme.title
            : t.comicList.filter,
      ),
      // 内容本身不套滚动视图：全屏外壳的正文区已经是滚动视图，套两层
      // 会让内层拿不到有界高度。要滚就交给 `scrollable`（与
      // `AlertDialog.scrollable` 同义）。
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widget.scheme.fields
            .map((field) => _buildField(context, field))
            .toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.common.cancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, Map<String, String>.from(_selections)),
          child: Text(t.common.ok),
        ),
      ],
    );
  }

  Widget _buildField(BuildContext context, PluginChoiceField field) {
    final selectedPath =
        field.findPathByValue(_selections[field.key]) ?? const [];
    final visibleLevelOptionSets = field.buildVisibleLevels(
      _selections[field.key],
    );

    if (visibleLevelOptionSets.length == 1 &&
        visibleLevelOptionSets.first.options.length <= 1) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (field.label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                field.label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: context.theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ...visibleLevelOptionSets.asMap().entries.map((entry) {
            final level = entry.key;
            final filterLevel = entry.value;
            final levelOptions = filterLevel.options;
            final selectedValue = selectedPath.length > filterLevel.pathIndex
                ? selectedPath[filterLevel.pathIndex].value
                : '';
            final levelLabel = level == 0
                ? null
                : level == 1
                ? t.comicList.subCategory
                : t.comicList.levelCategory(level: level + 1);

            return Padding(
              padding: EdgeInsets.only(
                bottom: level == visibleLevelOptionSets.length - 1 ? 0 : 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (levelLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        levelLabel,
                        style: TextStyle(
                          color: context.theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: levelOptions.map((option) {
                      final value = option.value;
                      final optionLabel = option.label.isNotEmpty
                          ? option.label
                          : value;
                      final selected = selectedValue == value;

                      return ChoiceChip(
                        label: Text(optionLabel),
                        selected: selected,
                        showCheckmark: false,
                        onSelected: (_) {
                          setState(() {
                            _selections[field.key] = value;
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
