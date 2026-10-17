// 全局设置

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// `JsonKey`（下面 `readerBackgroundMode` 上的跨版本降级要用）由 freezed_annotation
// 一并重导出，不必单独 import json_annotation。
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:zephyr/i18n/i18n_helper.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/type/breadcrumb_style.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/service/operation_binding/operation_binding_migration.dart';
import 'package:zephyr/page/comic_read/model/reader_magnifier.dart';
import 'package:zephyr/page/comic_read/model/reader_page_order.dart';
import 'package:zephyr/page/comic_read/model/reader_presentation.dart';
import 'package:zephyr/page/comic_read/model/reader_slideshow.dart';
import 'package:zephyr/page/search/model/search_history_entry.dart';
import 'package:zephyr/util/comic/favorite_artist_matcher.dart';
import 'package:zephyr/util/json/converter.dart';
import 'package:zephyr/util/layout/layout_overflow_guard.dart';
import 'package:zephyr/util/text/tag_text.dart';
import 'package:zephyr/util/text/tag_translation.dart';
// 只是为了 `kDefaultNarrowNavigationWidth` 这个默认值 —— 判定层的常量，
// 设置层引用它，避免「默认值」与「判定用的阈值」各存一个数（见
// `navigation_layout.dart` 顶部说明）。
import 'package:zephyr/widgets/navigation/navigation_layout.dart';

part 'global_setting.freezed.dart';
part 'global_setting.g.dart';
part 'parts/global_setting_read_part.dart';
part 'parts/global_setting_toast_part.dart';
part 'parts/global_setting_notify_part.dart';
part 'parts/global_setting_favorite_part.dart';
part 'parts/global_setting_workspace_part.dart';
part 'parts/global_setting_navigation_part.dart';
part 'parts/global_setting_read_extras_part.dart';

enum ReaderInfoVerticalPosition { top, bottom }

enum ReaderInfoHorizontalPosition { left, center, right }

/// 阅读背景档位。
///
/// `auto` 是「跟随主题明暗」，`adaptive` / `adaptiveEdge` 是「从当前画面取色」——
/// 两者不是一回事，所以 `adaptive` **不能**复用 `auto` 这个名字。
///
/// 后两档优先使用本地漫画的 GPU 页缓存；在线漫画在图片落盘后走轻量文件取样。
/// 两条链路都异步更新背景，首帧仍使用静态兜底色。
enum ReaderBackgroundMode { auto, black, white, grey, adaptive, adaptiveEdge }

enum ReaderTapPageTurnMode { fullScreen, leftHand, rightHand }

enum SyncServiceType { none, webdav, s3 }

/// 代理协议类型。
enum ProxyType { http, socks5 }

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

/// 墨水屏整屏刷新方式。
///
/// 应用拿不到厂商的 EPD 局部刷新接口，只能靠整屏色块切换迫使驱动走一次全刷。
enum EinkRefreshMode { none, whiteFlash, fullFlash }

extension EinkRefreshModeExtension on EinkRefreshMode {
  String get label {
    switch (this) {
      case EinkRefreshMode.none:
        return t.settings.einkRefreshNone;
      case EinkRefreshMode.whiteFlash:
        return t.settings.einkRefreshWhite;
      case EinkRefreshMode.fullFlash:
        return t.settings.einkRefreshFull;
    }
  }
}

/// 路由构建器拿不到 BuildContext，瞬时切页开关在这里留一份同步好的镜像。
bool eInkInstantRoutes = false;

const Color readerBackgroundBlack = Colors.black;
const Color readerBackgroundWhite = Colors.white;
const Color readerBackgroundGrey = Color(0xFF2D2D2D);

