import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/widgets/popup_panel.dart';

/// 删除插件的确认框。
///
/// 返回 null 表示取消；否则返回「是否同时删除该源数据」。
/// 开关默认关闭：卸载通常只是移除插件或清掉登录信息，不该顺手带走书架数据。
Future<bool?> showDeletePluginConfirmDialog(BuildContext context) {
  var deleteRelatedData = false;
  return showPopupPanel<bool>(
    context: context,
    presentation: PopupPresentation.modal,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        final theme = Theme.of(context);
        return PopupPanel(
          title: Text(t.plugin.deletePlugin),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.plugin.confirmDeletePlugin),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.plugin.deletePluginAlsoRemoveData),
                subtitle: Text(t.plugin.deletePluginAlsoRemoveDataSubtitle),
                value: deleteRelatedData,
                onChanged: (value) =>
                    setDialogState(() => deleteRelatedData = value),
              ),
              Text(
                deleteRelatedData
                    ? t.plugin.deletePluginRemoveDataHint
                    : t.plugin.deletePluginKeepDataHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t.common.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(deleteRelatedData),
              child: Text(t.common.confirm),
            ),
          ],
        );
      },
    ),
  );
}
