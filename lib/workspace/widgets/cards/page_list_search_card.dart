import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/search/search_history_field.dart';
import 'package:zephyr/widgets/search/search_history_store.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/widgets/cards/expressive_widgets.dart';
import 'package:zephyr/workspace/widgets/cards/page_list_panel_controller.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation_button.dart';

/// 页面导航面板的「搜索与视图控制栏」MD3 无标题栏小组件。
///
/// - **日常展开态**：紧凑展示搜索框、跟随阅读进度按钮、展墙排版设置与视图切换；
/// - **日常折叠态**：缩成一颗搜索胶囊（显示当前搜索词或视图模式）；
/// - **编辑模式态**：出现拖拽手柄与尺寸/布局控制，支持在面板内任意移动位置。
class PageListSearchCard extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final bool isStandalone;
  final PageListPanelController? controller;

  const PageListSearchCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.isStandalone = false,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = controller ?? PageListPanelController.instance;

    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final bar = PageListSearchToolbar(controller: ctrl);
        if (isStandalone) {
          return bar;
        }
        return CollapsibleCard(
          cardId: WorkspaceCardRegistry.pageListSearch,
          title: t.workspace.searchField,
          icon: AppGlyphs.search,
          expressive: true,
          headerless: true,
          scrollContent: false,
          margin: EdgeInsets.zero,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          isExpanded: isExpanded,
          onToggle: onToggle,
          onMoveUp: onMoveUp,
          onMoveDown: onMoveDown,
          onHide: onHide,
          trailing: ExpressiveStatusPill(
            text: ctrl.searchQuery.isEmpty
                ? ctrl.viewModeLabel
                : t.workspace.filteringBy(query: ctrl.searchQuery),
            compact: true,
            dot: false,
            tone: ctrl.searchQuery.isEmpty
                ? ExpressiveTone.neutral
                : ExpressiveTone.primary,
          ),
          collapsedChild: Text(
            ctrl.searchQuery.isEmpty
                ? t.workspace.searchPageOrFileName
                : t.workspace.filteringBy(query: ctrl.searchQuery),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          child: Align(alignment: Alignment.centerLeft, child: bar),
        );
      },
    );
  }
}

/// 搜索框 + 跟随阅读进度 + 展墙设置 + 视图切换工具条（供小组件与 standalone 复用）。
class PageListSearchToolbar extends StatelessWidget {
  final PageListPanelController controller;

  const PageListSearchToolbar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 32,
              child: SearchHistoryField(
                history: SearchHistoryStore.local('reader-pages'),
                controller: controller.searchController,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: t.workspace.searchPageOrFileName,
                  hintStyle: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  prefixIcon: const GlyphIcon(AppGlyphs.search, size: 16),
                  contentPadding: EdgeInsets.zero,
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            tooltip: controller.followProgress
                ? t.workspace.followingProgress
                : t.workspace.followProgressPaused,
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: controller.followProgress
                  ? theme.colorScheme.secondaryContainer
                  : null,
              foregroundColor: controller.followProgress
                  ? theme.colorScheme.onSecondaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
            onPressed: controller.toggleFollowProgress,
            icon: const GlyphIcon(AppGlyphs.target),
          ),
          LibraryPresentationButton(canvasKey: controller.canvasKey),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            tooltip: t.workspace.viewModeLabel,
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: controller.cycleViewMode,
            icon: GlyphIcon(controller.viewModeIcon),
          ),
        ],
      ),
    );
  }
}
