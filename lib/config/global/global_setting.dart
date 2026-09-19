// 全局设置

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:zephyr/config/global/color_theme_types.dart';
import 'package:zephyr/i18n/i18n_helper.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/util/json/converter.dart';

part 'global_setting.freezed.dart';
part 'global_setting.g.dart';

enum ReaderInfoVerticalPosition { top, bottom }

enum ReaderInfoHorizontalPosition { left, center, right }

enum ReaderBackgroundMode { auto, black, white, grey }

enum ReaderTapPageTurnMode { fullScreen, leftHand, rightHand }

enum SyncServiceType { none, webdav, s3 }

/// 代理协议类型。
enum ProxyType { http, socks5 }

/// 提示条（toast）在屏幕上的停靠位置，九宫格。
///
/// 口径参考 neoview 的「提示悬浮窗」：位置可配、可调边距，
/// 对应关系 [ToastPosition.topLeft] → `Alignment.topLeft` 等。
enum ToastPosition {
  topLeft,
  topCenter,
  topRight,
  middleLeft,
  center,
  middleRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

extension ToastPositionExtension on ToastPosition {
  String get label {
    switch (this) {
      case ToastPosition.topLeft:
        return t.settings.toastPositionTopLeft;
      case ToastPosition.topCenter:
        return t.settings.toastPositionTopCenter;
      case ToastPosition.topRight:
        return t.settings.toastPositionTopRight;
      case ToastPosition.middleLeft:
        return t.settings.toastPositionMiddleLeft;
      case ToastPosition.center:
        return t.settings.toastPositionCenter;
      case ToastPosition.middleRight:
        return t.settings.toastPositionMiddleRight;
      case ToastPosition.bottomLeft:
        return t.settings.toastPositionBottomLeft;
      case ToastPosition.bottomCenter:
        return t.settings.toastPositionBottomCenter;
      case ToastPosition.bottomRight:
        return t.settings.toastPositionBottomRight;
    }
  }
}

extension SyncServiceTypeExtension on SyncServiceType {
  String get label {
    switch (this) {
      case SyncServiceType.none:
        return t.common.disabled;
      case SyncServiceType.webdav:
        return 'WebDAV';
      case SyncServiceType.s3:
        return 'S3';
    }
  }
}

// 简繁转换模式:off 不转换;simplified 转简体;traditional 转繁体
enum ChineseConvertMode { off, simplified, traditional }

extension ChineseConvertModeExtension on ChineseConvertMode {
  String get label {
    switch (this) {
      case ChineseConvertMode.off:
        return t.settings.chineseConvertOff;
      case ChineseConvertMode.simplified:
        return t.settings.chineseConvertSimplified;
      case ChineseConvertMode.traditional:
        return t.settings.chineseConvertTraditional;
    }
  }

  // 对应的 OpenCC 配置文件名;off 时返回空字符串(不转换)
  String get openccConfig {
    switch (this) {
      case ChineseConvertMode.off:
        return '';
      case ChineseConvertMode.simplified:
        return 'tw2sp.json';
      case ChineseConvertMode.traditional:
        return 's2twp.json';
    }
  }
}

const Color readerBackgroundBlack = Colors.black;
const Color readerBackgroundWhite = Colors.white;
const Color readerBackgroundGrey = Color(0xFF2D2D2D);

extension ReadSettingStateBackgroundColor on ReadSettingState {
  Color resolveReaderBackgroundColor(Brightness brightness) {
    switch (readerBackgroundMode) {
      case ReaderBackgroundMode.auto:
        return brightness == Brightness.dark
            ? readerBackgroundBlack
            : readerBackgroundWhite;
      case ReaderBackgroundMode.black:
        return readerBackgroundBlack;
      case ReaderBackgroundMode.white:
        return readerBackgroundWhite;
      case ReaderBackgroundMode.grey:
        return readerBackgroundGrey;
    }
  }

