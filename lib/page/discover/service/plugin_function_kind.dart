// 插件功能入口的语义归类 —— 判据只有这一份。
//
// 为什么要归：插件的 `getInfo().function[]` 只给 `{id, title, action}`，标题是作者
// 随手写的「排行」「最新」「云端收藏」，宿主读不出它们各自是什么。于是发现页每张卡上
// 全是同色同形的一排描边药丸，只能逐个读字 —— 而「点哪个」恰恰是这排东西唯一要回答的问题。
// 归成有限的几类之后，UI 就能按类别配图标与配色档位。
//
// 输入按 id → 标题 的顺序试，是因为 `id` 比标题稳定：标题会被翻译、会被作者改名，
// 而 id 是插件自己路由用的键（`recent` 配「最新」这种对不上是常态，所以两个都要读）。
//
// 规则改动后跑判据：
//   dart run test/discover/plugin_function_kind_check.dart
//
// 本文件**不 import** package:flutter/**（会拖进 dart:ui），所以能用 dart run 直接断言。

/// 一个插件功能入口的语义类别。
enum PluginFunctionKind {
  latest,
  ranking,
  popular,
  recommend,
  random,
  favorite,
  cloudFavorite,
  history,
  search,
  category,
  unknown,
}

/// 胶囊的视觉档位：图标负责「这是哪一项」，档位负责「它跟这一排里谁是一伙的」。
enum PluginFunctionTone {
  /// 进去看内容的入口。
  browse,

  /// 用户自己的东西（云端/本地收藏、足迹）。
  library,

  /// 工具，以及读不出语义的那些。
  tool,
}

extension PluginFunctionKindTone on PluginFunctionKind {
  PluginFunctionTone get tone => switch (this) {
    PluginFunctionKind.latest ||
    PluginFunctionKind.ranking ||
    PluginFunctionKind.popular ||
    PluginFunctionKind.recommend ||
    PluginFunctionKind.random => PluginFunctionTone.browse,

    PluginFunctionKind.favorite ||
    PluginFunctionKind.cloudFavorite ||
    PluginFunctionKind.history => PluginFunctionTone.library,

    PluginFunctionKind.search ||
    PluginFunctionKind.category ||
    PluginFunctionKind.unknown => PluginFunctionTone.tool,
  };
}

/// 非 `[a-z0-9]`、非中日韩表意文字一律丢掉：
/// `Cloud Favorite` / `cloud_favorite` / `云端 收藏` 归一后同形，规则里就不用堆变体。
final _noisePattern = RegExp(r'[^a-z0-9一-鿿]');
String _normalize(String raw) =>
    raw.trim().toLowerCase().replaceAll(_noisePattern, '');

/// 按顺序命中的关键词表。
///
/// 顺序有三处是硬约束，挪动就会串味：
/// - `cloudFavorite` 必须在 `favorite` 前 —— 「云端收藏」里也含「收藏」；
/// - `history` 必须在 `latest` 前 —— `recentView` 里也含 `recent`（那是足迹不是更新）；
/// - `search` 必须在 `popular` 前 —— 「热搜」里也含「热」；
/// - `category` 必须在 `ranking` 前 —— `topic`（专题）里也含 `top`。
const List<(PluginFunctionKind, List<String>)> _rules = [
  (
    PluginFunctionKind.cloudFavorite,
    [
      'cloudfavorite',
      'cloudfavourite',
      'cloudfav',
      '云端收藏',
      '雲端收藏',
      '云收藏',
      '收藏夹',
      '收藏夾',
    ],
  ),
  (
    PluginFunctionKind.favorite,
    [
      'favourite',
      'favorite',
      'fav',
      'collect',
      'bookmark',
      'subscribe',
      'follow',
      '收藏',
      '订阅',
      '訂閱',
      '关注',
      '關注',
      '追更',
      '书签',
      '書籤',
    ],
  ),
  (
    PluginFunctionKind.history,
    [
      'history',
      'recentview',
      'recentwatch',
      'footprint',
      '足迹',
      '足跡',
      '历史',
      '歷史',
      '浏览记录',
      '瀏覽記錄',
      '阅读记录',
      '閱讀記錄',
    ],
  ),
  (
    PluginFunctionKind.search,
    ['search', 'query', '搜索', '搜寻', '搜尋', '查找', '热搜', '熱搜'],
  ),
  (
    PluginFunctionKind.category,
    [
      'category',
      'genre',
      'label',
      'classify',
      'navigation',
      'nav',
      'topic',
      'tag',
      '分类',
      '分類',
      '标签',
      '標籤',
      '分区',
      '分區',
      '类型',
      '類型',
      '题材',
      '題材',
      '类别',
      '類別',
      '专题',
      '專題',
      '话题',
      '話題',
      '导航',
      '導航',
    ],
  ),
  (
    PluginFunctionKind.ranking,
    ['ranking', 'rank', 'toplist', 'leaderboard', 'top', '排行', '榜', '排名'],
  ),
  (
    PluginFunctionKind.latest,
    ['latest', 'recent', 'newest', 'new', '更新', '最新', '最近', '新作', '新番', '上新'],
  ),
  (
    PluginFunctionKind.popular,
    ['popular', 'trending', 'trend', 'hot', '热门', '熱門', '人气', '人氣', '热', '熱'],
  ),
  (
    PluginFunctionKind.recommend,
    [
      'recommend',
      'guess',
      'feature',
      'choice',
      'digest',
      'discover',
      '推荐',
      '推薦',
      '精选',
      '精選',
      '荐',
      '发现',
      '發現',
    ],
  ),
  (
    PluginFunctionKind.random,
    ['random', 'shuffle', 'lucky', '随机', '隨機', '手气', '手氣'],
  ),
];

PluginFunctionKind? _firstMatch(String haystack) {
  for (final (kind, keywords) in _rules) {
    for (final keyword in keywords) {
      if (haystack.contains(keyword)) return kind;
    }
  }
  return null;
}

/// `{id, title, action.type}` → 语义类别。读不出来就是 [PluginFunctionKind.unknown]。
///
/// [actionType] 先判：`openCloudFavorite` 这类是宿主路由协议里的键，比作者手写的
/// 标题可靠得多；`openComicList` / `openPluginFunction` 什么语义都不带，落到 id 与标题上。
PluginFunctionKind classifyPluginFunction({
  required String id,
  required String title,
  String actionType = '',
}) {
  switch (actionType.trim()) {
    case 'openCloudFavorite':
      return PluginFunctionKind.cloudFavorite;
    case 'openSearch':
      return PluginFunctionKind.search;
  }

  final normalizedId = _normalize(id);
  if (normalizedId.isNotEmpty) {
    final kind = _firstMatch(normalizedId);
    if (kind != null) return kind;
  }
  return _firstMatch(_normalize(title)) ?? PluginFunctionKind.unknown;
}