extension ReadSettingStateBackgroundColor on ReadSettingState {
  /// **静态**底色。
  ///
  /// 自适应档位返回的是**兜底**底色而不是取色结果，这是刻意的：
  /// 取色是一条异步链路（翻页 → 呈现 → 探针 → 插值），它到得比首帧晚。
  /// 把动态色并进这个函数，就等于让"取色到了"变成一次
  /// `readSetting` 变化 —— 而所有 `context.select(readSetting)` 的地方
  /// （含整棵阅读子树）都会跟着重建。动态色只走
  /// `ReaderAmbientBackground` 那一层，见那里的说明。
  Color resolveReaderBackgroundColor(Brightness brightness) {
    switch (readerBackgroundMode) {
      case ReaderBackgroundMode.auto:
      // 自适应档位的兜底底色与 `auto` 同值：取色还没到、或这一本是在线漫画
      // （取色那条路不适用）时，看到的应当是一个**用户预期内的**颜色 ——
      // 跟随主题明暗就是那个颜色，而不是一块没来由的灰。
      case ReaderBackgroundMode.adaptive:
      case ReaderBackgroundMode.adaptiveEdge:
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

  /// 当前档位是不是「从当前画面取色」那一类。
  ///
  /// 抽成纯函数而不是在调用点写 `mode == adaptive || mode == adaptiveEdge`：
  /// 调用点有两处（呈现链路决定要不要去读探针、背景层决定要不要用调色板），
  /// 而**这两处必须同时为真**功能才成立 —— 分开写就会出现
  /// 「读了探针但背景层不理」这种白花钱的组合。
  bool get readerAmbientEnabled =>
      readerBackgroundMode == ReaderBackgroundMode.adaptive ||
      readerBackgroundMode == ReaderBackgroundMode.adaptiveEdge;

  /// 取色后铺成「边缘渐变」还是「单色」。
  bool get readerAmbientEdge =>
      readerBackgroundMode == ReaderBackgroundMode.adaptiveEdge;
}

GlobalSettingState get globalSetting {
  return objectbox.userSettingBox.get(1)!.globalSetting;
}

@freezed
abstract class GlobalSettingState with _$GlobalSettingState {
  const factory GlobalSettingState({
    @Default(true) bool dynamicColor,
    @Default(ThemeMode.system) ThemeMode themeMode,
    @Default(true) bool isAMOLED,
    // 取自应用图标的面具色（poc/mask-upright.svg 的 fill）。
    @ColorConverter() @Default(Color(0xFF9C4B5E)) Color seedColor,
    // 导入的 tweakcn / shadcn 主题：`TweakcnTheme.encode()` 的 JSON 串，空串 = 未导入。
    // 存**解析后的 token 表**而不是原始 CSS：解析只在导入那一次发生，
    // 每次主题重建只是 jsonDecode，且同步 / 导出时人能直接读懂。
    @Default('') String tweakcnThemeJson,
    // 导入的主题是否生效。与 [tweakcnThemeJson] 分开，是为了「先导入存着、随时开关」。
    @Default(false) bool tweakcnThemeEnabled,
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
    // 布局溢出时那条「黄黑斜纹」画不画。默认开 ＝ Flutter 原生行为（改造前的行为）。
    // 关掉只覆盖**我们自己造的 Flex** 与错误上报 —— 框架没有全局开关，
    // 口径与适用范围见 `lib/util/layout/layout_overflow_guard.dart` 顶部。
    @Default(true) bool showLayoutOverflowStripes,
    @Default(false) bool forceEnableImpeller,
    @Default(false) bool androidKeepAliveEnabled,
    @Default(false) bool backPressExitEnabled,
    @Default(true) bool updateAccelerate,
    // 启动时跳过「检查上游新版本」。**本仓是 fork**：版本号（0.1.x）永远低于
    // 上游（3.x），弹窗必然每次都弹，且安装按钮指向 deretame/Breeze 的产物 ——
    // 所以默认跳过。想恢复弹窗就在设置里把这个开关关掉。
    @Default(true) bool skipUpdateCheck,
    @Default(true) bool retryDownloadUntilSuccess,
    @Default(3) int downloadConcurrency,
    // 同时下载几个章节。默认 2：章节级并行是「同时下多个」最直接的旋钮，
    // 1 = 回到逐个下载；遇到风控/验证码时调小。
    @Default(2) int downloadTaskConcurrency,
    @Default(150) int downloadDelayMs,
    @Default(3) int downloadAutoRetryCount,
    @Default(false) bool oldPageRollbackEnabled,
    @Default(false) bool cloudFavoritePreferred,
    @Default(false) bool autoFollowOnCollect,
    @Default(false) bool autoFavoriteOnDownload,
    // 下载完成后是否在下载目录的漫画根目录留下元数据 JSON（见 download_metadata_writer.dart）。
    // 默认关：下载目录本来就是「hash 目录 + hash 文件名」，只有 ObjectBox 认得，
    // 多写两份 JSON 属于用户主动要的可移植性，不该默认改变磁盘内容。
    @Default(false) bool writeDownloadMetadataFile,
    // 点击「下载」按钮时是否弹出下载选项（整本 / 最近 N 章 / 手动挑选）。
    // 默认关（false）：点击直接下载全本；开启后多章节漫画会弹窗询问，单集漫画仍直接下载。
    @Default(false) bool promptDownloadOptions,
    @Default(false) bool leftHandModeEnabled,
    @Default(false) bool clickCoverToStartReading,
    // 详情页「阅读」入口：桌面端放进操作行（「下载」旁边），并撤掉右下角的悬浮按钮。
    // 触摸端不受这个开关影响 —— 那边只有悬浮按钮一种落点。
    @Default(true) bool comicInfoInlineReadButton,
    // 详情页左右那颗悬浮胶囊用液态玻璃还是实底（`surfaceContainerHigh`）。
    //
    // **默认开**，与 `ToastSettingState.liquidGlass`（默认关）不一致，理由是刻意的：
    // 提示条那条要保住改造前的观感，而 rail 是新控件、没有旧观感可保护，且用户
    // 2026-09-21 点名要玻璃。关掉仍然能看清本体（实底 + 描边 + elevation）。
    @Default(true) bool comicInfoRailLiquidGlass,
    // 启动后是否直接进工作台（泳道 / 四边栏）。默认关 = 改造前的行为（落在导航栏）。
    // 只在**真有工作台入口**的布局（平板 / 桌面四边栏）落地，手机端忽略 ——
    // 判定收在 `lib/workspace/model/workspace_startup.dart`。
    @Default(false) bool startWithWorkspace,
    // 工作台在场时，被盖住的首页壳要不要「休眠」：内容里的图片换成纯色占位，
    // 让出 imageCache 里的解码位图（live image 随 widget 卸载而释放），
    // 退场后按磁盘文件重新解码。默认开 —— 首页壳被盖住期间那些位图本来
    // 一帧都画不上，属于纯内存成本；关掉 = 保持位图常驻（回首页更快，但更吃内存）。
    @Default(true) bool workspaceSleepCoveredUi,
    // 桌面端自制标题栏（`lib/widgets/desktop/custom_title_bar.dart`）改不改成
    // **透明浮层**：不再占那 40px，内容顶到窗口顶部，标题栏只把应用名与窗口按钮
    // 浮在画面上。口径照 JHenTai 桌面端的 `TitleBarStyle.hidden` + 透明窗口背景。
    //
    // 默认关 = 改造前的样子（一条 40px 的实色栏占在内容之上），没进过设置页的
    // 用户零感知。桌面三平台之外不读它（手机端根本没有这条栏）。
    // 摆放判定收在 `resolveDesktopTitleBarPlacement`，判据不用起整个 app。
    @Default(false) bool transparentDesktopTitleBar,
    // 透明标题栏的**摆放方式**：false = 独立行（栏仍占一行、只是不带底色，
    // 与页面背景连成一体，JHenTai 桌面端自制标题栏就是这一档），true =
    // 融合浮层（内容顶到窗口顶部，栏浮在画面上）。默认独立行。
    // 只在 transparentDesktopTitleBar 打开时才被读到；关着时它是死数据。
    @Default(false) bool transparentTitleBarFused,
    // 搜索历史。顺序即时间序（新的在前），每条带一个图源归属。
    // 读的时候走 [searchHistoryFromJson]，兼容老版本那份纯 `List<String>`，
    // 所以不需要一次数据库迁移。
    @Default([])
    @JsonKey(fromJson: searchHistoryFromJson)
    List<SearchHistoryEntry> searchHistory,
    // 「按插件分时间线」开关。开 = 历史按图源分组，每个插件各自一条；
    // 关 = 改造前的样子，全部堆在一条时间线上。默认关，保住老观感。
    @Default(false) bool searchHistoryGroupBySource,
    @Default(ProxySettingState()) ProxySettingState proxySetting,
    @Default(1280.0) double windowWidth,
    @Default(720.0) double windowHeight,
    @Default(0) double windowX,
    @Default(0) double windowY,
    @Default(ReadSettingState()) ReadSettingState readSetting,
    @Default('') String customExportPath,
    // 导出的产物（文件夹 / zip）里要不要带上封面图。默认关。
    //
    // 关的理由不是「省那一张图」：导出侧的封面**不是本地已有的一份拷贝**，而是
    // `_tryDownloadCover` 走 `downloadPicture(pictureType: cover)` 现场再取一次
    // （见 `export_comic.dart`）。导出要保证的是该导的页都进了归档，一张封面属于
    // 顺手塞进来的额外内容。
    // 关掉后 `original_comic_info.json` 里仍有封面地址，书架卡片与详情页展示的
    // 也是同一个 `downloadPicture`，本地没有就按地址在线取，不会因为不打包而空白。
    @Default(false) bool exportIncludeCover,
    @Default(AppLockSettingState()) AppLockSettingState appLockSetting,
    @Default("") String compatibleVersion,
    @Default(CacheSettingState()) CacheSettingState cacheSetting,
    @Default(ChineseConvertMode.off) ChineseConvertMode chineseConvertMode,
    @Default(BookshelfSettingState()) BookshelfSettingState bookshelfSetting,
    @Default(FavoriteArtistSettingState())
    FavoriteArtistSettingState favoriteArtistSetting,
    @Default(FavoriteTagSettingState())
    FavoriteTagSettingState favoriteTagSetting,
    @Default(ComicCardSettingState()) ComicCardSettingState comicCardSetting,
    @Default(ToastSettingState()) ToastSettingState toastSetting,
    @Default(SwitchToastSettingState())
    SwitchToastSettingState switchToastSetting,
    @Default(NotifySettingState()) NotifySettingState notifySetting,
    @Default(FileManagerSettingState())
    FileManagerSettingState fileManagerSetting,
    @Default(DiscoverSettingState()) DiscoverSettingState discoverSetting,
    @Default(OperationBindingSettingState())
    OperationBindingSettingState operationBindingSetting,
    @Default(EInkSettingState()) EInkSettingState eInkSetting,
    // 顶部导航栏（Arc 侧栏 / 悬浮 Dock）的偏好。默认值全在
    // `parts/global_setting_navigation_part.dart` 里带说明。
    @Default(NavigationSettingState()) NavigationSettingState navigationSetting,
  }) = _GlobalSettingState;

  factory GlobalSettingState.fromJson(Map<String, dynamic> json) =>
      _$GlobalSettingStateFromJson(json);
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
    @Default(0) int settingsSyncTime,
  }) = _SyncSettingState;

