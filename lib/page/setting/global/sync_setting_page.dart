import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/network/sync/sync_service.dart';
import 'package:zephyr/page/comic_follow/cubit/comic_follow_cubit.dart';
import 'package:zephyr/page/setting/common/setting_group.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/setting/data_backup/data_backup_page.dart';
import 'package:zephyr/page/setting/global/widgets.dart';
import 'package:zephyr/util/event/event.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/icons/icons.dart';

@RoutePage()
class SyncSettingPage extends StatefulWidget {
  const SyncSettingPage({super.key});

  @override
  State<SyncSettingPage> createState() => _SyncSettingPageState();
}

class _SyncSettingPageState extends State<SyncSettingPage> {
  bool _uploading = false;
  bool _downloading = false;

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final state = cubit.state;
    final configuredSync = isSyncServiceConfigured(state);

    return SettingPageShell(
      title: t.settings.sync,
      description: t.settings.syncServiceSubtitle,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
            child: Text(
              t.dataBackup.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(t.settings.dataBackupSubtitle),
          ),
          const DataBackupControls(),
          SettingSectionCard(
            title: t.settings.syncConfig,
            icon: AppGlyphs.cloud,
            children: [
              _syncServiceType(state, cubit),
              webdavSync(context, state.syncSetting.syncServiceType),
              if (configuredSync) _autoSync(state, cubit),
              if (configuredSync) _syncSettings(state, cubit),
              if (configuredSync) _syncPlugins(state, cubit),
            ],
          ),
          if (configuredSync)
            SettingSectionCard(
              title: t.settings.manualSyncSection,
              icon: AppGlyphs.refresh,
              children: [
                _buildManualSyncTile(
                  icon: AppGlyphs.arrowUp,
                  title: t.settings.uploadToCloud,
                  subtitle: t.settings.uploadToCloudSubtitle,
                  actionLabel: t.settings.manualUpload,
                  busy: _uploading,
                  onPressed: _manualUpload,
                ),
                _buildManualSyncTile(
                  icon: AppGlyphs.download,
                  title: t.settings.downloadFromCloud,
                  subtitle: t.settings.downloadFromCloudSubtitle,
                  actionLabel: t.settings.manualDownload,
                  busy: _downloading,
                  onPressed: _manualDownload,
                ),
              ],
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _manualUpload() async {
    final cubit = context.read<GlobalSettingCubit>();
    setState(() => _uploading = true);
    try {
      await manualUploadToCloud(
        state: cubit.state,
        globalSettingCubit: cubit,
        comicFollowCubit: context.read<ComicFollowCubit>(),
      );
      if (mounted) showSuccessToast(t.settings.manualUploadSuccess);
    } catch (e, s) {
      logger.e('手动上传失败', error: e, stackTrace: s);
      if (mounted) {
        showErrorToast('${t.settings.manualSyncFailed}: $e');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _manualDownload() async {
    final cubit = context.read<GlobalSettingCubit>();
    setState(() => _downloading = true);
    try {
      await manualDownloadFromCloud(
        state: cubit.state,
        globalSettingCubit: cubit,
        comicFollowCubit: context.read<ComicFollowCubit>(),
      );
      if (mounted) showSuccessToast(t.settings.manualDownloadSuccess);
    } catch (e, s) {
      logger.e('手动下载失败', error: e, stackTrace: s);
      if (mounted) {
        showErrorToast('${t.settings.manualSyncFailed}: $e');
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Widget _buildManualSyncTile({
    required Glyph icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required bool busy,
    required VoidCallback onPressed,
  }) {
    return ListTile(
      leading: GlyphIcon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : FilledButton.tonal(onPressed: onPressed, child: Text(actionLabel)),
    );
  }

  Widget _syncServiceType(GlobalSettingState state, GlobalSettingCubit cubit) {
    final syncServiceItems = <SyncServiceType, String>{
      SyncServiceType.none: t.settings.syncServiceNone,
      SyncServiceType.webdav: t.settings.syncServiceWebdav,
      SyncServiceType.s3: t.settings.syncServiceS3,
    };

    return ListTile(
      leading: const GlyphIcon(AppGlyphs.storage),
      title: Text(t.settings.syncService),
      subtitle: Text(t.settings.syncServiceSubtitle),
      trailing: FluentDropdown<SyncServiceType>(
        value: state.syncSetting.syncServiceType,
        displayValue: syncServiceItems[state.syncSetting.syncServiceType]!,
        items: syncServiceItems,
        onChanged: (SyncServiceType value) {
          if (value == state.syncSetting.syncServiceType) return;
          cubit.updateSyncSetting(
            (current) => current.copyWith(
              syncServiceType: value,
              syncSettings: value == SyncServiceType.none
                  ? false
                  : current.syncSettings,
            ),
          );
        },
      ),
    );
  }

  Widget _autoSync(GlobalSettingState state, GlobalSettingCubit cubit) {
    return SettingGroup.switchTile(
      leading: const GlyphIcon(AppGlyphs.cloudSync),
      title: Text(t.settings.autoSync),
      subtitle: Text(t.settings.autoSyncSubtitle),
      value: state.syncSetting.autoSync,
      onChanged: (bool value) {
        cubit.updateSyncSetting((current) => current.copyWith(autoSync: value));
        if (value) {
          eventBus.fire(NoticeSync());
        }
      },
    );
  }

  Widget _syncSettings(GlobalSettingState state, GlobalSettingCubit cubit) {
    return SettingGroup.switchTile(
      leading: const GlyphIcon(AppGlyphs.sliders),
      title: Text(t.settings.syncSettings),
      subtitle: Text(t.settings.syncSettingsSubtitle),
      value: state.syncSetting.syncSettings,
      onChanged: (bool value) {
        cubit.updateSyncSetting(
          (current) => current.copyWith(syncSettings: value),
        );
      },
    );
  }

  Widget _syncPlugins(GlobalSettingState state, GlobalSettingCubit cubit) {
    return SettingGroup.switchTile(
      leading: const GlyphIcon(AppGlyphs.puzzle),
      title: Text(t.settings.syncPlugins),
      subtitle: Text(t.settings.syncPluginsSubtitle),
      value: state.syncSetting.syncPlugins,
      onChanged: (bool value) {
        cubit.updateSyncSetting(
          (current) => current.copyWith(syncPlugins: value),
        );
      },
    );
  }
}
