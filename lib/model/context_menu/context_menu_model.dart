/// 上下文菜单的**用户偏好模型** —— 纯 Dart，不 import Flutter。
///
/// 判据：`dart run test/context_menu/context_menu_resolve_check.dart`
///
/// 两类数据分开存，理由不同：
/// - [ContextMenuScopeLayout.order] 是一整个 scope 的完整次序（空 = 没排过）。
///   不按「拖过的项记一个 int」做稀疏：那样未记录项与记录项之间会不断产生
///   并列，要么引入分数排序、要么周期性重整，而且「新增项追加末尾」与「并列」
///   两套规则会打架。完整列表的写法与 `NavigationSettingState.desktopPageIds`
///   完全一致，新增项由解析器补到末尾，不需要迁移。
/// - [ContextMenuScopeLayout.overrides] 才是稀疏的：只记被改过的项。布尔与枚举
///   的默认值明确，缺省即出厂，不存在并列问题。
///
/// JSON 手写而不用 json_serializable：这两个类要吃掉**云同步回来的任意数据**，
/// 一个非字符串的 key、一个未来版本写入的枚举名都不该让整份设置读不出来。
/// 枚举按名字解析（认不出回默认），`order` 去重并丢掉空串，`overrides` 丢掉
/// 非对象值 —— 与 `decodeNavigationEntryIds` 的「坏数据回出厂」是同一条口径。
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'context_menu_model.freezed.dart';

/// 菜单项的显隐档位。
enum ContextMenuVisibility {
  /// 正常出现在列表里。
  normal,

  /// 收进一条合成的「更多」子菜单。
  collapsed,

  /// 完全不出现。
  hidden;

  static ContextMenuVisibility parse(Object? raw) {
    for (final value in ContextMenuVisibility.values) {
      if (value.name == raw) return value;
    }
    return ContextMenuVisibility.normal;
  }
}

/// 菜单项在菜单里的固定位置。
enum ContextMenuPin {
  /// 跟随用户排序。
  none,

  /// 固定在菜单顶部。
  top,

  /// 固定在菜单底部。
  bottom;

  static ContextMenuPin parse(Object? raw) {
    for (final value in ContextMenuPin.values) {
      if (value.name == raw) return value;
    }
    return ContextMenuPin.none;
  }
}

/// 单个菜单项的用户覆盖项。缺省值 = 出厂。
///
/// `fromJson` / `toJson` 手写（见文件头），所以显式关掉 freezed 的 JSON 生成。
@Freezed(fromJson: false, toJson: false)
abstract class ContextMenuItemOverride with _$ContextMenuItemOverride {
  const ContextMenuItemOverride._();

  const factory ContextMenuItemOverride({
    @Default(ContextMenuVisibility.normal) ContextMenuVisibility visibility,
    @Default(ContextMenuPin.none) ContextMenuPin pin,

    /// 仅在 [pin] 为 [ContextMenuPin.top] 时有意义：顶部那一排只画图标。
    /// 其余档位解析器会忽略它，切走 pin 时也由编辑函数清掉。
    @Default(false) bool iconOnly,
  }) = _ContextMenuItemOverride;

  factory ContextMenuItemOverride.fromJson(Map<String, dynamic> json) =>
      ContextMenuItemOverride(
        visibility: ContextMenuVisibility.parse(json['visibility']),
        pin: ContextMenuPin.parse(json['pin']),
        iconOnly: json['iconOnly'] == true,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'visibility': visibility.name,
    'pin': pin.name,
    'iconOnly': iconOnly,
  };

  /// 与出厂一致 —— 这种覆盖项没有存的必要（保持稀疏）。
  bool get isDefault =>
      visibility == ContextMenuVisibility.normal &&
      pin == ContextMenuPin.none &&
      !iconOnly;
}

/// 一个菜单（scope）的用户偏好。
@Freezed(fromJson: false, toJson: false)
abstract class ContextMenuScopeLayout with _$ContextMenuScopeLayout {
  const ContextMenuScopeLayout._();

  const factory ContextMenuScopeLayout({
    /// 用户排过的完整次序；空 = 没排过 ⇒ 用 definition 的出厂次序。
    /// 只装 `persistent == true` 的项；动态生成项（如「恢复隐藏卡 X」）不进这里。
    @Default(<String>[]) List<String> order,

    /// 稀疏：只存被改过的项，未出现的项 = 全默认。
    @Default(<String, ContextMenuItemOverride>{})
    Map<String, ContextMenuItemOverride> overrides,
  }) = _ContextMenuScopeLayout;

  factory ContextMenuScopeLayout.fromJson(Map<String, dynamic> json) =>
      ContextMenuScopeLayout(
        order: _parseOrder(json['order']),
        overrides: _parseOverrides(json['overrides']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'order': order,
    'overrides': <String, dynamic>{
      for (final entry in overrides.entries) entry.key: entry.value.toJson(),
    },
  };

  /// 一条偏好都没记过 —— 这个 scope 不需要落键。
  bool get isPristine => order.isEmpty && overrides.isEmpty;
}

List<String> _parseOrder(Object? raw) {
  if (raw is! List) return const <String>[];
  final result = <String>[];
  for (final item in raw) {
    if (item is! String) continue;
    final id = item.trim();
    if (id.isEmpty || result.contains(id)) continue;
    result.add(id);
  }
  return result;
}

Map<String, ContextMenuItemOverride> _parseOverrides(Object? raw) {
  if (raw is! Map) return const <String, ContextMenuItemOverride>{};
  final result = <String, ContextMenuItemOverride>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is! String || key.trim().isEmpty || value is! Map) continue;
    final map = <String, dynamic>{};
    for (final field in value.entries) {
      if (field.key is String) map[field.key as String] = field.value;
    }
    final override = ContextMenuItemOverride.fromJson(map);
    if (override.isDefault) continue;
    result[key.trim()] = override;
  }
  return result;
}
