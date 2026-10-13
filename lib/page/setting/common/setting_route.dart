import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/popup_panel.dart';

/// 设置子页面沿用路由守卫与返回保护，只将出场接到统一弹层。
Route<T> settingAutoRoute<T>(
  BuildContext context,
  Widget child,
  AutoRoutePage<T> page,
) => settingPageRoute<T>(
  context: context,
  settings: page,
  builder: (_) => child,
);

CommonPopupRoute<T> settingPageRoute<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  final navigator = Navigator.of(context);
  final box = navigator.context.findRenderObject();
  final pointer = PopupPointerOrigin.last;
  final origin = pointer != null && box is RenderBox
      ? box.globalToLocal(pointer)
      : MediaQuery.sizeOf(context).center(Offset.zero);
  return CommonPopupRoute<T>(
    settings: settings,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    anchorOf: () => Rect.fromCenter(center: origin, width: 48, height: 48),
    fullscreen: true,
    builder: builder,
  );
}
