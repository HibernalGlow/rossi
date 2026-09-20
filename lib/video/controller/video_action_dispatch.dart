/// `video.*` 动作的执行体（ADR-0015 §5 的第 ③ 件事在视频侧的落点）。
///
/// 动作 id 的权威清单在 Rust 的 `ACTION_CATALOG`；这里只回答「这条 id 在 Rossi 怎么执行」。
/// 与 neoview 的差别只有一个：上游的动作派发是 `ReaderInputActionExecutor.ts` 直接持有
/// video 元素，Rossi 的元素活在 `ActiveVideoScope` 里（哪一页是当前页由聚焦决定）。
library;

import 'package:zephyr/video/controller/video_transport.dart';
import 'package:zephyr/video/service/video_poster_service.dart';
import 'package:zephyr/video/view/active_video_scope.dart';

/// 视频动作 id —— 与 `vocabulary.rs` 的 `action::VIDEO_*` 逐条同名。
///
/// 命名照 neoview：`video.play-pause` 与 `video.toggle-speed` 是上游的写法。
/// 动作 id 与绑定表是要落进用户配置的东西，名字与上游分叉，将来两边的绑定包对不上。
class BindingVideoAction {
  static const String playPause = 'video.play-pause';
  static const String seekBackward = 'video.seek-backward';
  static const String seekForward = 'video.seek-forward';
  static const String seekModeToggle = 'video.seek-mode-toggle';
  static const String frameStep = 'video.frame-step';
  static const String frameStepBack = 'video.frame-step-back';
  static const String speedUp = 'video.speed-up';
  static const String speedDown = 'video.speed-down';
  static const String toggleSpeed = 'video.toggle-speed';
  static const String volumeUp = 'video.volume-up';
  static const String volumeDown = 'video.volume-down';
  static const String toggleMute = 'video.toggle-mute';
  static const String cycleLoop = 'video.cycle-loop';
  static const String abLoopTap = 'video.ab-loop-tap';
  static const String abLoopClear = 'video.ab-loop-clear';
  static const String screenshot = 'video.screenshot';
  static const String toggleControls = 'video.toggle-controls';
  static const String toggleSubtitle = 'video.toggle-subtitle';
  static const String subtitleDelayUp = 'video.subtitle-delay-up';
  static const String subtitleDelayDown = 'video.subtitle-delay-down';
  static const String toggleAudioOnly = 'video.toggle-audio-only';
  static const String toggleFullscreen = 'video.toggle-fullscreen';
  static const String nextChapter = 'video.next-chapter';
  static const String previousChapter = 'video.previous-chapter';
}

/// 已知的视频动作全集。设置页与校验用（不是第二份注册表 —— 注册表在 Rust）。
const List<String> kVideoActionIds = <String>[
  BindingVideoAction.playPause,
  BindingVideoAction.seekBackward,
  BindingVideoAction.seekForward,
  BindingVideoAction.seekModeToggle,
  BindingVideoAction.frameStep,
  BindingVideoAction.frameStepBack,
  BindingVideoAction.speedUp,
  BindingVideoAction.speedDown,
  BindingVideoAction.toggleSpeed,
  BindingVideoAction.volumeUp,
  BindingVideoAction.volumeDown,
  BindingVideoAction.toggleMute,
  BindingVideoAction.cycleLoop,
  BindingVideoAction.abLoopTap,
  BindingVideoAction.abLoopClear,
  BindingVideoAction.screenshot,
  BindingVideoAction.toggleControls,
  BindingVideoAction.toggleSubtitle,
  BindingVideoAction.subtitleDelayUp,
  BindingVideoAction.subtitleDelayDown,
  BindingVideoAction.toggleAudioOnly,
  BindingVideoAction.toggleFullscreen,
  BindingVideoAction.nextChapter,
  BindingVideoAction.previousChapter,
];

/// 「翻页」在快进档下变成「跳转」—— 这是 neoview
/// `ReaderInputActionExecutor.ts:180-190, 226-229` 的那条重映射。
///
/// 返回 true 表示这条翻页动作已被视频侧吃掉。
bool remapPageTurnToSeekWhenSeekMode(String pageActionId) {
  final scope = ActiveVideoScope.instance;
  if (!scope.seekModeActive) return false;
  final controller = scope.controller;
  if (controller == null) return false;
  switch (pageActionId) {
    case 'reader.next-page':
    case 'reader.page-right':
      unawaitedSeek(controller.seekForward());
      return true;
    case 'reader.previous-page':
    case 'reader.page-left':
      unawaitedSeek(controller.seekBackward());
      return true;
    default:
      return false;
  }
}

void unawaitedSeek(Future<bool> future) {
  // seek 结果只影响「有没有活动播放器」，界面上的位置由流回推，所以不等。
  future.ignore();
}