  factory SyncSettingState.fromJson(Map<String, dynamic> json) =>
      _$SyncSettingStateFromJson(json);
}

class GlobalSettingCubit extends Cubit<GlobalSettingState> {
  // 构造函数，传入由 freezed 生成的默认 state
  GlobalSettingCubit() : super(const GlobalSettingState());

  // 用于获取 freezed 中定义的默认值的便捷实例
  static const _defaults = GlobalSettingState();

  Future<void> initBox() async {
    // 收藏 tag 的自动别名要靠 EhTagTranslation 表；不 await —— 加载失败或
    // 没加载完都只是退回「只有登记别名」，不该拖住设置的首帧。
    TagTranslation.ensureLoaded();
    final original = objectbox.userSettingBox.get(1)!.globalSetting;
    final persisted = migrateOperationBindingsInSettings(original);
    if (!identical(original, persisted)) _updateDataBase(persisted);
    _applyLayoutOverflowGuard(persisted);
    _syncRuntimeFlags(persisted);
    emit(persisted);
  }

  GlobalSettingState get defaults => _defaults;

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

  void updateSwitchToastSetting(
    SwitchToastSettingState Function(SwitchToastSettingState current) updates,
  ) {
    updateState(
      (current) => current.copyWith(
        switchToastSetting: updates(current.switchToastSetting),
      ),
    );
  }

