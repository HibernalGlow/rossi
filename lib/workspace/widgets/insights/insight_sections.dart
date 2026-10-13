import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/motion/retained_panel_switcher.dart';
import 'package:zephyr/workspace/widgets/card_header_actions.dart';
import 'package:zephyr/workspace/widgets/insights/insight_header_controls.dart';

export 'package:zephyr/workspace/widgets/insights/insight_header_controls.dart'
    show InsightDetailButton;

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
    this.dataRevision,
  });
  final List<String> labels;
  final List<Widget> sections;
  final Widget full;
  final double fullHeight;
  final String detailTitle;
  final String tinySummary;
  final Object? dataRevision;

  @override
  State<InsightSectionPager> createState() => _InsightSectionPagerState();
}

class _InsightSectionPagerState extends State<InsightSectionPager> {
  int _index = 0;

  void _select(int index) {
    HapticFeedback.lightImpact();
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final full =
          !bounds.hasBoundedHeight || bounds.maxHeight >= widget.fullHeight;
      final tiny = !full && bounds.maxHeight < 72 * scale;
      final paged = !full && !tiny;
      final body = full
          ? Align(alignment: Alignment.topLeft, child: widget.full)
          : tiny
          ? Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.tinySummary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          : RetainedPanelSwitcher(
              axis: Axis.vertical,
              selectedId: '$_index',
              children: {
                for (var i = 0; i < widget.sections.length; i++)
                  '$i': widget.sections[i],
              },
            );
      return CardHeaderActions(
        revision: (widget.dataRevision ?? widget.full, full, tiny, _index),
        actions: InsightPagerHeader(
          index: _index,
          labels: widget.labels,
          onPrevious: _index == 0 ? null : () => _select(_index - 1),
          onNext: _index == widget.sections.length - 1
              ? null
              : () => _select(_index + 1),
          title: widget.detailTitle,
          detailBuilder: (_) => widget.full,
          paged: paged,
        ),
        child: body,
      );
    },
  );
}
