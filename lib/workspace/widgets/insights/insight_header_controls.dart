import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/expressive/expressive_icon_button.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 切段与展开入口固定在标题栏；窄标题只显示进度，极窄时保留展开入口。
class InsightPagerHeader extends StatelessWidget {
  const InsightPagerHeader({
    super.key,
    required this.index,
    required this.labels,
    required this.onPrevious,
    required this.onNext,
    required this.title,
    required this.detailBuilder,
    required this.paged,
  });
  final int index;
  final List<String> labels;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final String title;
  final WidgetBuilder detailBuilder;
  final bool paged;

  @override
  Widget build(BuildContext context) {
    Widget expand() => ActionBubbleRegion(
      child: InsightDetailButton(
        label: '',
        title: title,
        detailBuilder: detailBuilder,
        compact: true,
        iconOnly: true,
      ),
    );
    // 无分段时直接按图标固有宽度布局，不为隐藏的段名预留半个标题。
    if (!paged) return expand();
    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth < 96) return expand();
        final width = bounds.maxWidth.clamp(96.0, 160.0);
        const size = 32.0;
        Widget arrow(Glyph glyph, String tooltip, VoidCallback? action) =>
            ActionBubbleTarget(
              enabled: action != null,
              corner: 20,
              child: ExpressiveIconButton(
                size: size,
                glyph: glyph,
                tooltip: tooltip,
                onPressed: action,
              ),
            );
        return ActionBubbleRegion(
          child: SizedBox(
            width: width,
            height: 48,
            child: Row(
              children: [
                arrow(AppGlyphs.chevronUp, t.workspace.prevSegment, onPrevious),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: InsightDetailButton(
                      label: width >= 150
                          ? '${labels[index]} ${index + 1}/${labels.length}'
                          : '${index + 1}/${labels.length}',
                      title: title,
                      description: t.workspace.insightHeaderExpand(
                        label: labels[index],
                        position: index + 1,
                        total: labels.length,
                        title: title,
                      ),
                      detailBuilder: detailBuilder,
                      showIcon: false,
                      compact: true,
                    ),
                  ),
                ),
                arrow(AppGlyphs.chevronDown, t.workspace.nextSegment, onNext),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 图表需要更多空间时展开同一份数据，复用应用已有的托盘弹层。
class InsightDetailButton extends StatelessWidget {
  const InsightDetailButton({
    super.key,
    required this.label,
    required this.title,
    required this.detailBuilder,
    this.showIcon = true,
    this.compact = false,
    this.iconOnly = false,
    this.description,
  });
  final String label;
  final String title;
  final WidgetBuilder detailBuilder;
  final bool showIcon;
  final bool compact;
  final bool iconOnly;
  final String? description;

  @override
  Widget build(BuildContext context) => CommonPopupBox(
    targetBuilder: (open) => ActionBubbleTarget(
      corner: 24,
      child: iconOnly
          ? SizedBox.square(
              dimension: 32,
              child: ExpressiveIconButton(
                glyph: AppGlyphs.openInFull,
                tooltip: description ?? '展开$title',
                size: 32,
                onPressed: open,
              ),
            )
          : ElasticButton(
              child: Tooltip(
                message: description ?? '展开$title',
                child: TextButton.icon(
                  onPressed: open,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.square(compact ? 32 : 48),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ).merge(ElasticPress.buttonStyle),
                  icon: showIcon
                      ? const GlyphIcon(AppGlyphs.openInFull, size: 18)
                      : null,
                  label: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: compact
                        ? Theme.of(context).textTheme.labelSmall
                        : null,
                  ),
                ),
              ),
            ),
    ),
    popupBuilder: (context) => PopupPanel(
      title: Text(title),
      scrollable: true,
      content: SizedBox(width: 380, child: Builder(builder: detailBuilder)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
