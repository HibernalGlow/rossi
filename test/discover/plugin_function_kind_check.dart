// 插件功能胶囊语义归类的**纯 Dart** 判据。
//
//   dart run test/discover/plugin_function_kind_check.dart
//
// 为什么值得单独立一份：这排胶囊的图标与配色档位全押在归类上，而它错的方式是
// 「排行画成时钟」这种看着怪，不抛异常。所以下面既钉真实插件的输入，
// 也钉那四处**顺序**约束 —— 每条都配一个「不排序就会串味」的输入。
//
// ignore_for_file: avoid_print
import 'package:zephyr/page/discover/service/plugin_function_kind.dart';

int _passed = 0;

void check(String label, bool condition, [String? detail]) {
  if (!condition) {
    throw StateError('FAIL: $label${detail == null ? '' : ' — $detail'}');
  }
  _passed++;
}

PluginFunctionKind _id(String id) => classifyPluginFunction(id: id, title: '');

PluginFunctionKind _title(String title) =>
    classifyPluginFunction(id: '', title: title);

void main() {
  _realPlugins();
  _byTitle();
  _orderGuards();
  _tones();
  _fallbacks();
  print('OK: plugin_function_kind 通过 $_passed 项');
}

/// 本机在用的两个插件仓库里真实写下的 id / 标题。
///
/// 注意「最新」的 id 是 `recent` 而不是 `latest` —— 这正是必须两个字段都读的理由。
void _realPlugins() {
  check('绅士漫画 ranking', _id('ranking') == PluginFunctionKind.ranking);
  check('绅士漫画 recent→最新', _id('recent') == PluginFunctionKind.latest);
  check(
    '绅士漫画 cloudFavorite',
    _id('cloudFavorite') == PluginFunctionKind.cloudFavorite,
  );
  check('e-hentai latest', _id('latest') == PluginFunctionKind.latest);
  check('e-hentai popular', _id('popular') == PluginFunctionKind.popular);

  check('标题 排行', _title('排行') == PluginFunctionKind.ranking);
  check('标题 排行榜', _title('排行榜') == PluginFunctionKind.ranking);
  check('标题 最新', _title('最新') == PluginFunctionKind.latest);
  check('标题 热门', _title('热门') == PluginFunctionKind.popular);
  check('标题 推荐', _title('推荐') == PluginFunctionKind.recommend);
  check('标题 云端收藏', _title('云端收藏') == PluginFunctionKind.cloudFavorite);
  check('标题 收藏', _title('收藏') == PluginFunctionKind.favorite);
}

/// 繁简、空格、下划线、大小写都不能影响结果。
void _byTitle() {
  check('繁体 雲端收藏', _title('雲端收藏') == PluginFunctionKind.cloudFavorite);
  check('繁体 推薦', _title('推薦') == PluginFunctionKind.recommend);
  check('繁体 熱門', _title('熱門') == PluginFunctionKind.popular);
  check(
    '带空格 Cloud Favorite',
    _title('Cloud Favorite') == PluginFunctionKind.cloudFavorite,
  );
  check(
    '下划线 cloud_favorite',
    _id('cloud_favorite') == PluginFunctionKind.cloudFavorite,
  );
  check('大小写 LATEST', _id('LATEST') == PluginFunctionKind.latest);
  check('带前缀 jm_latest', _id('jm_latest') == PluginFunctionKind.latest);
  check('英文 收藏夹', _title('收藏夹') == PluginFunctionKind.cloudFavorite);
}

/// 四条顺序约束：每条的输入在「不排序」时都会落到错的那一类。
void _orderGuards() {
  // cloudFavorite 必须在 favorite 前：否则「云端收藏」被 `收藏` 抢先。
  check('云端收藏 不被 收藏 抢', _title('云端收藏') == PluginFunctionKind.cloudFavorite);
  // history 必须在 latest 前：否则 recentView 被 `recent` 抢成「最新」。
  check('recentView 是足迹不是更新', _id('recentView') == PluginFunctionKind.history);
  // search 必须在 popular 前：否则「热搜」被 `热` 抢成热门。
  check('热搜 不被 热 抢', _title('热搜') == PluginFunctionKind.search);
  // category 必须在 ranking 前：否则 topic 被 `top` 抢成排行。
  check('topic 不被 top 抢', _id('topic') == PluginFunctionKind.category);

  // id 优先于标题：作者把 latest 那条改名成「推荐」时，路由语义仍跟着 id 走。
  check(
    'id 压过标题',
    classifyPluginFunction(id: 'latest', title: '推荐') ==
        PluginFunctionKind.latest,
  );
  // action.type 是宿主协议的键，压过一切。
  check(
    'openCloudFavorite 压过标题',
    classifyPluginFunction(
          id: 'x',
          title: '我的清单',
          actionType: 'openCloudFavorite',
        ) ==
        PluginFunctionKind.cloudFavorite,
  );
  check(
    'openComicList 不带语义，落到标题上',
    classifyPluginFunction(id: '', title: '排行', actionType: 'openComicList') ==
        PluginFunctionKind.ranking,
  );
}

void _tones() {
  check('最新=浏览档', PluginFunctionKind.latest.tone == PluginFunctionTone.browse);
  check('排行=浏览档', PluginFunctionKind.ranking.tone == PluginFunctionTone.browse);
  check(
    '收藏=用户档',
    PluginFunctionKind.favorite.tone == PluginFunctionTone.library,
  );
  check(
    '云端收藏=用户档',
    PluginFunctionKind.cloudFavorite.tone == PluginFunctionTone.library,
  );
  check('搜索=工具档', PluginFunctionKind.search.tone == PluginFunctionTone.tool);
  check('认不出=工具档', PluginFunctionKind.unknown.tone == PluginFunctionTone.tool);

  // 三档必须真的互不相同，否则「按档位分色」这件事是空的。
  check(
    '三档各一',
    {
          PluginFunctionKind.latest.tone,
          PluginFunctionKind.favorite.tone,
          PluginFunctionKind.search.tone,
        }.length ==
        3,
  );
}

void _fallbacks() {
  check('空 id 空标题 → unknown', _id('') == PluginFunctionKind.unknown);
  check('插件自造名 → unknown', _title('啵哩啵哩') == PluginFunctionKind.unknown);
  check(
    '数字 id → unknown',
    classifyPluginFunction(id: '1', title: '2') == PluginFunctionKind.unknown,
  );
}
