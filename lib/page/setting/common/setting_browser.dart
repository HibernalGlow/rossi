import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/setting/common/setting_detail_scope.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/motion/retained_panel_switcher.dart';
import 'package:zephyr/widgets/search/search_history_field.dart';
import 'package:zephyr/widgets/search/search_history_store.dart';

/// 入口只描述展示与挂点，不维护第二份设置值或导航栈。
class SettingDestination {
  const SettingDestination({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onOpen,
    this.detailBuilder,
  });

  final String id;
  final String title;
  final String subtitle;
  final Glyph icon;
  final VoidCallback onOpen;

  /// 没有详情挂点的入口（阅读面板、有未保存编辑的页面）沿用原打开方式。
  final WidgetBuilder? detailBuilder;
}

class SettingDestinationGroup {
  const SettingDestinationGroup({required this.title, required this.entries});

  final String title;
  final List<SettingDestination> entries;
}

/// 按设置实际可用宽度决定单双栏，工作台里的窄面板也走单栏。
class SettingBrowser extends StatefulWidget {
  const SettingBrowser({
    super.key,
    required this.groups,
    required this.summary,
  });

  final List<SettingDestinationGroup> groups;
  final String summary;

  @override
  State<SettingBrowser> createState() => _SettingBrowserState();
}

class _SettingBrowserState extends State<SettingBrowser> {
  final TextEditingController _search = TextEditingController();
  String? _selectedId;
  String _query = '';
  final Set<String> _visited = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(SettingDestination entry, bool wide) {
    if (wide && entry.detailBuilder != null) {
      if (_selectedId == entry.id) return;
      HapticFeedback.lightImpact();
      setState(() => _selectedId = entry.id);
    } else {
      HapticFeedback.lightImpact();
      entry.onOpen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.groups.expand((group) => group.entries).toList();
    final details = entries.where((entry) => entry.detailBuilder != null);
    final selected =
        details.where((entry) => entry.id == _selectedId).firstOrNull ??
        details.firstOrNull;
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 放大字号时给分类与表单更多空间，避免刚到断点就把控件挤碎。
        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final wide =
            constraints.maxWidth >= 1000 * scale.clamp(1, 1.4) &&
            selected != null;
        if (wide) _visited.add(selected.id);
        final list = _categoryList(context, wide, selected?.id);
        if (!wide) {
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 768),
              child: list,
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 320 * scale.clamp(1, 1.3), child: list),
              const SizedBox(width: 20),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: ColoredBox(
                    color: theme.colorScheme.surface,
                    child: SettingDetailScope(
                      child: RetainedPanelSwitcher(
                        selectedId: selected.id,
                        children: {
                          for (final entry in details)
                            if (_visited.contains(entry.id))
                              entry.id: entry.detailBuilder!(context),
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _categoryList(BuildContext context, bool wide, String? selectedId) {
    final theme = Theme.of(context);
    final query = _query.trim().toLowerCase();
    final filtered = [
      for (final group in widget.groups)
        SettingDestinationGroup(
          title: group.title,
          entries: group.entries
              .where(
                (entry) => '${group.title} ${entry.title} ${entry.subtitle}'
                    .toLowerCase()
                    .contains(query),
              )
              .toList(),
        ),
    ];
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: ActionBubbleRegion(
        child: ListView(
          key: const PageStorageKey('setting-categories'),
          padding: EdgeInsets.fromLTRB(wide ? 0 : 16, 8, wide ? 0 : 16, 24),
          children: [
            if (!wide && query.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(28),
                      topRight: Radius.circular(28),
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(28),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GlyphIcon(
                        AppGlyphs.settings,
                        size: 32,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        t.settings.overviewSubtitle,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.summary,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            SearchHistoryField(
              history: SearchHistoryStore.local('settings-categories'),
              key: const ValueKey('settings-category-search'),
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: t.settings.searchCategories,
                prefixIcon: const Padding(
                  padding: EdgeInsets.all(12),
                  child: GlyphIcon(AppGlyphs.search),
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: t.common.clear,
                        icon: const GlyphIcon(AppGlyphs.close),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHigh,
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(28)),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (filtered.every((group) => group.entries.isEmpty))
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  t.settings.noMatchingCategories,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            for (final group in filtered)
              if (group.entries.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 24, 8, 10),
                  child: Semantics(
                    header: true,
                    child: Text(
                      group.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                M3EList(
                  key: ValueKey(group.title),
                  itemCount: group.entries.length,
                  outerRadius: 24,
                  innerRadius: 4,
                  gap: 2,
                  padding: EdgeInsets.zero,
                  color: theme.colorScheme.surfaceContainerLow,
                  colorBuilder: (index) =>
                      wide && group.entries[index].id == selectedId
                      ? theme.colorScheme.secondaryContainer
                      : null,
                  borderRadiusBuilder: (index, _) =>
                      wide && group.entries[index].id == selectedId
                      ? BorderRadius.circular(28)
                      : null,
                  onTap: (index) => _open(group.entries[index], wide),
                  semanticLabelBuilder: (index) =>
                      '${group.entries[index].title}, ${group.entries[index].subtitle}',
                  itemBuilder: (context, index) {
                    final entry = group.entries[index];
                    final selected = wide && entry.id == selectedId;
                    return Semantics(
                      selected: wide && entry.detailBuilder != null
                          ? selected
                          : null,
                      child: ActionBubbleTarget(
                        corner: 24,
                        enabled: !eInkInstantRoutes,
                        child: ElasticPress(
                          enabled:
                              !eInkInstantRoutes &&
                              !MediaQuery.disableAnimationsOf(context),
                          child: M3EListItem(
                            headline: entry.title,
                            supportingText: entry.subtitle,
                            selected: selected,
                            leading: SettingIconBadge(
                              icon: entry.icon,
                              selected: selected,
                            ),
                            trailing: GlyphIcon(
                              entry.detailBuilder == null && wide
                                  ? AppGlyphs.openInFull
                                  : AppGlyphs.chevronForward,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
          ],
        ),
      ),
    );
  }
}

class SettingIconBadge extends StatelessWidget {
  const SettingIconBadge({
    super.key,
    required this.icon,
    this.selected = false,
  });

  final Glyph icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: selected ? scheme.primary : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(selected ? 22 : 14),
      ),
      child: Center(
        child: GlyphIcon(
          icon,
          size: 24,
          color: selected ? scheme.onPrimary : scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
