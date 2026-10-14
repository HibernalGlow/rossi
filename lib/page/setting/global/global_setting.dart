import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/i18n_helper.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_sheet.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/setting/common/setting_browser.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_super_resolution.dart';
import 'package:zephyr/service/notify/notify_topic.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';
import 'package:zephyr/workspace/model/workspace_startup.dart';
import 'package:zephyr/icons/icons.dart';

import 'package:zephyr/page/setting/global/appearance_setting_page.dart';
import 'package:zephyr/page/setting/global/toast_setting_page.dart';
import 'package:zephyr/page/setting/global/notify_setting_page.dart';
import 'package:zephyr/page/setting/global/file_manager_setting_page.dart';
import 'package:zephyr/page/setting/global/swimlane_panel_setting_page.dart';
import 'package:zephyr/page/setting/global/workspace_layout_setting_page.dart';
import 'package:zephyr/page/setting/global/content_network_setting_page.dart';
import 'package:zephyr/page/setting/global/app_behavior_setting_page.dart';
import 'package:zephyr/page/setting/global/eink_setting_page.dart';
import 'package:zephyr/page/setting/global/storage_setting_page.dart';
import 'package:zephyr/page/setting/global/debug_setting_page.dart';
import 'package:zephyr/page/setting/global/sync_setting_page.dart';
import 'package:zephyr/page/about/about.dart';
import 'package:zephyr/page/setting/data_backup/data_backup_page.dart';
import 'package:zephyr/page/setting/bookshelf/bookshelf_setting_page.dart';
import 'package:zephyr/page/setting/ocr/ocr_setting_page.dart';
import 'package:zephyr/page/setting/real_sr/real_sr_setting_page.dart';

part 'parts/global_setting_destinations.dart';

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
      // 一级页：下面就是双栏总览，不再挂一个大标题。
      collapsingTitle: false,
      maxWidth: 1440,
      child: FutureBuilder<bool>(
        future: _realSrAvailable,
        builder: (context, snapshot) => SettingBrowser(
          summary: '${_languageLabel(state)} · ${_themeLabel(state.themeMode)}',
          groups: _destinationGroups(state, snapshot.data == true),
        ),
      ),
    );
  }
}
