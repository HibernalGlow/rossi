import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/setting/common/setting_detail_scope.dart';
import 'package:zephyr/page/setting/common/setting_scroll_spy.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:zephyr/widgets/motion/retained_panel_switcher.dart';
import 'package:zephyr/widgets/search/search_history_field.dart';
import 'package:zephyr/widgets/search/search_history_store.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';

export 'package:zephyr/page/setting/common/setting_detail_scope.dart'
    show SettingSectionSpec;

/// 响应式断点档位：
/// - [compact]（移动端 `< 680px`）：单栏卡片总览入口 + 搜索直达子项 + 详情页内吸顶目录胶囊；
/// - [medium]（平板端 `680px–1039px`）：紧凑双栏主从视图 + 可折叠侧栏子树 + Scroll Spy；
/// - [expanded]（桌面端 `>= 1040px`）：宽敞双栏主从视图 + 可折叠侧栏子树 + Scroll Spy。
enum SettingResponsiveTier { compact, medium, expanded }

/// 入口只描述展示、页内二级分组元数据与挂点，不维护第二份设置值或导航栈。
class SettingDestination {
  const SettingDestination({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onOpen,
    this.detailBuilder,
    this.sections = const <SettingSectionSpec>[],
  });

  final String id;
  final String title;
  final String subtitle;
  final Glyph icon;
  final VoidCallback onOpen;

  /// 没有详情挂点的入口（阅读面板、有未保存编辑的页面）沿用原打开方式。
  final WidgetBuilder? detailBuilder;

  /// 该设置页内部的二级分组列表：用于侧栏展开子树、Scroll Spy 高亮同步与搜索直达。
  final List<SettingSectionSpec> sections;
}

class SettingDestinationGroup {
  const SettingDestinationGroup({required this.title, required this.entries});

  final String title;
  final List<SettingDestination> entries;
}

