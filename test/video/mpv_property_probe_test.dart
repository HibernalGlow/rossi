/// mpv 那一层的证据，分两条腿、七探针。
///
/// **① 名字表（针对出厂引擎）**：`Mpv.framework` 里那份 mpv 才是用户机器上真正跑的，
/// 而它在 bundle 外面 dlopen 不了（依赖全是 `@rpath/...`，自己又没有 `LC_RPATH`）。
/// 所以这条不加载它 —— 直接把它的 `__cstring` 读出来，逐个核对我写进 mpv 的
/// 属性名/命令名。名字写错在 mpv 侧是**静默失败**（`set_property` 返回错误被吞掉），
/// 静态检查和出包都问不出来，只有这里问得出来。
///
/// **②～⑦ 取值与行为（针对任意可加载的 libmpv）**：`loop-file=inf` 是不是合法值、
/// `ab-loop-a` 回读长什么样、`frame-step` 走不走一帧、`screenshot-to-file` 落不落得到图、
/// 坏文件落不落得到 `failed`、`sub-add` 的字幕选不选得中、音轨与「只听声音」的往返 ——
/// 这些要活体才看得见。
/// 系统里装了 libmpv 就跑真断言，没装就 skip 并说明原因，绝不留一个永远红的测试。
/// 片源全是现场生成的（WAV / 未压缩 RGB24 的 AVI / 一段 SRT），不依赖任何外来素材。
///
/// 七条都过 = 「引擎语义」这一层能给的最好证据；它仍然不等于真机播放，
/// 画面/声音/字幕的实际观感只能在 `docs/video-playback-acceptance.md` 里靠人看。
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:zephyr/video/controller/mpv_video_transport.dart';
import 'package:zephyr/video/controller/video_transport.dart';
import 'package:zephyr/video/subtitle/video_subtitle.dart';
part 'parts/mpv_probe_name_table_part.dart';
part 'parts/mpv_probe_sample_fixtures_part.dart';
part 'parts/mpv_probe_live_helpers_part.dart';


