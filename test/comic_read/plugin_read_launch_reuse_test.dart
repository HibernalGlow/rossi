import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_info/method/get_plugin_detail.dart';
import 'package:zephyr/page/comic_info/models/read_launch_adapter.dart';
import 'package:zephyr/page/comic_read/method/load_plugin_read_launch.dart';
import 'package:zephyr/page/comic_read/model/comic_read_snapshot.dart';
import 'package:zephyr/page/comic_read/model/plugin_read_launch.dart';
import 'package:zephyr/page/download/adapters/download_chapter_adapter.dart';
import 'package:zephyr/page/download/adapters/download_chapter_matcher.dart';

/// 「一次 `getReadSnapshot` 顶掉整本详情回源」这条路的成立条件。
///
/// 优化的本质是：起读时那一次快照带回的 `data.chapters`，必须能当详情页那份
/// eps 目录用；并且阅读器随后算出的章节 key 要**命中**这份快照，否则就是白取。
/// 这两件事在这里钉住 —— 它们错了不会崩，只会静默变慢或读错章。
///
/// JSON 形状照抄三份真实实现：`Breeze-plugin-ehentai` 的
/// `src/services/read-snapshot.service.ts`（chunkChapters / chapterRef）、
/// `Breeze-plugin-shenShiManHua` 的 `getReadSnapshot`（data.chapters），
/// 以及 `rust/rquickjs_playground/tests/fixtures/breeze-plugin-example.bundle.cjs`。
void main() {
  const from = 'plugin-uuid';
  const comicId = '10001';

  Map<String, dynamic> page(String id) => {
    'id': id,
    'name': '$id.jpg',
    'path': 'g/$id.jpg',
    'url': 'https://img.example/$id.jpg',
    'extern': const <String, dynamic>{},
  };

  Map<String, dynamic> chapter(
    String id,
    int order, {
    List<Map<String, dynamic>>? pages,
  }) => {
    'id': id,
    'name': '第$order话',
    'order': order,
    'requestId': id,
    'logicalKey': id,
    'storageChapterId': id,
    'extern': const <String, dynamic>{},
    'pages': pages ?? [page('$id-p1'), page('$id-p2')],
  };

  Map<String, dynamic> snapshotJson({
    required Map<String, dynamic> chapterJson,
    required List<Map<String, dynamic>> chaptersJson,
  }) => {
    'source': from,
    'data': {
      'comic': {'id': comicId, 'source': from, 'title': '示例本'},
      'chapter': chapterJson,
      'chapters': chaptersJson,
    },
  };

  PluginReadLaunch launchFor({
    required Map<String, dynamic> chapterJson,
    required List<Map<String, dynamic>> chaptersJson,
  }) {
    final snapshot = ComicReadSnapshot.fromMap(
      snapshotJson(chapterJson: chapterJson, chaptersJson: chaptersJson),
    );
    final launch = pluginReadLaunchFromSnapshot(
      snapshot: snapshot,
      fallbackComicId: comicId,
    );
    expect(launch, isNotNull, reason: '这份快照应当能直接起读');
    return launch!;
  }

  /// 复刻 `pushComicReadRoute` 里选章那一步用到的同一套公开件
  /// （目录解析 + 适配器 + 匹配器），用它算出阅读器随后会请求的章节 key。
  String requestIdOfSelectedChapter(
    PluginReadLaunch launch, {
    String? historyChapterId,
  }) {
    const adapter = DownloadChapterAdapter();
    const matcher = DownloadChapterMatcher();
    final chapters = launch.chapterRefs.map(adapter.fromChapterRef).toList();
    final selected = historyChapterId == null
        ? chapters.first
        : matcher.find(chapters, historyChapterId) ?? chapters.first;
    return selected.effectiveRequestId;
  }

  final threeChapters = [
    chapter('ch-1', 1),
    chapter('ch-2', 2),
    chapter('ch-3', 3),
  ];

  group('快照目录当详情目录用', () {
    test('章节数与规范 comicId 都取自快照', () {
      final launch = launchFor(
        chapterJson: threeChapters.first,
        chaptersJson: threeChapters,
      );

      expect(resolveReadEpsCount(launch, from, isDownload: false), 3);
      expect(resolveReadComicId(launch, from, isDownload: false), comicId);
    });

    test('requestId / storageChapterId / logicalKey 不再被丢掉', () {
      // 这三个 key 以前压根没解析：`ComicReadSnapshotChapterRef` 只读了
      // id/name/order/extern，于是插件返回的下载 key、存储目录 key 全落下。
      final snapshot = ComicReadSnapshot.fromMap(
        snapshotJson(
          chapterJson: threeChapters.first,
          chaptersJson: threeChapters,
        ),
      );

      expect(snapshot.chapters.map((e) => e.requestId), [
        'ch-1',
        'ch-2',
        'ch-3',
      ]);
      expect(snapshot.chapters.map((e) => e.logicalKey), [
        'ch-1',
        'ch-2',
        'ch-3',
      ]);
      expect(snapshot.chapters.map((e) => e.storageChapterId), [
        'ch-1',
        'ch-2',
        'ch-3',
      ]);
      expect(snapshot.chapter.requestId, 'ch-1');
    });

    test('目录顺序按 order 升序，不受插件返回顺序影响', () {
      final launch = launchFor(
        chapterJson: threeChapters.first,
        chaptersJson: [
          chapter('ch-3', 3),
          chapter('ch-1', 1),
          chapter('ch-2', 2),
        ],
      );

      expect(
        resolveUnifiedComicChapters(launch, from).map((e) => e.order).toList(),
        [1, 2, 3],
      );
    });
  });

  group('阅读器复用那次快照', () {
    test('从头读：插件默认给的第一章即命中', () {
      final launch = launchFor(
        chapterJson: threeChapters.first,
        chaptersJson: threeChapters,
      );

      expect(
        launch.matches(requestIdOfSelectedChapter(launch)),
        isTrue,
        reason: '没历史记录时，第二次要请求的章就是快照已经带回来的那章',
      );
    });

    test('续读：插件按我们传的 chapterId 返回同一章时即命中', () {
      final launch = launchFor(
        chapterJson: threeChapters[1],
        chaptersJson: threeChapters,
      );

      expect(
        launch.matches(
          requestIdOfSelectedChapter(launch, historyChapterId: 'ch-2'),
        ),
        isTrue,
      );
    });

    test('插件没吃我们传的 chapterId（回的是第一章）时不得复用', () {
      // 这是本组最关键的一条：误判成「命中」会直接把用户送到错误章节。
      final launch = launchFor(
        chapterJson: threeChapters.first,
        chaptersJson: threeChapters,
      );

      expect(
        launch.matches(
          requestIdOfSelectedChapter(launch, historyChapterId: 'ch-2'),
        ),
        isFalse,
        reason: '章对不上就必须让阅读器重新回源，最差等于改动前',
      );
    });

    test('章 key 对得上但一页都没有时不得复用', () {
      // 阳性对照：这把尺子要看得见「空快照」。插件把不认识的 key 当
      // 「无分页」处理并返回空数组是真实存在的行为，复用它会显示空白页。
      final launch = launchFor(
        chapterJson: chapter('ch-2', 2, pages: const <Map<String, dynamic>>[]),
        chaptersJson: threeChapters,
      );

      expect(
        launch.matches(
          requestIdOfSelectedChapter(launch, historyChapterId: 'ch-2'),
        ),
        isFalse,
      );
    });

    test('未知 key 一律不复用', () {
      final launch = launchFor(
        chapterJson: threeChapters.first,
        chaptersJson: threeChapters,
      );

      expect(launch.matches(''), isFalse);
      expect(launch.matches('ch-9'), isFalse);
    });
  });

  group('快照不可用时退回整本详情', () {
    test('插件没在快照里给 chapters 时折算失败', () {
      final launch = pluginReadLaunchFromSnapshot(
        snapshot: ComicReadSnapshot.fromMap(
          snapshotJson(
            chapterJson: threeChapters.first,
            chaptersJson: const [],
          ),
        ),
        fallbackComicId: comicId,
      );

      expect(launch, isNull);
    });

    test('快照没回 comicId 时用卡片上的 id 兜住', () {
      // 历史记录的键是 `from:comicId`，这里退化必须落到与调用方同一个 id 上，
      // 否则会写出第二条历史。
      final launch = pluginReadLaunchFromSnapshot(
        snapshot: ComicReadSnapshot.fromMap({
          'source': from,
          'data': {
            'comic': {'id': '', 'source': from, 'title': ''},
            'chapter': threeChapters.first,
            'chapters': threeChapters,
          },
        }),
        fallbackComicId: comicId,
      );

      expect(launch, isNotNull);
      expect(resolveReadComicId(launch, from, isDownload: false), comicId);
    });
  });
}