  Color resolveReaderForegroundColor(Brightness brightness) {
    final backgroundColor = resolveReaderBackgroundColor(brightness);
    return backgroundColor.computeLuminance() < 0.5
        ? Colors.white
        : Colors.black;
  }
}

GlobalSettingState get globalSetting {
  return objectbox.userSettingBox.get(1)!.globalSetting;
}

/// 提示条设置的读入口。
///
/// 提示（toast）会在**任意时刻**被触发（后台下载完成、同步失败……），
/// 这些调用点多半拿不到 `BuildContext`/Cubit，所以这里直接从本地库读；
/// 本地库还没起来（启动早期）或已关闭时回落到默认样式 ——
/// 绝不让「读设置」本身把提示炸掉。
ToastSettingState get toastSetting {
  try {
    return objectbox.userSettingBox.get(1)?.globalSetting.toastSetting ??
        const ToastSettingState();
  } catch (_) {
    return const ToastSettingState();
  }
}

@freezed
abstract class GlobalSettingState with _$GlobalSettingState {
  const factory GlobalSettingState({
    @Default(true) bool dynamicColor,
    @Default(ThemeMode.system) ThemeMode themeMode,
    @Default(true) bool isAMOLED,
    @ColorConverter() @Default(Color(0xFFEF5350)) Color seedColor,
    @Default(0) int themeInitState,
    @LocaleConverter() @Default(Locale('zh', 'CN')) Locale locale,
    @Default(true) bool localeFollowsSystem,
    @Default(0) int welcomePageNum,
    @Default(SyncSettingState()) SyncSettingState syncSetting,
    @Default([]) List<String> maskedKeywords,
    @Default(true) bool socks5ProxyEnabled,
    @Default('') String socks5Proxy,
    @Default(false) bool needCleanCache,
    @Default(1) int comicChoice,
    @Default(false) bool disableBika,
    @Default(false) bool enableMemoryDebug,
    @Default(false) bool blockRustHttpRequests,
    @Default('') String logAddress,
    @Default(false) bool forceEnableImpeller,
    @Default(false) bool androidKeepAliveEnabled,
    @Default(false) bool backPressExitEnabled,
    @Default(true) bool updateAccelerate,
    @Default(true) bool retryDownloadUntilSuccess,
    @Default(3) int downloadConcurrency,
    @Default(150) int downloadDelayMs,
    @Default(3) int downloadAutoRetryCount,
    @Default(false) bool oldPageRollbackEnabled,
    @Default(false) bool cloudFavoritePreferred,
    @Default(false) bool autoFollowOnCollect,
    @Default(false) bool autoFavoriteOnDownload,
    @Default(false) bool leftHandModeEnabled,
    @Default(false) bool clickCoverToStartReading,
    // 详情页「阅读」入口：桌面端放进操作行（「下载」旁边），并撤掉右下角的悬浮按钮。
    // 触摸端不受这个开关影响 —— 那边只有悬浮按钮一种落点。
    @Default(true) bool comicInfoInlineReadButton,
    // 启动后是否直接进工作台（泳道 / 四边栏）。默认关 = 改造前的行为（落在导航栏）。
    // 只在**真有工作台入口**的布局（平板 / 桌面四边栏）落地，手机端忽略 ——
    // 判定收在 `lib/workspace/model/workspace_startup.dart`。
    @Default(false) bool startWithWorkspace,
    @Default([]) List<String> searchHistory,
    @Default(ProxySettingState()) ProxySettingState proxySetting,
    @Default(1280.0) double windowWidth,
    @Default(720.0) double windowHeight,
    @Default(0) double windowX,
    @Default(0) double windowY,
    @Default(ReadSettingState()) ReadSettingState readSetting,
    @Default('') String customExportPath,
    @Default(AppLockSettingState()) AppLockSettingState appLockSetting,
    @Default("") String compatibleVersion,
    @Default(CacheSettingState()) CacheSettingState cacheSetting,
    @Default(ChineseConvertMode.off) ChineseConvertMode chineseConvertMode,
    @Default(BookshelfSettingState()) BookshelfSettingState bookshelfSetting,
    @Default(FavoriteArtistSettingState())
    FavoriteArtistSettingState favoriteArtistSetting,
    @Default(ComicCardSettingState()) ComicCardSettingState comicCardSetting,
    @Default(ToastSettingState()) ToastSettingState toastSetting,
  }) = _GlobalSettingState;

