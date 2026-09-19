import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/platform/desktop/window_logic.dart';
import 'package:zephyr/service/lifecycle/foreground_task/foreground_task_service.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/gesture_lock.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/workspace/model/workspace_startup.dart';

@RoutePage()
class AppBehaviorSettingPage extends StatefulWidget {
  const AppBehaviorSettingPage({super.key});

  @override
  State<AppBehaviorSettingPage> createState() => _AppBehaviorSettingPageState();
}

class _AppBehaviorSettingPageState extends State<AppBehaviorSettingPage> {
  DesktopCloseBehavior _desktopCloseBehavior = DesktopCloseBehavior.ask;

  List<String> _splashPageList(bool oldPageRollbackEnabled) {
    if (oldPageRollbackEnabled) {
      return [
        t.navigation.home,
        t.navigation.rank,
        t.navigation.bookshelf,
        t.navigation.discover,
        t.navigation.more,
      ];
    }
    return [t.navigation.bookshelf, t.navigation.discover, t.navigation.more];
  }

  @override
  void initState() {
    super.initState();
    _loadDesktopCloseBehavior();
  }

  Future<void> _loadDesktopCloseBehavior() async {
    if (!isDesktop) return;
    final value = await WindowLogic.loadCloseBehavior();
    if (!mounted) return;
    setState(() => _desktopCloseBehavior = value);
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final state = cubit.state;

    return SettingPageShell(
      title: t.settings.appBehavior,
      child: ListView(
        children: [
          settingSectionTitle(
            context,
            t.settings.appBehavior,
            icon: Icons.settings_outlined,
          ),
          // 「启动直接打开工作台」并进了这一条的下拉（见 `_splashPage`），
          // 不再单开一栏 —— 两者本来就是同一件事：启动落到哪儿。
          _splashPage(state, cubit),
          if (isDesktop) _desktopCloseBehaviorTile(),
          if (Platform.isAndroid) _androidKeepAlive(state, cubit),
          if (Platform.isAndroid) _backPressExit(state, cubit),
          _appLockSetting(state, cubit),
          _oldPageRollback(state, cubit),
          _cloudFavoritePreferred(state, cubit),
          _autoFollowOnCollect(state, cubit),
          _autoFavoriteOnDownload(state, cubit),
          _writeDownloadMetadataFile(state, cubit),
          _leftHandMode(state, cubit),
          _clickCoverToStartReading(state, cubit),
          // 只在桌面端给这个开关：触摸端只有右下角悬浮按钮一种落点，
          // 摆一个点了没反应的开关比不摆更糟（与 `_desktopCloseBehaviorTile` 同口径）。
          if (isDesktop) _comicInfoInlineReadButton(state, cubit),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _splashPage(GlobalSettingState state, GlobalSettingCubit cubit) {
    final splashPageList = _splashPageList(state.oldPageRollbackEnabled);
    // 本机有没有工作台入口。手机（既不是平板宽度、也不是桌面）没有 —— 那边导航栏
    // 上根本没有工作台按钮，下拉里也就摆这一项：摆了也落不了地。
    final workspaceOptionAvailable = hasWorkspaceEntry(context);
    // 老版回滚开关会让选项表在 3 项 / 5 项之间变，旧值可能越界，读之前先夹一次。
    final clampedWelcomePageNum = splashPageList.isEmpty
        ? 0
        : state.welcomePageNum.clamp(0, splashPageList.length - 1);

    // 键用**标签页编号**（工作台是 `splashWorkspaceOption` 哨兵），不用显示名：
    // 拿显示名当键的话，改一次文案就把选中项对丢了。
    final items = <int, String>{
      for (var index = 0; index < splashPageList.length; index++)
        index: splashPageList[index],
      if (workspaceOptionAvailable)
        splashWorkspaceOption: t.settings.startWithWorkspace,
    };
    final selected = resolveSplashDropdownValue(
      startWithWorkspace: state.startWithWorkspace,
      workspaceEntryAvailable: workspaceOptionAvailable,
      welcomePageNum: clampedWelcomePageNum,
    );

    return ListTile(
      leading: const Icon(Icons.rocket_launch_outlined),
      title: Text(t.settings.splashPage),
      subtitle: Text(t.settings.splashPageSubtitle),
      trailing: FluentDropdown<int>(
        value: selected,
        displayValue: items[selected] ?? items.values.first,
        items: items,
        onChanged: (int value) {
          if (value == selected) return;
          final next = resolveSplashSelection(
            selected: value,
            currentWelcomePageNum: state.welcomePageNum,
          );
          cubit.updateState(
            (current) => current.copyWith(
              startWithWorkspace: next.startWithWorkspace,
              welcomePageNum: next.welcomePageNum,
            ),
          );
          showSuccessToast(t.common.restartToTakeEffect);
        },
      ),
    );
  }

  Widget _oldPageRollback(GlobalSettingState state, GlobalSettingCubit cubit) {
    return SwitchListTile(
      secondary: const Icon(Icons.restore_outlined),
      title: Text(t.settings.oldPageRollback),
      subtitle: Text(t.settings.oldPageRollbackSubtitle),
      thumbIcon: kSettingSwitchThumbIcon,
      value: state.oldPageRollbackEnabled,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(oldPageRollbackEnabled: value),
        );
        showSuccessToast(t.common.restartToTakeEffect);
      },
    );
  }

  Widget _cloudFavoritePreferred(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return SwitchListTile(
      secondary: const Icon(Icons.cloud_outlined),
      title: Text(t.settings.cloudFavoritePreferred),
      subtitle: Text(t.settings.cloudFavoritePreferredSubtitle),
      thumbIcon: kSettingSwitchThumbIcon,
      value: state.cloudFavoritePreferred,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(cloudFavoritePreferred: value),
        );
        showSuccessToast(t.common.settingSaved);
      },
    );
  }

