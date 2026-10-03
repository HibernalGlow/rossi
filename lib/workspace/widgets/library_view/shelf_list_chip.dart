import 'package:material_ui/material_ui.dart';

/// 书签列表轨上的一颗单选 chip。
///
/// 抽出来放在 `library_view` 而不是留在卡片里，是为了让它能被单独断言
/// （判据 `test/workspace/shelf_list_toolbar_test.dart`）：卡片本体要 ObjectBox
/// 与全局设置 Cubit 才搭得起来，而「选中长什么样」这件事不需要那些。
///
/// # 三处偏离默认画法，各有各的理由
///
/// 1. **不画勾**。这个版本的 `material_ui` 里 `ChoiceChip` 的 M3 默认是
///    `showCheckmark: true`，于是单选轨上会出现一个勾选符号 —— 那是**多选**
///    （FilterChip）的符号，画在这里等于告诉用户「还能再选一个」，
///    而点下去只会换掉当前这个。
/// 2. **底色写在项上，不改全局 `chipTheme`**。`main.dart` 把
///    `chipTheme.backgroundColor` 覆成了 `surface`，而在 `useMaterial3` 下这一项
///    **盖得过** M3 默认的 `surfaceContainerLow`（解析顺序见 `material_ui` 的
///    `RawChip._getBackgroundColor`），于是未选中的那颗只剩一圈描边、读起来
///    不像一个可点的档。全局那一处牵动整个 app 的所有 chip，不该由一个面板
///    的观感来定 —— 要收口就单独收口一次。
/// 3. **选中态用 `secondaryContainer`**，与工具栏那几颗开关键同一个语言：
///    「当前选中的东西」在这一块面板里只有一种画法。
class ShelfListChip extends StatelessWidget {
  const ShelfListChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.secondaryContainer,
        labelStyle: theme.textTheme.labelLarge?.copyWith(
          color: selected
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
        ),
        side: BorderSide(
          color: selected ? Colors.transparent : scheme.outlineVariant,
        ),
        onSelected: (_) => onTap(),
      ),
    );
  }
}
