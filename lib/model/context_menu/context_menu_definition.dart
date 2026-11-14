/// 上下文菜单的**定义模型** —— 纯 Dart，不 import Flutter。
///
/// 一个菜单 = 一个 [ContextMenuDefinition]（scope + 出厂次序 + 每项的语义状态）。
/// 定义里不放文案与图标：那两样要 `t.*` 与 `Glyph`，放进来这份文件就不能被
/// `dart run` 直接跑了 —— 与 `ShelfEntryMenuItemSpec` 的分工完全一致。
///
/// **`id` 是持久化契约**：用户的排序/显隐/pin 都按 id 记账，改 id 等于让老用户
/// 的选择全部落空。只能改文案，不能改 id；确需改名时走 `context_menu_id_aliases.dart`
/// 的读取映射，并保留旧 id 一个发布周期。
library;

/// 一个菜单项**允许被用户怎么改**。
///
/// 结构性的行（子菜单父行、内嵌输入框行、动态生成行）一律用
/// [ContextMenuEntryCapabilities.structural]：它们的位置与存在由功能决定，
/// 不该变成可排序/可隐藏的偏好。
class ContextMenuEntryCapabilities {
  const ContextMenuEntryCapabilities({
    this.canPin = true,
    this.canCollapse = true,
    this.canHide = true,
    this.canIconOnly = true,
  });

  /// 允许 pin 到顶部/底部。
  final bool canPin;

  /// 允许折叠进「更多」。
  final bool canCollapse;

  /// 允许隐藏。
  final bool canHide;

  /// 允许在顶部图标条里只画图标。
  final bool canIconOnly;

  /// 结构性行：不可排序、不可折叠、不可隐藏、不可变成图标。
  static const ContextMenuEntryCapabilities structural =
      ContextMenuEntryCapabilities(
        canPin: false,
        canCollapse: false,
        canHide: false,
        canIconOnly: false,
      );
}

/// 菜单里的一项。
class ContextMenuEntryDefinition {
  const ContextMenuEntryDefinition({
    required this.id,
    this.group = 0,
    this.enabled = true,
    this.dangerous = false,
    this.destructive = false,
    this.checked,
    this.persistent = true,
    this.available = true,
    this.capabilities = const ContextMenuEntryCapabilities(),
  }) : assert(id.length > 0, 'id 不能为空'),
       assert(!destructive || dangerous, 'destructive 必须同时 dangerous');

  /// 稳定 id，形如 `<scope>.<itemName>`（lowerCamel）。**改名 = 丢用户偏好。**
  final String id;

  /// 组号：组内不画分隔线，组间画。沿用现有「动作 / 复制 / 危险」的分法。
  final int group;

  /// 当前可点吗。不可点仍然渲染（置灰），**不隐藏** —— 隐藏会让人以为没这功能。
  final bool enabled;

  /// 画危险色。可撤销的破坏性动作（如移入回收站）也用它。
  final bool dangerous;

  /// 需要二次确认（不可撤销）。不变式：`destructive ⇒ dangerous`。
  final bool destructive;

  /// 勾选态（三态：null = 不显示勾）。
  final bool? checked;

  /// 参与用户偏好（排序/显隐/pin）。`false` = 每次现场生成，不进偏好。
  final bool persistent;

  /// 这一次菜单里有没有这一项。
  ///
  /// 与 [persistent] 分工不同：模式差异（竖向轨只给「上/下」两条、
  /// 卡片没有布局时不给尺寸预设）用 `available: false` 临时不渲染，
  /// **但 id 仍然留在 order 里** —— 切回那个模式时用户排的位置还在。
  /// 用户主动隐藏是 [ContextMenuItemOverride.visibility]，不是这个字段。
  final bool available;

  final ContextMenuEntryCapabilities capabilities;
}

/// 一个右键菜单的完整定义。
class ContextMenuDefinition {
  const ContextMenuDefinition({
    required this.scope,
    required this.entries,
    this.supportsTopStrip = true,
  });

  /// scope id，lowerCamel 单数：`shelf` / `fileManager` / `folder` / ...
  final String scope;

  /// 出厂次序。用户没改过时，渲染结果就是它。
  final List<ContextMenuEntryDefinition> entries;

  /// 这个菜单是否支持顶部图标条。纯开关/视图类菜单可以关掉。
  final bool supportsTopStrip;

  ContextMenuEntryDefinition? entryById(String id) {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  /// 参与用户偏好的项（`persistent == true`），出厂次序。
  Iterable<ContextMenuEntryDefinition> get orderableEntries =>
      entries.where((entry) => entry.persistent);

  /// 每次现场生成的项，出厂次序。
  Iterable<ContextMenuEntryDefinition> get ephemeralEntries =>
      entries.where((entry) => !entry.persistent);
}