  Widget _autoFollowOnCollect(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return SwitchListTile(
      secondary: const Icon(Icons.notifications_active_outlined),
      title: Text(t.settings.autoFollowOnCollect),
      subtitle: Text(t.settings.autoFollowOnCollectSubtitle),
      thumbIcon: kSettingSwitchThumbIcon,
      value: state.autoFollowOnCollect,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(autoFollowOnCollect: value),
        );
        showSuccessToast(t.common.settingSaved);
      },
    );
  }

  Widget _autoFavoriteOnDownload(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return SwitchListTile(
      secondary: const Icon(Icons.bookmark_add_outlined),
      title: Text(t.settings.autoFavoriteOnDownload),
      subtitle: Text(t.settings.autoFavoriteOnDownloadSubtitle),
      thumbIcon: kSettingSwitchThumbIcon,
      value: state.autoFavoriteOnDownload,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(autoFavoriteOnDownload: value),
        );
        showSuccessToast(t.common.settingSaved);
      },
    );
  }

  Widget _writeDownloadMetadataFile(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return SwitchListTile(
      secondary: const Icon(Icons.description_outlined),
      title: Text(t.settings.writeDownloadMetadataFile),
      subtitle: Text(t.settings.writeDownloadMetadataFileSubtitle),
      thumbIcon: kSettingSwitchThumbIcon,
      value: state.writeDownloadMetadataFile,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(writeDownloadMetadataFile: value),
        );
        showSuccessToast(t.common.settingSaved);
      },
    );
  }

  Widget _leftHandMode(GlobalSettingState state, GlobalSettingCubit cubit) {
    return SwitchListTile(
      secondary: const Icon(Icons.back_hand_outlined),
      title: Text(t.settings.leftHandMode),
      subtitle: Text(t.settings.leftHandModeSubtitle),
      thumbIcon: kSettingSwitchThumbIcon,
      value: state.leftHandModeEnabled,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(leftHandModeEnabled: value),
        );
        showSuccessToast(t.common.settingSaved);
      },
    );
  }

  Widget _clickCoverToStartReading(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return SwitchListTile(
      secondary: const Icon(Icons.touch_app_outlined),
      title: Text(t.settings.clickCoverToStartReading),
      subtitle: Text(t.settings.clickCoverToStartReadingSubtitle),
      thumbIcon: kSettingSwitchThumbIcon,
      value: state.clickCoverToStartReading,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(clickCoverToStartReading: value),
        );
        showSuccessToast(t.common.settingSaved);
      },
    );
  }

  Widget _comicInfoInlineReadButton(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return SwitchListTile(
      secondary: const Icon(Icons.menu_book_outlined),
      title: Text(t.settings.comicInfoInlineReadButton),
      subtitle: Text(t.settings.comicInfoInlineReadButtonSubtitle),
      thumbIcon: kSettingSwitchThumbIcon,
      value: state.comicInfoInlineReadButton,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(comicInfoInlineReadButton: value),
        );
        showSuccessToast(t.common.settingSaved);
      },
    );
  }

  Widget _androidKeepAlive(GlobalSettingState state, GlobalSettingCubit cubit) {
    return SwitchListTile(
      secondary: const Icon(Icons.battery_charging_full_outlined),
      title: Text(t.settings.androidKeepAlive),
      subtitle: Text(t.settings.androidKeepAliveSubtitle),
      thumbIcon: kSettingSwitchThumbIcon,
      value: state.androidKeepAliveEnabled,
      onChanged: (bool value) async {
        cubit.updateState(
          (current) => current.copyWith(androidKeepAliveEnabled: value),
        );
        try {
          if (value) {
            await ForegroundTaskService.instance.enableKeepAlive();
          } else {
            await ForegroundTaskService.instance.disableKeepAlive();
          }
          showSuccessToast(t.common.settingSaved);
        } catch (e) {
          cubit.updateState(
            (current) => current.copyWith(androidKeepAliveEnabled: !value),
          );
          showErrorToast(e.toString());
        }
      },
    );
  }

  Widget _backPressExit(GlobalSettingState state, GlobalSettingCubit cubit) {
    return SwitchListTile(
      secondary: const Icon(Icons.exit_to_app_outlined),
      title: Text(t.settings.backPressExit),
      subtitle: Text(t.settings.backPressExitSubtitle),
      thumbIcon: kSettingSwitchThumbIcon,
      value: state.backPressExitEnabled,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(backPressExitEnabled: value),
        );
        showSuccessToast(t.common.settingSaved);
      },
    );
  }

  Widget _desktopCloseBehaviorTile() {
    final closeBehaviorItems = <DesktopCloseBehavior, String>{
      DesktopCloseBehavior.ask: t.settings.desktopCloseAsk,
      DesktopCloseBehavior.hide: t.settings.desktopCloseHide,
      DesktopCloseBehavior.close: t.settings.desktopCloseClose,
    };

    return ListTile(
      leading: const Icon(Icons.close_fullscreen_outlined),
      title: Text(t.settings.desktopCloseBehavior),
      subtitle: Text(t.settings.desktopCloseBehaviorSubtitle),
      trailing: FluentDropdown<DesktopCloseBehavior>(
        value: _desktopCloseBehavior,
        displayValue: closeBehaviorItems[_desktopCloseBehavior]!,
        items: closeBehaviorItems,
        onChanged: (DesktopCloseBehavior value) async {
          if (value == _desktopCloseBehavior) return;
          await WindowLogic.saveCloseBehavior(value);
          if (!mounted) return;
          setState(() => _desktopCloseBehavior = value);
          showSuccessToast(t.common.settingSaved);
        },
      ),
    );
  }

  Widget _appLockSetting(GlobalSettingState state, GlobalSettingCubit cubit) {
    final lockSetting = state.appLockSetting;
    final isReady = lockSetting.isReady;

    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.lock_outline),
          title: Text(t.settings.appLock),
          subtitle: Text(t.settings.appLockSubtitle),
          thumbIcon: kSettingSwitchThumbIcon,
          value: lockSetting.enabled,
          onChanged: (bool value) async {
            if (value && !isReady) {
              final nextSetting = await _configureAppLock();
              if (nextSetting == null) {
                return;
              }
              cubit.updateState(
                (current) => current.copyWith(appLockSetting: nextSetting),
              );
              showSuccessToast(t.common.settingSaved);
              return;
            }

            cubit.updateState(
              (current) => current.copyWith(
                appLockSetting: current.appLockSetting.copyWith(enabled: value),
              ),
            );
            showSuccessToast(t.common.settingSaved);
          },
        ),
        ListTile(
          leading: const Icon(Icons.gesture_outlined),
          title: Text(t.settings.appLock),
          subtitle: Text(t.settings.appLockSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final nextSetting = await _configureAppLock();
            if (nextSetting == null) {
              return;
            }
            cubit.updateState(
              (current) => current.copyWith(appLockSetting: nextSetting),
            );
            showSuccessToast(t.common.settingSaved);
          },
        ),
        if (isReady)
          ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: Text(t.gestureLock.pinTitle),
            subtitle: Text(t.gestureLock.pinHint),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final pin = await showPinCodeSetupDialog(
                context,
                title: t.gestureLock.pinTitle,
                confirmTitle: t.gestureLock.pinHint,
              );
              if (pin == null) {
                return;
              }
              cubit.updateState(
                (current) => current.copyWith(
                  appLockSetting: current.appLockSetting.copyWith(
                    resetPinHash: hashPinCode(pin),
                  ),
                ),
              );
              showSuccessToast(t.common.settingSaved);
            },
          ),
        if (isReady)
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(t.common.delete),
            subtitle: Text(t.settings.appLock),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final shouldDelete = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(t.common.delete),
                  content: Text(t.settings.appLockSubtitle),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(t.common.cancel),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(t.common.delete),
                    ),
                  ],
                ),
              );
              if (shouldDelete != true) {
                return;
              }
              cubit.updateState(
                (current) => current.copyWith(
                  appLockSetting: const AppLockSettingState(),
                ),
              );
              showSuccessToast(t.common.settingSaved);
            },
          ),
      ],
    );
  }

  Future<AppLockSettingState?> _configureAppLock() async {
    final pattern = await showGesturePasswordSetupDialog(
      context,
      title: t.gestureLock.gestureTitle,
      confirmTitle: t.gestureLock.confirmGesture,
    );
    if (pattern == null) {
      return null;
    }

    if (!mounted) {
      return null;
    }

    final pin = await showPinCodeSetupDialog(
      context,
      title: '设置重置 PIN',
      confirmTitle: '确认重置 PIN',
    );
    if (pin == null) {
      return null;
    }

    return AppLockSettingState(
      enabled: true,
      gesturePasswordHash: hashGesturePattern(pattern),
      resetPinHash: hashPinCode(pin),
    );
  }
}
