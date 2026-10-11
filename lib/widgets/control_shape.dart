import 'package:material_ui/material_ui.dart';

/// 页签、筛选和工具条共用的圆角轮廓；绘制与染色裁剪使用同一份路径。
abstract final class ControlShape {
  static const double corner = 12;
  static const double compactCorner = 8;
  static const double labelCorner = 14;
  static const double trackCorner = 16;

  static const RoundedRectangleBorder rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(corner)),
  );
  static const RoundedRectangleBorder track = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(trackCorner)),
  );

  static RoundedRectangleBorder withCorner(double? value) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(value ?? corner),
      );

  static Path path(Rect bounds, {double? corner}) =>
      withCorner(corner).getOuterPath(bounds);
}
