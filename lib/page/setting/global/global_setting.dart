import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/i18n_helper.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_sheet.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_super_resolution.dart';
import 'package:zephyr/service/notify/notify_topic.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';
import 'package:zephyr/workspace/model/workspace_startup.dart';
import 'package:zephyr/icons/icons.dart';

@RoutePage()
class GlobalSettingPage extends StatefulWidget {
  const GlobalSettingPage({super.key});

  @override
  State<GlobalSettingPage> createState() => _GlobalSettingPageState();
}

class _GlobalSettingPageState extends State<GlobalSettingPage> {
  late final Future<bool> _realSrAvailable;

  @override
  void initState() {
    super.initState();
    _realSrAvailable = RealSrSuperResolution.isDeviceSupported;
  }

  Future<void> _openSubPage(PageRouteInfo route) async {
    await context.pushRoute(route);
    if (mounted) setState(() {});
  }

  String _themeLabel(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => t.common.followSystem,
      ThemeMode.light => t.common.lightMode,
      ThemeMode.dark => t.common.darkMode,
    };
  }

  String _languageLabel(GlobalSettingState state) {
    if (state.localeFollowsSystem) return t.settings.followSystemLanguage;
    for (final appLocale in AppLocale.values) {
      if (I18nHelper.toFlutterLocale(appLocale) == state.locale) {
        return I18nHelper.displayName(appLocale);
      }
    }
    return state.locale.toLanguageTag();
  }

  /// 提示时长的简短展示：`0` 是常驻，其余按秒。
  String _toastDurationLabel(int durationMs) {
    if (durationMs <= 0) return t.settings.toastDurationPermanent;
    return '${(durationMs / 1000).toStringAsFixed(1)}s';
  }

  /// 入口那一行读的是**当前真状态**，不写死一句介绍词：
  /// 「总闸关了」和「单独静音了 N 项」是两件不同的事，用户在列表页就该分得清。
  String _notifySummary(NotifySettingState setting) {
    if (!setting.enabled) {
      return t.settings.notifySummaryMasterOff;
    }
    final off = NotifyTopic.ambientTopics
        .where((topic) => !topic.enabledIn(setting))
        .length;
    if (off == 0) return t.settings.notifySummaryAllOn;
    return t.settings.notifySummaryOffCount(count: off);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<GlobalSettingCubit>().state;

    return SettingPageShell(
      title: t.settings.globalTitle,
      child: ListView(
        children: [
          settingCategoryTile(
            icon: AppGlyphs.palette,
            title: t.settings.appearance,
            subtitle:
                '${_languageLabel(state)} · ${_themeLabel(state.themeMode)}',
            onTap: () => _openSubPage(const AppearanceSettingRoute()),
          ),
          const Divider(height: 1, thickness: 0.3),
          settingCategoryTile(
            icon: AppGlyphs.bell,
            title: t.settings.toastStyle,
            subtitle:
                '${state.toastSetting.position.label} · '
                '${_toastDurationLabel(state.toastSetting.durationMs)}',
            onTap: () => _openSubPage(const ToastSettingRoute()),
          ),
          const Divider(height: 1, thickness: 0.3),
          settingCategoryTile(
            icon: AppGlyphs.sliders,
            title: t.settings.notifyPersonalize,
            subtitle: _notifySummary(state.notifySetting),
            onTap: () => _openSubPage(const NotifySettingRoute()),
          ),
          const Divider(height: 1, thickness: 0.3),
          settingCategoryTile(
            icon: AppGlyphs.folder,
            title: t.settings.fileManager,
            subtitle: state.fileManagerSetting.homePath.isEmpty
                ? t.settings.fileManagerHomePathEmpty
                : state.fileManagerSetting.homePath,
            onTap: () => _openSubPage(const FileManagerSettingRoute()),
          ),
          const Divider(height: 1, thickness: 0.3),
          settingCategoryTile(
            icon: AppGlyphs.book,
            title: t.reader.settings,
            subtitle:
                '${t.reader.readingMode} · ${t.reader.hoverReveal} · ${t.reader.doubleTapAction}',
            onTap: () => showReaderSettingsSheet(context),
          ),
          // 整页讲的是**工作台**（泳道 / 四边栏 / 唤出区）。本机用不了工作台时
          // 不摆这一项（判据与开屏那条同源：`workspaceAvailableOnDevice`）。
          // 手机端现在摆 —— 那一页顶部就是「进入工作台」的按钮，
          // 而且切换轨 / 唤出区那些触摸触发的手感都只能在那一页调。
          if (workspaceAvailableOnDevice(context)) ...[
            const Divider(height: 1, thickness: 0.3),
            settingCategoryTile(
              icon: AppGlyphs.columnsThree,
              title: t.settings.workspaceLayout,
              subtitle: t.settings.workspaceLayoutSubtitle,
              onTap: () => _openSubPage(const WorkspaceLayoutSettingRoute()),
            ),
          ],
          const Divider(height: 1, thickness: 0.3),
          settingCategoryTile(
            icon: AppGlyphs.gamepad,
            title: t.settings.operationBinding,
            subtitle: t.settings.operationBindingEntrySubtitle,
            onTap: () => _openSubPage(const OperationBindingSettingRoute()),
          ),
          const Divider(height: 1, thickness: 0.3),
          settingCategoryTile(
            icon: AppGlyphs.sliders,
            title: t.settings.contentAndNetwork,
            subtitle: '${t.settings.maskedKeywords} · ${t.settings.proxy}',
            onTap: () => _openSubPage(const ContentNetworkSettingRoute()),
          ),
          const Divider(height: 1, thickness: 0.3),
          settingCategoryTile(
            icon: AppGlyphs.settings,
            title: t.settings.appBehavior,
            subtitle: '${t.settings.splashPage} · ${t.settings.appLock}',
            onTap: () => _openSubPage(const AppBehaviorSettingRoute()),
          ),
          const Divider(height: 1, thickness: 0.3),
          settingCategoryTile(
            icon: AppGlyphs.devices,
            title: t.settings.eink,
            subtitle: state.eInkSetting.enabled
                ? '${t.settings.einkEnabled} · ${state.eInkSetting.refreshMode.label}'
                : t.settings.einkSubtitle,
            onTap: () => _openSubPage(const EInkSettingRoute()),
          ),
          const Divider(height: 1, thickness: 0.3),
          settingCategoryTile(
            icon: AppGlyphs.bookmark,
            title: t.settings.bookshelf,
            subtitle: t.settings.bookshelfSubtitle,
            onTap: () => _openSubPage(const BookshelfSettingRoute()),
          ),
          const Divider(height: 1, thickness: 0.3),
          settingCategoryTile(
            icon: AppGlyphs.storage,
            title: t.settings.storage,
            subtitle: '${t.settings.cache} · ${t.settings.dataBackup}',
            onTap: () => _openSubPage(const StorageSettingRoute()),
          ),
          FutureBuilder<bool>(
            future: _realSrAvailable,
            builder: (context, snapshot) {
              if (snapshot.data != true) {
                return const SizedBox.shrink();
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Divider(height: 1, thickness: 0.3),
                  settingCategoryTile(
                    icon: AppGlyphs.wand,
                    title: t.settings.realSr,
                    subtitle: t.settings.realSrSubtitle,
                    onTap: () => _openSubPage(const RealSrSettingRoute()),
                  ),
                ],
              );
            },
          ),
          const Divider(height: 1, thickness: 0.3),
          // 移动端整条不画：ADR-0018 §决定 6 把 Android / iOS 定为排除项，
          // 摆一个点了只会报错的入口比少一个入口更糟。
          if (ocrSupportedHere) ...[
            settingCategoryTile(
              icon: AppGlyphs.translate,
              title: t.settings.ocr,
              subtitle: t.settings.ocrSubtitle,
              onTap: () => _openSubPage(const OcrSettingRoute()),
            ),
            const Divider(height: 1, thickness: 0.3),
          ],
          settingCategoryTile(
            icon: AppGlyphs.bug,
            title: t.settings.debug,
            subtitle: t.settings.logAddress,
            onTap: () => _openSubPage(const DebugSettingRoute()),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
