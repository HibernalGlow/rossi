import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/setting/common/setting_group.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';

/// 只排列入口，功能页面与路由由宿主沿用应用已有实现。
enum WorkspaceTool {
  settings,
  appearance,
  reader,
  layout,
  downloads,
  sync,
  follow,
  changelog,
  about,
}

class WorkspaceToolsPanel extends StatelessWidget {
  const WorkspaceToolsPanel({
    super.key,
    required this.onOpen,
    required this.settingsSummary,
    this.updateCount = 0,
  });

  final ValueChanged<WorkspaceTool> onOpen;
  final String settingsSummary;
  final int updateCount;

  void _open(WorkspaceTool tool) {
    HapticFeedback.lightImpact();
    onOpen(tool);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
            final wide = constraints.maxWidth >= 720 * scale.clamp(1, 1.5);
            final settings = _settings(context);
            final tools = _tools(context);
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Theme(
                  data: theme.copyWith(
                    splashFactory: NoSplash.splashFactory,
                    highlightColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                  ),
                  child: SingleChildScrollView(
                    key: const PageStorageKey('workspace-tools-scroll'),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 6, child: settings),
                              const SizedBox(width: 24),
                              Expanded(flex: 5, child: tools),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [settings, tools],
                          ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _settings(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ActionBubbleRegion(
          child: ActionBubbleTarget(
            enabled: !eInkInstantRoutes,
            corner: 28,
            child: ElasticPress(
              enabled:
                  !eInkInstantRoutes &&
                  !MediaQuery.disableAnimationsOf(context),
              child: Material(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(28),
                child: InkWell(
                  key: const ValueKey('workspace-tool:settings'),
                  borderRadius: BorderRadius.circular(28),
                  overlayColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  onTap: () => _open(WorkspaceTool.settings),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        M3EShapeContainer(
                          kind: M3EShapeKind.cookie4Sided,
                          width: 48,
                          height: 48,
                          color: scheme.primary,
                          child: GlyphIcon(
                            AppGlyphs.settings,
                            color: scheme.onPrimary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.settings.globalTitle,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                settingsSummary,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        GlyphIcon(
                          AppGlyphs.chevronForward,
                          size: 20,
                          color: scheme.onPrimaryContainer,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ActionBubbleRegion(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _shortcut(
                context,
                WorkspaceTool.appearance,
                t.settings.appearance,
                AppGlyphs.palette,
              ),
              _shortcut(
                context,
                WorkspaceTool.reader,
                t.reader.settings,
                AppGlyphs.book,
              ),
              _shortcut(
                context,
                WorkspaceTool.layout,
                t.settings.workspaceLayout,
                AppGlyphs.dashboard,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _shortcut(
    BuildContext context,
    WorkspaceTool tool,
    String label,
    Glyph icon,
  ) => ActionBubbleTarget(
    enabled: !eInkInstantRoutes,
    corner: 24,
    child: ElasticPress(
      enabled: !eInkInstantRoutes && !MediaQuery.disableAnimationsOf(context),
      child: FilledButton.tonal(
        key: ValueKey('workspace-tool:${tool.name}'),
        style:
            FilledButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: const StadiumBorder(),
                )
                .merge(ElasticPress.buttonStyle)
                .copyWith(
                  overlayColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                ),
        onPressed: () => _open(tool),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlyphIcon(icon, size: 18),
            const SizedBox(width: 8),
            Flexible(child: Text(label)),
          ],
        ),
      ),
    ),
  );

  Widget _tools(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SettingGroup(
        title: t.more.common,
        children: [
          _entry(
            WorkspaceTool.downloads,
            t.more.downloadTasks,
            AppGlyphs.download,
          ),
          _entry(WorkspaceTool.sync, t.more.sync, AppGlyphs.sync),
          _entry(
            WorkspaceTool.follow,
            t.more.comicFollow,
            AppGlyphs.bell,
            badge: updateCount > 0
                ? Semantics(
                    label: t.comicFollow.updateBodyMultiple(count: updateCount),
                    excludeSemantics: true,
                    child: Badge(
                      label: Text(updateCount > 99 ? '99+' : '$updateCount'),
                    ),
                  )
                : null,
          ),
        ],
      ),
      SettingGroup(
        title: t.more.others,
        children: [
          _entry(WorkspaceTool.changelog, t.more.changelog, AppGlyphs.history),
          _entry(WorkspaceTool.about, t.about.title, AppGlyphs.info),
        ],
      ),
    ],
  );

  Widget _entry(
    WorkspaceTool tool,
    String label,
    Glyph icon, {
    Widget? badge,
  }) => ListTile(
    key: ValueKey('workspace-tool:${tool.name}'),
    minTileHeight: 64,
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    leading: GlyphIcon(icon),
    title: Text(label),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (badge != null) ...[badge, const SizedBox(width: 12)],
        const GlyphIcon(AppGlyphs.chevronForward, size: 20),
      ],
    ),
    onTap: () => _open(tool),
  );
}
