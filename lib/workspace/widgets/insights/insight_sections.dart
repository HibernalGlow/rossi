import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/expressive/expressive_icon_button.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/motion/retained_panel_switcher.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';

/// 小卡片按语义分段；足够高时合并展示。切段不滚动、不改变卡片尺寸。
class InsightSectionPager extends StatefulWidget {
  const InsightSectionPager({
    super.key,
    required this.labels,
    required this.sections,
    required this.full,
    required this.fullHeight,
    required this.detailTitle,
    required this.tinySummary,
  });
  final List<String> labels;
  final List<Widget> sections;
  final Widget full;
  final double fullHeight;
  final String detailTitle;
  final String tinySummary;

  @override
  State<InsightSectionPager> createState() => _InsightSectionPagerState();
}

class _InsightSectionPagerState extends State<InsightSectionPager> {
  int _index = 0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      if (!bounds.hasBoundedHeight || bounds.maxHeight >= widget.fullHeight) {
        return Align(alignment: Alignment.topLeft, child: widget.full);
      }
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      // 最小槽位连一段内容和操作条都放不下，直接给出摘要及完整视图入口。
      if (bounds.maxHeight < 48 + 60 * scale) {
        return InsightDetailButton(
          label: widget.tinySummary,
          title: widget.detailTitle,
          detailBuilder: (_) => widget.full,
        );
      }
      Widget arrow(Glyph glyph, String tooltip, int next) {
        final enabled = next >= 0 && next < widget.sections.length;
        return ActionBubbleTarget(
          enabled: enabled,
          corner: 24,
          child: ExpressiveIconButton(
            size: 48,
            glyph: glyph,
            tooltip: tooltip,
            onPressed: !enabled
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    setState(() => _index = next);
                  },
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: RetainedPanelSwitcher(
              axis: Axis.vertical,
              selectedId: '$_index',
              children: {
                for (var i = 0; i < widget.sections.length; i++)
                  '$i': widget.sections[i],
              },
            ),
          ),
          ActionBubbleRegion(
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  arrow(AppGlyphs.chevronUp, '上一段', _index - 1),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: InsightDetailButton(
                        label:
                            '${widget.labels[_index]} · ${_index + 1}/${widget.sections.length}',
                        title: widget.detailTitle,
                        detailBuilder: (_) => widget.full,
                        showIcon: false,
                      ),
                    ),
                  ),
                  arrow(AppGlyphs.chevronDown, '下一段', _index + 1),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// 图表需要更多空间时展开同一份数据，复用应用已有的托盘弹层。
class InsightDetailButton extends StatelessWidget {
  const InsightDetailButton({
    super.key,
    required this.label,
    required this.title,
    required this.detailBuilder,
    this.showIcon = true,
  });
  final String label;
  final String title;
  final WidgetBuilder detailBuilder;
  final bool showIcon;

  @override
  Widget build(BuildContext context) => CommonPopupBox(
    targetBuilder: (open) => ActionBubbleTarget(
      corner: 24,
      child: ElasticButton(
        child: Tooltip(
          message: '展开$title',
          child: TextButton.icon(
            onPressed: open,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(48, 48),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ).merge(ElasticPress.buttonStyle),
            icon: showIcon
                ? const GlyphIcon(AppGlyphs.openInFull, size: 18)
                : null,
            label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
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