  factory GlobalSettingState.fromJson(Map<String, dynamic> json) =>
      _$GlobalSettingStateFromJson(json);
}

/// 提示条（toast）的位置、时长与外观。
///
/// 字段口径（对齐 neoview 的 switchToast 配置，落到 Flutter 的九宫格 + 尺寸）：
/// - [position] / [edgePadding]：停靠位置与距屏幕边缘的安全留白；
/// - [durationMs]：自动关闭时长，`0` 表示常驻（只能手动关闭）；
/// - [maxWidth]：卡片最大宽度（手机端还会被屏幕宽度再夹一次）；
/// - [opacityPercent]：整卡不透明度；
/// - [maxVisible]：同屏最多堆叠条数，超出时挤掉最旧的一条；
/// - [animationDurationMs]：进出场动画时长；
/// - [liquidGlass]：液态玻璃（模糊 + 半透明）背景；
/// - [showProgressBar] / [showIcon] / [showCloseButton]：进度条、类型图标、关闭按钮。
@freezed
abstract class ToastSettingState with _$ToastSettingState {
  const factory ToastSettingState({
    @Default(ToastPosition.topRight) ToastPosition position,
    @Default(12) int edgePadding,
    @Default(3000) int durationMs,
    @Default(400) int maxWidth,
    @Default(100) int opacityPercent,
    @Default(3) int maxVisible,
    @Default(220) int animationDurationMs,
    @Default(false) bool liquidGlass,
    @Default(true) bool showProgressBar,
    @Default(true) bool showIcon,
    @Default(true) bool showCloseButton,
  }) = _ToastSettingState;

  factory ToastSettingState.fromJson(Map<String, dynamic> json) =>
      _$ToastSettingStateFromJson(json);
}

@freezed
abstract class FavoriteArtistSettingState with _$FavoriteArtistSettingState {
  const factory FavoriteArtistSettingState({
    @Default(true) bool highlightEnabled,
    @Default([]) List<String> artists,
  }) = _FavoriteArtistSettingState;

  factory FavoriteArtistSettingState.fromJson(Map<String, dynamic> json) =>
      _$FavoriteArtistSettingStateFromJson(json);
}

/// 漫画卡片上的封面角标显示开关。
///
/// 约定：**新加的卡片角标一律要在这里有一个开关**，默认开，
/// 用户随时能在「设置 → 书架 → 卡片角标」关掉（见 `.workbuddy/memory/MEMORY.md`）。
/// 组件自身的 `showXxx` 参数是**给具体页面**用的（某页不想要角标），
/// 这里是**给用户**用的总开关，两者是「与」的关系。
@freezed
abstract class ComicCardSettingState with _$ComicCardSettingState {
  const factory ComicCardSettingState({
    @Default(true) bool downloadBadgeEnabled,
    @Default(true) bool translationBadgeEnabled,
  }) = _ComicCardSettingState;

  factory ComicCardSettingState.fromJson(Map<String, dynamic> json) =>
      _$ComicCardSettingStateFromJson(json);
}

/// 角标开关的读入口（非 widget 上下文也能读）。
///
/// 同 [toastSetting]：读设置这件事本身不能把调用方炸掉。
ComicCardSettingState get comicCardSetting {
  try {
    return objectbox.userSettingBox.get(1)?.globalSetting.comicCardSetting ??
        const ComicCardSettingState();
  } catch (_) {
    return const ComicCardSettingState();
  }
}

@freezed
abstract class CacheSettingState with _$CacheSettingState {
  const factory CacheSettingState({
    @Default(true) bool autoCleanCache,
    @Default(1073741824) int cacheSizeLimit,
  }) = _CacheSettingState;

  factory CacheSettingState.fromJson(Map<String, dynamic> json) =>
      _$CacheSettingStateFromJson(json);
}

@freezed
abstract class AppLockSettingState with _$AppLockSettingState {
  const AppLockSettingState._();

  const factory AppLockSettingState({
    @Default(false) bool enabled,
    @Default('') String gesturePasswordHash,
    @Default('') String resetPinHash,
  }) = _AppLockSettingState;

  factory AppLockSettingState.fromJson(Map<String, dynamic> json) =>
      _$AppLockSettingStateFromJson(json);

  bool get hasGesturePassword => gesturePasswordHash.trim().isNotEmpty;

  bool get hasResetPin => resetPinHash.trim().isNotEmpty;

  bool get isReady => hasGesturePassword && hasResetPin;
}

@freezed
abstract class ProxySettingState with _$ProxySettingState {
  const factory ProxySettingState({
    @Default(false) bool enabled,
    @Default(ProxyType.http) ProxyType type,
    @Default('') String address,
  }) = _ProxySettingState;

  factory ProxySettingState.fromJson(Map<String, dynamic> json) =>
      _$ProxySettingStateFromJson(json);
}

@freezed
abstract class WebDavSettingState with _$WebDavSettingState {
  const factory WebDavSettingState({
    @Default('') String host,
    @Default('') String username,
    @Default('') String password,
  }) = _WebDavSettingState;

