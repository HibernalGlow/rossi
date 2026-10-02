import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/type/enum.dart';

/// 导出对话框的一次选择：格式，以及导出成功后要不要删掉本地下载。
class ExportChoice {
  const ExportChoice({required this.type, required this.deleteAfterExport});

  final ExportType type;
  final bool deleteAfterExport;
}

/// 导出格式选择对话框，带「导出后删除原下载」勾选。
///
/// iOS 不要用它：那边的导出走系统分享面板，面板返回时用户是否已经把文件存下来并不可知，
/// 不能连带删除本地下载。调用方在 iOS 上应直接构造 [ExportChoice]。
Future<ExportChoice?> showExportChoiceDialog(
  BuildContext context, {
  required String title,
  required String subtitle,
}) {
  return showDialog<ExportChoice>(
    context: context,
    builder: (context) => _ExportChoiceDialog(title: title, subtitle: subtitle),
  );
}

class _ExportChoiceDialog extends StatefulWidget {
  const _ExportChoiceDialog({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  State<_ExportChoiceDialog> createState() => _ExportChoiceDialogState();
}

class _ExportChoiceDialogState extends State<_ExportChoiceDialog> {
  /// 默认不勾：删除是不可逆的，必须用户明确要。
  bool _deleteAfterExport = false;

  void _submit(ExportType type) {
    Navigator.of(
      context,
    ).pop(ExportChoice(type: type, deleteAfterExport: _deleteAfterExport));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.subtitle),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _deleteAfterExport,
            title: Text(t.comicInfo.exportDeleteAfter),
            subtitle: Text(t.comicInfo.exportDeleteAfterSubtitle),
            contentPadding: EdgeInsets.zero,
            onChanged: (value) {
              setState(() => _deleteAfterExport = value ?? false);
            },
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.common.cancel),
        ),
        TextButton(
          onPressed: () => _submit(ExportType.folder),
          child: Text(t.comicInfo.folder),
        ),
        FilledButton(
          onPressed: () => _submit(ExportType.zip),
          child: Text(t.comicInfo.zip),
        ),
      ],
    );
  }
}
