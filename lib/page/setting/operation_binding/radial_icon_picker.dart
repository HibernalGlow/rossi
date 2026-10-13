import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/service/operation_binding/action_labels.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/radial/radial_action_icons.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';

class RadialIconPickerTile extends StatelessWidget {
  const RadialIconPickerTile({
    super.key,
    required this.iconId,
    required this.action,
    required this.menuJump,
    required this.onChanged,
  });
  final String? iconId;
  final String? action;
  final bool menuJump;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: GlyphIcon(
      radialActionGlyph(action: action, overrideId: iconId, menuJump: menuJump),
    ),
    title: Text(t.settings.operationBindingRadialIcon),
    subtitle: Text(
      iconId == null || !radialIconActionIds.contains(iconId)
          ? t.settings.operationBindingRadialIconAuto
          : actionLabelForId(iconId!),
    ),
    trailing: const GlyphIcon(AppGlyphs.chevronForward),
    onTap: () async {
      final chosen = await showPopupPanel<String>(
        context: context,
        builder: (context) => _RadialIconPicker(selected: iconId),
      );
      if (context.mounted && chosen != null) onChanged(chosen);
    },
  );
}

class _RadialIconPicker extends StatelessWidget {
  const _RadialIconPicker({this.selected});
  final String? selected;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labels = actionLabelsById();
    final motion =
        !eInkInstantRoutes && !MediaQuery.disableAnimationsOf(context);
    return PopupPanel(
      title: Text(t.settings.operationBindingRadialIcon),
      content: SizedBox(
        height: 360,
        child: ActionBubbleRegion(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 100,
              mainAxisExtent: 84,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: radialIconActionIds.length,
            itemBuilder: (context, index) {
              final id = radialIconActionIds[index];
              final label = labels[id] ?? id;
              return ActionBubbleTarget(
                child: ElasticPress(
                  enabled: motion,
                  child: Semantics(
                    selected: id == selected,
                    child: Material(
                      color: id == selected
                          ? scheme.secondaryContainer
                          : scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(24),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        splashFactory: NoSplash.splashFactory,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).pop(id);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GlyphIcon(
                                radialActionGlyph(action: id),
                                size: 24,
                              ),
                              const SizedBox(height: 6),
                              Flexible(
                                child: Text(
                                  label,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.common.cancel),
        ),
        ElasticPress(
          enabled: motion,
          child: TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop('');
            },
            child: Text(t.settings.operationBindingRadialIconAuto),
          ),
        ),
      ],
    );
  }
}