  factory WebDavSettingState.fromJson(Map<String, dynamic> json) =>
      _$WebDavSettingStateFromJson(json);
}

@freezed
abstract class S3SettingState with _$S3SettingState {
  const factory S3SettingState({
    @Default('') String endpoint,
    @Default('') String accessKey,
    @Default('') String secretKey,
    @Default('') String bucket,
    @Default('') String region,
    @Default(true) bool useSSL,
    @Default(0) int port,
    @Default(false) bool pathStyle,
  }) = _S3SettingState;

  factory S3SettingState.fromJson(Map<String, dynamic> json) =>
      _$S3SettingStateFromJson(json);
}

@freezed
abstract class SyncSettingState with _$SyncSettingState {
  const factory SyncSettingState({
    @Default(SyncServiceType.none) SyncServiceType syncServiceType,
    @Default(WebDavSettingState()) WebDavSettingState webdavSetting,
    @Default(S3SettingState()) S3SettingState s3Setting,
    @Default(false) bool syncSettings,
    @Default(false) bool syncPlugins,
    @Default(true) bool autoSync,
    @Default(true) bool syncNotify,
    @Default(0) int settingsSyncTime,
  }) = _SyncSettingState;

  factory SyncSettingState.fromJson(Map<String, dynamic> json) =>
      _$SyncSettingStateFromJson(json);
}

@freezed
abstract class ReadSettingState with _$ReadSettingState {
  const factory ReadSettingState({
    @Default(false) bool noAnimation,
    @Default(true) bool comicReadTopContainer,
    @Default(0) int readMode,
    @Default(ReaderTapPageTurnMode.rightHand)
    ReaderTapPageTurnMode tapPageTurnMode,
    @Default(false) bool tapPageTurnInWebtoon,
    @Default(ReaderBackgroundMode.auto)
    ReaderBackgroundMode readerBackgroundMode,
    @Default(true) bool readFilterEnabled,
    @Default(50) int readFilterOpacityPercent,
    @Default(false) bool einkOptimization,
    @Default(120) int einkDelayMs,
    @Default(false) bool autoScroll,
    @Default(false) bool autoScrollHidePauseButton,
    @Default(false) bool autoScrollSmooth,
    @Default(1600) int autoScrollColumnIntervalMs,
    @Default(3000) int autoScrollPageIntervalMs,
    @Default(72) int autoScrollColumnDistancePercent,
    @Default(3) int preloadImageCount,
    @Default(1) int preloadChapterCount,
    @Default(true) bool readWhileDownloading,
    @Default(false) bool landscapeReader,
    @Default(false) bool doublePageMode,
    @Default(false) bool doublePageSeamless,
    @Default(false) bool doublePageLeadingBlank,
    @Default(false) bool splitLandscapePages,
    @Default(0) int landscapeSplitDirection,
    @Default(false) bool sidePaddingEnabled,
    @Default(10) int sidePaddingPercent,
    @Default(true) bool volumeKeyPageTurn,
    @Default(72) int volumeKeyPageTurnDistancePercent,
    @Default(false) bool doubleTapZoom,
    @Default(false) bool doubleTapOpenMenu,
    @Default(true) bool pageInfoShowPage,
    @Default(true) bool pageInfoShowNetwork,
    @Default(false) bool pageInfoShowBattery,
    @Default(true) bool pageInfoShowTime,
    @Default(ReaderInfoVerticalPosition.bottom)
    ReaderInfoVerticalPosition pageInfoVerticalPosition,
    @Default(false) bool pageInfoTopInStatusBar,
    @Default(ReaderInfoHorizontalPosition.left)
    ReaderInfoHorizontalPosition pageInfoHorizontalPosition,
    @Default(12) int pageInfoEdgePadding,
    @Default(82) int pageInfoOpacityPercent,
    @Default(12) int pageInfoFontSize,
    @Default(true) bool hoverRevealEnabled,
    @Default(true) bool hoverRevealTop,
    @Default(true) bool hoverRevealBottom,
    @Default(32) int hoverTriggerAreaTop,
    @Default(32) int hoverTriggerAreaBottom,
    @Default(500) int hoverHideDelayMs,
    @Default(false) bool hoverShowVisualIndicator,
    // 「点击阅读区唤出/收起上下栏」。关掉后单击不再显隐上下栏 —— 只能靠桌面端
    // 边缘悬停、或（若开着）双击打开操作栏唤出；条漫模式下「点哪儿都算中间」
    // 的那一条也一并关掉。
    // 默认 true = 改造前的行为，没进过设置页的用户零感知。
    @Default(true) bool centerTapToggleBars,
    // 底部缩略图条是否展开（与进度条同处一块玻璃面板）。
    //
    // **必须住在全局设置里，不能放阅读页的 State**：阅读页每个 route 一份
    // `_BottomWidgetState`，换书（`router.replace` 会换 key 重建整棵子树）、
    // 甚至同一本换章都会重建，开关会被「重置」回默认值。放这里则跟其他阅读
    // 设置一样持久化、跨书跨重启保持。
    @Default(false) bool showThumbnailStrip,
  }) = _ReadSettingState;

