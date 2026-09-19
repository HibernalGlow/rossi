/// 「当前被聚焦的那个视频页」—— 绑定体系与页面之间的桥。
///
/// 为什么要有这么一层：Rossi 的动作派发（ADR-0015）是**全局的**，
/// 而播放动作必须有作用对象（哪一页的播放器）。`InputContext::Video`
/// 已经存在于 `vocabulary.rs`，但动作要落到哪个控制器上，需要一个显式的
/// 「当前活动视频」引用 —— 否则键盘派发的动作会打到已经 dispose 的页面上。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zephyr/video/controller/reader_video_controller.dart';
import 'package:zephyr/video/controller/video_transport.dart';
import 'package:zephyr/video/model/video_media_kind.dart';
import 'package:zephyr/video/view/video_control_overlay.dart';

class ActiveVideoScope {
  ActiveVideoScope._();

  static final ActiveVideoScope instance = ActiveVideoScope._();

  final ValueNotifier<ReaderVideoController?> _controller =
      ValueNotifier<ReaderVideoController?>(null);

  ValueListenable<ReaderVideoController?> get listenable => _controller;

  ReaderVideoController? get controller => _controller.value;

  /// 是否有**当前页**的可控视频。只有它成立时，adapter 才把 `video` 记进活跃 context。
  bool get hasTarget => _controller.value != null;

  /// 是否处于 seek-mode：开着时「翻页」输入被重映射成跳转（neo 的快进档）。
  bool get seekModeActive => _controller.value?.snapshot.seekMode ?? false;

  final StreamController<String> _uiActions = StreamController<String>.broadcast();

  /// 「这条动作的界面效果长在页面上」的那一类：控制条显隐、全屏。
  ///
  /// 为什么要有这条桥：动作派发是全局的（注册表在 Rust），而这两条的作用对象是
  /// 某个具体页面的 State（控制条归它所有、全屏归泳道）。没有这条桥，注册表里
  /// 那两条就只能写成「返回 true 但什么都不做」—— 那是摆设，不是实现。
  Stream<String> get uiActions => _uiActions.stream;

  void publishUiAction(String actionId) {
    if (!_uiActions.isClosed) _uiActions.add(actionId);
  }

  /// [claim] 只在**这一页是当前页**时调用：PageView 会同时挂着邻居页，
  /// 谁后建谁抢走引用的话，用户看着静图、按键却打到邻居那段视频上。
  void claim(ReaderVideoController controller) {
    _controller.value = controller;
  }

  void release(ReaderVideoController controller) {
    // 只释放自己的那一页：相邻页同时挂载时，后 dispose 的那个不能把前一个的引用抢走。
    if (identical(_controller.value, controller)) _controller.value = null;
  }
}

/// 视频播放设置 —— 与 `ReadSettingState` 分开存。
///
/// 理由是**变更频率与影响面**都不同：阅读排版设置改一项要重建整个页列表，
/// 而视频这几项（钉住控制条、倍速区间、硬解、自动播放）只影响播放本身。
/// 分开存也让它们能像 neoview 那样跨书、跨重启保持，而不牵动排版设置的 schema。
class VideoSettingsStore {
  const VideoSettingsStore({this.key = 'rossi.video.settings'});

  final String key;
  static const VideoSettingsStore instance = VideoSettingsStore();

  Future<VideoSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    final settings =
        raw == null ? const VideoSettings() : VideoSettings.parse(raw);
    // 读设置顺带刷新别名登记表：判定「这一页是不是视频」有 5 个使用点，
    // 逐个传参会漏，漏掉的那处的症状是把视频字节当图片写进封面缓存。
    VideoAliasRegistry.instance.update(settings.extraVideoExtensions);
    return settings;
  }

  Future<void> save(VideoSettings settings) async {
    VideoAliasRegistry.instance.update(settings.extraVideoExtensions);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, settings.encode());
  }
}

