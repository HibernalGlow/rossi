/// 视频播放的纯逻辑回归测试。
///
/// 覆盖面按「两个上游各自最容易被改坏的部分」选：
/// - 媒体身份表（neoview `media.ts`）：伪装后缀与「gif 不是视频」这两条一旦漂移，
///   症状是同一本书每次打开页数不一样；
/// - 播放状态机（neoview `ReaderVideoController.ts` + mimage `engine/state.rs`）：
///   倍速归一化、音量⇔静音联动、`ended` 只在 list 档翻页；
/// - 完成/恢复阈值（neo `PageVideo.tsx:99-141`）；
/// - 字幕匹配与 SRT/ASS→VTT 转换；
/// - 抽帧缓存的容差最近帧查找（mimage `thumbnail.rs` 的核心不变式）。
///
/// 这里**不起播放器**：所有测试都打到 `ReaderVideoController` 与纯函数上，
/// `VideoTransport` 用假实现。真机播放验证属于手工验收，不放自动化。
library;

import 'dart:async';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/video/controller/reader_video_controller.dart';
import 'package:zephyr/video/controller/video_action_dispatch.dart';
import 'package:zephyr/video/controller/video_transport.dart';
import 'package:zephyr/video/service/video_frame_preview.dart';
import 'package:zephyr/video/subtitle/video_subtitle.dart';
import 'package:zephyr/video/model/animated_video_mode.dart';
import 'package:zephyr/video/model/video_media_kind.dart';
import 'package:zephyr/video/view/active_video_scope.dart';

