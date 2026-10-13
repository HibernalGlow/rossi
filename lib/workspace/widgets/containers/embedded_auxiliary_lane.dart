import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_follow/cubit/comic_follow_cubit.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_sheet.dart';
import 'package:zephyr/workspace/widgets/tools/workspace_tools_panel.dart';

/// 工作台入口的展示适配；打开与返回仍由原路由守卫落在当前面板。
class EmbeddedAuxiliaryLane extends StatelessWidget {
  const EmbeddedAuxiliaryLane({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<GlobalSettingCubit, ThemeMode>(
      (cubit) => cubit.state.themeMode,
    );
    final updateCount = context.select<ComicFollowCubit, int>(
      (cubit) => cubit.state.updateCount,
    );
    final themeLabel = switch (mode) {
      ThemeMode.system => t.common.followSystem,
      ThemeMode.light => t.common.lightMode,
      ThemeMode.dark => t.common.darkMode,
    };
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(12),
        bottomRight: Radius.circular(12),
      ),
      child: WorkspaceToolsPanel(
        settingsSummary:
            '${t.settings.personalizationGroup} · '
            '${t.settings.readingGroup}\n$themeLabel',
        updateCount: updateCount,
        onOpen: (tool) {
          if (tool == WorkspaceTool.reader) {
            showReaderSettingsSheet(context);
          } else {
            context.pushRoute(workspaceToolRoute(tool)!);
          }
        },
      ),
    );
  }
}

/// 复用现有页面与路由，阅读入口继续打开应用共享的统一弹层。
PageRouteInfo? workspaceToolRoute(WorkspaceTool tool) => switch (tool) {
  WorkspaceTool.settings => const GlobalSettingRoute(),
  WorkspaceTool.appearance => const AppearanceSettingRoute(),
  WorkspaceTool.layout => const WorkspaceLayoutSettingRoute(),
  WorkspaceTool.reader => null,
  WorkspaceTool.downloads => DownloadTaskRoute(),
  WorkspaceTool.sync => const SyncSettingRoute(),
  WorkspaceTool.follow => ComicFollowRoute(),
  WorkspaceTool.changelog => const ChangelogRoute(),
  WorkspaceTool.about => const AboutRoute(),
};