class VideoSettings {
  const VideoSettings({
    this.controlsPinned = false,
    this.hardwareDecode = true,
    this.autoPlay = true,
    this.minRate = 0.25,
    this.maxRate = 16,
    this.rateStep = 0.25,
    this.autoHideMilliseconds = 3000,
    this.volumePercent = 100,
    this.animatedVideoEnabled = false,
    this.animatedVideoKeywords = const <String>['[#dyna]'],
    this.extraVideoExtensions = const <String>[],
    this.deinterlace = false,
    this.subtitleStyle = const VideoSubtitleStyle(),
  });

  /// 控制条图钉。上游同样持久化它（`videoControlsPinned`），
  /// 因为「每次重开都要重新钉一次」会让桌面端用户直接把这条功能当摆设。
  final bool controlsPinned;
  final bool hardwareDecode;
  final bool autoPlay;
  final double minRate;
  final double maxRate;
  final double rateStep;
  final int autoHideMilliseconds;
  final int volumePercent;

  /// 「动图当视频播」（neoview `animatedVideoEnabled`，上游默认关闭）。
  final bool animatedVideoEnabled;
  final List<String> animatedVideoKeywords;

  /// 用户自定义视频后缀别名（neoview `MediaSettingsCard` 的 format alias）。
  final List<String> extraVideoExtensions;

  /// 去隔行（mImageViewer `VideoPlayer::open` 的 `deinterlace`）。
  final bool deinterlace;

  /// 字幕样式（neoview 的 `sub*` 配置项：字号 / 颜色 / 底色 / 底部位置）。
  final VideoSubtitleStyle subtitleStyle;

  /// 打包成一个字段存：拆成四条键值会让 encode/parse 各多四段样板。
  static String encodeSubtitleStyle(VideoSubtitleStyle s) =>
      '${s.sizeEm.toStringAsFixed(2)},${s.colorHex},'
      '${s.backgroundOpacityPercent},${s.bottomPercent}';

  static VideoSubtitleStyle parseSubtitleStyle(String? raw) {
    if (raw == null || raw.isEmpty) return const VideoSubtitleStyle();
    final parts = raw.split(',');
    if (parts.length < 4) return const VideoSubtitleStyle();
    return VideoSubtitleStyle(
      sizeEm: double.tryParse(parts[0]) ?? 1.0,
      colorHex: parts[1],
      backgroundOpacityPercent: int.tryParse(parts[2]) ?? 70,
      bottomPercent: int.tryParse(parts[3]) ?? 5,
    );
  }

  /// `copyWith` 存在的意义是让「改一条」不写成「重建所有条」：
  /// 手写字段列表时漏一条的症状是「调音量把硬解开关悄悄关掉」，很难查。
  VideoSettings copyWith({
    bool? controlsPinned,
    bool? hardwareDecode,
    bool? autoPlay,
    double? minRate,
    double? maxRate,
    double? rateStep,
    int? autoHideMilliseconds,
    int? volumePercent,
    bool? animatedVideoEnabled,
    List<String>? animatedVideoKeywords,
    List<String>? extraVideoExtensions,
    bool? deinterlace,
    VideoSubtitleStyle? subtitleStyle,
  }) => VideoSettings(
    controlsPinned: controlsPinned ?? this.controlsPinned,
    hardwareDecode: hardwareDecode ?? this.hardwareDecode,
    autoPlay: autoPlay ?? this.autoPlay,
    minRate: minRate ?? this.minRate,
    maxRate: maxRate ?? this.maxRate,
    rateStep: rateStep ?? this.rateStep,
    autoHideMilliseconds: autoHideMilliseconds ?? this.autoHideMilliseconds,
    volumePercent: volumePercent ?? this.volumePercent,
    animatedVideoEnabled: animatedVideoEnabled ?? this.animatedVideoEnabled,
    animatedVideoKeywords: animatedVideoKeywords ?? this.animatedVideoKeywords,
    extraVideoExtensions: extraVideoExtensions ?? this.extraVideoExtensions,
    deinterlace: deinterlace ?? this.deinterlace,
    subtitleStyle: subtitleStyle ?? this.subtitleStyle,
  );

