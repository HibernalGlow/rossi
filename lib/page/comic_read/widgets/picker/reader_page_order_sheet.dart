import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/comic_read/cubit/reader_page_order_cubit.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/model/normal_comic_ep_info.dart';
import 'package:zephyr/page/comic_read/model/reader_page_order.dart';

/// 本章页面的手动排序表。
///
/// 返回「显示位置 → 源下标」的排列；用户取消时返回 `null`。
///
/// 起点是**当前画面上看到的顺序**（而不是图源顺序）：用户通常是在倒序或自然序
/// 之下想「就把这两页换一下」，从原样顺序起步会让这一次改动变成整章重排。
Future<List<int>?> showReaderPageOrderSheet({
  required BuildContext context,
  required NormalComicEpInfo epInfo,
}) {
  final orderCubit = context.read<ReaderPageOrderCubit>();
  final mode = context
      .read<GlobalSettingCubit>()
      .state
      .readSetting
      .readerPageOrderMode;
  final seed = orderCubit.resolveOrder(
    chapterId: epInfo.epId,
    mode: mode,
    docs: epInfo.docs,
  );

  return showModalBottomSheet<List<int>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) =>
        _ReaderPageOrderSheet(epInfo: epInfo, initialOrder: seed),
  );
}

class _ReaderPageOrderSheet extends StatefulWidget {
  const _ReaderPageOrderSheet({
    required this.epInfo,
    required this.initialOrder,
  });

  final NormalComicEpInfo epInfo;
  final List<int> initialOrder;

  @override
  State<_ReaderPageOrderSheet> createState() => _ReaderPageOrderSheetState();
}

class _ReaderPageOrderSheetState extends State<_ReaderPageOrderSheet> {
  late List<int> _order = List<int>.of(widget.initialOrder);

  /// 用户是否真的动过 —— 没动过时「应用」按下去不该产生一次跳转。
  bool _dirty = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final docs = widget.epInfo.docs;
    final height = MediaQuery.sizeOf(context).height * 0.72;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '手动页序 · ${widget.epInfo.epName}',
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '拖动调整显示顺序；应用后画面仍停在当前这一页',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: _dirty
                      ? () => Navigator.of(
                          context,
                        ).pop(List<int>.unmodifiable(_order))
                      : null,
                  child: const Text('应用'),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: theme.colorScheme.outlineVariant,
          ),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: _order.length,
              onReorder: (oldIndex, newIndex) => setState(() {
                _order = readerMoveInOrder(_order, oldIndex, newIndex);
                _dirty = true;
              }),
              itemBuilder: (context, position) {
                final sourceIndex = _order[position];
                final doc = sourceIndex < docs.length
                    ? docs[sourceIndex]
                    : null;
                return _PageOrderRow(
                  key: ValueKey<int>(sourceIndex),
                  position: position,
                  doc: doc,
                  sourceIndex: sourceIndex,
                  total: _order.length,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PageOrderRow extends StatelessWidget {
  const _PageOrderRow({
    super.key,
    required this.position,
    required this.doc,
    required this.sourceIndex,
    required this.total,
  });

  final int position;
  final Doc? doc;
  final int sourceIndex;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = doc == null
        ? ''
        : (doc!.originalName.isNotEmpty ? doc!.originalName : doc!.path);

    return ListTile(
      dense: true,
      leading: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${position + 1}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSecondaryContainer,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
      title: Text(
        name.isEmpty ? '第 ${sourceIndex + 1} 页' : name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
      // 源下标是这一行唯一能说明「它原本是哪一页」的东西：只看名字的话，
      // 图源给的名字本身就可能是乱序的，用户分不清自己拖的是同一页。
      subtitle: Text(
        '源第 ${sourceIndex + 1} / $total 页',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: ReorderableDragStartListener(
        index: position,
        child: const GlyphIcon(AppGlyphs.dragHandle),
      ),
    );
  }
}
