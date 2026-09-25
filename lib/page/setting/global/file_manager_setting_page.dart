import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/widgets/toast.dart';

/// 文件管理器设置：本地文件浏览卡片的跨重启偏好。
///
/// 主页是这里的重点。它在卡片工具栏上也有入口（单击 / 长按 / 右键），
/// 但这个页面负责回答两个卡片回答不了的问题：
/// 1. 当前主页到底是哪个路径（卡片只在 hover 提示里显示）；
/// 2. 保存的那个路径已经失效时怎么办（目录被删 / 移动盘没插）——
///    卡片上只会表现为主页键点不动，看不出原因。
///
/// 失效判定：核心（Rust）只接受存在的目录，所以「持久化里非空、会话里为空」
/// 就是「这个路径现在不可用」。这里不去猜原因，只把事实和重选入口摆出来。
@RoutePage()
class FileManagerSettingPage extends StatelessWidget {
  const FileManagerSettingPage({super.key});

  Future<void> _pickHome(BuildContext context, GlobalSettingCubit cubit) async {
    final current = cubit.state.fileManagerSetting.homePath;
    String? picked;
    try {
      picked = await getDirectoryPath(
        initialDirectory: current.isEmpty ? null : current,
        confirmButtonText: t.settings.fileManagerHomePathPick,
      );
    } catch (error) {
      if (context.mounted) {
        showErrorToast(
          '${t.settings.fileManagerHomePathUnsupported}（$error）',
          context: context,
        );
      }
      return;
    }
    if (picked == null || picked.isEmpty) return;
    final path = picked;
    cubit.updateFileManagerSetting(
      (setting) => setting.copyWith(homePath: path),
    );
    if (context.mounted) {
      showSuccessToast(
        path,
        title: t.settings.fileManagerHomePathSet,
        context: context,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final setting = cubit.state.fileManagerSetting;
    final homePath = setting.homePath;
    final stale =
        homePath.isNotEmpty &&
        !Platform.isIOS &&
        !Directory(homePath).existsSync();

    return SettingPageShell(
      title: t.settings.fileManager,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          settingSectionTitle(
            context,
            t.settings.fileManagerSectionToolbar,
            icon: Icons.build_outlined,
          ),
          SettingSectionCard(
            title: t.settings.fileManagerSectionHome,
            icon: Icons.home_outlined,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.toggle_on_outlined),
                title: Text(t.settings.fileManagerHomeEnabled),
                subtitle: Text(t.settings.fileManagerHomeEnabledSubtitle),
                thumbIcon: kSettingSwitchThumbIcon,
                value: setting.homeEnabled,
                onChanged: (value) => cubit.updateFileManagerSetting(
                  (current) => current.copyWith(homeEnabled: value),
                ),
              ),
              ListTile(
                enabled: setting.homeEnabled,
                leading: const Icon(Icons.folder_special_outlined),
                title: Text(t.settings.fileManagerHomePath),
                subtitle: Text(
                  homePath.isEmpty
                      ? t.settings.fileManagerHomePathEmpty
                      : homePath,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: FilledButton.tonal(
                  onPressed: setting.homeEnabled
                      ? () => _pickHome(context, cubit)
                      : null,
                  child: Text(t.settings.fileManagerHomePathPick),
                ),
              ),
              // 只有设过主页才摆这一条：没主页时它没有任何可生效的值，
              // 摆一个开不动的开关比不摆更糟（与「清除主页」同口径）。
              if (homePath.isNotEmpty)
                SwitchListTile(
                  secondary: const Icon(Icons.rocket_launch_outlined),
                  title: Text(t.settings.fileManagerOpenHomeOnStart),
                  subtitle: Text(t.settings.fileManagerOpenHomeOnStartSubtitle),
                  thumbIcon: kSettingSwitchThumbIcon,
                  value: setting.openHomeOnStart,
                  // 主页键关掉 ⇒ 这条开不动：`material_ui` 的 SwitchListTile 由
                  // `onChanged == null` 自己推导禁用，它没有 `enabled` 形参。
                  onChanged: setting.homeEnabled
                      ? (value) {
                          cubit.updateFileManagerSetting(
                            (current) =>
                                current.copyWith(openHomeOnStart: value),
                          );
                          // 只管新建的会话：活着的会话不该被设置页偷偷搬走目录。
                          showSuccessToast(
                            t.common.restartToTakeEffect,
                            context: context,
                          );
                        }
                      : null,
                ),
              if (homePath.isNotEmpty)
                ListTile(
                  enabled: setting.homeEnabled,
                  leading: const Icon(Icons.link_off_outlined),
                  title: Text(t.settings.fileManagerHomePathClear),
                  subtitle: stale
                      ? Text(
                          t.settings.fileManagerHomePathStale,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        )
                      : null,
                  onTap: setting.homeEnabled
                      ? () {
                          cubit.updateFileManagerSetting(
                            (current) => current.copyWith(homePath: ''),
                          );
                          showInfoToast(
                            t.settings.fileManagerHomePathCleared,
                            context: context,
                          );
                        }
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 12),
          SettingSectionCard(
            title: t.settings.fileManagerSectionView,
            icon: Icons.grid_view_outlined,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.bookmark_added_outlined),
                title: Text(t.settings.fileManagerRememberViewState),
                subtitle: Text(t.settings.fileManagerRememberViewStateSubtitle),
                thumbIcon: kSettingSwitchThumbIcon,
                value: setting.rememberViewState,
                onChanged: (value) => cubit.updateFileManagerSetting(
                  (current) => current.copyWith(rememberViewState: value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingSectionCard(
            title: t.settings.fileManagerSectionTabs,
            icon: Icons.tab_outlined,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.restore_outlined),
                title: Text(t.settings.fileManagerRestoreTabs),
                subtitle: Text(t.settings.fileManagerRestoreTabsSubtitle),
                thumbIcon: kSettingSwitchThumbIcon,
                value: setting.restoreTabs,
                // 和「启动时默认打开主页」同一个口径：恢复是**新建会话**时才做的事，
                // 设置页不该把用户正开着的那批页签搬走，所以改完只说明「下次生效」。
                // （记录那一半是立刻停/立刻起的 —— 卡片每来一份快照都重新问一次开关。）
                onChanged: (value) {
                  cubit.updateFileManagerSetting(
                    (current) => current.copyWith(restoreTabs: value),
                  );
                  showSuccessToast(
                    t.common.restartToTakeEffect,
                    context: context,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingSectionCard(
            title: t.settings.fileManagerSectionFileOps,
            icon: Icons.drive_file_move_outlined,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.delete_sweep_outlined),
                title: Text(t.settings.fileManagerFileOperations),
                subtitle: Text(t.settings.fileManagerFileOperationsSubtitle),
                thumbIcon: kSettingSwitchThumbIcon,
                value: setting.fileOperations,
                onChanged: (value) => cubit.updateFileManagerSetting(
                  (current) => current.copyWith(fileOperations: value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              t.settings.fileManagerSubtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