void main() {
  test('加载尚未挂接时退出，不重新订阅播放器或恢复进度定时器', () async {
    final controller = ReaderVideoController(host: _NullHost(), progressKey: 'k');
    final attaching = controller.attach(_FakeTransport());
    controller.dispose();
    await attaching;
    expect(controller.transport, isNull);
  });

  group('媒体身份判定（neo media.ts）', () {
    test('常规后缀分档正确', () {
      expect(mediaKindOf('page01.jpg'), RossiMediaKind.image);
      expect(mediaKindOf('cover.PNG'), RossiMediaKind.image);
      expect(mediaKindOf('motion.gif'), RossiMediaKind.animatedImage);
      expect(mediaKindOf('intro.webm'), RossiMediaKind.video);
      expect(mediaKindOf('chapter.mkv'), RossiMediaKind.video);
      expect(mediaKindOf('README.txt'), isNull);
    });

    test('gif 不算视频：它是「动图」这一档，归「动图当视频播」那条开关管', () {
      expect(isVideoName('a.gif'), isFalse);
    });

    test('伪装后缀按真实内容解析：.nov 其实是被改名的 mp4', () {
      expect(mediaKindOf('episode.nov'), RossiMediaKind.video);
      expect(mimeTypeForExtension('nov'), 'video/mp4');
      expect(mediaKindOf('pic.wbp'), RossiMediaKind.image);
    });

    test('目录名里的点不算后缀（与 Rust extension_lower 同一条判断）', () {
      expect(extensionLower('Vol.2/page'), isNull);
      expect(extensionLower('vol.2/page.jpg'), 'jpg');
      expect(mediaKindOf('archive.mkv/001.png'), RossiMediaKind.image);
    });

    test('用户别名要能加，但与图片档冲突要报出来', () {
      const ok = MediaKindOverrides(extraVideoExtensions: ['xvid']);
      expect(mediaKindOf('clip.xvid', ok), RossiMediaKind.video);
      expect(ok.invalidEntries, isEmpty);

      const conflicting = MediaKindOverrides(
        extraVideoExtensions: ['png', 'xvid2', 'png'],
      );
      // 只报「与图片档重叠」这一条问题；重复项按集合语义去重，不该刷两条。
      expect(conflicting.invalidEntries.length, 1);
      expect(conflicting.invalidEntries.single, contains('png'));
    });
  });

  group('倍速与音量夹取（neo normalizeRuntime）', () {
    test('0 / 负数这类配置要归一到可用下界，而不是把时钟停在原地', () {
      final r = normalizePlaybackRateRuntime(min: 0, max: 0, step: 0);
      expect(r.min, 0.05);
      expect(r.max, greaterThanOrEqualTo(r.min));
      expect(r.step, 0.01);
    });

    test('倍速按步长吸附再夹到区间', () async {
      final controller = ReaderVideoController(
        host: _NullHost(),
        progressKey: 'k',
        transport: _FakeTransport(duration: const Duration(seconds: 100)),
        rateRuntime: (min: 0.25, max: 4, step: 0.25),
      );
      await controller.setPlaybackRate(1.3);
      expect(controller.snapshot.playbackRate, 1.25);
      await controller.setPlaybackRate(99);
      expect(controller.snapshot.playbackRate, 4.0);
      expect(
        (controller.transport as _FakeTransport).commands,
        contains('rate=4.0'),
      );
    });

    test('音量归零等于静音，恢复音量解除静音', () async {
      final controller = ReaderVideoController(
        host: _NullHost(),
        progressKey: 'k',
        transport: _FakeTransport(),
      );
      await controller.setVolume(0);
      expect(controller.snapshot.muted, isTrue);
      await controller.setVolume(0.5);
      expect(controller.snapshot.muted, isFalse);
      expect(controller.snapshot.volume, 0.5);
    });

    test('没有活动播放器时动作一律返回 false（不可用而不是崩）', () async {
      final controller = ReaderVideoController(
        host: _NullHost(),
        progressKey: 'k',
      );
      expect(await controller.togglePlay(), isFalse);
      expect(await controller.seekBackward(), isFalse);
      expect(await controller.stepFrame(1), isFalse);
    });
  });

  group('循环档与翻页（neo onListEnded）', () {
    test('循环档按 list → single → none 轮换', () {
      expect(ReaderVideoLoopMode.list.next(), ReaderVideoLoopMode.single);
      expect(ReaderVideoLoopMode.single.next(), ReaderVideoLoopMode.none);
      expect(ReaderVideoLoopMode.none.next(), ReaderVideoLoopMode.list);
    });

    test('只有 list 档在播完时翻页；single 档不翻', () async {
      final host = _NullHost();
      final transport = _FakeTransport()..autoplayEnded = false;
      final controller = ReaderVideoController(
        host: host,
        progressKey: 'k',
        transport: transport,
      );
      await controller.attach(transport);
      await controller.setLoopMode(ReaderVideoLoopMode.single);
      transport.emitCompleted();
      await Future<void>.delayed(Duration.zero);
      expect(host.listEndedCalls, 0);

      transport.emitCompleted();
      await Future<void>.delayed(Duration.zero);
      expect(
        host.listEndedCalls,
        0,
        reason: '同一次播放只允许触发一次 ended',
      );

      await controller.setLoopMode(ReaderVideoLoopMode.list);
      transport.resetEnded();
      transport.emitCompleted();
      await Future<void>.delayed(Duration.zero);
      expect(host.listEndedCalls, 1);
    });

    test('single 档要把 loop-file 打开（mimage set_loop_enabled 的等效）', () async {
      final transport = _FakeTransport();
      final controller = ReaderVideoController(
        host: _NullHost(),
        progressKey: 'k',
        transport: transport,
      );
      await controller.setLoopMode(ReaderVideoLoopMode.single);
      expect(transport.commands, contains('loopFile=true'));
      await controller.setLoopMode(ReaderVideoLoopMode.none);
      expect(transport.commands, contains('loopFile=false'));
    });
  });

  group('进度完成与恢复阈值（neo PageVideo）', () {
    test('结尾容差取「5 秒」与「总时长 5%」的小值', () {
      // 3 分钟视频：5% = 9 s > 5 s ⇒ 用 5 s，门槛落在 175 s。
      expect(
        VideoPlaybackProgress.isCompletedAt(
          position: const Duration(seconds: 176),
          duration: const Duration(seconds: 180),
        ),
        isTrue,
      );
      expect(
        VideoPlaybackProgress.isCompletedAt(
          position: const Duration(seconds: 174),
          duration: const Duration(seconds: 180),
        ),
        isFalse,
      );
      // 10 分钟视频：5% = 30 s > 5 s ⇒ 仍是 5 s。
      expect(
        VideoPlaybackProgress.isCompletedAt(
          position: const Duration(seconds: 596),
          duration: const Duration(minutes: 10),
        ),
        isTrue,
      );
      // 60 秒短片：5% = 3 s < 5 s ⇒ 用 3 s，第 58 秒即算看完。
      expect(
        VideoPlaybackProgress.isCompletedAt(
          position: const Duration(seconds: 58),
          duration: const Duration(seconds: 60),
        ),
        isTrue,
      );
    });

    test('已完成的条目不再给恢复位置', () {
      expect(
        VideoPlaybackProgress.restorePosition(
          position: const Duration(seconds: 30),
          duration: const Duration(seconds: 60),
          completed: true,
        ),
        isNull,
      );
      expect(
        VideoPlaybackProgress.restorePosition(
          position: const Duration(seconds: 58),
          duration: const Duration(seconds: 60),
          completed: false,
        ),
        isNull,
        reason: '落在结尾 5 秒内，重开等于没看完，那就从头放',
      );
      expect(
        VideoPlaybackProgress.restorePosition(
          position: const Duration(seconds: 20),
          duration: const Duration(seconds: 60),
          completed: false,
        ),
        const Duration(seconds: 20),
      );
    });
  });

  group('A–B 循环与 seek-mode', () {
    test('点三次：设 A → 设 B 成区间 → 第三次在 A 之前则清空', () async {
      final transport = _FakeTransport();
      final controller = ReaderVideoController(
        host: _NullHost(),
        progressKey: 'k',
        transport: transport,
      );
      await controller.attach(transport);
      // 位置是经 `positionStream` **异步**回推到快照的，不打一拍就点，
      // 点到的还是 currentTime == 0。
      Future<void> positionAt(Duration at) async {
        transport.emitPosition(at);
        await Future<void>.delayed(Duration.zero);
      }

      await positionAt(const Duration(seconds: 5));
      controller.tapAbLoop();
      expect(controller.markedPointA, const Duration(seconds: 5));
      expect(controller.snapshot.abLoop, isNull);

      await positionAt(const Duration(seconds: 9));
      controller.tapAbLoop();
      expect(controller.snapshot.abLoop, isNotNull);
      expect(transport.commands, contains('ab=5s..9s'));

      await positionAt(const Duration(seconds: 2));
      controller.tapAbLoop();
      expect(controller.snapshot.abLoop, isNull);
    });

    test('seek-mode 只翻开关，不动别的状态', () async {
      final controller = ReaderVideoController(
        host: _NullHost(),
        progressKey: 'k',
        transport: _FakeTransport(),
      );
      final before = controller.snapshot.playbackRate;
      controller.toggleSeekMode();
      expect(controller.snapshot.seekMode, isTrue);
      expect(controller.snapshot.playbackRate, before);
    });
  });

  group('字幕：同名匹配与格式转换', () {
    test('同主干 + 语言后缀命中，前缀巧合不误伤', () {
      final found = matchSubtitleNames(
        videoName: 'movie.mp4',
        entryNames: <String>[
          'movie.zh-CN.srt',
          'movie.ass',
          'movieost.srt',
          'movie.ssa',
          'other.vtt',
        ],
      );
      expect(
        // 命中 3 条：movie.ass / movie.ssa 都是「默认」，movie.zh-CN.srt 带语言；
        // `movieost.srt` 与 `other.vtt` 都不算（前者主干不是 `movie` + 分隔符）。
        // 排序按 label 字符串，`zh-CN` 的 ASCII 小于中文，所以排在最前。
        found.map((c) => c.label),
        <String>['zh-CN', '默认', '默认'],
      );
      expect(found.any((c) => c.label == 'ost'), isFalse);
    });

    test('SRT → VTT：逗号毫秒、多行文本、序号行都要处理', () {
      final vtt = convertSubtitlesToWebVtt(
        '''
1
00:00:01,500 --> 00:00:04,000
第一行
第二行

2
00:00:05,000 --> 00:00:06,000
你好
''',
        format: 'srt',
      );
      expect(vtt, startsWith('WEBVTT'));
      expect(vtt, contains('00:00:01.500 --> 00:00:04.000'));
      expect(vtt, contains('第一行\n第二行'));
      expect(vtt, contains('00:00:05.000 --> 00:00:06.000'));
    });

    test('ASS → VTT：只取 Dialogue 行，剥离 {} 覆盖标签，\\N 转换行', () {
      final vtt = convertSubtitlesToWebVtt(
        '''
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.20,0:00:03.40,Default,,0,0,0,,主字幕{\\an8}\\N第二行
Comment: 0,0:00:00.00,0:00:01.00,Default,,0,0,0,,不该出现
''',
        format: 'ass',
      );
      expect(vtt, contains('00:00:01.200 --> 00:00:03.400'));
      expect(vtt, contains('主字幕\n第二行'));
      expect(vtt, isNot(contains('不该出现')));
      expect(vtt, isNot(contains('{\\an8}')));
    });

    test('正文里含逗号时不能切错（ASS 第 11 个字段之后全归正文）', () {
      final vtt = convertSubtitlesToWebVtt(
        'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,前半,后半',
        format: 'ass',
      );
      expect(vtt, contains('前半,后半'));
    });

    test('.sub（MicroDVD）按帧号换算，竖线是换行', () {
      final vtt = convertSubtitlesToWebVtt(
        '#V2.00\n{24}{48}你好\n{72}{96}第一行|第二行\n',
        format: 'sub',
        fps: 24,
      );
      // 24/24 = 1.0 s，48/24 = 2.0 s
      expect(vtt, contains('00:00:01.000 --> 00:00:02.000'));
      expect(vtt, contains('你好'));
      expect(vtt, contains('第一行\n第二行'));
      expect(vtt, isNot(contains('#V2.00')));
    });

    test('.sub 里一条都没有时不产出可用字幕（宁可不挂）', () {
      final vtt = convertSubtitlesToWebVtt(
        '#V2.00\n这一行根本不合格式\n',
        format: 'sub',
      );
      expect(vtt.contains('-->'), isFalse);
    });

    test('.sub 的帧号倒挂时跳过该条', () {
      final vtt = convertSubtitlesToWebVtt(
        '{100}{50}倒挂\n{10}{20}正常\n',
        format: 'sub',
        fps: 10,
      );
      expect(vtt, isNot(contains('倒挂')));
      expect(vtt, contains('正常'));
    });

  });

  group('抽帧缓存（mimage thumbnail.rs 的容差最近帧）', () {
    test('键量化到 0.5 秒，鼠标蹭同一片区域命中同一格', () {
      expect(
        VideoFrameCache.quantizeMicros(const Duration(milliseconds: 1200)),
        VideoFrameCache.quantizeMicros(const Duration(milliseconds: 1400)),
      );
    });

    test('优先返回「已过的那一帧」，超容差才允许用未来的', () {
      final cache = VideoFrameCache();
      cache.put(const Duration(seconds: 10), '/f10.jpg');
      cache.put(const Duration(seconds: 20), '/f20.jpg');

      final near = cache.nearest(target: const Duration(seconds: 11));
      expect(near?.filePath, '/f10.jpg');

      expect(
        cache.nearest(
          target: const Duration(seconds: 40),
          tolerance: const Duration(seconds: 1),
        ),
        isNull,
      );
      // 目标在两帧之前：默认容差 1.5 s 够不到 10 s 那一帧 ⇒ 不给；
      // 放宽到 2 s 才允许用「未来的帧」顶上。
      expect(cache.nearest(target: const Duration(seconds: 8)), isNull);
      expect(
        cache.nearest(
          target: const Duration(seconds: 8),
          tolerance: const Duration(seconds: 2),
        )?.filePath,
        '/f10.jpg',
      );
    });

    test('超过上限淘汰最旧的，不淘汰刚写入的', () {
      final cache = VideoFrameCache(maxEntries: 3);
      for (var i = 0; i < 5; i++) {
        cache.put(Duration(seconds: i), '/f$i.jpg');
      }
      expect(cache.length, 3);
      expect(
        cache.nearest(
          target: const Duration(seconds: 4),
          tolerance: const Duration(seconds: 5),
        )?.filePath,
        '/f4.jpg',
        reason: '精确键优先，不能因为「过去一格也存在」就退回 3 秒那帧',
      );
    });

    test('拖动条预览要先定位到鼠标所指的时刻，再截当前帧', () async {
      // 这条断言防的是「预览永远显示现在这一帧」：screenshot 截的是当前解码位置，
      // 不先 seek 过去，划到哪儿看到的都是同一张图。
      final transport = _FakeTransport()..autoplayEnded = false;
      final provider = VideoFramePreviewProvider(
        transport: transport,
        cacheDirOverride: Directory.systemTemp.createTempSync('rossi-preview').path,
      );
      await provider.request(const Duration(seconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(transport.commands, contains('seek=30s'));
      expect(
        transport.commands.indexOf('seek=30s') < transport.commands.indexOf('shot'),
        isTrue,
        reason: '顺序必须是先定位再截图',
      );
      // 播放中不许抢用户的位置：那时只给已缓存的帧。
      transport.commands.clear();
      transport.isPlaying = true;
      provider.cache.clear();
      await provider.request(const Duration(seconds: 12));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(transport.commands, isNot(contains('seek=12s')));
      expect(transport.commands, isNot(contains('shot')));
      await provider.dispose();
      await Directory(provider.cacheDirOverride!).delete(recursive: true);
    });
  });

  group('章节跳转（mimage 章节边界 + neo boundary_starts_from_chapters）', () {
    test('容器没有章节时动作不适用，不假装跳到了第 0 章', () async {
      final transport = _FakeTransport();
      final controller = ReaderVideoController(
        host: _NullHost(),
        progressKey: 'k',
        transport: transport,
      );
      expect(await controller.nextChapter(), isFalse);
      expect(await controller.previousChapter(), isFalse);
      expect(transport.commands, isEmpty);
    });

    test('有章节时 ±1 落到引擎', () async {
      final transport = _FakeTransport(chapters: const <VideoChapter>[
        VideoChapter(index: 0, title: '开场', at: Duration.zero),
        VideoChapter(index: 1, title: '正片', at: Duration(minutes: 2)),
      ]);
      final controller = ReaderVideoController(
        host: _NullHost(),
        progressKey: 'k',
        transport: transport,
      );
      expect(await controller.nextChapter(), isTrue);
      expect(transport.commands, contains('chapter=1'));
      expect(await controller.previousChapter(), isTrue);
      expect(transport.commands, contains('chapter=-1'));
    });
  });

  group('用户后缀别名（neo format alias，登记表形态）', () {
    tearDown(() => VideoAliasRegistry.instance.update(const <String>[]));

    test('登记后别名算视频，且不再被当成图片页', () {
      VideoAliasRegistry.instance.update(const <String>['MyVid ']);
      expect(isVideoName('clip.myvid'), isTrue);
      expect(isImageName('clip.myvid'), isFalse,
          reason: '用户明确声明成视频的后缀，不该在封面/缩略图那条路被当图片处理');
      expect(mediaKindOf('clip.myvid'), RossiMediaKind.video);
    });

    test('清空登记表后别名立刻失效', () {
      VideoAliasRegistry.instance.update(const <String>['myvid']);
      VideoAliasRegistry.instance.update(const <String>[]);
      expect(isVideoName('clip.myvid'), isFalse);
    });

    test('过长的别名不进登记表（与校验同一口径）', () {
      VideoAliasRegistry.instance.update(const <String>[
        'a-very-long-extension-name',
      ]);
      expect(VideoAliasRegistry.instance.extraVideoExtensions, isEmpty);
    });
  });

  test('formatVideoTime：一小时内不显示小时位', () {
    expect(formatVideoTime(const Duration(seconds: 9)), '00:09');
    expect(formatVideoTime(const Duration(minutes: 5, seconds: 7)), '05:07');
    expect(
      formatVideoTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });

  group('动图当视频播（neo animatedVideoEnabled，默认关）', () {
    test('开关关闭时一律不接管：不改设置行为与改造前逐字一致', () {
      expect(shouldOpenAnimatedImageAsVideo('motion.gif', enabled: false), isFalse);
    });

    test('开启后 gif / apng 自动接管，webp 不自动接管', () {
      expect(shouldOpenAnimatedImageAsVideo('m.gif', enabled: true), isTrue);
      expect(shouldOpenAnimatedImageAsVideo('m.apng', enabled: true), isTrue);
      expect(
        shouldOpenAnimatedImageAsVideo('page.webp', enabled: true),
        isFalse,
        reason: '静图 webp 远多于动图，自动接管会把整本正常页换成播放器',
      );
    });

    test('关键字命中不看后缀，且大小写与方括号都归一', () {
      expect(
        shouldOpenAnimatedImageAsVideo('p [#dyna].png', enabled: true),
        isTrue,
      );
      expect(shouldOpenAnimatedImageAsVideo('p #dyna#.jpg', enabled: true), isTrue);
      expect(normalizeAnimatedVideoKeyword(' [#DYNA] '), '#dyna');
    });

    test('空关键字不能吞掉一切', () {
      expect(
        shouldOpenAnimatedImageAsVideo('normal.png', enabled: true, keywords: ['']),
        isFalse,
      );
    });
  });

  group('注册表跨语言一致性', () {
    /// 动作 id 在 Rust 注册表与 Dart 执行体两边各有一份字面量，漂移的症状不是编译失败，
    /// 而是「设置页里能看到这条动作、绑了键却永远什么都不发生」。这次改名
    /// （`video.toggle-play` → `video.play-pause` 等）正是靠这条断言兜住的。
    test('Dart 侧的 video 动作 id 必须逐条出现在 Rust 注册表里', () {
      final vocab = File(
        'rust/local_core/src/operation_binding/vocabulary.rs',
      ).readAsStringSync();
      expect(kVideoActionIds.toSet().length, kVideoActionIds.length,
          reason: 'Dart 侧不许重复登记');
      for (final id in kVideoActionIds) {
        expect(id.startsWith('video.'), isTrue, reason: '前缀要跟 context 一致');
        expect(
          vocab,
          contains('"$id"'),
          reason: 'Rust 注册表里没有这条：设置页列不出来，或列出来了但解析不到执行体',
        );
      }
    });

    test('注册表里的每条 video 动作在 Dart 都有登记（双向）', () {
      final vocab = File(
        'rust/local_core/src/operation_binding/vocabulary.rs',
      ).readAsStringSync();
      final registered = RegExp(r'"(video\.[a-z-]+)"')
          .allMatches(vocab)
          .map((m) => m.group(1)!)
          .toSet();
      expect(
        registered.difference(kVideoActionIds.toSet()),
        isEmpty,
        reason: 'Rust 登记了、Dart 不认：这条动作会被静默吞掉',
      );
      expect(registered.length, kVideoActionIds.length);
    });
  });


  group('视频文案的 i18n', () {
    // 用异步的 build()：en 的翻译库是懒加载的（生成码里 build() 会先
    // `await l_en_US.loadLibrary()`），buildSync() 在没加载过的进程里会炸。
    test('中英两套都有完整覆盖，且不是同一份中文兜底', () async {
      final zh = await AppLocale.zhCn.build();
      final en = await AppLocale.enUs.build();
      final zhLabels = <String, String>{
        'play': zh.video.play,
        'pause': zh.video.pause,
        'seekMode': zh.video.seekMode,
        'hwDecode': zh.video.hwDecode,
        'animatedVideo': zh.video.animatedVideo,
      };
      final enLabels = <String, String>{
        'play': en.video.play,
        'pause': en.video.pause,
        'seekMode': en.video.seekMode,
        'hwDecode': en.video.hwDecode,
        'animatedVideo': en.video.animatedVideo,
      };
      for (final entry in enLabels.entries) {
        expect(entry.value.trim().isNotEmpty, isTrue, reason: '${entry.key} 缺英文');
        expect(
          entry.value == zhLabels[entry.key],
          isFalse,
          reason: '${entry.key} 英文与中文相同：多半是没翻，只是把中文复制过去',
        );
      }
      expect(zh.video.muted.contains('静音'), isTrue);
    });
  });

  group('SAR 归一化（mimage normalize_sar）', () {
    test('非法值退回 1:1，合法值约分', () {
      expect(VideoMetadata.normalizeSar(0, 0), (1, 1));
      expect(VideoMetadata.normalizeSar(-3, 4), (1, 1));
      expect(VideoMetadata.normalizeSar(1920, 1080), (16, 9));
    });
  });

  group('动作派发：每条注册过的视频动作都要接到执行器', () {
    // 判据表按 id 给；**表里没有这条 id 就失败**。理由是这类缺陷的形状：
    // 注册表里加了动作、派发器却走进 default 分支 —— 用户看到的是「按了没反应」，
    // 而键还被吃掉（跨语言那组测试只核对 id 集合对不对，问不出有没有执行器）。
    final judges =
      <String, void Function(_FakeTransport, ReaderVideoController, bool)>{
      // 控制器按当前相位选 play/pause（不是无条件 playOrPause），
      // 所以这里认「四条里任一」而不是钉某一条。
      BindingVideoAction.playPause: (t, c, n) => expect(
        t.commands.any(
          (x) => x == 'play' || x == 'pause' || x == 'toggle' || x.startsWith('playing='),
        ),
        isTrue,
      ),
      BindingVideoAction.seekBackward: (t, c, n) =>
          expect(t.commands, contains('rel=-10s')),
      BindingVideoAction.seekForward: (t, c, n) =>
          expect(t.commands, contains('rel=10s')),
      BindingVideoAction.seekModeToggle: (t, c, n) =>
          expect(c.snapshot.seekMode, isTrue),
      BindingVideoAction.frameStep: (t, c, n) =>
          expect(t.commands, contains('frame=1')),
      BindingVideoAction.frameStepBack: (t, c, n) =>
          expect(t.commands, contains('frame=-1')),
      BindingVideoAction.speedUp: (t, c, n) =>
          expect(t.commands, contains('rate=1.25')),
      BindingVideoAction.speedDown: (t, c, n) =>
          expect(t.commands, contains('rate=0.75')),
      BindingVideoAction.toggleSpeed: (t, c, n) => expect(
        t.commands.where((x) => x.startsWith('rate=')),
        isNotEmpty,
      ),
      BindingVideoAction.volumeUp: (t, c, n) =>
          expect(t.commands.any((x) => x.startsWith('vol=')), isTrue),
      BindingVideoAction.volumeDown: (t, c, n) =>
          expect(t.commands.any((x) => x.startsWith('vol=')), isTrue),
      BindingVideoAction.toggleMute: (t, c, n) =>
          expect(t.commands.any((x) => x.startsWith('mute=')), isTrue),
      BindingVideoAction.cycleLoop: (t, c, n) =>
          expect(c.snapshot.loopMode, ReaderVideoLoopMode.single),
      // 第一跳只把 A 记在控制器里（B 要等位置往前走），所以这里认「快照通知过」；
      // 三段语义本身在状态机那组测试里逐条钉过，这里是「接没接到执行器」。
      BindingVideoAction.abLoopTap: (t, c, n) =>
          expect(n, isTrue, reason: '打点要刷新快照'),
      BindingVideoAction.abLoopClear: (t, c, n) =>
          expect(t.commands, contains('ab=off')),
      BindingVideoAction.toggleSubtitle: (t, c, n) =>
          expect(t.commands, contains('subTrack=1')),
      BindingVideoAction.subtitleDelayUp: (t, c, n) =>
          expect(t.commands, contains('subDelay=250ms')),
      BindingVideoAction.subtitleDelayDown: (t, c, n) =>
          expect(t.commands, contains('subDelay=-250ms')),
      BindingVideoAction.toggleAudioOnly: (t, c, n) =>
          expect(t.commands, contains('video=false')),
      BindingVideoAction.nextChapter: (t, c, n) =>
          expect(t.commands, contains('chapter=1')),
      BindingVideoAction.previousChapter: (t, c, n) =>
          expect(t.commands, contains('chapter=-1')),
      // 这两条的效果长在页面上，派发器把它们广播给页面执行 —— 收到就算接到。
      BindingVideoAction.toggleControls: (t, c, n) {},
      BindingVideoAction.toggleFullscreen: (t, c, n) {},
      // 截图要往应用目录落盘（那条路径由 App 侧给出，纯测试到不了），
      // 所以这里只保证派发不抛、且不吃键；真正的落盘由 mpv 探针 ③ 覆盖。
      BindingVideoAction.screenshot: (t, c, n) {},
    };

    // 下面这条只是集合检查；单独写一条是为了让「漏了判据」在失败报告里显眼。
    test('每条 id 都有判据（漏了就是在注册表里挂了个没人执行的动作）', () {
      expect(
        kVideoActionIds.where((id) => !judges.containsKey(id)).toList(),
        isEmpty,
      );
      expect(judges.length, kVideoActionIds.length);
    });

    test('逐条派发：接到执行器，且没有活动视频时一条都不吃', () async {
      final scope = ActiveVideoScope.instance;
      for (final id in kVideoActionIds) {
        final transport = _FakeTransport(
          duration: const Duration(seconds: 120),
          chapters: const <VideoChapter>[
            VideoChapter(index: 0, title: 'a', at: Duration.zero),
            VideoChapter(index: 1, title: 'b', at: Duration(seconds: 60)),
          ],
        )..subs = const <VideoMediaTrack>[
            VideoMediaTrack(id: '1', title: 'zh'),
            VideoMediaTrack(id: '2', title: 'en'),
          ];
        final controller = ReaderVideoController(
          host: _NullHost(),
          progressKey: 'k',
          transport: transport,
        );
        await controller.attach(transport);
        var notified = false;
        controller.addListener(() => notified = true);
        // 每条动作都在「刚起播」的干净状态下派发：延迟与轮切下标是片内状态。
        resetVideoSubtitleActionState();
        scope.claim(controller);
        final ui = <String>[];
        final sub = scope.uiActions.listen(ui.add);
        // 截图那条内部是 unawaited 的异步落盘，测试 VM 里没有应用目录：
        // 用独立 zone 兜住，免得把无关的插件缺失算成派发的失败。
        var handled = false;
        runZonedGuarded(() {
          handled = dispatchVideoAction(id);
        }, (e, s) {});
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(handled, isTrue, reason: '$id 该被视频侧吃掉');
        judges[id]!(transport, controller, notified);
        if (id == BindingVideoAction.toggleControls ||
            id == BindingVideoAction.toggleFullscreen) {
          expect(ui, contains(id), reason: '$id 该广播给页面');
        }
        // 释放之后再派一次：没有目标时必须把键交回去，而不是凭空吞掉。
        scope.release(controller);
        expect(dispatchVideoAction(id), isFalse, reason: '$id 不该在无目标时吃键');
        await sub.cancel();
        controller.dispose();
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('暂停态按 ±10 s / 逐帧，时间标签要立刻跟着走（真机上位置流这时不发）', () async {
      final transport = _FakeTransport(duration: const Duration(seconds: 120));
      final controller = ReaderVideoController(
        host: _NullHost(),
        progressKey: 'k',
        transport: transport,
      );
      await controller.attach(transport);
      // 这个假实现**从不发**位置事件 —— 正是暂停态的真形状：只等事件，标签就不动。
      await controller.seekRelative(const Duration(seconds: 10));
      expect(controller.snapshot.currentTime, const Duration(seconds: 10));
      await controller.seekRelative(const Duration(seconds: -30));
      expect(
        controller.snapshot.currentTime,
        Duration.zero,
        reason: '越过起点要贴到 0（clampedToStart）',
      );
      await controller.seekRelative(const Duration(seconds: 500));
      expect(
        controller.snapshot.currentTime,
        const Duration(seconds: 120),
        reason: '越过终点要贴到末尾（clampedToEnd）',
      );

      // 逐帧：有帧率时按 1/fps 回填，不等引擎回报。
      final fps = _FakeTransport(
        duration: const Duration(seconds: 120),
      )..fpsForStep = 25.0;
      final stepped = ReaderVideoController(
        host: _NullHost(),
        progressKey: 'k',
        transport: fps,
      );
      await stepped.attach(fps);
      await stepped.seek(const Duration(seconds: 10));
      await stepped.stepFrame(1);
      expect(
        stepped.snapshot.currentTime.inMilliseconds,
        closeTo(10040, 60),
        reason: '25 fps 下走一帧该到 10.04 s',
      );
      await stepped.stepFrame(-1);
      expect(
        stepped.snapshot.currentTime.inMilliseconds,
        closeTo(10000, 60),
        reason: '退一帧要回得来',
      );
      stepped.dispose();
      controller.dispose();
    });

    test('字幕延迟不跨片残留（换一本从 0 开始）', () async {
      final transport = _FakeTransport(duration: const Duration(seconds: 100));
      final controller = ReaderVideoController(
        host: _NullHost(),
        progressKey: 'k',
        transport: transport,
      );
      await controller.attach(transport);
      ActiveVideoScope.instance.claim(controller);
      addTearDown(() {
        ActiveVideoScope.instance.release(controller);
        controller.dispose();
      });
      resetVideoSubtitleActionState();

      dispatchVideoAction(BindingVideoAction.subtitleDelayUp);
      dispatchVideoAction(BindingVideoAction.subtitleDelayUp);
      await Future<void>.delayed(Duration.zero);
      expect(transport.commands, contains('subDelay=500ms'));

      // 模拟换片起播：VideoPageSurface._start 里就是这么调的。
      resetVideoSubtitleActionState();
      dispatchVideoAction(BindingVideoAction.subtitleDelayUp);
      await Future<void>.delayed(Duration.zero);
      expect(
        transport.commands.last,
        'subDelay=250ms',
        reason: '上一本调出来的延迟不该跟到这一本',
      );
    });
  });

  group('视频设置持久化（encode ⇄ parse）', () {
    test('十条字段往返一个都不许丢', () {
      const original = VideoSettings(
        controlsPinned: true,
        hardwareDecode: false,
        autoPlay: false,
        minRate: 0.5,
        maxRate: 3.5,
        rateStep: 0.5,
        autoHideMilliseconds: 4200,
        volumePercent: 40,
        animatedVideoEnabled: true,
        animatedVideoKeywords: <String>['[#dyna]', '[#动]'],
        extraVideoExtensions: <String>['myvid', 'cbr-video'],
        deinterlace: true,
        subtitleStyle: VideoSubtitleStyle(
          sizeEm: 1.6,
          colorHex: 'ffe066',
          backgroundOpacityPercent: 30,
          bottomPercent: 12,
        ),
      );
      final back = VideoSettings.parse(original.encode());
      expect(back.controlsPinned, isTrue);
      expect(back.hardwareDecode, isFalse);
      expect(back.autoPlay, isFalse);
      expect(back.minRate, 0.5);
      expect(back.maxRate, 3.5);
      expect(back.rateStep, 0.5);
      expect(back.autoHideMilliseconds, 4200);
      expect(back.volumePercent, 40);
      expect(back.animatedVideoEnabled, isTrue);
      expect(back.animatedVideoKeywords, <String>['[#dyna]', '[#动]']);
      expect(back.extraVideoExtensions, <String>['myvid', 'cbr-video']);
      expect(back.deinterlace, isTrue);
      expect(back.subtitleStyle.sizeEm, 1.6);
      expect(back.subtitleStyle.colorHex, 'ffe066');
      expect(back.subtitleStyle.backgroundOpacityPercent, 30);
      expect(back.subtitleStyle.bottomPercent, 12);
    });

    test('读到不认识的内容退回默认，而不是把功能关掉', () {
      expect(VideoSettings.parse('nonsense').autoHideMilliseconds, 3000);
      expect(VideoSettings.parse('').hardwareDecode, isTrue);
      expect(VideoSettings.parse('subStyle=junk').subtitleStyle.sizeEm, 1.0);
      expect(
        VideoSettings.parse('animatedKeywords=a\u001fb').animatedVideoKeywords,
        <String>['a', 'b'],
      );
    });
  });
}

class _NullHost implements ReaderVideoHost {
  int listEndedCalls = 0;

  @override
  void onVideoListEnded() => listEndedCalls++;

  @override
  void onVideoProgress(VideoPlaybackProgress progress) {}
}

class _FakeTransport implements VideoTransport {
  _FakeTransport({this.duration = Duration.zero, this.chapters = const <VideoChapter>[]});

  /// 章节列表：跳转动作在「没有章节」时必须判定为不适用。
  final List<VideoChapter> chapters;

  final List<String> commands = <String>[];
  final StreamController<bool> _completed = StreamController<bool>.broadcast();
  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  final StreamController<Duration> _duration =
      StreamController<Duration>.broadcast();
  final StreamController<VideoEnginePhase> _phase =
      StreamController<VideoEnginePhase>.broadcast();

  @override
  Duration duration;
  bool autoplayEnded = false;

  void emitCompleted() => _completed.add(true);
  void resetEnded() => _completed.add(false);
  void emitPosition(Duration at) => _position.add(at);

  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration> get durationStream => _duration.stream;
  @override
  Stream<bool> get completedStream => _completed.stream;
  @override
  Stream<VideoEnginePhase> get phaseStream => _phase.stream;

  /// 逐帧回填要按 1/fps 算，所以 metadata 里得能给出帧率。
  double? fpsForStep;
  @override
  VideoMetadata get metadata => VideoMetadata(
    duration: duration,
    chapters: chapters,
    frameRate: fpsForStep,
  );
  @override
  Duration get position => _pos;
  @override
  bool get isSeeking => false;
  @override
  String? get failureReason => null;
  /// 可写：动作派发那条测试要有「容器里已经有两条字幕」的可观察条件。
  List<VideoMediaTrack> subs = const <VideoMediaTrack>[];
  @override
  List<VideoMediaTrack> get subtitleTracks => subs;
  @override
  List<VideoMediaTrack> get audioTracks => const <VideoMediaTrack>[];

  @override
  Future<void> open(String uri, {VideoOpenOptions options = const VideoOpenOptions()}) async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> play() async => commands.add('play');
  @override
  Future<void> pause() async => commands.add('pause');
  @override
  Future<void> playOrPause() async => commands.add('toggle');
  @override
  Future<void> setPlaying(bool playing) async => commands.add('playing=$playing');
  /// 真位置：会跟着 seek 走，且按端点夹住 —— 「越界返回哪种 outcome」
  /// 是 mimage 边界规则的要点，只会返回 applied 的假实现验不出这些分支。
  Duration _pos = Duration.zero;
  @override
  Future<void> seek(Duration to) async {
    _pos = to;
    commands.add('seek=${to.inSeconds}s');
  }

  @override
  Future<void> seekPaused(Duration to) async => seek(to);
  @override
  Future<RelativeSeekOutcome> seekRelative(Duration delta) async {
    commands.add('rel=${delta.inSeconds}s');
    final next = _pos + delta;
    if (next < Duration.zero) {
      _pos = Duration.zero;
      return RelativeSeekOutcome.clampedToStart;
    }
    if (next > duration) {
      _pos = duration;
      return RelativeSeekOutcome.clampedToEnd;
    }
    _pos = next;
    return RelativeSeekOutcome.applied;
  }

  @override
  Future<void> stepFrame(int direction) async => commands.add('frame=$direction');
  @override
  Future<void> jumpChapter(int direction) async =>
      commands.add('chapter=$direction');
  @override
  Future<void> setRate(double rate) async => commands.add('rate=$rate');
  @override
  Future<void> setVolume(int percent) async => commands.add('vol=$percent');
  @override
  Future<void> setMuted(bool muted) async => commands.add('mute=$muted');
  @override
  Future<void> setLoopFile(bool enabled) async =>
      commands.add('loopFile=$enabled');
  @override
  Future<void> setAbLoop(VideoAbLoop? range) async => commands.add(
    range == null
        ? 'ab=off'
        : 'ab=${range.a.inSeconds}s..${range.b.inSeconds}s',
  );

  @override
  Future<void> setFilter(VideoFilterState filter) async {}
  @override
  Future<void> setSubtitleStyle(VideoSubtitleStyle style) async {}
  @override
  Future<void> setSubtitleDelay(Duration delay) async =>
      commands.add('subDelay=${delay.inMilliseconds}ms');
  @override
  Future<void> selectSubtitleTrack(String? id) async =>
      commands.add('subTrack=$id');
  @override
  Future<void> selectAudioTrack(String? id) async {}
  @override
  Future<void> addSubtitleFile(String path) async {}
  @override
  Future<void> setVideoEnabled(bool enabled) async =>
      commands.add('video=$enabled');
  /// 可写：预览提供器要在「播放中」时故意不去抢位置，测试要能切换它。
  @override
  bool isPlaying = false;
  @override
  Future<String?> screenshot(String path) async {
    commands.add('shot');
    return path;
  }
  @override
  Future<double> avDriftMs() async => 0;
}