  factory ReadSettingState.fromJson(Map<String, dynamic> json) =>
      _$ReadSettingStateFromJson(json);
}

@freezed
abstract class BookshelfSettingState with _$BookshelfSettingState {
  const factory BookshelfSettingState({
    @Default(0) int homePageIndex,
    @Default(false) bool rememberFavoriteSort,
    @Default('dd') String favoriteSort,
    @Default(false) bool rememberHistorySort,
    @Default('dd') String historySort,
    @Default(false) bool rememberDownloadSort,
    @Default('dd') String downloadSort,
  }) = _BookshelfSettingState;

  factory BookshelfSettingState.fromJson(Map<String, dynamic> json) =>
      _$BookshelfSettingStateFromJson(json);
}

class GlobalSettingCubit extends Cubit<GlobalSettingState> {
  // 构造函数，传入由 freezed 生成的默认 state
  GlobalSettingCubit() : super(const GlobalSettingState());

  // 用于获取 freezed 中定义的默认值的便捷实例
  static const _defaults = GlobalSettingState();
  // colorThemeList[6].color 是动态的，不能在 const 中，单独处理
  late final Color _defaultSeedColor = colorThemeList[6].color;

  Future<void> initBox() async {
    emit(objectbox.userSettingBox.get(1)!.globalSetting);
  }

  GlobalSettingState get defaults =>
      _defaults.copyWith(seedColor: _defaultSeedColor);

  void updateALl(GlobalSettingState state) {
    _persistAndEmit(state);
  }

  void updateState(
    GlobalSettingState Function(GlobalSettingState current) updates,
  ) {
    final newState = updates(state);
    _persistAndEmit(newState);
  }

  void updateReadSetting(
    ReadSettingState Function(ReadSettingState current) updates,
  ) {
    updateState(
      (current) => current.copyWith(readSetting: updates(current.readSetting)),
    );
  }

  void updateSyncSetting(
    SyncSettingState Function(SyncSettingState current) updates,
  ) {
    updateState(
      (current) => current.copyWith(syncSetting: updates(current.syncSetting)),
    );
  }

  void updateCacheSetting(
    CacheSettingState Function(CacheSettingState current) updates,
  ) {
    updateState(
      (current) =>
          current.copyWith(cacheSetting: updates(current.cacheSetting)),
    );
  }

  void updateBookshelfSetting(
    BookshelfSettingState Function(BookshelfSettingState current) updates,
  ) {
    updateState(
      (current) =>
          current.copyWith(bookshelfSetting: updates(current.bookshelfSetting)),
    );
  }

  void updateToastSetting(
    ToastSettingState Function(ToastSettingState current) updates,
  ) {
    updateState(
      (current) =>
          current.copyWith(toastSetting: updates(current.toastSetting)),
    );
  }

  void updateComicCardSetting(
    ComicCardSettingState Function(ComicCardSettingState current) updates,
  ) {
    updateState(
      (current) =>
          current.copyWith(comicCardSetting: updates(current.comicCardSetting)),
    );
  }

  void updateFavoriteArtistSetting(
    FavoriteArtistSettingState Function(FavoriteArtistSettingState current)
    updates,
  ) {
    updateState(
      (current) => current.copyWith(
        favoriteArtistSetting: updates(current.favoriteArtistSetting),
      ),
    );
  }

  void addFavoriteArtist(String artist) {
    final trimmed = artist.trim();
    if (trimmed.isEmpty) return;
    updateFavoriteArtistSetting((current) {
      if (current.artists.any(
        (a) => a.trim().toLowerCase() == trimmed.toLowerCase(),
      )) {
        return current;
      }
      return current.copyWith(artists: [...current.artists, trimmed]);
    });
  }

