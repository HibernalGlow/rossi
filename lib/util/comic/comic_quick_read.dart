import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/page/comic_info/method/get_plugin_detail.dart';
import 'package:zephyr/page/comic_info/models/go_to_comic_read.dart';
import 'package:zephyr/page/comic_read/method/load_plugin_read_launch.dart';
import 'package:zephyr/service/download/models/download_task_json.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/path_util.dart';
import 'package:zephyr/widgets/toast.dart';

/// 封面卡上「直接阅读」按钮的起读入口 —— 不经过详情页。
///
/// 三条路按「本地有没有章节目录」排序，越靠前越不用联网：
///
/// 1. **本地来源**（`from == 'local'`，或 comicId 本身就是路径 / 归档）：全本就在盘上，
///    直接推 [ComicReadRoute]。这与 `openComicItem`、`ComicSimplifyEntry` 的本地分支同口径 ——
///    本地漫画的 `source` 没有插件，送进详情页会被当成「插件 id = local」去问 qjs 运行时，
///    得到 `plugin_not_found:local`。
/// 2. **已有下载记录**（ObjectBox 的 `UnifiedComicDownload` 里存着整本章节目录）：
///    把这条记录当作 `comicInfo` 交给 [pushComicReadRoute]，零网络起读。
///    这一档优先于问插件，正是这个功能存在的理由：下载过的书不必再回源一次。
/// 3. **远程插件漫画**：阅读器必须拿到章节列表才能起读，所以先 `getComicDetail`
///    问一次插件，再交给同一套解析。等待期间按钮自己转圈（见 `ComicReadButton`）。
///
/// 第 2、3 条都走 [pushComicReadRoute]（详情页「开始阅读」用的那一份解析），
/// 所以「续读优先」的语义与详情页完全一致：有历史记录就回到上次章节 + 页码，没有才第一章。
///
/// 失败时自己弹提示，调用方只管 await（用于显示进度圈）。
Future<void> startComicQuickRead(
  BuildContext context, {
  required String comicId,
  required String from,
}) async {
  final pluginId = from.trim();
  final id = comicId.trim();
  if (pluginId.isEmpty || id.isEmpty) return;

  final key = _flightKey(pluginId, id);
  // 连点去重：不同卡片指向同一本漫画时也只发起一次。
  if (!_inFlight.add(key)) return;

  final startSw = Stopwatch()..start();
  try {
    if (isLocalComicSource(pluginId, id)) {
      // 本地来源写历史时用的 from 就是 'local'（阅读器收到的就是这个值），
      // 所以续读记录也按 'local' 查，不能按卡片上的 source。
      _pushLocalComicRead(
        context,
        id,
        hasHistory: _hasComicHistory('local', id),
      );
      _logQuickRead(startSw, '本地');
      return;
    }

    final record = _findDownloadRecord(pluginId, id);
    if (record != null) {
      pushComicReadRoute(
        context,
        allInfo: record,
        comicId: id,
        from: pluginId,
        isDownload: true,
        hasHistory: _hasComicHistory(pluginId, id),
        stringSelectCubit: StringSelectCubit(),
      );
      _logQuickRead(startSw, '下载记录');
      return;
    }

    // 在线漫画只回源**一次**：`getReadSnapshot` 内部本来就要抓详情页，并且把
    // 整本章节目录放在 `data.chapters` 里一起带回来。旧的写法是先单独抓一遍整本
    // 详情，进阅读器后 `getReadSnapshot` 再抓一遍 —— 同一本书回源三遍，封面按钮
    // 和阅读器里那两个转圈其实在等同一件事。
    final launchSw = Stopwatch()..start();
    final launch = await loadPluginReadLaunch(
      comicId: id,
      from: pluginId,
      history: _findHistory(pluginId, id),
    );
    launchSw.stop();
    // 等待期间用户可能已经退掉这一页；往死掉的 context 上 push 会抛。
    if (!context.mounted) return;

    if (launch != null) {
      // 仍然用插件返回的 id 查历史 —— 阅读器存历史用的就是它，卡片上的 id
      // 可能只是列表给的简写（`pushComicReadRoute` 内部选章也是按这个 id 查的）。
      pushComicReadRoute(
        context,
        allInfo: launch,
        comicId: launch.comicId,
        from: pluginId,
        isDownload: false,
        hasHistory: _findHistory(pluginId, launch.comicId) != null,
        stringSelectCubit: StringSelectCubit(),
      );
      _logQuickRead(startSw, '快照起读', detailMs: launchSw.elapsedMilliseconds);
      return;
    }

    // 插件没在快照里给目录、或这条路直接失败了 —— 退回原来那次整本详情。
    final detailSw = Stopwatch()..start();
    final detail = await getComicDetailByPlugin(id, pluginId);
    detailSw.stop();
    if (!context.mounted) return;
    final resolvedId = detail.comicId.trim();
    final readId = resolvedId.isEmpty ? id : resolvedId;
    pushComicReadRoute(
      context,
      allInfo: detail.source,
      comicId: readId,
      from: pluginId,
      isDownload: false,
      hasHistory: _hasComicHistory(pluginId, readId),
      stringSelectCubit: StringSelectCubit(),
    );
    _logQuickRead(startSw, '退回整本详情', detailMs: detailSw.elapsedMilliseconds);
  } catch (e, s) {
    logger.e('直接阅读起读失败', error: e, stackTrace: s);
    showErrorToast(t.comicEntry.readFailed);
  } finally {
    _inFlight.remove(key);
  }
}

