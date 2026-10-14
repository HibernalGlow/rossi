part of '../global_setting.dart';

extension _GlobalSettingDestinations on _GlobalSettingPageState {
  List<SettingDestinationGroup> _destinationGroups(
    GlobalSettingState state,
    bool realSrAvailable,
  ) {
    SettingDestination destination({
      required String id,
      required String title,
      required String subtitle,
      required Glyph icon,
      required PageRouteInfo route,
      Widget? detail,
    }) => SettingDestination(
      id: id,
      title: title,
      subtitle: subtitle,
      icon: icon,
      onOpen: () => _openSubPage(route),
      detailBuilder: detail == null ? null : (_) => detail,
    );

    return [
      SettingDestinationGroup(
        title: t.settings.personalizationGroup,
        entries: [
          destination(
            id: 'appearance',
            title: t.settings.appearance,
            subtitle:
                '${_languageLabel(state)} · ${_themeLabel(state.themeMode)}',
            icon: AppGlyphs.palette,
            route: const AppearanceSettingRoute(),
            detail: const AppearanceSettingPage(),
          ),
          destination(
            id: 'toast',
            title: t.settings.toastStyle,
            subtitle:
                '${state.toastSetting.position.label} · '
                '${_toastDurationLabel(state.toastSetting.durationMs)}',
            icon: AppGlyphs.bell,
            route: const ToastSettingRoute(),
            detail: const ToastSettingPage(),
          ),
          destination(
            id: 'notify',
            title: t.settings.notifyPersonalize,
            subtitle: _notifySummary(state.notifySetting),
            icon: AppGlyphs.sliders,
            route: const NotifySettingRoute(),
            detail: const NotifySettingPage(),
          ),
        ],
      ),
      SettingDestinationGroup(
        title: t.settings.readingGroup,
        entries: [
          SettingDestination(
            id: 'reader',
            title: t.reader.settings,
            subtitle: switch (state.readSetting.readMode) {
              1 => t.reader.singlePageLtr,
              2 => t.reader.singlePageRtl,
              _ => t.reader.webtoon,
            },
            icon: AppGlyphs.book,
            onOpen: () => showReaderSettingsSheet(context),
          ),
          if (realSrAvailable)
            destination(
              id: 'upscale',
              title: t.settings.realSr,
              subtitle: t.settings.realSrSubtitle,
              icon: AppGlyphs.wand,
              route: const RealSrSettingRoute(),
              detail: const RealSrSettingPage(),
            ),
          if (ocrSupportedHere)
            destination(
              id: 'ocr',
              title: t.settings.ocr,
              subtitle: t.settings.ocrSubtitle,
              icon: AppGlyphs.translate,
              route: const OcrSettingRoute(),
              detail: const OcrSettingPage(),
            ),
          destination(
            id: 'eink',
            title: t.settings.eink,
            subtitle: state.eInkSetting.enabled
                ? '${t.settings.einkEnabled} · ${state.eInkSetting.refreshMode.label}'
                : t.settings.einkSubtitle,
            icon: AppGlyphs.devices,
            route: const EInkSettingRoute(),
            detail: const EInkSettingPage(),
          ),
        ],
      ),
      SettingDestinationGroup(
        title: t.settings.libraryGroup,
        entries: [
          destination(
            id: 'files',
            title: t.settings.fileManager,
            subtitle: state.fileManagerSetting.homePath.isEmpty
                ? t.settings.fileManagerHomePathEmpty
                : state.fileManagerSetting.homePath,
            icon: AppGlyphs.folder,
            route: const FileManagerSettingRoute(),
            detail: const FileManagerSettingPage(),
          ),
          destination(
            id: 'bookshelf',
            title: t.settings.bookshelf,
            subtitle: t.settings.bookshelfSubtitle,
            icon: AppGlyphs.bookmark,
            route: const BookshelfSettingRoute(),
            detail: const BookshelfSettingPage(),
          ),
          destination(
            id: 'storage',
            title: t.settings.storage,
            subtitle: '${t.settings.cache} · ${t.settings.dataBackup}',
            icon: AppGlyphs.storage,
            route: const StorageSettingRoute(),
            detail: const StorageSettingPage(),
          ),
          destination(
            id: 'sync',
            title: t.more.sync,
            subtitle: t.settings.syncDestinationsSubtitle,
            icon: AppGlyphs.sync,
            route: const SyncSettingRoute(),
            detail: const SyncSettingPage(),
          ),
          destination(
            id: 'backup',
            title: t.settings.dataBackup,
            subtitle: t.settings.dataBackupSubtitle,
            icon: AppGlyphs.archive,
            route: const DataBackupRoute(),
            detail: const DataBackupPage(),
          ),
        ],
      ),
      SettingDestinationGroup(
        title: t.settings.applicationGroup,
        entries: [
          if (workspaceAvailableOnDevice(context)) ...[
            destination(
              id: 'workspace',
              title: t.settings.workspaceLayout,
              subtitle: t.settings.workspaceLayoutSubtitle,
              icon: AppGlyphs.columnsThree,
              route: const WorkspaceLayoutSettingRoute(),
              detail: const WorkspaceLayoutSettingPage(),
            ),
            destination(
              id: 'swimlane_panel',
              title: t.settings.swimlanePanelKanban,
              subtitle: t.settings.swimlanePanelKanbanSubtitle,
              icon: AppGlyphs.dashboard,
              route: const SwimlanePanelSettingRoute(),
              detail: const SwimlanePanelSettingPage(),
            ),
          ],
          // 该页有未保存编辑的 PopScope，仍走原路由以执行保存 / 放弃确认。
          destination(
            id: 'bindings',
            title: t.settings.operationBinding,
            subtitle: t.settings.operationBindingEntrySubtitle,
            icon: AppGlyphs.gamepad,
            route: const OperationBindingSettingRoute(),
          ),
          destination(
            id: 'network',
            title: t.settings.contentAndNetwork,
            subtitle: '${t.settings.maskedKeywords} · ${t.settings.proxy}',
            icon: AppGlyphs.wifi,
            route: const ContentNetworkSettingRoute(),
            detail: const ContentNetworkSettingPage(),
          ),
          destination(
            id: 'behavior',
            title: t.settings.appBehavior,
            subtitle: '${t.settings.splashPage} · ${t.settings.appLock}',
            icon: AppGlyphs.settings,
            route: const AppBehaviorSettingRoute(),
            detail: const AppBehaviorSettingPage(),
          ),
          destination(
            id: 'debug',
            title: t.settings.debug,
            subtitle: t.settings.logAddress,
            icon: AppGlyphs.bug,
            route: const DebugSettingRoute(),
            detail: const DebugSettingPage(),
          ),
          destination(
            id: 'about',
            title: t.about.title,
            subtitle: t.settings.aboutAppSubtitle,
            icon: AppGlyphs.info,
            route: const AboutRoute(),
            detail: const AboutPage(),
          ),
        ],
      ),
    ];
  }
}