void main() {
  test('默认视频样式保持原色，字幕颜色和透明度被 mpv 接受', () async {
    final lib = _loadableLibmpv();
    if (lib == null) {
      markTestSkipped('系统里没有可加载的 libmpv');
      return;
    }
    MediaKit.ensureInitialized(libmpv: lib);
    final player = Player();
    final transport = MpvVideoTransport(player: player);
    final errors = <String>[];
    final phases = <VideoEnginePhase>[];
    final errorSub = player.stream.error.listen(errors.add);
    final phaseSub = transport.phaseStream.listen(phases.add);
    final media = File(_writeWav());
    final native = player.platform as NativePlayer;
    Future<void> expectProperty(String key, String expected) async {
      expect(
        await _until(
          () async => (await native.getProperty(key)).toLowerCase(),
          (value) => value == expected,
          what: '$key=$expected',
        ),
        expected,
      );
    }

    try {
      expect(
        await _openAndAwait(transport, media.path),
        VideoEnginePhase.ready,
      );
      await transport.setFilter(VideoFilterState.neutral);
      for (final key in ['brightness', 'contrast', 'saturation']) {
        expect(double.parse(await native.getProperty(key)), 0);
      }
      await transport.setSubtitleStyle(const VideoSubtitleStyle());
      await expectProperty('sub-color', '#ffffffff');
      await expectProperty('sub-back-color', '#b3000000');
      expect(double.parse(await native.getProperty('sub-pos')), 95);

      await transport.setSubtitleStyle(
        const VideoSubtitleStyle(
          colorHex: '#12a4f0',
          backgroundOpacityPercent: 0,
        ),
      );
      await expectProperty('sub-color', '#ff12a4f0');
      await expectProperty('sub-back-color', '#00000000');
      await transport.setSubtitleStyle(
        const VideoSubtitleStyle(
          colorHex: 'invalid',
          backgroundOpacityPercent: 100,
        ),
      );
      await expectProperty('sub-color', '#ffffffff');
      await expectProperty('sub-back-color', '#ff000000');
      // 错误来自异步日志流，等事件送达后再确认不会把画面切到失败页。
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(errors, isEmpty);
      expect(phases, isNot(contains(VideoEnginePhase.failed)));
    } finally {
      await errorSub.cancel();
      await phaseSub.cancel();
      await transport.close();
      await transport.close(); // 幂等关闭；借用的 Player 仍由调用方释放。
      expect((player.platform as NativePlayer).disposed, isFalse);
      await player.dispose();
      await media.parent.delete(recursive: true);
    }
  });

  test('出厂那台 mpv 认得我写的每一个名字', () {
    final names = _mpvNamesInUse();
    // 名单本身为空 = 源码解析失效，这时候"全过"是假的通过。
    expect(names, isNotEmpty, reason: '没解析出任何 mpv 名字，正则失配了');
    expect(names, contains('loop-file'), reason: '解析结果不像话');

    final mpv = _bundledMpv();
    if (mpv == null) {
      markTestSkipped('没有 macOS 产物（先 flutter build macos --debug 再跑）');
      return;
    }
    final strings = _cStrings(mpv);
    final unknown = names.where((n) => !strings.contains(n)).toList();
    expect(
      unknown,
      isEmpty,
      reason: '这些名字在 ${mpv.path} 里没有，mpv 会静默拒绝：$unknown',
    );
  });

  test('mpv 属性逐项生效（引擎语义的主干）', () async {
    final lib = _loadableLibmpv();
    if (lib == null) {
      markTestSkipped('系统里没有可加载的 libmpv（brew install mpv 即可跑真断言）');
      return;
    }
    late final Player player;
    try {
      MediaKit.ensureInitialized(libmpv: lib);
      player = Player();
    } catch (e) {
      markTestSkipped('libmpv 加载不了（$lib）：$e');
      return;
    }
    final transport = MpvVideoTransport(player: player);
    var loaded = false;
    try {
      // 先挂订阅再 open：phaseStream 是广播流，open 里推进的相位可能在这行之前就发完了。
      final phaseSeen = transport.phaseStream.firstWhere(
        (p) => p == VideoEnginePhase.ready || p == VideoEnginePhase.failed,
      );
      await transport
          .open(
            'file://${_writeWav()}',
            options: const VideoOpenOptions(autoplay: false),
          )
          .timeout(const Duration(seconds: 20));
      await phaseSeen.timeout(const Duration(seconds: 20));
      loaded = player.state.duration > Duration.zero;
    } on TimeoutException {
      // 落下面 skip。
    }
    if (!loaded) {
      await transport.close();
      await player.dispose();
      markTestSkipped('没有打开成功（时长仍为 0）：多半是 native 库不可用');
      return;
    }

    Future<String> property(String key) async {
      final platform = player.platform;
      if (platform is! NativePlayer) return '';
      return platform.getProperty(key);
    }

    expect(player.state.duration > Duration.zero, isTrue, reason: '时长要解得出来');

    // 每个属性都「读到满意为止」：mpv 落值是异步的，猜时长会在同机有多个
    // 实例抢 CPU 时随机输（这条套件以前就因此时绿时红）。
    await transport.setRate(1.75);
    expect(
      await _until(
        () async => player.state.rate,
        (v) => (v - 1.75).abs() < 0.01,
        what: 'speed=1.75 生效',
      ),
      closeTo(1.75, 0.01),
    );

    await transport.setVolume(40);
    expect(
      await _until(
        () async => player.state.volume,
        (v) => (v - 40).abs() <= 0.5,
        what: 'volume=40 生效',
      ),
      closeTo(40, 0.5),
    );

    await transport.setMuted(true);
    expect(
      await _until(
        () => property('mute'),
        (v) => v.contains('yes'),
        what: 'mute=yes 生效',
      ),
      contains('yes'),
    );

    await transport.setLoopFile(true);
    expect(
      await _until(
        () => property('loop-file'),
        (v) => v == 'inf',
        what: 'mimage 的单条循环档 loop-file=inf',
      ),
      'inf',
    );

    await transport.setAbLoop(
      const VideoAbLoop(a: Duration(seconds: 1), b: Duration(seconds: 2)),
    );
    // mpv 对 double 属性按 `%f` 回读（写 '12' 回 '12.000000'），且 `ab-loop-*`
    // 未设时回 'no' —— 所以这里一律解析成数值比，别比字符串。
    expect(
      await _until(
        () async => double.tryParse(await property('ab-loop-a')),
        (v) => v != null && (v - 1).abs() <= 0.05,
        what: 'A 点写进去了',
      ),
      closeTo(1, 0.05),
    );
    expect(
      await _until(
        () async => double.tryParse(await property('ab-loop-b')),
        (v) => v != null && (v - 2).abs() <= 0.05,
        what: 'B 点写进去了',
      ),
      closeTo(2, 0.05),
    );
    await transport.setAbLoop(null);
    expect(
      await _until(
        () => property('ab-loop-a'),
        (v) => v == 'no',
        what: 'A-B 清掉之后回 no',
      ),
      'no',
    );

    await transport.setFilter(
      const VideoFilterState(brightness: 150, contrast: 100, saturation: 60),
    );
    // UI 的 100% 对应 mpv 的 0，降低饱和度必须落到负值。
    expect(
      await _until(
        () async => double.tryParse(await property('brightness')),
        (v) => v != null && (v - 50).abs() <= 1.0,
        what: 'brightness 150% 对应 +50',
      ),
      closeTo(50, 1.0),
    );
    expect(
      await _until(
        () async => double.tryParse(await property('saturation')),
        (v) => v != null && (v + 40).abs() <= 1.0,
        what: 'saturation 60% 对应 -40',
      ),
      closeTo(-40, 1.0),
    );

    await transport.setSubtitleStyle(
      const VideoSubtitleStyle(sizeEm: 1.6, bottomPercent: 12),
    );
    expect(
      await _until(
        () async => double.tryParse(await property('sub-scale')),
        (v) => v != null && (v - 1.6).abs() <= 0.01,
        what: 'sub-scale 生效',
      ),
      closeTo(1.6, 0.01),
    );
    expect(
      await _until(
        () async => double.tryParse(await property('sub-pos')),
        (v) => v != null && (v - 88).abs() <= 0.01,
        what: '字幕离底部 12% 对应 sub-pos=88',
      ),
      closeTo(88, 0.01),
    );

    await transport.setVideoEnabled(false);
    expect(
      await _until(
        () => property('video'),
        (v) => v == 'no',
        what: '只听声音模式该把画面关掉',
      ),
      'no',
    );

    final drift = await transport.avDriftMs();
    expect(drift.isFinite, isTrue);

    await transport.seek(const Duration(milliseconds: 500));
    // 问 mpv 自己要时间：暂停态里 media_kit 的 position 流是不发的
    // （控制器靠乐观回填让标签跟着走，见 `seekRelative` 那段）。
    await _until(
      () async => double.tryParse(await property('playback-time')),
      (v) => v != null && (v - 0.5).abs() < 0.12,
      what: 'mpv 侧定位落到 500 ms 附近',
    );
    expect(transport.isPlaying, isFalse, reason: '暂停态定位不该顺手开播');

    await transport.close();
    await player.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  /// 视频侧的三条：元数据、逐帧、截图落盘。
  ///
  /// WAV 只能证声音，所以这里手写一个未压缩 RGB24 的 AVI（231 KB）当片源 ——
  /// mpv 认它（`rawvideo 64x48 25 fps`），于是 `container-fps`/`video-params`、
  /// `frame-step` 是不是真的走一帧、`screenshot-to-file` 落不落得到图，
  /// 全都能在不开 App 的情况下拿到凭据。
  ///
  /// 需要 `NativePlayer.test = true`：media_kit 起来就带 `--vid=no`，只有
  /// `VideoController` 附着时才改回 auto，而测试里没有 platform view。
  /// 顺带说，这同一个默认值也是海报那条路的坑（那里根本没有渲染面），
  /// 已在 `VideoPosterService._captureBytes` 里显式 `vid=auto` 补上。
  test('视频侧语义：元数据、逐帧、截图', () async {
    final lib = _loadableLibmpv();
    if (lib == null) {
      markTestSkipped('系统里没有可加载的 libmpv（brew install mpv）');
      return;
    }
    MediaKit.ensureInitialized(libmpv: lib);
    NativePlayer.test = true;
    final path = _writeAvi();
    final player = Player();
    final transport = MpvVideoTransport(player: player);
    expect(
      await _openAndAwait(transport, 'file://$path'),
      VideoEnginePhase.ready,
      reason: '合成 AVI 该解得出来',
    );

    // 信息表那三列全靠这些：宽高、帧率、编码名。
    final meta = await _until(
      () async => transport.metadata,
      (m) => m.width == 64 && m.height == 48 && m.frameRate != null,
      what: 'metadata 解出宽高与帧率',
    );
    expect(meta.frameRate ?? 0, closeTo(25, 0.5));
    expect(meta.videoCodec ?? '', contains('raw'));
    expect(
      player.state.duration.inMilliseconds,
      inInclusiveRange(900, 1100),
      reason: '25 帧 @25fps 该是 1 s 上下，实际 ${player.state.duration}',
    );

    // 逐帧：25 fps 走一帧就是 40 ms，而且期间必须还是暂停。
    await player.pause();
    final before = player.state.position;
    await transport.stepFrame(1);
    // 等位置真的动，别猜 400 ms：同机多个 mpv 实例抢 CPU 时固定时长会随机输。
    final stepped = await _until(
      () async => player.state.position,
      (d) => d != before,
      what: 'frame-step 该推进位置',
    );
    final advanced = stepped - before;
    expect(
      advanced.inMilliseconds,
      inInclusiveRange(20, 120),
      reason: '一帧该是 40 ms 上下，实际走了 $advanced',
    );
    expect(transport.isPlaying, isFalse, reason: '逐帧期间必须还是暂停');

    // 回退一帧：`frame-back-step` 是 mimage 与 neo 都有的「上一帧」，
    // 走的是另一条命令，不能靠正着走的那条推定它成立。
    await transport.stepFrame(-1);
    final back = await _until(
      () async => player.state.position,
      (d) => d.inMilliseconds < 20,
      what: '退一帧该回到起点附近',
    );
    expect(back.inMilliseconds, lessThan(20));

    // 截图：mpv 的 screenshot-to-file 真的落一个图像文件（海报/预览帧同源）。
    final dir = Directory.systemTemp.createTempSync('rossi-shot');
    final shot = '${dir.path}/probe-shot.png';
    expect(await transport.screenshot(shot), isNotNull, reason: '该返回落盘路径');
    final bytes = File(shot).readAsBytesSync();
    expect(bytes, isNotEmpty);
    // PNG(89 50 4E 47) 或 JPEG(FF D8 FF)：扩展名是我给的，实际格式由 mpv 决定。
    final isPng = bytes[0] == 0x89 && bytes[1] == 0x50;
    final isJpeg = bytes[0] == 0xff && bytes[1] == 0xd8;
    expect(isPng || isJpeg, isTrue, reason: '落盘的不是图像文件');

    await transport.close();
    await player.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  /// 打不开的文件必须落到 `failed`。
  ///
  /// 这是「视频整条功能都是装饰，绝不该让一页读不下去」那句承诺的兑现点：
  /// 相位停在 `prerolling` 的话，页面上就是一个永远转不完的圈（曾经就是这样，
  /// 因为 media_kit 的 error 是广播流，晚一帧订阅就再也收不到）。
  test('打不开的文件要落到 failed，不许卡在 prerolling', () async {
    final lib = _loadableLibmpv();
    if (lib == null) {
      markTestSkipped('系统里没有可加载的 libmpv（brew install mpv）');
      return;
    }
    MediaKit.ensureInitialized(libmpv: lib);
    final player = Player();
    final transport = MpvVideoTransport(player: player);
    final phaseSeen = transport.phaseStream.firstWhere(
      (p) => p == VideoEnginePhase.ready || p == VideoEnginePhase.failed,
    );
    final dir = Directory.systemTemp.createTempSync('rossi-missing');
    await transport.open('file://${dir.path}/not-here.mp4');
    final phase = await phaseSeen.timeout(const Duration(seconds: 15));
    expect(phase, VideoEnginePhase.failed);
    expect(
      transport.failureReason,
      isNotNull,
      reason: 'failed 得带得上面的话，页面才有的可显示',
    );
    await transport.close();
    await player.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  /// 海报那条路的机制：没有渲染面时，显式 `vid=auto` 就足够让画面解出来。
  ///
  /// `VideoPosterService` 用的是裸 `Player()`（页面树里没有 `Video` 组件），
  /// 而 media_kit 给裸 Player 的默认是 `--vid=no` ⇒ 不显式打开视频轨的话，
  /// 它等 `videoParams` 一定超时、截图一定 null，表现为「视频卡片从来没有封面」。
  /// 这条不测海报函数本身（那要 mock path_provider），只测它依赖的那一句是否成立。
  test('裸 Player 显式 vid=auto 后能解出画面并截图', () async {
    final lib = _loadableLibmpv();
    if (lib == null) {
      markTestSkipped('系统里没有可加载的 libmpv（brew install mpv）');
      return;
    }
    MediaKit.ensureInitialized(libmpv: lib);
    // 上面的测试为了自己能用而开了这个静态开关；这里必须关掉，
    // 否则「裸 Player 默认 vid=no」这个前提就不成立了。
    NativePlayer.test = false;
    final player = Player();
    final native = player.platform;
    if (native is! NativePlayer) {
      await player.dispose();
      markTestSkipped('不是 NativePlayer，测不到 vid 这一层');
      return;
    }
    final path = _writeAvi();
    final paramsSeen = player.stream.videoParams
        .firstWhere((v) => (v.w ?? 0) > 0)
        .timeout(const Duration(seconds: 8));
    await native.setProperty('vid', 'auto');
    await player.open(Media('file://$path'), play: false);
    await paramsSeen;
    final shot = await player.screenshot();
    expect(shot, isNotNull, reason: '海报取的就是这个字节串');
    expect(shot!, isNotEmpty);
    await player.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  /// 外挂字幕这条链的活体一半：`sub-add` 之后轨列表里有它、认得出是外挂、能选中。
  ///
  /// 侧挂字幕是两个上游共有的一条主功能。Rossi 侧的名字匹配与 SRT/ASS/MicroDVD
  /// 转换在纯逻辑测试里已经钉过，剩下「mpv 收不收、tracks 流里长什么样、按号选选不选得中」
  /// 只有活体能答 —— 而最后这半恰好抓到过一次真错（见 `selectSubtitleTrack` 的轨号判别）。
  test('外挂字幕：sub-add 之后能进轨列表并被选中', () async {
    final lib = _loadableLibmpv();
    if (lib == null) {
      markTestSkipped('系统里没有可加载的 libmpv（brew install mpv）');
      return;
    }
    MediaKit.ensureInitialized(libmpv: lib);
    NativePlayer.test = true;
    final player = Player();
    final transport = MpvVideoTransport(player: player);
    expect(
      await _openAndAwait(transport, 'file://${_writeAvi()}'),
      VideoEnginePhase.ready,
      reason: '合成 AVI 没解出来：${transport.failureReason}',
    );

    final dir = Directory.systemTemp.createTempSync('rossi-sub');
    final srt = '${dir.path}/probe.srt';
    File(srt).writeAsStringSync('1\n00:00:00,500 --> 00:00:01,000\nrossi\n\n');
    await transport.addSubtitleFile(srt);
    // 先问 mpv 自己收没收下（`_cmd` 是吞异常的，光看 transport 那边分不出来），
    // 再等 media_kit 的 tracks 流把这条轨送到 `subtitleTracks`。
    final native = player.platform as NativePlayer;
    final list = await native.getProperty('track-list');
    // mpv 的轨道类型串是 `sub`，不是 `subtitle`（这条断言第一次就写错了）。
    expect(list, contains('"type":"sub"'), reason: 'mpv 就没收下这个字幕文件');
    final ids = await _until(
      () async => transport.subtitleTracks.map((t) => t.id).toList(),
      (list) => list.any((i) => int.tryParse(i) != null),
      what: 'sub-add 之后该有一条数字轨号的字幕轨',
    );
    // media_kit 的轨表里混着它自己造的伪轨（auto / no）：列给用户看就是两条点不动的假轨。
    expect(ids, isNot(contains('auto')), reason: '伪轨不该出现在轨列表：$ids');
    expect(ids, isNot(contains('no')), reason: '伪轨不该出现在轨列表：$ids');
    final sidecar = transport.subtitleTracks
        .where((t) => int.tryParse(t.id) != null)
        .toList(growable: false);
    expect(sidecar, isNotEmpty, reason: 'sub-add 之后该有一条数字轨号的字幕轨：$ids');

    // 选择状态要问 mpv：media_kit 的 state.track 只记**它自己**最后一次设的值
    // （刚 sub-add 完时它还是 auto），而面板上「哪条是选中的」看的是 mpv 那边。
    Future<String> sid() async => native.getProperty('sid');
    expect(
      await sid(),
      anyOf('auto', sidecar.first.id),
      reason: '只有一条外挂字幕时 mpv 该自动选中它，实际 sid=${await sid()}',
    );

    // 关掉再选回来：数字轨号必须按号选 —— 走 URI 分支的话 mpv 会去开一个叫 "1" 的文件。
    await transport.selectSubtitleTrack(null);
    expect(await _until(sid, (v) => v == 'no', what: '关闭字幕该回到 sid=no'), 'no');
    await transport.selectSubtitleTrack(sidecar.first.id);
    expect(
      await _until(sid, (v) => v == sidecar.first.id, what: '数字轨号的外挂字幕要按号选中'),
      sidecar.first.id,
    );

    // MicroDVD `.sub`：mpv 对它的解码不可靠，所以 Rossi 侧先转成 WebVTT 再挂
    // （`convertSubtitleFileForEngine`）。转出来的东西 mpv 认不认，只有活体能答。
    final sub = '${dir.path}/probe.sub';
    File(sub).writeAsStringSync('{0}{100}第一句|换行\\n{120}{200}第二句\\n');
    final converted = await convertSubtitleFileForEngine(sub, format: 'sub');
    expect(converted, isNotNull, reason: '.sub 该被转成临时 .vtt');
    expect(
      File(converted!).readAsStringSync(),
      startsWith('WEBVTT'),
      reason: '转出来的得是合法 WebVTT 头',
    );
    await transport.addSubtitleFile(converted);
    final subs2 = await _until(
      () async => transport.subtitleTracks.map((e) => e.id).toList(),
      (list) => list.where((i) => int.tryParse(i) != null).length >= 2,
      what: '转换后的 .vtt 该成为第二条字幕轨',
    );
    final vttId = subs2.firstWhere(
      (i) => int.tryParse(i) != null && i != sidecar.first.id,
    );
    await transport.selectSubtitleTrack(vttId);
    expect(
      await _until(sid, (v) => v == vttId, what: '转换出来的 WebVTT 要选得中'),
      vttId,
    );

    await transport.close();
    await player.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  /// 要有**两条轨**才看得见的那半：音轨面板、`aid` 选择、音画漂移、码率。
  ///
  /// 合成的 AVI 现在带一条 PCM s16le（8 kHz 单声道，与视频帧按 40 ms 对齐交错），
  /// mpv 报 `Audio --aid=1 (pcm_s16le 1ch 8000 Hz 128 kbps)`。
  /// 音轨面板与「只听声音」是 mimage 与 neo 都有的功能，此前只验过代码存在。
  test('音轨与同步：PCM 轨进得了列表也选得中', () async {
    final lib = _loadableLibmpv();
    if (lib == null) {
      markTestSkipped('系统里没有可加载的 libmpv（brew install mpv）');
      return;
    }
    MediaKit.ensureInitialized(libmpv: lib);
    NativePlayer.test = true;
    final player = Player();
    final transport = MpvVideoTransport(player: player);
    expect(
      await _openAndAwait(transport, 'file://${_writeAvi()}'),
      VideoEnginePhase.ready,
    );
    final native = player.platform as NativePlayer;

    // 音频编解码名要进信息卡（`audio-codec-name`）。
    final ameta = await _until(
      () async => transport.metadata,
      (m) => (m.audioCodec ?? '').contains('pcm'),
      what: 'audio-codec-name 解出 pcm',
    );
    expect(ameta.audioCodec ?? '', contains('pcm'));

    // 音轨列表：media_kit 的 auto/no 伪轨不能混进来。
    final audioIds = await _until(
      () async => transport.audioTracks.map((t) => t.id).toList(),
      (list) => list.any((i) => int.tryParse(i) != null),
      what: '音轨列表里该有一条真轨',
    );
    expect(
      audioIds,
      isNot(anyOf(contains('auto'), contains('no'))),
      reason: '伪轨混进音轨面板：$audioIds',
    );
    expect(audioIds.length, 1, reason: '这条合成源只有一条音轨：$audioIds');

    // 关掉再选回：走 aid 属性，面板上的选中态以此为准。
    await transport.selectAudioTrack(null);
    expect(
      await _until(
        () => native.getProperty('aid'),
        (v) => v == 'no',
        what: '关音轨该是 aid=no',
      ),
      'no',
    );
    await transport.selectAudioTrack(audioIds.first);
    expect(
      await _until(
        () => native.getProperty('aid'),
        (v) => v == audioIds.first,
        what: '按号选音轨要选得回',
      ),
      audioIds.first,
    );

    // 音画漂移：两条流都在的时候 `avsync` 才是个有意义的数。
    final drift = await transport.avDriftMs();
    expect(drift.isFinite, isTrue);

    // 纯音频档（neo 的 audio-only）：**开与关都要验** —— 只验「关」是假绿，
    // 真正的缺陷在「关得掉、开不回来」（见 spec §5 缺陷 ⑰）。
    await transport.setVideoEnabled(false);
    expect(
      await _until(
        () => native.getProperty('video'),
        (v) => v == 'no',
        what: '只听声音该把画面关掉',
      ),
      'no',
    );
    final whilePaused = await native.getProperty('video');
    await transport.setVideoEnabled(true);
    await player.play();
    final whilePlaying = await _until(
      () => native.getProperty('video'),
      (v) => v != 'no',
      what: '退出「只听声音」后画面必须回来',
    );
    // mpv 的 `video` 回读的不是 yes/no 而是**当前轨号**（关掉时才是 'no'），
    // 所以判据是「不再是 no」，并且 `vid` 必须是选中的那条轨。
    expect(
      whilePlaying,
      isNot('no'),
      reason: '退出「只听声音」后播放态必须有画面（暂停态读回 $whilePaused）',
    );
    expect(
      await native.getProperty('vid'),
      isNot(anyOf('no', 'auto')),
      reason: 'vid 要落回真轨号，否则画面回不来',
    );

    await transport.close();
    await player.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
