part of '../global_setting.dart';
// 工作台/发现页/操作绑定/卡片外观（rossi）


/// 文件管理器卡片（工作台里的本地文件浏览）的跨重启偏好。
///
/// 为什么这些不放卡片的 State，而放全局设置：工作台的卡片会被整棵重建
/// （换布局、收起再展开、重启），住在 `State` 里的值表现为「一换布局就重置」。
/// 需要「设了以后一直在」的东西一律走这里。
///
/// - [homeEnabled]：工具栏是否显示主页键。默认开。
/// - [homePath]：主页目录，空串表示未设置。真正的校验在 Rust 侧
///   （`FileManagerState::set_home_path` 只接受存在的目录），这里只保存用户的选择。
/// - [openHomeOnStart]：新建会话时是否直接落在主页目录。默认关 = 落在系统默认目录。
///   与 [homeEnabled] 同样只在主页键开着时生效 —— 那一节整体关掉后，
///   启动落点不该偷偷跟着走。
/// - [rememberViewState]：记住每个目录的视图与排序（写进 `settings.db` 的
///   `file_manager_view_states` 表）。默认开；关掉之后浏览照常，只是不再读写目录偏好。
/// - [restoreTabs]：把上次打开的**那几个页签**摆回来（记在 SharedPreferences 的
///   `rossi.fileManager.openTabs`，为什么不走这份设置见
///   `file_manager_tab_session_store.dart`）。默认开；关掉之后浏览照常，
///   只是不再记也不再恢复。
///   只有**两个以上**页签才记 —— 单个页签谈不上页签条，记它等于悄悄把
///   [openHomeOnStart] 顶掉。两条都开着时以本条为准：「回到我上次待的那几个目录」
///   比「回到主页」更接近用户关掉应用之前的意图。
/// - [fileOperations]：**写操作的总开关**（复制 / 移动 / 重命名 / 新建 / 删除）。
///   默认开；关掉之后文件浏览器回到「只看不改」—— 没有右键菜单、没有多选、
///   没有操作条。之所以给它一个总开关而不是逐个动作给：这一层第一次具备了
///   **修改用户磁盘**的能力，而这类能力的方向应该是「默认给了，但随时能整个收回去」，
///   不是「一样一样地关」（那样关到一半是最糟的状态）。
@freezed
abstract class FileManagerSettingState with _$FileManagerSettingState {
  const factory FileManagerSettingState({
    @Default(true) bool homeEnabled,
    @Default('') String homePath,
    @Default(false) bool openHomeOnStart,
    @Default(true) bool rememberViewState,
    @Default(true) bool restoreTabs,
    @Default(true) bool fileOperations,
  }) = _FileManagerSettingState;

  factory FileManagerSettingState.fromJson(Map<String, dynamic> json) =>
      _$FileManagerSettingStateFromJson(json);
}


/// 发现页标签条摆在哪一条边上。
///
/// 与 `plat` 的 `TabBarSide` 一一对应，但**不在这里 import 那个包**：
/// 设置模型是持久层，不该被一个 UI 依赖拖着走（哪天换掉那个包，
/// 用户存的值不该跟着变成一串读不出来的整数）。
enum DiscoverTabBarSide {
  /// 横向：标签条就是发现页顶栏那一行。
  top('横向（顶栏）'),

  /// 竖向：标签轨在内容左边。
  left('竖向（左侧）'),

  /// 竖向：标签轨在内容右边。
  right('竖向（右侧）');

  const DiscoverTabBarSide(this.label);

  /// 设置项上的中文名（这个枚举只有三个值，不值得走 i18n 词条）。
  final String label;
}


/// 发现页**标签条**的显示口径。
///
/// 为什么放全局而不是页面的 State：标签条在发现页活着的时候才画得出来，
/// 而用户调完这几颗想看的效果是「以后每次都是这样」—— 关掉应用再开不该弹回去。
///
/// - [tabIconEnabled]：标签上画不画插件图标。关掉之后只剩文字，窄轨上能多塞几条。
/// - [tabPluginShortEnabled]：标签上画不画插件名缩写（「绅士 · 排行」里那截「绅士」）。
///   两个都关掉就只剩功能名 —— 那时同一功能的多个标签只能靠序号分辨。
/// - [tabSide]：标签条的朝向与靠边（见 [DiscoverTabBarSide]）。
/// - [tabRailWidth]：竖向轨的厚度。轨从内容区里扣宽度，所以它是个用户可调的取舍
///   （见 `DiscoverPlatView` 的拖拽把手），不是一个我们自己拍死的常量。
@freezed
abstract class DiscoverSettingState with _$DiscoverSettingState {
  const factory DiscoverSettingState({
    @Default(true) bool tabIconEnabled,
    @Default(true) bool tabPluginShortEnabled,
    @Default(DiscoverTabBarSide.top) DiscoverTabBarSide tabSide,

    /// 竖向轨的厚度（像素）。拖动轨内侧那条边即改这个值。
    @Default(132.0) double tabRailWidth,
  }) = _DiscoverSettingState;

