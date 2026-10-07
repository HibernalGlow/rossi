/// 在线图源那条译文轨的判据。
///
/// # 这批测试守的是什么
///
/// 在线那一路没有 GPU 呈现器，「把这一页换成成品页」退化成了「显示端来问该画哪个
/// 路径」。于是最容易出的两种错都在这张表上：
/// 1. **串页** —— 换了一本书，旧书那一页的归属还留在表里，新书同号页直接端出
///    旧书的画面（本仓栽过两次，都是 per-book 状态住在单例里）；
/// 2. **谎报已显示** —— 写入成功就说「译文页」。这里给的答案是可核对的：
///    显示端每次 build 会把自己实际用上的路径记回来，芯片那句「译文页」只认它。
/// 第 2 条的证伪办法就写在测试里：不 `displayPathFor` 一次，证据必须是「不知道」，
/// 接线漏了会红在这里，而不是绿成一个假的成功。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:zephyr/reader/online_translated_page_surface.dart';
import 'package:zephyr/reader/online_translated_page_track.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/reader/translated_page_controller.dart';
import 'package:zephyr/widgets/picture_bloc/models/picture_info.dart';

const _bookA = 'pluginA|comicA|ch1';
const _bookB = 'pluginB|comicB|ch1';

PictureInfo _info({
  String from = 'pluginA',
  String cartoonId = 'comicA',
  String chapterId = 'ch1',
  String storageChapterId = '',
  String url = '',
}) => PictureInfo(
  from: from,
  cartoonId: cartoonId,
  chapterId: chapterId,
  storageChapterId: storageChapterId,
  url: url,
);

