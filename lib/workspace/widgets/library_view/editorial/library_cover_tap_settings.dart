import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/navigation/navigation_shape.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_settings_controls.dart';

class LibraryCoverTapSettings extends StatelessWidget {
  const LibraryCoverTapSettings({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final LibraryCoverTapAction value;
  final ValueChanged<LibraryCoverTapAction> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LibrarySettingsGroup(
      title: '点击封面',
      glyph: AppGlyphs.touch,
      description: '只调整当前面板。封面右下角的详情按钮始终向下展开。',
      children: [
        for (final action in LibraryCoverTapAction.values)
          Padding(
            padding: const EdgeInsets.all(8),
            child: ElasticButton(
              enabled: !MediaQuery.disableAnimationsOf(context),
              child: Semantics(
                selected: action == value,
                child: ChoiceChip(
                  key: ValueKey('library-cover-tap-${action.name}'),
                  selected: action == value,
                  label: Text(action.label),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  side: BorderSide.none,
                  shape: action == value ? AppShape.xl : AppShape.md,
                  backgroundColor: colors.surfaceContainerHigh,
                  selectedColor: colors.secondaryContainer,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    onChanged(action);
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}