/// 起读耗时埋点。整条链路原本一处计时都没有，「点了到进阅读器」慢在哪只能猜。
void _logQuickRead(Stopwatch sw, String branch, {int? detailMs}) {
  final detail = detailMs == null ? '' : ' 详情回源=${detailMs}ms';
  logger.d(
    '[read-start] quick-read 分支=$branch '
    '合计(push 前)=${sw.elapsedMilliseconds}ms$detail',
  );
}

/// 正在起读的 `from|comicId`。模块级：两处卡片同一本书也要去重。
final Set<String> _inFlight = <String>{};

String _flightKey(String from, String comicId) =>
    '${from.trim()}|${comicId.trim()}';

/// 这本书的阅读记录（决定阅读器进「续读」还是从头读，以及续读该点哪一章）。
UnifiedComicHistory? _findHistory(String from, String comicId) {
  return objectbox.unifiedHistoryBox
      .query(
        UnifiedComicHistory_.uniqueKey.equals(
          '${from.trim()}:${comicId.trim()}',
        ),
      )
      .build()
      .findFirst();
}

/// 这本书有没有阅读记录。
bool _hasComicHistory(String from, String comicId) =>
    _findHistory(from, comicId) != null;

/// 这本书的下载记录（里面有整本章节目录，零网络就能起读）。
///
/// key 的口径用 [buildDownloadTaskKey] —— 与下载角标判断「这本书下过没有」
/// 用的是同一把钥匙。两边各写一份拼接的话，一旦分隔符变了就会变成
/// 「明明下过却回源去问插件」，而且看不出来。
UnifiedComicDownload? _findDownloadRecord(String from, String comicId) {
  return objectbox.unifiedDownloadBox
      .query(
        UnifiedComicDownload_.uniqueKey.equals(
          buildDownloadTaskKey(from, comicId),
        ),
      )
      .build()
      .findFirst();
}

void _pushLocalComicRead(
  BuildContext context,
  String comicId, {
  required bool hasHistory,
}) {
  context.pushRoute(
    ComicReadRoute(
      comicId: comicId,
      order: 0,
      from: 'local',
      epsNumber: 1,
      type: hasHistory ? ComicEntryType.history : ComicEntryType.normal,
      comicInfo: comicId,
      stringSelectCubit: StringSelectCubit(),
    ),
  );
}
