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
  });

  /// 用户的「下载角标」总开关。
  final bool downloadBadgeEnabled;

  /// 用户的「语言角标」（汉化 / 中文 / 生肉）总开关。
  final bool translationBadgeEnabled;

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
}