  void removeFavoriteArtist(String artist) {
    final trimmed = artist.trim().toLowerCase();
    updateFavoriteArtistSetting((current) {
      return current.copyWith(
        artists: current.artists
            .where((a) => a.trim().toLowerCase() != trimmed)
            .toList(),
      );
    });
  }

  void setFavoriteArtists(List<String> artists) {
    final seen = <String>{};
    final unique = <String>[];
    for (final a in artists) {
      final t = a.trim();
      if (t.isNotEmpty && seen.add(t.toLowerCase())) {
        unique.add(t);
      }
    }
    updateFavoriteArtistSetting((current) => current.copyWith(artists: unique));
  }

  void toggleHighlightFavoriteArtists(bool enabled) {
    updateFavoriteArtistSetting(
      (current) => current.copyWith(highlightEnabled: enabled),
    );
  }

  /// 设置应用显示语言。
  ///
  /// [locale] 为目标 Flutter Locale；[followsSystem] 为 true 时表示跟随系统。
  /// 该方法会自动持久化、切换 slang 当前 locale，并同步 Rust 侧错误消息语言。
  /// 如果 [locale] 无法匹配到已支持的语言，则回退到英文。
  Future<void> setLocale(Locale locale, {bool followsSystem = false}) async {
    final appLocale = I18nHelper.toAppLocale(locale) ?? AppLocale.enUs;

    await LocaleSettings.setLocale(appLocale);
    I18nHelper.setRustErrorLanguage(appLocale);

    updateState(
      (current) => current.copyWith(
        locale: I18nHelper.toFlutterLocale(appLocale),
        localeFollowsSystem: followsSystem,
      ),
    );
  }

  /// 根据系统 locale 设置应用语言。
  /// 无法匹配时由 [setLocale] 自动回退到英文。
  Future<void> setSystemLocale(Locale systemLocale) async {
    await setLocale(systemLocale, followsSystem: true);
  }

  void updateWebDavSetting(
    WebDavSettingState Function(WebDavSettingState current) updates,
  ) {
    updateSyncSetting(
      (current) =>
          current.copyWith(webdavSetting: updates(current.webdavSetting)),
    );
  }

  void resetState(
    GlobalSettingState Function(
      GlobalSettingState current,
      GlobalSettingState defaults,
    )
    updates,
  ) {
    final newState = updates(state, defaults);
    _persistAndEmit(newState);
  }

  void _persistAndEmit(GlobalSettingState newState) {
    final normalizedState = _preserveCompatibleVersion(newState, state);
    if (_withoutSettingsSyncTime(normalizedState) ==
        _withoutSettingsSyncTime(state)) {
      return;
    }

    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final persistedState = normalizedState.copyWith(
      syncSetting: normalizedState.syncSetting.copyWith(
        settingsSyncTime: nowMs,
      ),
    );
    _updateDataBase(persistedState);
    emit(persistedState);
  }

  void applySyncedState(GlobalSettingState value) {
    final normalized = _preserveCompatibleVersion(value, state);
    _updateDataBase(normalized);
    emit(normalized);
  }

  GlobalSettingState _preserveCompatibleVersion(
    GlobalSettingState incoming,
    GlobalSettingState fallback,
  ) {
    if (incoming.compatibleVersion.trim().isNotEmpty) {
      return incoming;
    }
    final preserved = fallback.compatibleVersion.trim();
    if (preserved.isEmpty) {
      return incoming;
    }
    return incoming.copyWith(compatibleVersion: preserved);
  }

  GlobalSettingState _withoutSettingsSyncTime(GlobalSettingState value) {
    return value.copyWith(
      syncSetting: value.syncSetting.copyWith(settingsSyncTime: 0),
    );
  }

  void _updateDataBase(GlobalSettingState state) {
    // logger.d(state.toJson());
    final userBox = objectbox.userSettingBox;
    var dbSettings = userBox.get(1)!;
    var toSave = state;
    final existingVersion = dbSettings.globalSetting.compatibleVersion.trim();
    if (toSave.compatibleVersion.trim().isEmpty && existingVersion.isNotEmpty) {
      toSave = toSave.copyWith(compatibleVersion: existingVersion);
    }
    dbSettings.globalSetting = toSave;
    userBox.put(dbSettings);
  }
}
