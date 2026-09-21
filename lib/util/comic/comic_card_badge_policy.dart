import 'package:zephyr/util/path_util.dart';

/// 漫画卡片封面角标的显示策略。
///
/// **单一真源**：网格卡（`ComicSimplifyEntry`）与横滑卡
/// （`ComicFixedSizeHorizontalList`）都走这里，避免两处各写一份判断而漂移
/// （横滑卡此前就漏了「多选模式」与「组件级开关」两道判断）。
///
/// 纯函数、零 Flutter 依赖，便于写判据 —— 角标开关是用户能点到的功能，
/// 「关掉之后真的不显示」必须可验证，不能只靠肉眼看 UI。
///
/// 三道闸门，全部都要过：
/// 1. **用户开关**（设置 → 书架 → 卡片角标）：用户随时能关掉任何角标；
/// 2. **卡片开关**（`showDownloadAction` / `showTranslationBadge`）：
///    给具体页面用的 —— 某个页面不想要角标时不必去动全局设置；
/// 3. **场景约束**：本地漫画本来就在盘上（没有「下载」这回事）、
///    多选模式下右上角让给勾选圈。
class ComicCardBadgePolicy {
  const ComicCardBadgePolicy({
    this.downloadBadgeEnabled = true,
    this.translationBadgeEnabled = true,
    this.readButtonEnabled = true,
    this.favoriteTagBadgeEnabled = true,
    this.unreadIndicatorEnabled = true,
  });

  /// 用户的「下载角标」总开关。
  final bool downloadBadgeEnabled;

  /// 用户的「语言角标」（汉化 / 中文 / 生肉）总开关。
  final bool translationBadgeEnabled;

  /// 用户的「直接阅读按钮」总开关（封面正中）。
  final bool readButtonEnabled;

  /// 用户的「收藏 tag 角标」总开关（封面左上角）。
  final bool favoriteTagBadgeEnabled;

  /// 用户的「未读标识」总开关（封面右上角，下载书架）。
  final bool unreadIndicatorEnabled;

  /// 下载角标是否显示（右上角）。
  ///
  /// [pluginId] 已按调用方口径归一（`info.source` 优先、回退 `info.from`）。
  bool showDownloadBadge({
    required String pluginId,
    required String comicId,
    bool cardEnabled = true,
    bool selectionMode = false,
  }) {
    if (!downloadBadgeEnabled || !cardEnabled || selectionMode) {
      return false;
    }
    final id = pluginId.trim();
    if (id.isEmpty) return false;
    // 本地漫画本来就在盘上，不显示下载角标。
    if (isLocalComicSource(id, comicId)) return false;
    return true;
  }

  /// 语言角标是否显示（左上角）。
  ///
  /// 它同时是「要不要去跑匹配」的闸门：关掉时调用方应当直接跳过
  /// `ChineseTranslationMatcher.match`，省掉每张卡片的词表扫描。
  bool showTranslationBadge({bool cardEnabled = true}) {
    return translationBadgeEnabled && cardEnabled;
  }

  /// 收藏 tag 的封面角标是否显示（左上角，语言角标之上）。
  ///
  /// 同样兼任「要不要跑匹配」的闸门。这里把用户那两把开关（书架 → 卡片角标、
  /// 设置 → 内容 → 收藏 tag 高亮）合成一次判断，调用方就不会只查到一半。
  bool showFavoriteTagBadge({
    bool highlightEnabled = true,
    bool cardEnabled = true,
  }) {
    return favoriteTagBadgeEnabled && highlightEnabled && cardEnabled;
  }

  /// 封面正中的「直接阅读」按钮是否显示。
  ///
  /// 与下载角标相反，**本地漫画一定要画** —— 它就在盘上，是这条路径最划算的一种。
  /// 多选模式下不画：那时整张卡是让给勾选的，中间再扣一颗按钮会误触起读。
  bool showReadButton({
    required String pluginId,
    required String comicId,
    bool cardEnabled = true,
    bool selectionMode = false,
  }) {
    if (!readButtonEnabled || !cardEnabled || selectionMode) {
      return false;
    }
    if (pluginId.trim().isEmpty) return false;
    if (comicId.trim().isEmpty) return false;
    return true;
  }

  /// 「已下载但未读」标识是否显示（封面右上角，下载角标之下）。
  ///
  /// 只管**画不画**；画成圆点还是文字由 `ComicCardSettingState.unreadIndicatorStyle`
  /// 决定，属于呈现层，不在这道闸门里掺和。
  ///
  /// [unread] 由调用方批量算好（见 `folder_shelf_bloc` 的 `unreadComicKeys`），
  /// 这里只做闸门：**卡片本身不查库**，一屏几十张卡逐张查历史是白付的开销。
  /// 多选模式下不画，同下载角标 —— 右上角那颗是勾选圈的地盘。
  bool showUnreadIndicator({required bool unread, bool selectionMode = false}) {
    if (!unread) return false;
    return unreadIndicatorEnabled && !selectionMode;
  }
}