  void updateNotifySetting(
    NotifySettingState Function(NotifySettingState current) updates,
  ) {
    updateState(
      (current) =>
          current.copyWith(notifySetting: updates(current.notifySetting)),
    );
  }

  /// 改导航栏偏好（侧栏 / Dock 开关、阈值、两支各自的条目清单）。
  ///
  /// 走一个具名入口而不是让调用方自己 `copyWith`：导航栏那两处（布局分支与
  /// 弹窗）都要写它，收在一处省得将来加字段时漏改一边。
  void updateNavigationSetting(
    NavigationSettingState Function(NavigationSettingState current) updates,
  ) {
    updateState(
      (current) => current.copyWith(
        navigationSetting: updates(current.navigationSetting),
      ),
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

  void updateFileManagerSetting(
    FileManagerSettingState Function(FileManagerSettingState current) updates,
  ) {
    updateState(
      (current) => current.copyWith(
        fileManagerSetting: updates(current.fileManagerSetting),
      ),
    );
  }

  void updateDiscoverSetting(
    DiscoverSettingState Function(DiscoverSettingState current) updates,
  ) {
    updateState(
      (current) =>
          current.copyWith(discoverSetting: updates(current.discoverSetting)),
    );
  }

  void updateOperationBindingSetting(
    OperationBindingSettingState Function(OperationBindingSettingState current)
    updates,
  ) {
    updateState(
      (current) => current.copyWith(
        operationBindingSetting: updates(current.operationBindingSetting),
      ),
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
      // 去重口径与匹配同一个（剥括号 + 小写），否则 `[X]` 与 `X` 会存成两条，
      // 列表里看着重复、徽标却只亮一次。
      final key = FavoriteArtistMatcher.normalizeArtist(trimmed);
      if (current.artists.any(
        (a) => FavoriteArtistMatcher.normalizeArtist(a) == key,
      )) {
        return current;
      }
      return current.copyWith(artists: [...current.artists, trimmed]);
    });
  }

  void removeFavoriteArtist(String artist) {
    final key = FavoriteArtistMatcher.normalizeArtist(artist);
    updateFavoriteArtistSetting((current) {
      return current.copyWith(
        artists: current.artists
            .where((a) => FavoriteArtistMatcher.normalizeArtist(a) != key)
            .toList(),
      );
    });
  }

  void setFavoriteArtists(List<String> artists) {
    final seen = <String>{};
    final unique = <String>[];
    for (final a in artists) {
      final t = a.trim();
      final key = FavoriteArtistMatcher.normalizeArtist(t);
      if (t.isNotEmpty && key.isNotEmpty && seen.add(key)) {
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

  void setFavoriteArtistCircleMode(FavoriteArtistCircleMode mode) {
    updateFavoriteArtistSetting(
      (current) => current.copyWith(circleMode: mode),
    );
  }

  void updateFavoriteTagSetting(
    FavoriteTagSettingState Function(FavoriteTagSettingState current) updates,
  ) {
    updateState(
      (current) => current.copyWith(
        favoriteTagSetting: updates(current.favoriteTagSetting),
      ),
    );
  }

  /// 收藏一个 tag。[raw] 与已有条目的本名或别名归一化后相同时不重复添加。
  ///
  /// 详情页胶囊长按与设置页输入框都走这里，所以「长按第二次不该出现两条同名」。
  void addFavoriteTag(String raw) {
    final name = raw.trim();
    final key = TagText.normalize(name);
    if (key.isEmpty) return;
    updateFavoriteTagSetting((current) {
      if (_indexOfFavoriteTag(current.tags, key) != null) return current;
      return current.copyWith(
        tags: [
          ...current.tags,
          FavoriteTag(name: name),
        ],
      );
    });
  }

  /// 取消收藏：[raw] 对上某条的本名或任一别名，就删掉那一条。
  void removeFavoriteTag(String raw) {
    final key = TagText.normalize(raw);
    if (key.isEmpty) return;
    updateFavoriteTagSetting((current) {
      final index = _indexOfFavoriteTag(current.tags, key);
      if (index == null) return current;
      final next = [...current.tags]..removeAt(index);
      return current.copyWith(tags: next);
    });
  }

  /// 整表替换（批量导入、清空、编辑别名后回写都走这里）。
  void setFavoriteTags(List<FavoriteTag> tags) {
    updateFavoriteTagSetting(
      (current) => current.copyWith(tags: _dedupeFavoriteTags(tags)),
    );
  }

  /// 给某条收藏加一个别名。[raw] 定位条目（本名或别名均可）。
  void addFavoriteTagAlias(String raw, String alias) {
    final key = TagText.normalize(raw);
    final aliasText = alias.trim();
    if (key.isEmpty || aliasText.isEmpty) return;
    updateFavoriteTagSetting((current) {
      final index = _indexOfFavoriteTag(current.tags, key);
      if (index == null) return current;
      final tag = current.tags[index];
      final nameKey = TagText.normalize(tag.name);
      final aliasKey = TagText.normalize(aliasText);
      // 与本名同形的别名是噪声（归一化后本来就等价），与别的条目撞号则会把
      // 两条收藏并成一个命中，两处都要挡掉。
      if (aliasKey.isEmpty || aliasKey == nameKey) return current;
      if (aliasKey != key &&
          _indexOfFavoriteTag(current.tags, aliasKey) != null) {
        return current;
      }
      final cleaned = _cleanTagAliases([
        ...tag.aliases,
        aliasText,
      ], nameKey: nameKey);
      final next = [...current.tags];
      next[index] = tag.copyWith(aliases: cleaned);
      return current.copyWith(tags: next);
    });
  }

  void removeFavoriteTagAlias(String raw, String alias) {
    final key = TagText.normalize(raw);
    final aliasKey = TagText.normalize(alias);
    if (key.isEmpty || aliasKey.isEmpty) return;
    updateFavoriteTagSetting((current) {
      final index = _indexOfFavoriteTag(current.tags, key);
      if (index == null) return current;
      final tag = current.tags[index];
      final next = [...current.tags];
      next[index] = tag.copyWith(
        aliases: tag.aliases
            .where((a) => TagText.normalize(a) != aliasKey)
            .toList(),
      );
      return current.copyWith(tags: next);
    });
  }

  void toggleHighlightFavoriteTags(bool enabled) {
    updateFavoriteTagSetting(
      (current) => current.copyWith(highlightEnabled: enabled),
    );
  }

  void updateEInkSetting(
    EInkSettingState Function(EInkSettingState current) updates,
  ) {
    updateState(
      (current) => current.copyWith(eInkSetting: updates(current.eInkSetting)),
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
    final incoming =
        newState.operationBindingSetting.bindingsJson ==
            state.operationBindingSetting.bindingsJson
        ? newState
        : migrateOperationBindingsInSettings(newState, fallback: state);
    final normalizedState = _preserveCompatibleVersion(incoming, state);
    _syncRuntimeFlags(normalizedState);
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
    _applyLayoutOverflowGuard(persistedState);
    emit(persistedState);
  }

  void applySyncedState(GlobalSettingState value) {
    final normalized = _preserveCompatibleVersion(
      migrateOperationBindingsInSettings(value, fallback: state),
      state,
    );
    _syncRuntimeFlags(normalized);
    _updateDataBase(normalized);
    _applyLayoutOverflowGuard(normalized);
    emit(normalized);
  }

  /// 把「黄黑溢出斜纹」开关同步到全局标志上。
  ///
  /// 绘制路径每帧都要读它，不能去查数据库（`initBox` / `_persistAndEmit` /
  /// `applySyncedState` 三条 emit 路径都得过一遍，否则云同步回来的值不生效）。
  void _applyLayoutOverflowGuard(GlobalSettingState state) {
    setLayoutOverflowStripesEnabled(enabled: state.showLayoutOverflowStripes);
  }

  void _syncRuntimeFlags(GlobalSettingState value) {
    eInkInstantRoutes = value.eInkSetting.shouldRemoveRouteTransition;
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
