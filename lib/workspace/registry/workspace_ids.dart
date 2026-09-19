/// 面板 id 常量。单独一个文件，于是**两张注册表互不 import**，
/// 也不会有谁「顺手」在这里塞业务。
///
/// 新增一个面板 = 在面板注册表里加一条定义 + 在这里加一个 id 常量；
/// 布局记账不需要迁移（未记录的项回落到定义里的默认值）。
class WorkspacePanelId {
  const WorkspacePanelId._();

  /// 左泳道：完整复用上游 `BookshelfPage`
  static const String bookshelf = 'bookshelf';

  /// 左泳道独立面板：我的收藏
  static const String favorite = 'favorite';

  /// 左泳道独立面板：阅读历史
  static const String history = 'history';

  /// 左泳道独立面板：下载与离线
  static const String download = 'download';

  /// 左泳道：书架卡片（收藏 / 历史 / 下载）
  static const String shelf = 'shelf';

  /// 左泳道：洞察（近 7 日趋势 / 连续阅读 / 阅读热力 / 来源拆分）
  static const String insights = 'insights';

  /// 右泳道：完整复用上游 `DiscoverPage`
  static const String discover = 'discover';

  /// 右泳道独立面板：文件管理器 / 本地漫画
  static const String fileManager = 'file_manager';

  /// 右泳道独立面板：页面导航
  static const String pageList = 'page_list';

  /// 右泳道独立面板：图源与扩展
  static const String plugins = 'plugins';

  /// 右泳道：控制面板（neoview 的 `panel("control", …, "right")` 同款落点，
  /// 收「切换提示」这类**读改设置**的功能卡片）
  static const String control = 'control';

  /// 右泳道：图源与本地卡片
  static const String sources = 'sources';

  /// 右泳道：完整复用上游 `MorePage`
  static const String tools = 'tools';

  /// **叠加**在阅读器视口右缘的信息面板（mimage 式）。
  ///
  /// 它不住在任何一条泳道的页签轨上，因此**不注册进面板注册表** ——
  /// 但它仍然是一个面板 id：信息卡片（书籍 / 图像 / 存储 / 时间 / 预加载）
  /// 的归属、展开、次序、隐藏全部按这张面板记账。
  static const String info = 'info';
}
