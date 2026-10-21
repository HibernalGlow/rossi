import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/plugin/source_visibility.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/icons/icons.dart';

Future<void> showPluginOrderDialog(BuildContext context) async {
  await showPopupPanel<void>(
    presentation: PopupPresentation.relative,
    context: context,
    builder: (_) => PluginOrderDialog(
      initialPlugins: filterRestrictedPlugins(
        PluginRegistryService.I.orderedPlugins(),
        showRestricted: context
            .read<GlobalSettingCubit>()
            .state
            .showRestrictedSources,
      ).toList(),
    ),
  );
}

class PluginOrderDialog extends StatefulWidget {
  const PluginOrderDialog({super.key, required this.initialPlugins});

  final List<PluginRuntimeState> initialPlugins;

  @override
  State<PluginOrderDialog> createState() => _PluginOrderDialogState();
}

class _PluginOrderDialogState extends State<PluginOrderDialog> {
  late final List<PluginRuntimeState> _plugins = [...widget.initialPlugins];
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final maxHeight = (MediaQuery.sizeOf(context).height - 220)
        .clamp(220.0, 560.0)
        .toDouble();

    return PopupPanel(
      title: Text(t.discover.customOrder),
      content: SizedBox(
        width: 420,
        height: maxHeight,
        child: ReorderableListView.builder(
          buildDefaultDragHandles: false,
          itemCount: _plugins.length,
          itemBuilder: (context, index) {
            final plugin = _plugins[index];
            final info = PluginRegistryService.I.getCachedPluginInfo(
              plugin.uuid,
            );
            final name = info?['name']?.toString().trim();
            return ListTile(
              key: ValueKey(plugin.uuid),
              title: Text(
                name?.isNotEmpty == true ? name! : plugin.uuid,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: plugin.isActive ? null : Text(t.discover.disabled),
              trailing: ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: GlyphIcon(AppGlyphs.dragHandle),
                ),
              ),
            );
          },
          onReorderItem: (oldIndex, newIndex) {
            setState(() {
              final plugin = _plugins.removeAt(oldIndex);
              _plugins.insert(newIndex, plugin);
            });
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : _reset,
          child: Text(t.discover.resetOrder),
        ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(t.common.cancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t.common.apply),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await PluginRegistryService.I.reorderPlugins(
      _plugins.map((plugin) => plugin.uuid).toList(),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _reset() async {
    setState(() => _saving = true);
    await PluginRegistryService.I.resetPluginOrder();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
