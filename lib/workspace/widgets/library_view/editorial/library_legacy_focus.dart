import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_inline_expansion.dart';

/// 传统列表/网格同样能多项原位展开，业务与缓存由共享宿主管理。
class LibraryLegacyFocus extends StatelessWidget {
  const LibraryLegacyFocus({
    super.key,
    required this.count,
    required this.itemBuilder,
    this.columns = 1,
    this.extent,
    this.details = const {},
    this.header,
    this.padding = EdgeInsets.zero,
    this.footer,
    this.physics,
    this.controller,
    this.shrinkWrap = false,
  });
  final ScrollController? controller;
  final int count;
  final int columns;
  final double? extent;
  final Map<int, Widget> details;
  final Widget? header;
  final EdgeInsets padding;
  final Widget? footer;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final IndexedWidgetBuilder itemBuilder;
  @override
  Widget build(BuildContext context) {
    final list = ListView.builder(
      controller: controller,
      primary: false,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : physics,
      shrinkWrap: shrinkWrap,
      padding: padding,
      itemCount: (count / columns).ceil() + (footer == null ? 0 : 1),
      itemBuilder: (context, row) {
        if (row == (count / columns).ceil()) return footer!;
        final start = row * columns;
        final end = math.min(start + columns, count);
        Widget items;
        if (columns == 1 && extent == null) {
          items = itemBuilder(context, start);
        } else {
          items = SizedBox(
            height: extent,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = start; i < end; i++) ...[
                  if (i > start) const SizedBox(width: 6),
                  Expanded(child: itemBuilder(context, i)),
                ],
                for (var i = end; i < start + columns; i++)
                  const Expanded(child: SizedBox.shrink()),
              ],
            ),
          );
        }
        final rowDetails = [for (var i = start; i < end; i++) ?details[i]];
        return LibraryDetailRetention(
          keep: rowDetails.isNotEmpty,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [items, ...rowDetails],
            ),
          ),
        );
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?header,
        if (shrinkWrap) list else Expanded(child: list),
      ],
    );
  }
}