/// 执行一条视频动作。返回 `false` = 这不是视频动作（交回阅读器的普通分支）。
bool dispatchVideoAction(String actionId) {
  final scope = ActiveVideoScope.instance;
  final controller = scope.controller;
  if (!kVideoActionIds.contains(actionId)) return false;
  // 没有活动视频页时**不吃**这条输入：视频动作的 context 只有在当前页是视频时
  // 才会进活跃集合，但上游把倍速三键挂在 `global` 一档 —— 全局绑定了却没有目标时
  // 返回 true 就等于「按了没反应」，按键被凭空吞掉。
  if (controller == null) return false;
  final transport = controller.transport;

  switch (actionId) {
    case BindingVideoAction.playPause:
      unawaitedSeek(controller.togglePlay());
    case BindingVideoAction.seekBackward:
      unawaitedSeek(controller.seekBackward());
    case BindingVideoAction.seekForward:
      unawaitedSeek(controller.seekForward());
    case BindingVideoAction.seekModeToggle:
      controller.toggleSeekMode();
    case BindingVideoAction.frameStep:
      unawaitedSeek(controller.stepFrame(1));
    case BindingVideoAction.frameStepBack:
      unawaitedSeek(controller.stepFrame(-1));
    case BindingVideoAction.speedUp:
      unawaitedSeek(
        controller.setPlaybackRate(
          controller.snapshot.playbackRate + controller.snapshot.playbackRateStep,
        ),
      );
    case BindingVideoAction.speedDown:
      unawaitedSeek(
        controller.setPlaybackRate(
          controller.snapshot.playbackRate - controller.snapshot.playbackRateStep,
        ),
      );
    case BindingVideoAction.toggleSpeed:
      // 上游的 `video.toggle-speed`：1x ⇄ 上一个用过的倍速，不是「回到 1x」。
      unawaitedSeek(controller.toggleSpeed());
    case BindingVideoAction.volumeUp:
      unawaitedSeek(controller.setVolume(controller.snapshot.volume + 0.05));
    case BindingVideoAction.volumeDown:
      unawaitedSeek(controller.setVolume(controller.snapshot.volume - 0.05));
    case BindingVideoAction.toggleMute:
      unawaitedSeek(controller.toggleMute());
    case BindingVideoAction.cycleLoop:
      controller.cycleLoopMode();
    case BindingVideoAction.abLoopTap:
      controller.tapAbLoop();
    case BindingVideoAction.abLoopClear:
      controller.clearAbLoop();
    case BindingVideoAction.screenshot:
      // 与按钮那条路共用同一个落盘规则：应用自己的目录，不写进用户的漫画库。
      () async {
        final path = await nextVideoScreenshotPath();
        await controller.screenshot(path);
      }();
    case BindingVideoAction.toggleSubtitle:
      _cycleSubtitleTrack(transport);
    case BindingVideoAction.subtitleDelayUp:
      _shiftSubtitleDelay(transport, 0.25);
    case BindingVideoAction.subtitleDelayDown:
      _shiftSubtitleDelay(transport, -0.25);
    case BindingVideoAction.toggleAudioOnly:
      unawaitedSeek(
        controller.setAudioOnly(!controller.snapshot.audioOnly),
      );
    case BindingVideoAction.nextChapter:
      controller.nextChapter();
    case BindingVideoAction.previousChapter:
      controller.previousChapter();
    case BindingVideoAction.toggleControls:
    case BindingVideoAction.toggleFullscreen:
      // 这两条的效果长在页面上（控制条显隐、铺满窗口全屏）：交给页面自己执行。
      scope.publishUiAction(actionId);
      return true;
    default:
      return true;
  }
  return true;
}

Duration _subtitleDelay = Duration.zero;

/// 换一条视频时起播前清零。延迟与轮切下标都是**这一条视频**的状态：
/// 挂在模块上会让「上一本调的 -0.5 s」跟着下一本走，而用户从没为它设过什么。
void resetVideoSubtitleActionState() {
  _subtitleDelay = Duration.zero;
  _subtitleIndex = -1;
}

void _shiftSubtitleDelay(VideoTransport? transport, double seconds) {
  _subtitleDelay += Duration(milliseconds: (seconds * 1000).round());
  transport?.setSubtitleDelay(_subtitleDelay);
}

/// 字幕轨在「关 → 第一条 → 第二条 → … → 关」上循环（mimage 的字幕切换键同一条语义）。
int _subtitleIndex = -1;

void _cycleSubtitleTrack(VideoTransport? transport) {
  if (transport == null) return;
  final tracks = transport.subtitleTracks;
  if (tracks.isEmpty) return;
  _subtitleIndex = (_subtitleIndex + 1) % (tracks.length + 1);
  transport.selectSubtitleTrack(
    _subtitleIndex >= tracks.length ? null : tracks[_subtitleIndex].id,
  );
}
