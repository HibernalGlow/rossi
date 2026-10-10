import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/search/method/on_search.dart';
import 'package:zephyr/page/search/model/search_history_entry.dart';
import 'package:zephyr/plugin/utils/plugin_display_name.dart';
import 'package:zephyr/type/pipe.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/workspace/model/shelf_library_query.dart';
import 'package:zephyr/icons/icons.dart';

class HistoryWidget extends StatefulWidget {
  const HistoryWidget({super.key, this.aggregateMode = true});

  final bool aggregateMode;

  /// 点历史词条前调用，丢弃 [SearchBar] 里待触发的输入防抖。
  /// 不丢的话：输入框旧词的防抖在提交后才开火，把新词盖掉。
  static VoidCallback? _cancelPendingKeywordSync;

  static void registerPendingKeywordSyncCanceller(VoidCallback? canceller) {
    _cancelPendingKeywordSync = canceller;
  }

  static void cancelPendingKeywordSync() {
    _cancelPendingKeywordSync?.call();
  }

  @override
  State<HistoryWidget> createState() => _HistoryWidgetState();
}

class _HistoryWidgetState extends State<HistoryWidget> {
  bool _isNewestFirst = true;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final globalSettingCubit = context.watch<GlobalSettingCubit>();
    final globalSettingState = globalSettingCubit.state;
    final history = globalSettingState.searchHistory;
    final groupBySource = globalSettingState.searchHistoryGroupBySource;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            children: [
              Text(
                t.search.history,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),

              if (history.isNotEmpty) ...[
                // 分组开关就地给一颗：它是「这一屏怎么看」的开关，藏在设置页里
                // 用户找不到，而它改的又确实是持久设置（同一份字段，见设置页
                // 「搜索历史按插件分时间线」）。
                IconButton(
                  icon: GlyphIcon(
                    groupBySource
                        ? AppGlyphs.viewAgenda
                        : AppGlyphs.layoutList,
                    size: 20,
                  ),
                  color: groupBySource
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  tooltip: groupBySource
                      ? t.search.groupByPluginTooltipOn
                      : t.search.groupByPluginTooltipOff,
                  onPressed: () => globalSettingCubit.updateState(
                    (current) => current.copyWith(
                      searchHistoryGroupBySource:
                          !current.searchHistoryGroupBySource,
                    ),
                  ),
                ),

                // 排序按钮
                _buildSortButton(),

                IconButton(
                  icon: const GlyphIcon(AppGlyphs.delete, size: 20),
                  tooltip: t.search.clearHistory,
                  color: colorScheme.onSurfaceVariant,
                  onPressed: _resetHistory,
                ),
              ],
            ],
          ),
        ),

        // --- 3. 历史记录内容区域 ---
        Expanded(
          child: history.isEmpty
              ? _buildEmpty()
              : _buildHistoryList(history, groupBySource: groupBySource),
        ),
      ],
    );
  }

  Widget _buildSortButton() {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: _isNewestFirst ? t.search.newestFirst : t.search.oldestFirst,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 36),
        ),
        icon: GlyphIcon(
          _isNewestFirst ? AppGlyphs.history : AppGlyphs.history, // 图标随状态变
          size: 18,
          color: colorScheme.primary,
        ),
        label: Text(
          _isNewestFirst ? t.search.descending : t.search.ascending,
          style: TextStyle(fontSize: 12, color: colorScheme.primary),
        ),
        onPressed: () {
          setState(() {
            _isNewestFirst = !_isNewestFirst;
          });
        },
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GlyphIcon(
            AppGlyphs.search,
            size: 64,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 16),
          Text(
            t.search.noHistory,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList(
    List<SearchHistoryEntry> history, {
    required bool groupBySource,
  }) {
    final ordered = _isNewestFirst ? history : history.reversed.toList();

    if (!groupBySource) {
      // 一条时间线。同一个词在几个插件下各有一条记录时只留最近那条，
      // 否则这里会看见并排的重复胶囊 —— 但删的时候仍按记录本身删，
      // 不误伤另一个插件下的同名记录。
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: 12.0,
            runSpacing: 12.0,
            alignment: WrapAlignment.start,
            children: [
              for (final entry in distinctSearchHistoryByKeyword(ordered))
                _buildChip(entry),
            ],
          ),
        ),
      );
    }

    // 按插件分时间线：桶的先后就是各插件最近一次搜索的先后。
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        for (final group in groupSearchHistoryBySource(ordered)) ...[
          _buildGroupHeader(group.source),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 12.0,
              runSpacing: 12.0,
              alignment: WrapAlignment.start,
              children: [
                for (final keyword in group.keywords)
                  _buildChip(
                    SearchHistoryEntry(keyword: keyword, source: group.source),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGroupHeader(String source) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          GlyphIcon(
            _groupIcon(source),
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _groupLabel(source),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Glyph _groupIcon(String source) {
    if (source == kAggregateSearchSource) return AppGlyphs.globe;
    if (source.isEmpty) return AppGlyphs.info;
    return AppGlyphs.puzzle;
  }

  /// 组标题：插件名解析走书签/历史那一套（一次取全表，别每行问一遍数据库）。
  String _groupLabel(String source) {
    if (source == kAggregateSearchSource) return t.search.historyGroupAggregate;
    if (source.isEmpty) return t.search.historyGroupUncategorized;
    final name = shelfPluginName(pluginDisplayNames(), source);
    if (name != null) return name.let(convertChineseForDisplay);
    // 认不出名字就只留 uuid 前 8 位：整串 36 个字符会吃掉行宽，认前缀够区分
    // 两个插件了。与 `shelfSourceLabel` 同一退路，但那里把 id 大写，这里不大写。
    return source.length <= 8 ? source : source.substring(0, 8);
  }

  Widget _buildChip(SearchHistoryEntry entry) {
    final theme = Theme.of(context);

    return GestureDetector(
      onLongPress: () => _deleteSingle(entry),
      child: InputChip(
        label: Text(entry.keyword),
        labelStyle: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        side: BorderSide(color: theme.colorScheme.outlineVariant, width: 1.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
        onPressed: () {
          HistoryWidget.cancelPendingKeywordSync();
          onSearch(context, entry.keyword, aggregateMode: widget.aggregateMode);
        },
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  /// 长按删的是「这个词 + 这个来源」这一对。
  ///
  /// 不能只按词删：同一个词在两个插件下各有一条，只按词删会把另一条一起删掉，
  /// 而且老代码用 `List.remove` 只删得掉第一条。
  void _deleteSingle(SearchHistoryEntry entry) {
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    final List<SearchHistoryEntry> newHistory = List.from(
      globalSettingCubit.state.searchHistory,
    )..removeWhere((item) => item == entry);
    globalSettingCubit.updateState(
      (current) => current.copyWith(searchHistory: newHistory),
    );
  }

  void _resetHistory() {
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    globalSettingCubit.resetState(
      (current, defaults) =>
          current.copyWith(searchHistory: defaults.searchHistory),
    );
  }
}
