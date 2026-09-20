import 'package:material_ui/material_ui.dart';

/// 顶栏二级面板的名单。
///
/// neoview 的 `ExpandedPanel` 有六档（sort / zoom / rotate / hover-scroll /
/// slideshow / magnifier），本仓目前只有真做得起来的这三档 —— **刻意不给
/// 做不出来的那几档留占位按钮**：一颗点了没反应的按钮比没有更糟。
enum ReaderToolbarPanel { zoom, rotate, layout }

/// 面板组之间的竖分隔线（neo 的 `Separator`：`mx-1 h-5 w-px bg-border/70`）。
class ReaderToolbarSeparator extends StatelessWidget {
  const ReaderToolbarSeparator({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Theme.of(
        context,
      ).colorScheme.outlineVariant.withValues(alpha: 0.45),
    );
  }
}

/// 一组紧密贴合的按钮/控件的外壳（neo 的 pill：`rounded-full bg-muted/35 p-0.5`）。
class ReaderToolbarPill extends StatelessWidget {
  final List<Widget> children;

  /// 内底色再深一档 —— neo 的滑条容器用的是 `bg-muted/60`。
  final bool emphasized;

  const ReaderToolbarPill({
    super.key,
    required this.children,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(
          alpha: emphasized ? 0.7 : 0.35,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// 组前的小标签（neo 的 `text-xs text-muted-foreground`）。
class ReaderToolbarLabel extends StatelessWidget {
  final String text;

  const ReaderToolbarLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 顶栏的一颗图标按钮：按下态与未按下态的差别照 neo 的 `ghost ↔ default`。
class ReaderToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final bool enabled;
  final VoidCallback? onPressed;

  const ReaderToolbarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = !enabled
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.35)
        : selected
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: enabled ? onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: selected && enabled
                ? colorScheme.primary
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }
}

/// neo 主行上有、本仓还没有对应能力的那几颗。
///
/// 保留占位是**刻意的**：顶栏的形状与 neo 对齐，将来做出一块就点亮一块，
/// 不用重排列。但它不能是静默失效的一颗 —— 点了要给一句话，否则人只会
/// 以为是自己点歪了。
class ReaderToolbarComingSoonButton extends StatelessWidget {
  final IconData icon;
  final String name;

  const ReaderToolbarComingSoonButton({
    super.key,
    required this.icon,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return ReaderToolbarIconButton(
      icon: icon,
      tooltip: '$name（本仓尚未实现）',
      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name 还没接进本仓的阅读器'),
          behavior: SnackBarBehavior.floating,
          width: 280,
          duration: const Duration(milliseconds: 1800),
        ),
      ),
    );
  }
}

/// 展开区的一行面板（neo 的 `data-reader-toolbar-row="expanded"`：
/// 顶边一条分隔线 + 居中换行排布的控件）。
class ReaderToolbarPanelRow extends StatelessWidget {
  final List<Widget> children;

  const ReaderToolbarPanelRow({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.18),
            width: 0.8,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      // 与 neo 同一处理：窄屏不折叠成溢出菜单，而是**换行摊开**。
      child: Wrap(
        spacing: 2,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}
