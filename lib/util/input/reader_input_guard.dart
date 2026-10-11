import 'package:flutter/widgets.dart';

/// 输入宿主的保护边界；编辑器的未消费按键也不能回落到阅读器。
abstract final class ReaderInputGuard {
  static bool get isEditing {
    final context = FocusManager.instance.primaryFocus?.context;
    return context != null &&
        (context.widget is EditableText ||
            context.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  static bool get isModal {
    final context = FocusManager.instance.primaryFocus?.context;
    return context != null && ModalRoute.of(context) is PopupRoute;
  }

  static bool get blocksKeyboard => isEditing || isModal;
}