  factory DiscoverSettingState.fromJson(Map<String, dynamic> json) =>
      _$DiscoverSettingStateFromJson(json);
}


/// 操作绑定（ADR-0015）的持久化。
///
/// [bindingsJson] 存的是**引擎的绑定包**（`InputBindingsConfig` 的 JSON，
/// schema 的权威在 `rossi_local_core::operation_binding`）：Dart 侧只当字符串拿着，
/// 需要时整串喂给 FRB。这里**不建**一套 Dart 强类型镜像 —— 建了就得跟着 schema 改生成物，
/// 而 ADR-0015 要的是「换外壳时绑定表零改动」。
///
/// 空串 = 还没播种（首次启动会用出厂预设填上）。播种前后 [bindingsRuntime]
/// 判定都要能成立，所以运行时的回退是「表是空的 → 走改造前的硬编码分区」，
/// 而不是「什么都不做」—— 那等于把阅读器锁死。
@freezed
abstract class OperationBindingSettingState
    with _$OperationBindingSettingState {
  const factory OperationBindingSettingState({
    /// 总开关：开=按键/点击经绑定表解析；关=走改造前的硬编码判断。
    @Default(true) bool bindingsRuntime,
    @Default('') String bindingsJson,

    /// 轮盘的**形状**（核心 `RadialConfig` 的 JSON：几个轮盘 / 几层 / 半径 /
    /// 生效项，外加轮盘自己的总开关）。
    ///
    /// 为什么不并进 [bindingsJson]：两者是两件事 —— 这份只有形状，槽位「干什么」
    /// 仍然是绑定表里那些 `device: radial` 的行。于是轮盘与键盘、点击同权，
    /// 共用同一个解析器与同一套冲突判定，不需要为它写第二遍判断。
    /// 空串 = 还没播种（首次启动用核心的出厂值填上）。
    @Default('') String radialJson,

    /// 滚轮方向词按**手推的方向**算，而不是按内容走的方向。
    ///
    /// `null` = 跟随平台：macOS 的 `scrollDelta.dy` 已经带过系统「自然滚动」那一次反转，
    /// 默认再翻一次才等于用户心里的「下滚」；其它平台不翻。用户在这颗开关上表过态就永远
    /// 听他的。**它不进 bindingsJson** —— 手方向是一台设备的属性，不该跟着绑定包导入导出。
    bool? invertWheelDirection,
  }) = _OperationBindingSettingState;

  factory OperationBindingSettingState.fromJson(Map<String, dynamic> json) =>
      _$OperationBindingSettingStateFromJson(json);
}


/// 封面「已下载但未读」标识的画法。
///
/// 三档说的是同一件事，辨识度与占位面积一起递增：嫌色块压封面的用 [dot]，
/// 嫌小点看不清又不要文字的用 [disc]，要一眼知道意思的用 [label]。
/// 与其替用户拍板，不如让他自己挑。
enum ComicUnreadIndicatorStyle {
  /// 加大白环的纯色圆点。
  dot,

  /// 圆点包进一枚中性色圆片，靠承底从封面里择出来。
  disc,

  /// 「未读」文字胶囊，与封面左上角的语言角标同一套形状语言。
  label,
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

    /// 封面正中间的「直接阅读」按钮。关掉后点封面仍然只进详情页。
    @Default(true) bool readButtonEnabled,

    /// 封面左上角的「收藏 tag」角标。
    @Default(true) bool favoriteTagBadgeEnabled,

    /// 封面右上角的「已下载但未读」标识（只在下载书架显示：有下载记录、没有任何阅读记录）。
    @Default(true) bool unreadIndicatorEnabled,

    /// 这颗标识画成什么样子（圆点 / 圆片 / 文字胶囊）。
    @Default(ComicUnreadIndicatorStyle.label)
    ComicUnreadIndicatorStyle unreadIndicatorStyle,
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
