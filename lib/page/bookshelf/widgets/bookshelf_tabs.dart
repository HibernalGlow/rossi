import 'package:material_ui/material_ui.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_bar.dart';

/// 顶部页签自己管理选中与悬停反馈，避免再叠一层 ActionBubble。
class BookshelfTabs extends StatelessWidget {
  const BookshelfTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    // 量宽度用的那份样式必须与 `_SleekTabLabel` **渲染的那一份**同源 ——
    // 拿 token 直接量、在 fontSize 为 null 的档位上量到的是回落值，
    // 于是「每格多宽」与实际排出来的宽度对不上，lens 的落点会偏。
    final labelStyle = DefaultTextStyle.of(
      context,
    ).style.merge(context.theme.textTheme.titleSmall);

    // 量每格宽度：文字实测宽 + 左右内边距。与 `_Slot` 里那个
    // `SizedBox(width: extent)` 用的是同一个数。
    final sizes = <double>[];
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: labelStyle.copyWith(fontWeight: FontWeight.bold),
        ),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      sizes.add(painter.width + _SleekTabLabel.hPadding * 2);
      painter.dispose();
    }

    return Container(
      decoration: BoxDecoration(
        color: context.theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.5,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(4),
      child: SpringLensBar(
        tabs: [
          for (var i = 0; i < labels.length; i++)
            SpringLensTab(
              child: _SleekTabLabel(
                text: labels[i],
                selected: i == selectedIndex,
                baseStyle: labelStyle,
              ),
              semanticLabel: labels[i],
            ),
        ],
        tabSizes: sizes,
        selectedIndex: selectedIndex,
        onSelected: onSelected,
        lensCorner: 14,
        lensColor: context.theme.colorScheme.surface,
        lensShadow: Shadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ),
    );
  }
}

class _SleekTabLabel extends StatelessWidget {
  const _SleekTabLabel({
    required this.text,
    required this.selected,
    required this.baseStyle,
  });

  /// 文字左右各留的内边距。
  ///
  /// **量与画必须读同一份**：`BookshelfTabs.build` 量每格宽度时用它算总宽，
  /// 这里用它排版。两处各写一个数的话，lens 的落点会与实际排出来的位置差
  /// 那一点点 —— 按内容取宽的档位最怕这个。
  static const double hPadding = 16;

  /// 文字上下的内边距（不参与宽度计算）。
  static const double vPadding = 6;

  final String text;
  final bool selected;

  /// 由 [_buildSleekTabs] 量宽度时用的**那一份**样式传进来 —— 量与画必须同源。
  final TextStyle baseStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: hPadding,
        vertical: vPadding,
      ),
      child: Text(
        text,
        style: baseStyle.copyWith(
          fontWeight: selected ? FontWeight.bold : FontWeight.w600,
          color: selected
              ? context.textColor
              : context.textColor.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
