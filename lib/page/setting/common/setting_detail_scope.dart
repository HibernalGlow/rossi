import 'package:flutter/widgets.dart';

/// 仅改变当前分类页的外壳；设置状态与下一级路由仍复用原页面。
class SettingDetailScope extends InheritedWidget {
  const SettingDetailScope({super.key, required super.child});

  static bool isEmbedded(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingDetailScope>() != null;

  @override
  bool updateShouldNotify(SettingDetailScope oldWidget) => false;
}
