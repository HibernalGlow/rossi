import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/util/context/context_extensions.dart';

/// 「这块子树现在该不该休眠」的显式声明。
///
/// 只有首页壳（`NavigationBar` 的页面栈）会提供它，值 = 工作台是否在场。
/// 没有这个祖先的子树（工作台内嵌页面、根栈上推的其他页）**默认清醒** ——
/// 休眠只针对「被工作台盖住的首页壳」，不能做成全局行为，否则工作台自己
/// 内嵌的发现页也会跟着变灰。
class WorkspaceImageSleepScope extends InheritedWidget {
  const WorkspaceImageSleepScope({
    super.key,
    required this.asleep,
    required super.child,
  });

  /// true = 这块子树被工作台盖住，图片该让出解码位图。
  final bool asleep;

  @override
  bool updateShouldNotify(WorkspaceImageSleepScope oldWidget) =>
      oldWidget.asleep != asleep;
}

/// 「这块图片现在该不该休眠」的判定（**纯函数**，判据直接打它）。
///
/// 两个条件同时成立：scope 显式声明了休眠（只有首页壳会声明），且用户
/// 没有把设置关掉。任何一条不满足都保持清醒 —— 尤其是前者：没有 scope
/// 的子树（工作台内嵌页、根栈上推的其他页）一律清醒。
bool resolveImageSleep({
  required bool scopeAsleep,
  required bool settingEnabled,
}) => scopeAsleep && settingEnabled;

/// 会休眠的图片：工作台在场时把自己换成一块纯色占位。
///
/// 动机：被工作台盖住的页面虽不绘制，但挂载着的 `Image` widget 仍握着
/// imageCache 里的 live image（解码位图），`imageCache.clear()` 清不掉它们。
/// 占位让 widget 卸载、监听归零，位图才真正释放；退场后按磁盘文件重新解码。
///
/// 布局约定：调用方通常已用 `SizedBox` / 外层容器给了**紧约束**（封面、头像
/// 都如此），占位的 `ColoredBox` 直接吃满同一块约束，不会引起布局跳动；
/// 里面的圆角交给调用方既有的 `ClipRRect`（所以它应包在 ClipRRect 之内）。
///
/// 开关：`globalSetting.workspaceSleepCoveredUi`（设置 → 应用行为），
/// 默认开。关掉 = 工作台在场时底下页面照旧持有位图（不省内存，但也不重解码）。
class ImageSleep extends StatelessWidget {
  const ImageSleep({super.key, required this.child, this.enabled});

  /// 真实内容（成功分支的那颗图片）。
  final Widget child;

  /// 可直接指定开关；缺省时只在 scope 休眠时订阅内存中的设置。
  final bool? enabled;

  @override
  Widget build(BuildContext context) {
    // dependOn：scope 值翻转（进/退工作台）时这里跟着重建。
    final scope = context
        .dependOnInheritedWidgetOfExactType<WorkspaceImageSleepScope>();
    // 大多数图片不在休眠范围内，不需要读取设置，更不能在每次布局时读库解码。
    if (scope?.asleep != true) return child;
    final settingOn =
        enabled ??
        context.select<GlobalSettingCubit, bool>(
          (cubit) => cubit.state.workspaceSleepCoveredUi,
        );
    if (!resolveImageSleep(
      scopeAsleep: scope?.asleep ?? false,
      settingEnabled: settingOn,
    )) {
      return child;
    }
    // 与封面加载中那一格同色（`cover.dart` 的 initial 分支），观感连贯。
    return ColoredBox(color: context.theme.colorScheme.surfaceContainerHigh);
  }
}
