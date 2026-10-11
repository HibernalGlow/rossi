import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/widgets/popup_panel.dart';

Future<bool> buttonDialog(
  BuildContext context,
  String title,
  String content,
) async {
  return await showPopupPanel<bool>(
        context: context,
        // 新入口没有 barrierDismissible：原来禁止点外部关闭，现在点外部也会关掉。
        presentation: PopupPresentation.modal,
        builder: (BuildContext context) {
          return PopupPanel(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                child: Text(t.common.cancel),
                onPressed: () {
                  Navigator.of(context).pop(false); // 返回 false
                },
              ),
              TextButton(
                child: Text(t.common.ok),
                onPressed: () {
                  Navigator.of(context).pop(true); // 返回 true
                },
              ),
            ],
          );
        },
      ) ??
      false; // 处理返回值为空的情况
}
