import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_workhole.dart';
import 'package:zephyr/workspace/widgets/panels/lane_panel_host.dart';
import 'package:zephyr/workspace/widgets/panels/panel_tab_strip.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// Workhole 的内容浮层。
///
/// Workhole 只负责呈现和操作边缘内容，内容本身仍由 [LanePanelHost] 提供，
/// 因此书架、图源、工具和卡片布局与泳道模式保持同一份状态。
class WorkholePanel extends StatelessWidget {
  const WorkholePanel({
    super.key,
    required this.side,
    required this.size,
    required this.onClose,
    required this.onSizeChanged,
    required this.onResetSize,
    this.debugContent,
  });

  final WorkspacePanelSide side;
  final WorkspaceWorkholeSize size;
  final VoidCallback onClose;
  final ValueChanged<WorkspaceWorkholeSize> onSizeChanged;
  final VoidCallback onResetSize;

  @visibleForTesting
  final Widget? debugContent;

  bool get isLeft => side == WorkspacePanelSide.left;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = isLeft
        ? t.workspace.resourceWorkhole
        : t.workspace.readingWorkhole;
    final subtitle = isLeft
        ? t.workspace.shelfFavoriteFiles
        : t.workspace.sourcesToolsOcr;
    final icon = isLeft ? AppGlyphs.openBook : AppGlyphs.sliders;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 30,
            spreadRadius: 1,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            _WorkholeHeader(
              icon: icon,
              title: title,
              subtitle: subtitle,
              onClose: onClose,
            ),
            Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.32,
                ),
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.32,
                    ),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: PanelTabStrip(side: side, maxWidth: double.infinity),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    size.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: debugContent ?? LanePanelHost(side: side)),
            _WorkholeFooter(
              size: size,
              onSizeChanged: onSizeChanged,
              onResetSize: onResetSize,
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkholeHeader extends StatelessWidget {
  const _WorkholeHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final Glyph icon;
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 9, 10, 8),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: GlyphIcon(
                icon,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const GlyphIcon(AppGlyphs.close, size: 18),
              tooltip: t.workspace.closeWorkhole,
              onPressed: onClose,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkholeFooter extends StatelessWidget {
  const _WorkholeFooter({
    required this.size,
    required this.onSizeChanged,
    required this.onResetSize,
  });

  final WorkspaceWorkholeSize size;
  final ValueChanged<WorkspaceWorkholeSize> onSizeChanged;
  final VoidCallback onResetSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.fromLTRB(12, 5, 10, 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.26,
        ),
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.28),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              primary: false,
              child: Row(
                children: [
                  Text(
                    t.workspace.workholeSize,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  for (final option in WorkspaceWorkholeSize.values.where(
                    (value) => value != WorkspaceWorkholeSize.custom,
                  )) ...[
                    _SizeButton(
                      size: option,
                      selected: option == size,
                      onPressed: () => onSizeChanged(option),
                    ),
                    const SizedBox(width: 4),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            icon: const GlyphIcon(AppGlyphs.resize, size: 16),
            tooltip: t.workspace.restoreDefaultSize,
            onPressed: onResetSize,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _SizeButton extends StatelessWidget {
  const _SizeButton({
    required this.size,
    required this.selected,
    required this.onPressed,
  });

  final WorkspaceWorkholeSize size;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.55)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Text(
          size.label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

extension on WorkspaceWorkholeSize {
  String get label => switch (this) {
    WorkspaceWorkholeSize.peek => t.workspace.peep,
    WorkspaceWorkholeSize.workbench => '工作台',
    WorkspaceWorkholeSize.takeover => t.workspace.takeOver,
    WorkspaceWorkholeSize.custom => '自定义',
  };
}