/// 按设置实际可用宽度决定响应式形态（移动单栏 / 平板紧凑双栏 / 桌面宽双栏），
/// 集成可折叠侧栏子树、基于 `scroll_spy` 的阅读位置同步与祖先路径自动展开搜索。
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
  final SettingDetailBridge _detailBridge = SettingDetailBridge();

  String? _selectedId;
  String _query = '';
  final Set<String> _visited = {};

  /// 非搜索状态下由用户受控展开的一级设置项 ID 集合。
  /// 搜索期间不覆写该集合，以便清空搜索框后完整恢复搜索前的展开状态。
  final Set<String> _expandedIds = {};

  /// 非搜索状态下被用户手动收起的顶层分类组标题集合。
  final Set<String> _collapsedGroups = {};
  bool _seededInitialExpand = false;

  @override
  void dispose() {
    _search.dispose();
    _detailBridge.dispose();
    super.dispose();
  }

  SettingResponsiveTier _resolveTier(double maxWidth, double scale) {
    final clampedScale = scale.clamp(1.0, 1.4);
    if (maxWidth >= 1040 * clampedScale) {
      return SettingResponsiveTier.expanded;
    }
    if (maxWidth >= 680 * clampedScale) {
      return SettingResponsiveTier.medium;
    }
    return SettingResponsiveTier.compact;
  }

  void _open(SettingDestination entry, bool wide) {
    if (wide && entry.detailBuilder != null) {
      HapticFeedback.lightImpact();
      setState(() {
        if (_selectedId == entry.id) {
          // 再次点击当前已选中的一级分类时，切换其子树展开/收起状态
          if (_expandedIds.contains(entry.id)) {
            _expandedIds.remove(entry.id);
          } else {
            _expandedIds.add(entry.id);
          }
        } else {
          _selectedId = entry.id;
          _expandedIds.add(entry.id);
        }
      });
    } else {
      HapticFeedback.lightImpact();
      entry.onOpen();
    }
  }

  void _toggleSubtree(SettingDestination entry) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_expandedIds.contains(entry.id)) {
        _expandedIds.remove(entry.id);
      } else {
        _expandedIds.add(entry.id);
      }
    });
  }

  void _toggleGroupCollapse(String groupTitle) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_collapsedGroups.contains(groupTitle)) {
        _collapsedGroups.remove(groupTitle);
      } else {
        _collapsedGroups.add(groupTitle);
      }
    });
  }

  void _openSection(
    SettingDestination entry,
    SettingSectionSpec section,
    bool wide,
  ) {
    HapticFeedback.lightImpact();
    if (wide && entry.detailBuilder != null) {
      setState(() {
        _selectedId = entry.id;
        _visited.add(entry.id);
        _expandedIds.add(entry.id);
      });
      _detailBridge.updateActiveSection(entry.id, section.id);
      requestSettingSectionJump(pageId: entry.id, sectionId: section.id);
    } else {
      requestSettingSectionJump(pageId: entry.id, sectionId: section.id);
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
        final tier = _resolveTier(constraints.maxWidth, scale);
        final wide = tier != SettingResponsiveTier.compact && selected != null;

        if (wide) {
          _visited.add(selected.id);
          if (!_seededInitialExpand) {
            _seededInitialExpand = true;
            _expandedIds.add(selected.id);
          }
        }

        final list = _categoryList(context, tier, wide, selected?.id);
        if (!wide) {
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 768),
              child: list,
            ),
          );
        }

        final isTablet = tier == SettingResponsiveTier.medium;
        final sidebarWidth = isTablet
            ? 276.0 * scale.clamp(1.0, 1.2)
            : 328.0 * scale.clamp(1.0, 1.3);
        final horizontalGap = isTablet ? 14.0 : 20.0;
        final outerPadding = isTablet
            ? const EdgeInsets.fromLTRB(12, 0, 12, 12)
            : const EdgeInsets.fromLTRB(16, 0, 16, 16);

        return Padding(
          padding: outerPadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: sidebarWidth, child: list),
              SizedBox(width: horizontalGap),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(isTablet ? 24 : 28),
                  child: ColoredBox(
                    color: theme.colorScheme.surface,
                    child: RetainedPanelSwitcher(
                      selectedId: selected.id,
                      children: {
                        for (final entry in details)
                          if (_visited.contains(entry.id))
                            entry.id: SettingDetailScope(
                              pageId: entry.id,
                              declaredSections: entry.sections,
                              bridge: _detailBridge,
                              child: Builder(
                                builder: (detailContext) =>
                                    entry.detailBuilder!(detailContext),
                              ),
                            ),
                      },
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

  Widget _categoryList(
    BuildContext context,
    SettingResponsiveTier tier,
    bool wide,
    String? selectedId,
  ) {
    final theme = Theme.of(context);
    final query = _query.trim().toLowerCase();
    final isSearching = query.isNotEmpty;

    final filteredGroups = <_FilteredGroup>[];
    for (final group in widget.groups) {
      final filteredEntries = <_FilteredEntry>[];
      for (final entry in group.entries) {
        final runtimeSections =
            _detailBridge.sectionsNotifier(entry.id).value.isNotEmpty
            ? _detailBridge.sectionsNotifier(entry.id).value
            : entry.sections;

        if (!isSearching) {
          filteredEntries.add(
            _FilteredEntry(
              destination: entry,
              visibleSections: runtimeSections,
              matchedByChild: false,
            ),
          );
          continue;
        }

        final directMatch = '${group.title} ${entry.title} ${entry.subtitle}'
            .toLowerCase()
            .contains(query);
        final matchingSections = runtimeSections
            .where((section) => section.matchesQuery(query))
            .toList();

        if (directMatch || matchingSections.isNotEmpty) {
          filteredEntries.add(
            _FilteredEntry(
              destination: entry,
              // 若命中了具体子分组则展示命中的子分组；若直接命中父级且子分组存在，也展开全部子分组供直达
              visibleSections: matchingSections.isNotEmpty
                  ? matchingSections
                  : runtimeSections,
              matchedByChild: matchingSections.isNotEmpty,
            ),
          );
        }
      }
      if (filteredEntries.isNotEmpty) {
        filteredGroups.add(
          _FilteredGroup(title: group.title, entries: filteredEntries),
        );
      }
    }

    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: ActionBubbleRegion(
        child: ListView(
          key: const PageStorageKey('setting-categories'),
          padding: EdgeInsets.fromLTRB(wide ? 0 : 16, 8, wide ? 0 : 16, 24),
          children: [
            if (!wide && !isSearching)
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
            if (filteredGroups.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  t.settings.noMatchingCategories,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            for (final group in filteredGroups) ...[
              _buildGroupHeader(
                context,
                title: group.title,
                isCollapsed:
                    !isSearching && _collapsedGroups.contains(group.title),
              ),
              ExpressiveReveal(
                visible: isSearching || !_collapsedGroups.contains(group.title),
                child: M3EList(
                  key: ValueKey(group.title),
                  itemCount: group.entries.length,
                  outerRadius: 24,
                  innerRadius: 4,
                  gap: 2,
                  // 让 M3EListItem 保留行内留白；列表 padding 会接管并关闭它。
                  color: theme.colorScheme.surfaceContainerLow,
                  colorBuilder: (index) {
                    final entry = group.entries[index].destination;
                    return wide && entry.id == selectedId
                        ? theme.colorScheme.secondaryContainer
                        : null;
                  },
                  borderRadiusBuilder: (index, _) {
                    final entry = group.entries[index].destination;
                    return wide && entry.id == selectedId
                        ? BorderRadius.circular(28)
                        : null;
                  },
                  onTap: (index) =>
                      _open(group.entries[index].destination, wide),
                  semanticLabelBuilder: (index) {
                    final entry = group.entries[index].destination;
                    return '${entry.title}, ${entry.subtitle}';
                  },
                  itemBuilder: (context, index) {
                    final item = group.entries[index];
                    final entry = item.destination;
                    final selected = wide && entry.id == selectedId;
                    return _buildDestinationItem(
                      context,
                      item: item,
                      wide: wide,
                      selected: selected,
                      isSearching: isSearching,
                      query: query,
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGroupHeader(
    BuildContext context, {
    required String title,
    required bool isCollapsed,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      key: ValueKey('setting-group-header:$title'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleGroupCollapse(title),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 24, 8, 10),
        child: Semantics(
          header: true,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              AnimatedRotation(
                turns: isCollapsed ? -0.25 : 0.0,
                duration: ExpressiveMotion.duration(
                  context,
                  ExpressiveMotion.spatialDuration,
                ),
                curve: ExpressiveMotion.spatialCurve,
                child: GlyphIcon(
                  AppGlyphs.chevronDown,
                  size: 16,
                  color: theme.colorScheme.primary.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDestinationItem(
    BuildContext context, {
    required _FilteredEntry item,
    required bool wide,
    required bool selected,
    required bool isSearching,
    required String query,
  }) {
    final entry = item.destination;
    return ValueListenableBuilder<List<SettingSectionSpec>>(
      valueListenable: _detailBridge.sectionsNotifier(entry.id),
      builder: (context, liveSections, _) {
        final allSections = liveSections.isNotEmpty
            ? liveSections
            : entry.sections;
        final visibleSections = isSearching
            ? item.visibleSections
            : allSections;
        final hasSubtree = visibleSections.isNotEmpty;
        // 搜索命中时自动展开所有匹配项的祖先子树；清空搜索后恢复 _expandedIds 的受控状态
        final isExpanded =
            hasSubtree &&
            (isSearching
                ? (item.matchedByChild || selected)
                : _expandedIds.contains(entry.id));

        final trailingIcon = GlyphIcon(
          entry.detailBuilder == null && wide
              ? AppGlyphs.openInFull
              : AppGlyphs.chevronForward,
          size: 20,
        );

        final trailing = hasSubtree
            ? GestureDetector(
                key: ValueKey('setting-subtree-toggle:${entry.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _toggleSubtree(entry),
                child: AnimatedRotation(
                  turns: isExpanded ? 0.25 : 0.0,
                  duration: ExpressiveMotion.duration(
                    context,
                    ExpressiveMotion.spatialDuration,
                  ),
                  curve: ExpressiveMotion.spatialCurve,
                  child: trailingIcon,
                ),
              )
            : trailingIcon;

        final rowTile = Semantics(
          selected: wide && entry.detailBuilder != null ? selected : null,
          child: ActionBubbleTarget(
            corner: 24,
            observeFocus: false,
            enabled: !eInkInstantRoutes,
            child: ElasticPress(
              enabled:
                  !eInkInstantRoutes &&
                  !MediaQuery.disableAnimationsOf(context),
              child: M3EListItem(
                headline: entry.title,
                supportingText: entry.subtitle,
                selected: selected,
                leading: SettingIconBadge(icon: entry.icon, selected: selected),
                trailing: trailing,
              ),
            ),
          ),
        );

        if (!hasSubtree) {
          return rowTile;
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            rowTile,
            ExpressiveReveal(
              visible: isExpanded,
              child: ValueListenableBuilder<String?>(
                valueListenable: _detailBridge.activeSectionNotifier(entry.id),
                builder: (context, activeSectionId, _) {
                  final effectiveActiveId = selected
                      ? (activeSectionId ?? visibleSections.first.id)
                      : null;
                  return _SettingSubtreePanel(
                    parentId: entry.id,
                    parentSelected: selected,
                    sections: visibleSections,
                    activeSectionId: effectiveActiveId,
                    query: isSearching ? query : '',
                    onSelectSection: (section) =>
                        _openSection(entry, section, wide),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FilteredGroup {
  const _FilteredGroup({required this.title, required this.entries});

  final String title;
  final List<_FilteredEntry> entries;
}

class _FilteredEntry {
  const _FilteredEntry({
    required this.destination,
    required this.visibleSections,
    required this.matchedByChild,
  });

  final SettingDestination destination;
  final List<SettingSectionSpec> visibleSections;
  final bool matchedByChild;
}

/// 侧栏内嵌的可折叠二级设置子树面板：
/// 带左侧树形引导轨、当前 Scroll Spy 分组胶囊指示器与搜索命中关键词徽标。
class _SettingSubtreePanel extends StatelessWidget {
  const _SettingSubtreePanel({
    required this.parentId,
    required this.parentSelected,
    required this.sections,
    required this.activeSectionId,
    required this.query,
    required this.onSelectSection,
  });

  final String parentId;
  final bool parentSelected;
  final List<SettingSectionSpec> sections;
  final String? activeSectionId;
  final String query;
  final ValueChanged<SettingSectionSpec> onSelectSection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 12, 10),
        child: Container(
          key: ValueKey('setting-subtree:$parentId'),
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          decoration: BoxDecoration(
            color: parentSelected
                ? scheme.surface.withValues(alpha: 0.62)
                : scheme.surfaceContainerLowest.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(18),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 左侧树形层级连接线
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  child: Container(
                    width: 2.5,
                    decoration: BoxDecoration(
                      color: parentSelected
                          ? scheme.primary.withValues(alpha: 0.32)
                          : scheme.outlineVariant.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < sections.length; i++) ...[
                        if (i > 0) const SizedBox(height: 2),
                        _SettingSubtreeNode(
                          parentId: parentId,
                          section: sections[i],
                          isActive: sections[i].id == activeSectionId,
                          matchedKeyword: sections[i].matchedKeyword(query),
                          onTap: () => onSelectSection(sections[i]),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingSubtreeNode extends StatefulWidget {
  const _SettingSubtreeNode({
    required this.parentId,
    required this.section,
    required this.isActive,
    required this.matchedKeyword,
    required this.onTap,
  });

  final String parentId;
  final SettingSectionSpec section;
  final bool isActive;
  final String? matchedKeyword;
  final VoidCallback onTap;

  @override
  State<_SettingSubtreeNode> createState() => _SettingSubtreeNodeState();
}

class _SettingSubtreeNodeState extends State<_SettingSubtreeNode> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isActive = widget.isActive;
    // MD3 Expressive 形状层级与按压形变：选中态为胶囊形（999px），按压态微形变为圆角矩形
    final borderRadius = BorderRadius.circular(
      _pressed
          ? 10
          : isActive
          ? 999
          : 12,
    );

    return Semantics(
      selected: isActive,
      button: true,
      label: widget.section.title,
      child: ActionBubbleTarget(
        corner: 16,
        observeFocus: false,
        enabled: !eInkInstantRoutes,
        child: ElasticPress(
          enabled:
              !eInkInstantRoutes && !MediaQuery.disableAnimationsOf(context),
          child: AnimatedContainer(
            duration: ExpressiveMotion.duration(
              context,
              ExpressiveMotion.effectDuration,
            ),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: isActive ? scheme.primaryContainer : Colors.transparent,
              borderRadius: borderRadius,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: ValueKey(
                  'setting-subtree-node:${widget.parentId}:${widget.section.id}',
                ),
                borderRadius: borderRadius,
                onHighlightChanged: (v) {
                  if (_pressed != v) setState(() => _pressed = v);
                },
                onTap: widget.onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: ExpressiveMotion.duration(
                          context,
                          ExpressiveMotion.effectDuration,
                        ),
                        width: isActive ? 6 : 4,
                        height: isActive ? 16 : 4,
                        decoration: BoxDecoration(
                          color: isActive
                              ? scheme.primary
                              : scheme.outlineVariant,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (widget.section.icon != null) ...[
                        GlyphIcon(
                          widget.section.icon!,
                          size: 15,
                          color: isActive
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          widget.section.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isActive
                                ? scheme.onPrimaryContainer
                                : scheme.onSurface,
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (widget.matchedKeyword case final keyword?
                          when keyword.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: ShapeDecoration(
                              color: scheme.tertiaryContainer,
                              shape: const StadiumBorder(),
                            ),
                            child: Text(
                              keyword,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onTertiaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
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
    return AnimatedContainer(
      duration: ExpressiveMotion.duration(
        context,
        ExpressiveMotion.effectDuration,
      ),
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
