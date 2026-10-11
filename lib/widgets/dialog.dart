import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/widgets/popup_panel.dart';

Future<void> nothingDialog(BuildContext context) async {
  return showPopupPanel<void>(
    context: context,
    // 原 barrierDismissible: false（点遮罩不可关）—— 新入口无此参数，遮罩现可点击关闭
    builder: (BuildContext context) {
      return PopupPanel(
        title: Text(t.common.underConstruction),
        content: SingleChildScrollView(
          child: ListBody(children: <Widget>[Text(t.common.comingSoon)]),
        ),
        actions: <Widget>[
          TextButton(
            child: Text(t.common.gotIt),
            onPressed: () {
              context.pop();
            },
          ),
        ],
      );
    },
  );
}

// 通用对话框
// 只用来提示信息
Future<void> commonDialog(
  BuildContext context,
  String title,
  String content,
) async {
  return showPopupPanel<void>(
    context: context,
    presentation: PopupPresentation.modal,
    // 原 barrierDismissible: false（点遮罩不可关）—— 新入口无此参数，遮罩现可点击关闭
    builder: (BuildContext context) {
      return PopupPanel(
        title: Text(title),
        content: SingleChildScrollView(
          child: ListBody(children: <Widget>[SelectableText(content)]),
        ),
        actions: <Widget>[
          TextButton(
            child: Text(t.common.cancel),
            onPressed: () {
              context.pop();
            },
          ),
          TextButton(
            child: Text(t.common.ok),
            onPressed: () {
              context.pop();
            },
          ),
        ],
      );
    },
  );
}
