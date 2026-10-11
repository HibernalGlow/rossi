import 'package:zephyr/widgets/control_shape.dart';
import 'package:zephyr/widgets/spring_lens/spring_choice_bar.dart';
// 书架筛选弹层（顶栏那颗滑块钮弹出来的那一块）。
//
// 形态交给 [`PopupPanel`]：宽屏是从按钮飞出来的托盘卡片，窄屏铺满整屏，
// 两档共用同一段弹簧动画。这里只负责**内容**与**选择状态** —— 两条外壳
// 读的是同一份状态，所以换个尺寸不会换出一套不一样的选择逻辑。
//
// 结果走 `Navigator.pop(BookshelfFilterResult)` 带出去，由页面落账；
// 面板自己不认识 `BookshelfSearchCubit`（它住在根路由里，改状态该由页面在
// 自己的 context 里做）。

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/bookshelf/models/shelf_page_mode.dart';
import 'package:zephyr/widgets/popup_panel.dart';

/// 一个可选图源：`pluginId` 是落账用的键，`title` 是画给人看的。
class FilterSourceOption {
  const FilterSourceOption({required this.pluginId, required this.title});

  final String pluginId;
  final String title;
}

/// 一次筛选的结果。取消（`pop()` 不带值）不会产生它 —— 页面据此区分
/// 「用户没动」与「用户把图源全取消勾选了」。
class BookshelfFilterResult {
  const BookshelfFilterResult({required this.sort, required this.sources});

  final String sort;
  final Set<String> sources;
}

class BookshelfFilterPanel extends StatefulWidget {
  const BookshelfFilterPanel({
    super.key,
    required this.mode,
    required this.initialSort,
    required this.initialSources,
    required this.sourceOptions,
  });

  final ShelfPageMode mode;
  final String initialSort;
  final Set<String> initialSources;
  final List<FilterSourceOption> sourceOptions;

  @override
  State<BookshelfFilterPanel> createState() => _BookshelfFilterPanelState();
}

class _BookshelfFilterPanelState extends State<BookshelfFilterPanel> {
  late String _selectedSort;
  late Set<String> _selectedSources;

  bool get _isFavoriteMode => widget.mode == ShelfPageMode.favorite;
  bool get _isDownloadMode => widget.mode == ShelfPageMode.download;

  @override
  void initState() {
    super.initState();
    _selectedSort = widget.initialSort;
    _selectedSources = Set<String>.from(widget.initialSources);
  }

  @override
  Widget build(BuildContext context) {
    return PopupPanel(
      title: Text(t.bookshelf.filter),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sortSection(context),
          const SizedBox(height: 16),
          _sourceSection(context),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(shape: ControlShape.rounded),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.common.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(shape: ControlShape.rounded),
          onPressed: () => Navigator.of(context).pop(
            BookshelfFilterResult(
              sort: _selectedSort,
              sources: _selectedSources,
            ),
          ),
          child: Text(t.common.apply),
        ),
      ],
    );
  }

  Widget _sortSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.bookshelf.sort, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SpringChoiceBar<String>(
          value: _selectedSort,
          onChanged: (value) => setState(() => _selectedSort = value),
          options: [
            (value: 'dd', label: t.bookshelf.sortDesc),
            (value: 'da', label: t.bookshelf.sortAsc),
            if (_isFavoriteMode || _isDownloadMode) ...[
              (value: 'vd', label: t.bookshelf.viewSortDesc),
              (value: 'va', label: t.bookshelf.viewSortAsc),
            ],
          ],
        ),
      ],
    );
  }

  Widget _sourceSection(BuildContext context) {
    final isAllSelected =
        _selectedSources.length == widget.sourceOptions.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              t.bookshelf.source,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(width: 8),
            TextButton(
              style: TextButton.styleFrom(shape: ControlShape.rounded),
              onPressed: () => setState(() {
                if (isAllSelected) {
                  _selectedSources.clear();
                } else {
                  _selectedSources = widget.sourceOptions
                      .map((source) => source.pluginId)
                      .toSet();
                }
              }),
              child: Text(
                isAllSelected ? t.bookshelf.deselectAll : t.common.selectAll,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final source in widget.sourceOptions)
              FilterChip(
                shape: ControlShape.rounded,
                showCheckmark: false,
                label: Text(source.title),
                selected: _selectedSources.contains(source.pluginId),
                onSelected: (selected) => setState(() {
                  if (selected) {
                    _selectedSources.add(source.pluginId);
                  } else {
                    _selectedSources.remove(source.pluginId);
                  }
                }),
              ),
          ],
        ),
      ],
    );
  }
}