  String encode() => <String, String>{
    'pinned': '$controlsPinned',
    'hw': '$hardwareDecode',
    'autoPlay': '$autoPlay',
    'minRate': '$minRate',
    'maxRate': '$maxRate',
    'rateStep': '$rateStep',
    'autoHide': '$autoHideMilliseconds',
    'volume': '$volumePercent',
    'animatedVideo': '$animatedVideoEnabled',
    'animatedKeywords': animatedVideoKeywords.join('\u001f'),
    'videoAliases': extraVideoExtensions.join('\u001f'),
    'deinterlace': '$deinterlace',
    'subStyle': encodeSubtitleStyle(subtitleStyle),
  }.entries.map((e) => '${e.key}=${e.value}').join('\n');

  static VideoSettings parse(String text) {
    const base = VideoSettings();
    final map = <String, String>{};
    for (final line in text.split('\n')) {
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      map[line.substring(0, separator)] = line.substring(separator + 1);
    }
    double? d(String k) => double.tryParse(map[k] ?? '');
    int? i(String k) => int.tryParse(map[k] ?? '');
    // 布尔必须**先判缺失**再比对：`map[k] == 'true'` 在键不存在时得到的是
    // `false` 而不是 `null`，于是 `?? base` 那层兜底永远不生效 ——
    // 后果是「设置文件里没有这一项」会被读成「用户把它关了」，
    // 硬件解码 / 自动播放 / 去隔行全部静默失效（升级新增字段时必踩）。
    bool? b(String k) {
      final raw = map[k];
      return raw == null ? null : raw == 'true';
    }
    return VideoSettings(
      controlsPinned: b('pinned') ?? base.controlsPinned,
      hardwareDecode: b('hw') ?? base.hardwareDecode,
      autoPlay: b('autoPlay') ?? base.autoPlay,
      minRate: d('minRate') ?? base.minRate,
      maxRate: d('maxRate') ?? base.maxRate,
      rateStep: d('rateStep') ?? base.rateStep,
      autoHideMilliseconds: i('autoHide') ?? base.autoHideMilliseconds,
      volumePercent: i('volume') ?? base.volumePercent,
      animatedVideoEnabled: b('animatedVideo') ?? base.animatedVideoEnabled,
      animatedVideoKeywords: (map['animatedKeywords']?.split('\u001f')) ??
          base.animatedVideoKeywords,
      extraVideoExtensions: (map['videoAliases']?.split('\u001f')) ??
          base.extraVideoExtensions,
      deinterlace: b('deinterlace') ?? base.deinterlace,
      subtitleStyle: parseSubtitleStyle(map['subStyle']),
    );
  }
}

/// 控制条文案。
///
/// 先落成一份 Dart 常量表而不是 slang 键：视频 UI 有约二十条 tooltip，
/// 逐条进 `reader.*` 命名空间会与阅读设置页的键混在一起，且要求先跑代码生成。
/// 需要接进 i18n 时，把这张表换成 `context.t.readerVideo.*` 即可 ——
/// 换的是**构造 `VideoLabels` 的地方**，控件本身不感知。
const VideoLabels defaultVideoLabels = VideoLabels(
  play: '播放',
  pause: '暂停',
  backward: '后退 10 秒',
  forward: '前进 10 秒',
  loop: '循环：接下一页',
  loopSingle: '循环：本页重复',
  loopOff: '循环：关闭',
  speed: '倍速',
  volume: '音量',
  subtitles: '字幕',
  subtitleOff: '关闭字幕',
  filters: '滤镜',
  resetFilters: '重置滤镜',
  abLoop: 'A–B 循环',
  abClear: '清除 A–B',
  screenshot: '截图',
  audioOnly: '只听声音',
  seekMode: '快进档（翻页改成跳转）',
  fullscreen: '全屏',
  pin: '钉住控制条',
  info: '信息',
  frameStepForward: '下一帧',
  frameStepBackward: '上一帧',
  pip: '画中画',
);
