import 'package:zephyr/page/setting/common/setting_group.dart';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_entry.dart';
import 'package:zephyr/page/setting/common/setting_entry_list.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/platform/desktop/window_logic.dart';
import 'package:zephyr/service/lifecycle/foreground_task/foreground_task_service.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/gesture_lock.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/workspace/model/workspace_startup.dart';
import 'package:zephyr/icons/icons.dart';

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
      child: SettingEntryList(
        children: [
          SettingSectionCard(
            children: [
              // 「启动直接打开工作台」并进了这一条的下拉（见 `_splashPage`），
              // 不再单开一栏 —— 两者本来就是同一件事：启动落到哪儿。
              settingEntry('behavior.splashPage', _splashPage(state, cubit)),
              if (workspaceAvailableOnDevice(context))
                settingEntry(
                  'behavior.workspaceSleepCoveredUi',
                  _workspaceSleepCoveredUi(state, cubit),
                ),
              settingEntry(
                'behavior.skipUpdateCheck',
                _skipUpdateCheck(state, cubit),
              ),
              if (isDesktop)
                settingEntry(
                  'behavior.desktopCloseBehavior',
                  _desktopCloseBehaviorTile(),
                ),
              if (Platform.isAndroid)
                settingEntry(
                  'behavior.androidKeepAlive',
                  _androidKeepAlive(state, cubit),
                ),
              if (Platform.isAndroid)
                settingEntry(
                  'behavior.backPressExit',
                  _backPressExit(state, cubit),
                ),
              // 这一块展开时有 2~4 行，但它们是同一件事（手势锁 + PIN + 删除），
              // 所以整块只给一个 id：落点停在开关那一行就够了。
              settingEntry('behavior.appLock', _appLockSetting(state, cubit)),
              settingEntry(
                'behavior.oldPageRollback',
                _oldPageRollback(state, cubit),
              ),
              settingEntry(
                'behavior.cloudFavoritePreferred',
                _cloudFavoritePreferred(state, cubit),
              ),
              settingEntry(
                'behavior.autoFollowOnCollect',
                _autoFollowOnCollect(state, cubit),
              ),
              settingEntry(
                'behavior.autoFavoriteOnDownload',
                _autoFavoriteOnDownload(state, cubit),
              ),
              settingEntry(
                'behavior.writeDownloadMetadataFile',
                _writeDownloadMetadataFile(state, cubit),
              ),
              settingEntry(
                'behavior.leftHandMode',
                _leftHandMode(state, cubit),
              ),
              settingEntry(
                'behavior.clickCoverToStartReading',
                _clickCoverToStartReading(state, cubit),
              ),
              settingEntry(
                'behavior.searchHistoryGroupBySource',
                _searchHistoryGroupBySource(state, cubit),
              ),
              // 只在桌面端给这个开关：触摸端只有右下角悬浮按钮一种落点，
              // 摆一个点了没反应的开关比不摆更糟（与 `_desktopCloseBehaviorTile` 同口径）。
              if (isDesktop)
                settingEntry(
                  'behavior.comicInfoInlineReadButton',
                  _comicInfoInlineReadButton(state, cubit),
                ),
              if (isDesktop)
                settingEntry(
                  'behavior.comicInfoRailLiquidGlass',
                  _comicInfoRailLiquidGlass(state, cubit),
                ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _splashPage(GlobalSettingState state, GlobalSettingCubit cubit) {
    final splashPageList = _splashPageList(state.oldPageRollbackEnabled);
    // 本机**用不用得了**工作台。判据不是「导航栏上有没有那颗按钮」
    // （`hasWorkspaceEntry`，手机上确实没有），而是「进得去且出得来」——
    // 那边靠「设置 → 布局」里的进入按钮、开屏这一项，以及系统返回键。
    final workspaceOptionAvailable = workspaceAvailableOnDevice(context);
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
      leading: const GlyphIcon(AppGlyphs.rocket),
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

  /// 工作台在场时被盖住的首页壳要不要休眠（图片让出解码位图）。
  /// 判据与落点见 `ImageSleep` / `WorkspacePresence`。
  Widget _workspaceSleepCoveredUi(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return SettingGroup.switchTile(
      leading: const GlyphIcon(AppGlyphs.battery1),
      title: Text(t.settings.workspaceSleepCoveredUi),
      subtitle: Text(t.settings.workspaceSleepCoveredUiSubtitle),
      value: state.workspaceSleepCoveredUi,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(workspaceSleepCoveredUi: value),
        );
        showSuccessToast(t.common.settingSaved);
      },
    );
  }

  /// 启动时要不要跳过「检查上游新版本」。默认开：本仓是 fork，版本号永远低于
  /// 上游，弹窗只会把人引向 deretame/Breeze 的安装包。
  Widget _skipUpdateCheck(GlobalSettingState state, GlobalSettingCubit cubit) {
    return SettingGroup.switchTile(
      leading: const GlyphIcon(AppGlyphs.block),
      title: Text(t.settings.skipUpdateCheck),
      subtitle: Text(t.settings.skipUpdateCheckSubtitle),
      value: state.skipUpdateCheck,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(skipUpdateCheck: value),
        );
        showSuccessToast(t.common.settingSaved);
      },
    );
  }

  Widget _oldPageRollback(GlobalSettingState state, GlobalSettingCubit cubit) {
    return SettingGroup.switchTile(
      leading: const GlyphIcon(AppGlyphs.reset),
      title: Text(t.settings.oldPageRollback),
      subtitle: Text(t.settings.oldPageRollbackSubtitle),
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
    return SettingGroup.switchTile(
      leading: const GlyphIcon(AppGlyphs.cloud),
      title: Text(t.settings.cloudFavoritePreferred),
      subtitle: Text(t.settings.cloudFavoritePreferredSubtitle),
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
    return SettingGroup.switchTile(
      leading: const GlyphIcon(AppGlyphs.bell),
      title: Text(t.settings.autoFollowOnCollect),
      subtitle: Text(t.settings.autoFollowOnCollectSubtitle),
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
    return SettingGroup.switchTile(
      leading: const GlyphIcon(AppGlyphs.bookmark),
      title: Text(t.settings.autoFavoriteOnDownload),
      subtitle: Text(t.settings.autoFavoriteOnDownloadSubtitle),
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
    return SettingGroup.switchTile(
      leading: const GlyphIcon(AppGlyphs.article),
      title: Text(t.settings.writeDownloadMetadataFile),
      subtitle: Text(t.settings.writeDownloadMetadataFileSubtitle),
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
    return SettingGroup.switchTile(
      leading: const GlyphIcon(AppGlyphs.hand),
      title: Text(t.settings.leftHandMode),
      subtitle: Text(t.settings.leftHandModeSubtitle),
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
    return SettingGroup.switchTile(
      leading: const GlyphIcon(AppGlyphs.touch),
      title: Text(t.settings.clickCoverToStartReading),
      subtitle: Text(t.settings.clickCoverToStartReadingSubtitle),
      value: state.clickCoverToStartReading,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(clickCoverToStartReading: value),
        );
        showSuccessToast(t.common.settingSaved);
      },
    );
  }

  /// 搜索历史按图源分时间线。与搜索页历史标题上那颗按钮是**同一个字段**，
  /// 两处入口、一份状态（改一处另一处立刻跟着变）。
  Widget _searchHistoryGroupBySource(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return SettingGroup.switchTile(
      leading: const GlyphIcon(AppGlyphs.category),
      title: Text(t.settings.searchHistoryGroupBySource),
      subtitle: Text(t.settings.searchHistoryGroupBySourceSubtitle),
      value: state.searchHistoryGroupBySource,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(searchHistoryGroupBySource: value),
        );
        showSuccessToast(t.common.settingSaved);
      },
    );
  }

  Widget _comicInfoInlineReadButton(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return SettingGroup.switchTile(
      leading: const GlyphIcon(AppGlyphs.book),
      title: Text(t.settings.comicInfoInlineReadButton),
      subtitle: Text(t.settings.comicInfoInlineReadButtonSubtitle),
      value: state.comicInfoInlineReadButton,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(comicInfoInlineReadButton: value),
        );
        showSuccessToast(t.common.settingSaved);
      },
    );
  }

  /// 详情页左右那颗悬浮胶囊的材质。只在桌面出现 —— rail 本身的判据是「有没有指针」
  /// （`comicInfoPlatformHasPointer`），手机端根本没有这颗控件，摆个开关比不摆更糟。
  Widget _comicInfoRailLiquidGlass(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return SettingGroup.switchTile(
      leading: const GlyphIcon(AppGlyphs.motion),
      title: Text(t.settings.comicInfoRailLiquidGlass),
      subtitle: Text(t.settings.comicInfoRailLiquidGlassSubtitle),
      value: state.comicInfoRailLiquidGlass,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(comicInfoRailLiquidGlass: value),
        );
        showSuccessToast(t.common.settingSaved);
      },
    );
  }

  Widget _androidKeepAlive(GlobalSettingState state, GlobalSettingCubit cubit) {
    return SettingGroup.switchTile(
      leading: const GlyphIcon(AppGlyphs.batteryCharging),
      title: Text(t.settings.androidKeepAlive),
      subtitle: Text(t.settings.androidKeepAliveSubtitle),
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
    return SettingGroup.switchTile(
      leading: const GlyphIcon(AppGlyphs.openExternal),
      title: Text(t.settings.backPressExit),
      subtitle: Text(t.settings.backPressExitSubtitle),
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
      leading: const GlyphIcon(AppGlyphs.fullscreenExit),
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
        SettingGroup.switchTile(
          leading: const GlyphIcon(AppGlyphs.lock),
          title: Text(t.settings.appLock),
          subtitle: Text(t.settings.appLockSubtitle),
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
          leading: const GlyphIcon(AppGlyphs.gesture),
          title: Text(t.settings.appLock),
          subtitle: Text(t.settings.appLockSubtitle),
          trailing: const GlyphIcon(AppGlyphs.chevronForward),
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
            leading: const GlyphIcon(AppGlyphs.pin),
            title: Text(t.gestureLock.pinTitle),
            subtitle: Text(t.gestureLock.pinHint),
            trailing: const GlyphIcon(AppGlyphs.chevronForward),
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
            leading: const GlyphIcon(AppGlyphs.delete),
            title: Text(t.common.delete),
            subtitle: Text(t.settings.appLock),
            trailing: const GlyphIcon(AppGlyphs.chevronForward),
            onTap: () async {
              final shouldDelete = await showPopupPanel<bool>(
                context: context,
                presentation: PopupPresentation.modal,
                builder: (context) => PopupPanel(
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
      title: t.settings.setResetPin,
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
