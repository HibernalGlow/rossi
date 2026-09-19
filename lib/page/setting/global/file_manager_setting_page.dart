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
