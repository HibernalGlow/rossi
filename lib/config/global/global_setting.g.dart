// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'global_setting.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_GlobalSettingState _$GlobalSettingStateFromJson(
  Map<String, dynamic> json,
) => _GlobalSettingState(
  dynamicColor: json['dynamicColor'] as bool? ?? true,
  themeMode:
      $enumDecodeNullable(_$ThemeModeEnumMap, json['themeMode']) ??
      ThemeMode.system,
  isAMOLED: json['isAMOLED'] as bool? ?? true,
  seedColor: json['seedColor'] == null
      ? const Color(0xFFEF5350)
      : const ColorConverter().fromJson((json['seedColor'] as num).toInt()),
  tweakcnThemeJson: json['tweakcnThemeJson'] as String? ?? '',
  tweakcnThemeEnabled: json['tweakcnThemeEnabled'] as bool? ?? false,
  themeInitState: (json['themeInitState'] as num?)?.toInt() ?? 0,
  locale: json['locale'] == null
      ? const Locale('zh', 'CN')
      : const LocaleConverter().fromJson(json['locale'] as String),
  localeFollowsSystem: json['localeFollowsSystem'] as bool? ?? true,
  welcomePageNum: (json['welcomePageNum'] as num?)?.toInt() ?? 0,
  syncSetting: json['syncSetting'] == null
      ? const SyncSettingState()
      : SyncSettingState.fromJson(json['syncSetting'] as Map<String, dynamic>),
  maskedKeywords:
      (json['maskedKeywords'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  socks5ProxyEnabled: json['socks5ProxyEnabled'] as bool? ?? true,
  socks5Proxy: json['socks5Proxy'] as String? ?? '',
  needCleanCache: json['needCleanCache'] as bool? ?? false,
  comicChoice: (json['comicChoice'] as num?)?.toInt() ?? 1,
  disableBika: json['disableBika'] as bool? ?? false,
  enableMemoryDebug: json['enableMemoryDebug'] as bool? ?? false,
  blockRustHttpRequests: json['blockRustHttpRequests'] as bool? ?? false,
  logAddress: json['logAddress'] as String? ?? '',
  showLayoutOverflowStripes: json['showLayoutOverflowStripes'] as bool? ?? true,
  forceEnableImpeller: json['forceEnableImpeller'] as bool? ?? false,
  androidKeepAliveEnabled: json['androidKeepAliveEnabled'] as bool? ?? false,
  backPressExitEnabled: json['backPressExitEnabled'] as bool? ?? false,
  updateAccelerate: json['updateAccelerate'] as bool? ?? true,
  retryDownloadUntilSuccess: json['retryDownloadUntilSuccess'] as bool? ?? true,
  downloadConcurrency: (json['downloadConcurrency'] as num?)?.toInt() ?? 3,
  downloadDelayMs: (json['downloadDelayMs'] as num?)?.toInt() ?? 150,
  downloadAutoRetryCount:
      (json['downloadAutoRetryCount'] as num?)?.toInt() ?? 3,
  oldPageRollbackEnabled: json['oldPageRollbackEnabled'] as bool? ?? false,
  cloudFavoritePreferred: json['cloudFavoritePreferred'] as bool? ?? false,
  autoFollowOnCollect: json['autoFollowOnCollect'] as bool? ?? false,
  autoFavoriteOnDownload: json['autoFavoriteOnDownload'] as bool? ?? false,
  writeDownloadMetadataFile:
      json['writeDownloadMetadataFile'] as bool? ?? false,
  leftHandModeEnabled: json['leftHandModeEnabled'] as bool? ?? false,
  clickCoverToStartReading: json['clickCoverToStartReading'] as bool? ?? false,
  comicInfoInlineReadButton: json['comicInfoInlineReadButton'] as bool? ?? true,
  startWithWorkspace: json['startWithWorkspace'] as bool? ?? false,
  transparentDesktopTitleBar:
      json['transparentDesktopTitleBar'] as bool? ?? false,
  transparentTitleBarFused: json['transparentTitleBarFused'] as bool? ?? false,
  searchHistory:
      (json['searchHistory'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  proxySetting: json['proxySetting'] == null
      ? const ProxySettingState()
      : ProxySettingState.fromJson(
          json['proxySetting'] as Map<String, dynamic>,
        ),
  windowWidth: (json['windowWidth'] as num?)?.toDouble() ?? 1280.0,
  windowHeight: (json['windowHeight'] as num?)?.toDouble() ?? 720.0,
  windowX: (json['windowX'] as num?)?.toDouble() ?? 0,
  windowY: (json['windowY'] as num?)?.toDouble() ?? 0,
  readSetting: json['readSetting'] == null
      ? const ReadSettingState()
      : ReadSettingState.fromJson(json['readSetting'] as Map<String, dynamic>),
  customExportPath: json['customExportPath'] as String? ?? '',
  appLockSetting: json['appLockSetting'] == null
      ? const AppLockSettingState()
      : AppLockSettingState.fromJson(
          json['appLockSetting'] as Map<String, dynamic>,
        ),
  compatibleVersion: json['compatibleVersion'] as String? ?? "",
  cacheSetting: json['cacheSetting'] == null
      ? const CacheSettingState()
      : CacheSettingState.fromJson(
          json['cacheSetting'] as Map<String, dynamic>,
        ),
  chineseConvertMode:
      $enumDecodeNullable(
        _$ChineseConvertModeEnumMap,
        json['chineseConvertMode'],
      ) ??
      ChineseConvertMode.off,
  bookshelfSetting: json['bookshelfSetting'] == null
      ? const BookshelfSettingState()
      : BookshelfSettingState.fromJson(
          json['bookshelfSetting'] as Map<String, dynamic>,
        ),
  favoriteArtistSetting: json['favoriteArtistSetting'] == null
      ? const FavoriteArtistSettingState()
      : FavoriteArtistSettingState.fromJson(
          json['favoriteArtistSetting'] as Map<String, dynamic>,
        ),
  comicCardSetting: json['comicCardSetting'] == null
      ? const ComicCardSettingState()
      : ComicCardSettingState.fromJson(
          json['comicCardSetting'] as Map<String, dynamic>,
        ),
  toastSetting: json['toastSetting'] == null
      ? const ToastSettingState()
      : ToastSettingState.fromJson(
          json['toastSetting'] as Map<String, dynamic>,
        ),
  switchToastSetting: json['switchToastSetting'] == null
      ? const SwitchToastSettingState()
      : SwitchToastSettingState.fromJson(
          json['switchToastSetting'] as Map<String, dynamic>,
        ),
  fileManagerSetting: json['fileManagerSetting'] == null
      ? const FileManagerSettingState()
      : FileManagerSettingState.fromJson(
          json['fileManagerSetting'] as Map<String, dynamic>,
        ),
  discoverSetting: json['discoverSetting'] == null
      ? const DiscoverSettingState()
      : DiscoverSettingState.fromJson(
          json['discoverSetting'] as Map<String, dynamic>,
        ),
  operationBindingSetting: json['operationBindingSetting'] == null
      ? const OperationBindingSettingState()
      : OperationBindingSettingState.fromJson(
          json['operationBindingSetting'] as Map<String, dynamic>,
        ),
);

Map<String, dynamic> _$GlobalSettingStateToJson(_GlobalSettingState instance) =>
    <String, dynamic>{
      'dynamicColor': instance.dynamicColor,
      'themeMode': _$ThemeModeEnumMap[instance.themeMode]!,
      'isAMOLED': instance.isAMOLED,
      'seedColor': const ColorConverter().toJson(instance.seedColor),
      'tweakcnThemeJson': instance.tweakcnThemeJson,
      'tweakcnThemeEnabled': instance.tweakcnThemeEnabled,
      'themeInitState': instance.themeInitState,
      'locale': const LocaleConverter().toJson(instance.locale),
      'localeFollowsSystem': instance.localeFollowsSystem,
      'welcomePageNum': instance.welcomePageNum,
      'syncSetting': instance.syncSetting.toJson(),
      'maskedKeywords': instance.maskedKeywords,
      'socks5ProxyEnabled': instance.socks5ProxyEnabled,
      'socks5Proxy': instance.socks5Proxy,
      'needCleanCache': instance.needCleanCache,
      'comicChoice': instance.comicChoice,
      'disableBika': instance.disableBika,
      'enableMemoryDebug': instance.enableMemoryDebug,
      'blockRustHttpRequests': instance.blockRustHttpRequests,
      'logAddress': instance.logAddress,
      'showLayoutOverflowStripes': instance.showLayoutOverflowStripes,
      'forceEnableImpeller': instance.forceEnableImpeller,
      'androidKeepAliveEnabled': instance.androidKeepAliveEnabled,
      'backPressExitEnabled': instance.backPressExitEnabled,
      'updateAccelerate': instance.updateAccelerate,
      'retryDownloadUntilSuccess': instance.retryDownloadUntilSuccess,
      'downloadConcurrency': instance.downloadConcurrency,
      'downloadDelayMs': instance.downloadDelayMs,
      'downloadAutoRetryCount': instance.downloadAutoRetryCount,
      'oldPageRollbackEnabled': instance.oldPageRollbackEnabled,
      'cloudFavoritePreferred': instance.cloudFavoritePreferred,
      'autoFollowOnCollect': instance.autoFollowOnCollect,
      'autoFavoriteOnDownload': instance.autoFavoriteOnDownload,
      'writeDownloadMetadataFile': instance.writeDownloadMetadataFile,
      'leftHandModeEnabled': instance.leftHandModeEnabled,
      'clickCoverToStartReading': instance.clickCoverToStartReading,
      'comicInfoInlineReadButton': instance.comicInfoInlineReadButton,
      'startWithWorkspace': instance.startWithWorkspace,
      'transparentDesktopTitleBar': instance.transparentDesktopTitleBar,
      'transparentTitleBarFused': instance.transparentTitleBarFused,
      'searchHistory': instance.searchHistory,
      'proxySetting': instance.proxySetting.toJson(),
      'windowWidth': instance.windowWidth,
      'windowHeight': instance.windowHeight,
      'windowX': instance.windowX,
      'windowY': instance.windowY,
      'readSetting': instance.readSetting.toJson(),
      'customExportPath': instance.customExportPath,
      'appLockSetting': instance.appLockSetting.toJson(),
      'compatibleVersion': instance.compatibleVersion,
      'cacheSetting': instance.cacheSetting.toJson(),
      'chineseConvertMode':
          _$ChineseConvertModeEnumMap[instance.chineseConvertMode]!,
      'bookshelfSetting': instance.bookshelfSetting.toJson(),
      'favoriteArtistSetting': instance.favoriteArtistSetting.toJson(),
      'comicCardSetting': instance.comicCardSetting.toJson(),
      'toastSetting': instance.toastSetting.toJson(),
      'switchToastSetting': instance.switchToastSetting.toJson(),
      'fileManagerSetting': instance.fileManagerSetting.toJson(),
      'discoverSetting': instance.discoverSetting.toJson(),
      'operationBindingSetting': instance.operationBindingSetting.toJson(),
    };

const _$ThemeModeEnumMap = {
  ThemeMode.system: 'system',
  ThemeMode.light: 'light',
  ThemeMode.dark: 'dark',
};

const _$ChineseConvertModeEnumMap = {
  ChineseConvertMode.off: 'off',
  ChineseConvertMode.simplified: 'simplified',
  ChineseConvertMode.traditional: 'traditional',
};

_FileManagerSettingState _$FileManagerSettingStateFromJson(
  Map<String, dynamic> json,
) => _FileManagerSettingState(
  homeEnabled: json['homeEnabled'] as bool? ?? true,
  homePath: json['homePath'] as String? ?? '',
  openHomeOnStart: json['openHomeOnStart'] as bool? ?? false,
  rememberViewState: json['rememberViewState'] as bool? ?? true,
  fileOperations: json['fileOperations'] as bool? ?? true,
);

Map<String, dynamic> _$FileManagerSettingStateToJson(
  _FileManagerSettingState instance,
) => <String, dynamic>{
  'homeEnabled': instance.homeEnabled,
  'homePath': instance.homePath,
  'openHomeOnStart': instance.openHomeOnStart,
  'rememberViewState': instance.rememberViewState,
  'fileOperations': instance.fileOperations,
};

_DiscoverSettingState _$DiscoverSettingStateFromJson(
  Map<String, dynamic> json,
) => _DiscoverSettingState(
  tabIconEnabled: json['tabIconEnabled'] as bool? ?? true,
  tabPluginShortEnabled: json['tabPluginShortEnabled'] as bool? ?? true,
  tabSide:
      $enumDecodeNullable(_$DiscoverTabBarSideEnumMap, json['tabSide']) ??
      DiscoverTabBarSide.top,
);

Map<String, dynamic> _$DiscoverSettingStateToJson(
  _DiscoverSettingState instance,
) => <String, dynamic>{
  'tabIconEnabled': instance.tabIconEnabled,
  'tabPluginShortEnabled': instance.tabPluginShortEnabled,
  'tabSide': _$DiscoverTabBarSideEnumMap[instance.tabSide]!,
};

const _$DiscoverTabBarSideEnumMap = {
  DiscoverTabBarSide.top: 'top',
  DiscoverTabBarSide.left: 'left',
  DiscoverTabBarSide.right: 'right',
};

_OperationBindingSettingState _$OperationBindingSettingStateFromJson(
  Map<String, dynamic> json,
) => _OperationBindingSettingState(
  bindingsRuntime: json['bindingsRuntime'] as bool? ?? true,
  bindingsJson: json['bindingsJson'] as String? ?? '',
  radialJson: json['radialJson'] as String? ?? '',
);

Map<String, dynamic> _$OperationBindingSettingStateToJson(
  _OperationBindingSettingState instance,
) => <String, dynamic>{
  'bindingsRuntime': instance.bindingsRuntime,
  'bindingsJson': instance.bindingsJson,
  'radialJson': instance.radialJson,
};

_ToastSettingState _$ToastSettingStateFromJson(Map<String, dynamic> json) =>
    _ToastSettingState(
      position:
          $enumDecodeNullable(_$ToastPositionEnumMap, json['position']) ??
          ToastPosition.topRight,
      edgePadding: (json['edgePadding'] as num?)?.toInt() ?? 12,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 3000,
      maxWidth: (json['maxWidth'] as num?)?.toInt() ?? 400,
      opacityPercent: (json['opacityPercent'] as num?)?.toInt() ?? 100,
      maxVisible: (json['maxVisible'] as num?)?.toInt() ?? 3,
      animationDurationMs:
          (json['animationDurationMs'] as num?)?.toInt() ?? 220,
      liquidGlass: json['liquidGlass'] as bool? ?? false,
      showProgressBar: json['showProgressBar'] as bool? ?? true,
      showIcon: json['showIcon'] as bool? ?? true,
      showCloseButton: json['showCloseButton'] as bool? ?? true,
    );

Map<String, dynamic> _$ToastSettingStateToJson(_ToastSettingState instance) =>
    <String, dynamic>{
      'position': _$ToastPositionEnumMap[instance.position]!,
      'edgePadding': instance.edgePadding,
      'durationMs': instance.durationMs,
      'maxWidth': instance.maxWidth,
      'opacityPercent': instance.opacityPercent,
      'maxVisible': instance.maxVisible,
      'animationDurationMs': instance.animationDurationMs,
      'liquidGlass': instance.liquidGlass,
      'showProgressBar': instance.showProgressBar,
      'showIcon': instance.showIcon,
      'showCloseButton': instance.showCloseButton,
    };

const _$ToastPositionEnumMap = {
  ToastPosition.topLeft: 'topLeft',
  ToastPosition.topCenter: 'topCenter',
  ToastPosition.topRight: 'topRight',
  ToastPosition.middleLeft: 'middleLeft',
  ToastPosition.center: 'center',
  ToastPosition.middleRight: 'middleRight',
  ToastPosition.bottomLeft: 'bottomLeft',
  ToastPosition.bottomCenter: 'bottomCenter',
  ToastPosition.bottomRight: 'bottomRight',
};

_SwitchToastSettingState _$SwitchToastSettingStateFromJson(
  Map<String, dynamic> json,
) => _SwitchToastSettingState(
  enableBook: json['enableBook'] as bool? ?? false,
  enablePage: json['enablePage'] as bool? ?? false,
  bookTitleTemplate:
      json['bookTitleTemplate'] as String? ??
      '已切换到 {{book.displayName}}（第 {{book.currentPageDisplay}} / {{book.totalPages}} 页）',
  bookDescriptionTemplate:
      json['bookDescriptionTemplate'] as String? ?? '路径：{{book.path}}',
  pageTitleTemplate:
      json['pageTitleTemplate'] as String? ??
      '第 {{page.indexDisplay}} / {{book.totalPages}} 页',
  pageDescriptionTemplate:
      json['pageDescriptionTemplate'] as String? ?? '{{page.name}}',
);

Map<String, dynamic> _$SwitchToastSettingStateToJson(
  _SwitchToastSettingState instance,
) => <String, dynamic>{
  'enableBook': instance.enableBook,
  'enablePage': instance.enablePage,
  'bookTitleTemplate': instance.bookTitleTemplate,
  'bookDescriptionTemplate': instance.bookDescriptionTemplate,
  'pageTitleTemplate': instance.pageTitleTemplate,
  'pageDescriptionTemplate': instance.pageDescriptionTemplate,
};

_FavoriteArtistSettingState _$FavoriteArtistSettingStateFromJson(
  Map<String, dynamic> json,
) => _FavoriteArtistSettingState(
  highlightEnabled: json['highlightEnabled'] as bool? ?? true,
  artists:
      (json['artists'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
);

Map<String, dynamic> _$FavoriteArtistSettingStateToJson(
  _FavoriteArtistSettingState instance,
) => <String, dynamic>{
  'highlightEnabled': instance.highlightEnabled,
  'artists': instance.artists,
};

_ComicCardSettingState _$ComicCardSettingStateFromJson(
  Map<String, dynamic> json,
) => _ComicCardSettingState(
  downloadBadgeEnabled: json['downloadBadgeEnabled'] as bool? ?? true,
  translationBadgeEnabled: json['translationBadgeEnabled'] as bool? ?? true,
  readButtonEnabled: json['readButtonEnabled'] as bool? ?? true,
);

Map<String, dynamic> _$ComicCardSettingStateToJson(
  _ComicCardSettingState instance,
) => <String, dynamic>{
  'downloadBadgeEnabled': instance.downloadBadgeEnabled,
  'translationBadgeEnabled': instance.translationBadgeEnabled,
  'readButtonEnabled': instance.readButtonEnabled,
};

_CacheSettingState _$CacheSettingStateFromJson(Map<String, dynamic> json) =>
    _CacheSettingState(
      autoCleanCache: json['autoCleanCache'] as bool? ?? true,
      cacheSizeLimit: (json['cacheSizeLimit'] as num?)?.toInt() ?? 1073741824,
    );

Map<String, dynamic> _$CacheSettingStateToJson(_CacheSettingState instance) =>
    <String, dynamic>{
      'autoCleanCache': instance.autoCleanCache,
      'cacheSizeLimit': instance.cacheSizeLimit,
    };

_AppLockSettingState _$AppLockSettingStateFromJson(Map<String, dynamic> json) =>
    _AppLockSettingState(
      enabled: json['enabled'] as bool? ?? false,
      gesturePasswordHash: json['gesturePasswordHash'] as String? ?? '',
      resetPinHash: json['resetPinHash'] as String? ?? '',
    );

Map<String, dynamic> _$AppLockSettingStateToJson(
  _AppLockSettingState instance,
) => <String, dynamic>{
  'enabled': instance.enabled,
  'gesturePasswordHash': instance.gesturePasswordHash,
  'resetPinHash': instance.resetPinHash,
};

_ProxySettingState _$ProxySettingStateFromJson(
  Map<String, dynamic> json,
) => _ProxySettingState(
  enabled: json['enabled'] as bool? ?? false,
  type: $enumDecodeNullable(_$ProxyTypeEnumMap, json['type']) ?? ProxyType.http,
  address: json['address'] as String? ?? '',
);

Map<String, dynamic> _$ProxySettingStateToJson(_ProxySettingState instance) =>
    <String, dynamic>{
      'enabled': instance.enabled,
      'type': _$ProxyTypeEnumMap[instance.type]!,
      'address': instance.address,
    };

const _$ProxyTypeEnumMap = {ProxyType.http: 'http', ProxyType.socks5: 'socks5'};

_WebDavSettingState _$WebDavSettingStateFromJson(Map<String, dynamic> json) =>
    _WebDavSettingState(
      host: json['host'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
    );

Map<String, dynamic> _$WebDavSettingStateToJson(_WebDavSettingState instance) =>
    <String, dynamic>{
      'host': instance.host,
      'username': instance.username,
      'password': instance.password,
    };

_S3SettingState _$S3SettingStateFromJson(Map<String, dynamic> json) =>
    _S3SettingState(
      endpoint: json['endpoint'] as String? ?? '',
      accessKey: json['accessKey'] as String? ?? '',
      secretKey: json['secretKey'] as String? ?? '',
      bucket: json['bucket'] as String? ?? '',
      region: json['region'] as String? ?? '',
      useSSL: json['useSSL'] as bool? ?? true,
      port: (json['port'] as num?)?.toInt() ?? 0,
      pathStyle: json['pathStyle'] as bool? ?? false,
    );

Map<String, dynamic> _$S3SettingStateToJson(_S3SettingState instance) =>
    <String, dynamic>{
      'endpoint': instance.endpoint,
      'accessKey': instance.accessKey,
      'secretKey': instance.secretKey,
      'bucket': instance.bucket,
      'region': instance.region,
      'useSSL': instance.useSSL,
      'port': instance.port,
      'pathStyle': instance.pathStyle,
    };

_SyncSettingState _$SyncSettingStateFromJson(Map<String, dynamic> json) =>
    _SyncSettingState(
      syncServiceType:
          $enumDecodeNullable(
            _$SyncServiceTypeEnumMap,
            json['syncServiceType'],
          ) ??
          SyncServiceType.none,
      webdavSetting: json['webdavSetting'] == null
          ? const WebDavSettingState()
          : WebDavSettingState.fromJson(
              json['webdavSetting'] as Map<String, dynamic>,
            ),
      s3Setting: json['s3Setting'] == null
          ? const S3SettingState()
          : S3SettingState.fromJson(json['s3Setting'] as Map<String, dynamic>),
      syncSettings: json['syncSettings'] as bool? ?? false,
      syncPlugins: json['syncPlugins'] as bool? ?? false,
      autoSync: json['autoSync'] as bool? ?? true,
      syncNotify: json['syncNotify'] as bool? ?? true,
      settingsSyncTime: (json['settingsSyncTime'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$SyncSettingStateToJson(_SyncSettingState instance) =>
    <String, dynamic>{
      'syncServiceType': _$SyncServiceTypeEnumMap[instance.syncServiceType]!,
      'webdavSetting': instance.webdavSetting.toJson(),
      's3Setting': instance.s3Setting.toJson(),
      'syncSettings': instance.syncSettings,
      'syncPlugins': instance.syncPlugins,
      'autoSync': instance.autoSync,
      'syncNotify': instance.syncNotify,
      'settingsSyncTime': instance.settingsSyncTime,
    };

const _$SyncServiceTypeEnumMap = {
  SyncServiceType.none: 'none',
  SyncServiceType.webdav: 'webdav',
  SyncServiceType.s3: 's3',
};

_ReadSettingState _$ReadSettingStateFromJson(Map<String, dynamic> json) =>
    _ReadSettingState(
      noAnimation: json['noAnimation'] as bool? ?? false,
      comicReadTopContainer: json['comicReadTopContainer'] as bool? ?? true,
      readMode: (json['readMode'] as num?)?.toInt() ?? 0,
      tapPageTurnMode:
          $enumDecodeNullable(
            _$ReaderTapPageTurnModeEnumMap,
            json['tapPageTurnMode'],
          ) ??
          ReaderTapPageTurnMode.rightHand,
      tapPageTurnInWebtoon: json['tapPageTurnInWebtoon'] as bool? ?? false,
      readerBackgroundMode:
          $enumDecodeNullable(
            _$ReaderBackgroundModeEnumMap,
            json['readerBackgroundMode'],
            unknownValue: ReaderBackgroundMode.auto,
          ) ??
          ReaderBackgroundMode.auto,
      readerAmbientDimPercent:
          (json['readerAmbientDimPercent'] as num?)?.toInt() ??
          readerAmbientDimPercentDefault,
      readFilterEnabled: json['readFilterEnabled'] as bool? ?? true,
      readFilterOpacityPercent:
          (json['readFilterOpacityPercent'] as num?)?.toInt() ?? 50,
      einkOptimization: json['einkOptimization'] as bool? ?? false,
      einkDelayMs: (json['einkDelayMs'] as num?)?.toInt() ?? 120,
      autoScroll: json['autoScroll'] as bool? ?? false,
      autoScrollHidePauseButton:
          json['autoScrollHidePauseButton'] as bool? ?? false,
      autoScrollSmooth: json['autoScrollSmooth'] as bool? ?? false,
      autoScrollColumnIntervalMs:
          (json['autoScrollColumnIntervalMs'] as num?)?.toInt() ?? 1600,
      autoScrollPageIntervalMs:
          (json['autoScrollPageIntervalMs'] as num?)?.toInt() ?? 3000,
      autoScrollColumnDistancePercent:
          (json['autoScrollColumnDistancePercent'] as num?)?.toInt() ?? 72,
      preloadImageCount: (json['preloadImageCount'] as num?)?.toInt() ?? 3,
      preloadChapterCount: (json['preloadChapterCount'] as num?)?.toInt() ?? 1,
      readWhileDownloading: json['readWhileDownloading'] as bool? ?? true,
      landscapeReader: json['landscapeReader'] as bool? ?? false,
      doublePageMode: json['doublePageMode'] as bool? ?? false,
      doublePageSeamless: json['doublePageSeamless'] as bool? ?? false,
      doublePageLeadingBlank: json['doublePageLeadingBlank'] as bool? ?? false,
      splitLandscapePages: json['splitLandscapePages'] as bool? ?? false,
      landscapeSplitDirection:
          (json['landscapeSplitDirection'] as num?)?.toInt() ?? 0,
      sidePaddingEnabled: json['sidePaddingEnabled'] as bool? ?? false,
      sidePaddingPercent: (json['sidePaddingPercent'] as num?)?.toInt() ?? 10,
      volumeKeyPageTurn: json['volumeKeyPageTurn'] as bool? ?? true,
      volumeKeyPageTurnDistancePercent:
          (json['volumeKeyPageTurnDistancePercent'] as num?)?.toInt() ?? 72,
      doubleTapZoom: json['doubleTapZoom'] as bool? ?? false,
      doubleTapOpenMenu: json['doubleTapOpenMenu'] as bool? ?? false,
      pageInfoShowPage: json['pageInfoShowPage'] as bool? ?? true,
      pageInfoShowNetwork: json['pageInfoShowNetwork'] as bool? ?? true,
      pageInfoShowBattery: json['pageInfoShowBattery'] as bool? ?? false,
      pageInfoShowTime: json['pageInfoShowTime'] as bool? ?? true,
      pageInfoVerticalPosition:
          $enumDecodeNullable(
            _$ReaderInfoVerticalPositionEnumMap,
            json['pageInfoVerticalPosition'],
          ) ??
          ReaderInfoVerticalPosition.bottom,
      pageInfoTopInStatusBar: json['pageInfoTopInStatusBar'] as bool? ?? false,
      pageInfoHorizontalPosition:
          $enumDecodeNullable(
            _$ReaderInfoHorizontalPositionEnumMap,
            json['pageInfoHorizontalPosition'],
          ) ??
          ReaderInfoHorizontalPosition.left,
      pageInfoEdgePadding: (json['pageInfoEdgePadding'] as num?)?.toInt() ?? 12,
      pageInfoOpacityPercent:
          (json['pageInfoOpacityPercent'] as num?)?.toInt() ?? 82,
      pageInfoFontSize: (json['pageInfoFontSize'] as num?)?.toInt() ?? 12,
      showBottomProgressBar: json['showBottomProgressBar'] as bool? ?? false,
      bottomProgressBarGlow: json['bottomProgressBarGlow'] as bool? ?? true,
      hoverRevealEnabled: json['hoverRevealEnabled'] as bool? ?? true,
      hoverRevealTop: json['hoverRevealTop'] as bool? ?? true,
      hoverRevealBottom: json['hoverRevealBottom'] as bool? ?? true,
      hoverTriggerAreaTop: (json['hoverTriggerAreaTop'] as num?)?.toInt() ?? 32,
      hoverTriggerAreaBottom:
          (json['hoverTriggerAreaBottom'] as num?)?.toInt() ?? 32,
      hoverHideDelayMs: (json['hoverHideDelayMs'] as num?)?.toInt() ?? 500,
      hoverShowVisualIndicator:
          json['hoverShowVisualIndicator'] as bool? ?? false,
      centerTapToggleBars: json['centerTapToggleBars'] as bool? ?? true,
      topBarPinned: json['topBarPinned'] as bool? ?? false,
      bottomBarPinned: json['bottomBarPinned'] as bool? ?? false,
      showThumbnailStrip: json['showThumbnailStrip'] as bool? ?? false,
      transparentTopBar: json['transparentTopBar'] as bool? ?? false,
      topBarScrimOpacityPercent:
          (json['topBarScrimOpacityPercent'] as num?)?.toInt() ?? 85,
      readingDirectionToggle: json['readingDirectionToggle'] as bool? ?? true,
      readerFitMode:
          $enumDecodeNullable(_$ReaderFitModeEnumMap, json['readerFitMode']) ??
          ReaderFitMode.fit,
      readerAutoRotation:
          $enumDecodeNullable(
            _$ReaderAutoRotationEnumMap,
            json['readerAutoRotation'],
          ) ??
          ReaderAutoRotation.none,
      readerWidePageStretch:
          $enumDecodeNullable(
            _$ReaderWidePageStretchEnumMap,
            json['readerWidePageStretch'],
          ) ??
          ReaderWidePageStretch.none,
    );

Map<String, dynamic> _$ReadSettingStateToJson(
  _ReadSettingState instance,
) => <String, dynamic>{
  'noAnimation': instance.noAnimation,
  'comicReadTopContainer': instance.comicReadTopContainer,
  'readMode': instance.readMode,
  'tapPageTurnMode': _$ReaderTapPageTurnModeEnumMap[instance.tapPageTurnMode]!,
  'tapPageTurnInWebtoon': instance.tapPageTurnInWebtoon,
  'readerBackgroundMode':
      _$ReaderBackgroundModeEnumMap[instance.readerBackgroundMode]!,
  'readerAmbientDimPercent': instance.readerAmbientDimPercent,
  'readFilterEnabled': instance.readFilterEnabled,
  'readFilterOpacityPercent': instance.readFilterOpacityPercent,
  'einkOptimization': instance.einkOptimization,
  'einkDelayMs': instance.einkDelayMs,
  'autoScroll': instance.autoScroll,
  'autoScrollHidePauseButton': instance.autoScrollHidePauseButton,
  'autoScrollSmooth': instance.autoScrollSmooth,
  'autoScrollColumnIntervalMs': instance.autoScrollColumnIntervalMs,
  'autoScrollPageIntervalMs': instance.autoScrollPageIntervalMs,
  'autoScrollColumnDistancePercent': instance.autoScrollColumnDistancePercent,
  'preloadImageCount': instance.preloadImageCount,
  'preloadChapterCount': instance.preloadChapterCount,
  'readWhileDownloading': instance.readWhileDownloading,
  'landscapeReader': instance.landscapeReader,
  'doublePageMode': instance.doublePageMode,
  'doublePageSeamless': instance.doublePageSeamless,
  'doublePageLeadingBlank': instance.doublePageLeadingBlank,
  'splitLandscapePages': instance.splitLandscapePages,
  'landscapeSplitDirection': instance.landscapeSplitDirection,
  'sidePaddingEnabled': instance.sidePaddingEnabled,
  'sidePaddingPercent': instance.sidePaddingPercent,
  'volumeKeyPageTurn': instance.volumeKeyPageTurn,
  'volumeKeyPageTurnDistancePercent': instance.volumeKeyPageTurnDistancePercent,
  'doubleTapZoom': instance.doubleTapZoom,
  'doubleTapOpenMenu': instance.doubleTapOpenMenu,
  'pageInfoShowPage': instance.pageInfoShowPage,
  'pageInfoShowNetwork': instance.pageInfoShowNetwork,
  'pageInfoShowBattery': instance.pageInfoShowBattery,
  'pageInfoShowTime': instance.pageInfoShowTime,
  'pageInfoVerticalPosition':
      _$ReaderInfoVerticalPositionEnumMap[instance.pageInfoVerticalPosition]!,
  'pageInfoTopInStatusBar': instance.pageInfoTopInStatusBar,
  'pageInfoHorizontalPosition':
      _$ReaderInfoHorizontalPositionEnumMap[instance
          .pageInfoHorizontalPosition]!,
  'pageInfoEdgePadding': instance.pageInfoEdgePadding,
  'pageInfoOpacityPercent': instance.pageInfoOpacityPercent,
  'pageInfoFontSize': instance.pageInfoFontSize,
  'showBottomProgressBar': instance.showBottomProgressBar,
  'bottomProgressBarGlow': instance.bottomProgressBarGlow,
  'hoverRevealEnabled': instance.hoverRevealEnabled,
  'hoverRevealTop': instance.hoverRevealTop,
  'hoverRevealBottom': instance.hoverRevealBottom,
  'hoverTriggerAreaTop': instance.hoverTriggerAreaTop,
  'hoverTriggerAreaBottom': instance.hoverTriggerAreaBottom,
  'hoverHideDelayMs': instance.hoverHideDelayMs,
  'hoverShowVisualIndicator': instance.hoverShowVisualIndicator,
  'centerTapToggleBars': instance.centerTapToggleBars,
  'topBarPinned': instance.topBarPinned,
  'bottomBarPinned': instance.bottomBarPinned,
  'showThumbnailStrip': instance.showThumbnailStrip,
  'transparentTopBar': instance.transparentTopBar,
  'topBarScrimOpacityPercent': instance.topBarScrimOpacityPercent,
  'readingDirectionToggle': instance.readingDirectionToggle,
  'readerFitMode': _$ReaderFitModeEnumMap[instance.readerFitMode]!,
  'readerAutoRotation':
      _$ReaderAutoRotationEnumMap[instance.readerAutoRotation]!,
  'readerWidePageStretch':
      _$ReaderWidePageStretchEnumMap[instance.readerWidePageStretch]!,
};

const _$ReaderTapPageTurnModeEnumMap = {
  ReaderTapPageTurnMode.fullScreen: 'fullScreen',
  ReaderTapPageTurnMode.leftHand: 'leftHand',
  ReaderTapPageTurnMode.rightHand: 'rightHand',
};

const _$ReaderBackgroundModeEnumMap = {
  ReaderBackgroundMode.auto: 'auto',
  ReaderBackgroundMode.black: 'black',
  ReaderBackgroundMode.white: 'white',
  ReaderBackgroundMode.grey: 'grey',
  ReaderBackgroundMode.adaptive: 'adaptive',
  ReaderBackgroundMode.adaptiveEdge: 'adaptiveEdge',
};

const _$ReaderInfoVerticalPositionEnumMap = {
  ReaderInfoVerticalPosition.top: 'top',
  ReaderInfoVerticalPosition.bottom: 'bottom',
};

const _$ReaderInfoHorizontalPositionEnumMap = {
  ReaderInfoHorizontalPosition.left: 'left',
  ReaderInfoHorizontalPosition.center: 'center',
  ReaderInfoHorizontalPosition.right: 'right',
};

const _$ReaderFitModeEnumMap = {
  ReaderFitMode.fit: 'fit',
  ReaderFitMode.fill: 'fill',
  ReaderFitMode.fitWidth: 'fitWidth',
  ReaderFitMode.fitHeight: 'fitHeight',
  ReaderFitMode.original: 'original',
  ReaderFitMode.fitLeft: 'fitLeft',
  ReaderFitMode.fitRight: 'fitRight',
};

const _$ReaderAutoRotationEnumMap = {
  ReaderAutoRotation.none: 'none',
  ReaderAutoRotation.left: 'left',
  ReaderAutoRotation.right: 'right',
  ReaderAutoRotation.horizontalLeft: 'horizontalLeft',
  ReaderAutoRotation.horizontalRight: 'horizontalRight',
  ReaderAutoRotation.forcedLeft: 'forcedLeft',
  ReaderAutoRotation.forcedRight: 'forcedRight',
};

const _$ReaderWidePageStretchEnumMap = {
  ReaderWidePageStretch.none: 'none',
  ReaderWidePageStretch.uniformHeight: 'uniformHeight',
  ReaderWidePageStretch.uniformWidth: 'uniformWidth',
};

_BookshelfSettingState _$BookshelfSettingStateFromJson(
  Map<String, dynamic> json,
) => _BookshelfSettingState(
  homePageIndex: (json['homePageIndex'] as num?)?.toInt() ?? 0,
  rememberFavoriteSort: json['rememberFavoriteSort'] as bool? ?? false,
  favoriteSort: json['favoriteSort'] as String? ?? 'dd',
  rememberHistorySort: json['rememberHistorySort'] as bool? ?? false,
  historySort: json['historySort'] as String? ?? 'dd',
  rememberDownloadSort: json['rememberDownloadSort'] as bool? ?? false,
  downloadSort: json['downloadSort'] as String? ?? 'dd',
  shelfCardContextMenu: json['shelfCardContextMenu'] as bool? ?? true,
);

Map<String, dynamic> _$BookshelfSettingStateToJson(
  _BookshelfSettingState instance,
) => <String, dynamic>{
  'homePageIndex': instance.homePageIndex,
  'rememberFavoriteSort': instance.rememberFavoriteSort,
  'favoriteSort': instance.favoriteSort,
  'rememberHistorySort': instance.rememberHistorySort,
  'historySort': instance.historySort,
  'rememberDownloadSort': instance.rememberDownloadSort,
  'downloadSort': instance.downloadSort,
  'shelfCardContextMenu': instance.shelfCardContextMenu,
};