void main() {
  group('作用域：这一页属于哪本书的哪一章', () {
    test('没有 comicId 的不算漫画页（封面、插件图标走这里）', () {
      expect(onlineTranslatedPageScope(_info(cartoonId: '')), isNull);
    });

    test('章缺失时往下退到 storageChapterId，再退到 url', () {
      expect(
        onlineTranslatedPageScope(
          _info(chapterId: '', storageChapterId: 'sc7'),
        ),
        'pluginA|comicA|sc7',
      );
      expect(
        onlineTranslatedPageScope(
          _info(chapterId: '', storageChapterId: '', url: 'https://x/1.jpg'),
        ),
        'pluginA|comicA|https://x/1.jpg',
      );
    });

    test('三项都空时判不成作用域，而不是并成一个空串', () {
      expect(
        onlineTranslatedPageScope(
          _info(chapterId: '', storageChapterId: '', url: ''),
        ),
        isNull,
      );
    });

    test('同一本书换一章，作用域要变（不然两章的第 3 页撞成一个键）', () {
      expect(
        onlineTranslatedPageScope(_info(chapterId: 'ch1')),
        isNot(onlineTranslatedPageScope(_info(chapterId: 'ch2'))),
      );
    });
  });

  group('译文轨：这一帧该画哪张图', () {
    late Directory tmp;
    late String original;
    late String artifact;
    late OnlineTranslatedPageTrack track;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('rossi_online_track_test_');
      original = File('${tmp.path}/orig.png').path;
      artifact = File('${tmp.path}/p3.png').path;
      await File(original).writeAsBytes(List.filled(16, 1));
      await File(artifact).writeAsBytes(List.filled(16, 1));
      track = OnlineTranslatedPageTrack.forTest();
    });

    tearDown(() async {
      await tmp.delete(recursive: true);
    });

    test('没认领时端回原图，同时把原图路径记成 OCR 的输入', () {
      final shown = track.displayPathFor(
        scope: _bookA,
        index: 3,
        sourcePath: original,
      );
      expect(shown, original);
      expect(track.sourcePathFor(3), original);
    });

    test('认领之后端出成品页', () {
      track.displayPathFor(scope: _bookA, index: 3, sourcePath: original);
      track.claim(3, artifact);
      expect(
        track.displayPathFor(scope: _bookA, index: 3, sourcePath: original),
        artifact,
      );
    });

    test('成品页文件不在了要退回原图，不能拿死路径去画', () async {
      track.displayPathFor(scope: _bookA, index: 3, sourcePath: original);
      track.claim(3, artifact);
      await File(artifact).delete();
      expect(
        track.displayPathFor(scope: _bookA, index: 3, sourcePath: original),
        original,
      );
    });

    test('换书之后旧书的归属不能跟过来（同序号也不行）', () {
      track.displayPathFor(scope: _bookA, index: 5, sourcePath: original);
      track.claim(5, artifact);
      expect(
        track.displayPathFor(scope: _bookB, index: 5, sourcePath: original),
        original,
        reason: '这里出 artifact 就是把 A 本第 5 页贴到 B 本第 5 页上',
      );
      expect(track.translationOwnedPages, isEmpty);
    });

    test('认领与摘除各播报一次；建作用域那一次挪到本帧之后播', () async {
      var notified = 0;
      track.addListener(() => notified++);
      // 绑定作用域发生在 build 里（显示端上报路径就是那一帧），当场播报会把
      // 监听者标脏在构建过程中 —— debug 下就是那句 markNeedsBuild during build。
      track.displayPathFor(scope: _bookA, index: 3, sourcePath: original);
      expect(notified, 0, reason: '当场就播 = 在构建过程中通知别人重建');
      await pumpEventQueue();
      expect(notified, 1, reason: '芯片要等这一拍才知道「现在是在线漫画页」');

      track.displayPathFor(scope: _bookA, index: 3, sourcePath: original);
      await pumpEventQueue();
      expect(notified, 1, reason: '同一作用域反复重建不该再播，否则一次重建风暴');

      track.claim(3, artifact);
      expect(notified, 2);
      track.release(3);
      expect(notified, 3);
      track.release(3);
      expect(notified, 3, reason: '重复摘除不该再播报');
    });
  });

  group('换章要让在飞的构建认出自己过期', () {
    test('第一次建作用域不 reset，换作用域才 reset', () async {
      final previous = TranslatedPageController.useForTest(
        TranslatedPageController(),
      );
      var controllerNotices = 0;
      TranslatedPageController.instance.addListener(() => controllerNotices++);
      addTearDown(() => TranslatedPageController.useForTest(previous));

      final track = OnlineTranslatedPageTrack.forTest();
      track.displayPathFor(scope: _bookA, index: 0, sourcePath: '/a/0.png');
      await pumpEventQueue();
      expect(controllerNotices, 0, reason: '开局没有旧状态可清，不该顺手关掉会话');
      track.displayPathFor(scope: _bookB, index: 0, sourcePath: '/b/0.png');
      expect(controllerNotices, 0, reason: 'reset 也跟在 build 后面，不能当场播');
      await pumpEventQueue();
      expect(controllerNotices, 1);
    });
  });

  group('画面证据：「注入了」与「画面上换了」是两件事', () {
    test('那一页还没在屏上建过 = 答不上来，不是没换上', () {
      final track = OnlineTranslatedPageTrack.forTest();
      expect(track.isShowing('/somewhere/p1.png', 1), isNull);
    });

    test('显示端真的拿成品页去画了，才算已显示', () async {
      final tmp = await Directory.systemTemp.createTemp('rossi_evidence_test_');
      final original = File('${tmp.path}/o.png')..writeAsBytesSync([1]);
      final artifact = File('${tmp.path}/p1.png')..writeAsBytesSync([1]);
      final track = OnlineTranslatedPageTrack.forTest();
      final surface = OnlineTranslatedPageSurface(track);
      addTearDown(() => tmp.delete(recursive: true));

      track.displayPathFor(scope: _bookA, index: 1, sourcePath: original.path);
      expect(await surface.setEnhancedImage(1, artifact.path), isTrue);
      // 写入成功了，但那一帧还没重建过 —— 画面上仍是原图。
      // 这里要的是 false（「我问过，它现在不是成品页」）而不是 null（「这页没建过」），
      // 两种「还不是」分不开的话，芯片就会在没换上的那一瞬谎报已显示。
      expect(
        await surface.presenterUsesEnhanced(1),
        isFalse,
        reason: '写入不等于上屏，这一格还不能是 true',
      );
      track.displayPathFor(scope: _bookA, index: 1, sourcePath: original.path);
      expect(await surface.presenterUsesEnhanced(1), isTrue);

      surface.translationOwnedPages.remove(1);
      track.displayPathFor(scope: _bookA, index: 1, sourcePath: original.path);
      expect(
        await surface.presenterUsesEnhanced(1),
        isFalse,
        reason: '摘掉之后证据要回到 false，不能停在 true 继续说「译文页」',
      );
    });
  });

  group('在线呈现适配器', () {
    test('拒绝注入一张不存在的图', () async {
      final track = OnlineTranslatedPageTrack.forTest();
      final surface = OnlineTranslatedPageSurface(track);
      expect(await surface.setEnhancedImage(2, '/nope/p2.png'), isFalse);
      expect(track.translationOwnedPages.containsKey(2), isFalse);
    });

    test('归属表就是轨那份表 —— 芯片与超分读的是同一份账', () async {
      final tmp = await Directory.systemTemp.createTemp('rossi_owned_test_');
      final artifact = File('${tmp.path}/p0.png')..writeAsBytesSync([1]);
      final track = OnlineTranslatedPageTrack.forTest();
      final surface = OnlineTranslatedPageSurface(track);
      addTearDown(() => tmp.delete(recursive: true));

      await surface.setEnhancedImage(0, artifact.path);
      surface.translationOwnedPages[9] = 'written-through';
      expect(track.translationOwnedPages[9], 'written-through');
    });

    test('在线这一路没有「对比原图」那种旁路', () {
      expect(OnlineTranslatedPageSurface().bypassesEnhancedTrack, isFalse);
    });
  });

  group('在线输入视图', () {
    test('只回答「第 N 页那个文件在哪」，没上报过的页回 null', () async {
      final track = OnlineTranslatedPageTrack.forTest();
      final input = OnlineTranslatedPageInput(track);
      expect(await input.getPageFilePath(4), isNull);
      expect(await input.getPageBytes(4), isNull);

      final tmp = await Directory.systemTemp.createTemp('rossi_input_test_');
      final file = File('${tmp.path}/p4.png')..writeAsBytesSync([7, 7]);
      track.displayPathFor(scope: _bookA, index: 4, sourcePath: file.path);
      expect(await input.getPageFilePath(4), file.path);
      expect(await input.getPageBytes(4), [7, 7]);
      addTearDown(() => tmp.delete(recursive: true));
    });

    test('源身份从轨上来（构建成品页时靠它分档）', () {
      final track = OnlineTranslatedPageTrack.forTest();
      final input = OnlineTranslatedPageInput(track);
      expect(input.translationCacheScope, isNull);
      track.displayPathFor(scope: _bookA, index: 0, sourcePath: '/a/0.png');
      expect(input.translationCacheScope, _bookA);
    });

    test('页表与解码不在这条路上：误用要抛出来，不能安静给空', () {
      final input = OnlineTranslatedPageInput(
        OnlineTranslatedPageTrack.forTest(),
      );
      expect(() => input.pages, throwsUnsupportedError);
      expect(() => input.pageCount, throwsUnsupportedError);
      expect(() => input.rasterTargetFor(0), throwsUnsupportedError);
    });
  });

  // # 这个测试守的是哪一句
  //
  // 「不报源身份的来源仍然是合法的 `PageSource`」。我差点把源身份做成 `PageSource`
  // 上的一个成员，那等于每加一个概念就改一遍全仓所有 `implements PageSource` 的类：
  // 抽象成员让六个假来源当场编译不过（先红的是 `animated_local_page_test.dart` 里那个），
  // 而**带默认实现的成员更阴** —— 上面这个 `_BarePageSource` 编译通过、
  // 运行时才抛 `NoSuchMethodError`，因为 `implements` 不继承实现，
  // 有 body 也只会生成转发到 `noSuchMethod` 的桩。
  // 所以它是一条独立的能力接口：不实现就是没有源身份，别人不用动一行。
  group('PageSource 仍可被裸实现', () {
    test('一个不报源身份的来源照样是合法的 PageSource', () async {
      final PageSource bare = _BarePageSource();
      expect(bare.pageCount, 0);
      expect(await bare.getPageFilePath(0), isNull);
      expect(
        bare is TranslationScopeBearing,
        isFalse,
        reason: '不实现那条接口 = 不参与成品页分档，行为与之前逐字一致',
      );
    });
  });
}

/// 把 `PageSource` 的每一个成员都自己实现一遍 —— 少一个都会在运行时炸，
/// 理由见上面那段注释。
class _BarePageSource implements PageSource {
  @override
  String get path => '/bare';

  @override
  List<PageRef> get pages => const <PageRef>[];

  @override
  int get pageCount => 0;

  @override
  RasterTargetRef? rasterTargetFor(int index) => null;

  @override
  Future<PageLoadOutcome> load(
    int index, {
    int? targetWidth,
    PageLoadIntent intent = PageLoadIntent.interactive,
  }) => throw UnimplementedError('这条测试不解码');

  @override
  Future<void> close() async {}

  @override
  Future<String?> getPageFilePath(int index) => Future.value(null);

  @override
  Future<Uint8List?> getPageBytes(int index) => Future.value(null);
}
