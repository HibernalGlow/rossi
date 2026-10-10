import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/service/operation_binding/action_labels.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';
import 'package:zephyr/icons/icons.dart';

/// 仅用于浏览的分组，不改变核心动作目录或持久化的 category。
enum BindingActionGroup {
  navigation,
  view,
  video,
  interface,
  radial;

  String get label => switch (this) {
    navigation => t.bindingEditor.groupNavigation,
    view => t.bindingEditor.groupView,
    video => t.bindingEditor.video,
    interface => t.bindingEditor.groupInterface,
    radial => t.bindingEditor.radial,
  };

  Glyph get icon => switch (this) {
    navigation => AppGlyphs.openBook,
    view => AppGlyphs.cropFree,
    video => AppGlyphs.playCircle,
    interface => AppGlyphs.dashboard,
    radial => AppGlyphs.donut,
  };
}

BindingActionGroup bindingActionGroup(BindingActionInfo action) {
  if (action.id.startsWith('video.')) return BindingActionGroup.video;
  if (action.category == 'radial') return BindingActionGroup.radial;
  if (action.category == 'navigation') return BindingActionGroup.navigation;
  if (action.category == 'session' ||
      const {
        'reader.toggle-library',
        'reader.toggle-controls',
        'reader.fullscreen',
      }.contains(action.id)) {
    return BindingActionGroup.interface;
  }
  return BindingActionGroup.view;
}

enum BindingVideoGroup {
  playback,
  audio,
  display;

  String get label => switch (this) {
    playback => t.bindingEditor.videoPlayback,
    audio => t.bindingEditor.videoAudio,
    display => t.bindingEditor.videoDisplay,
  };

  Glyph get icon => switch (this) {
    playback => AppGlyphs.play,
    audio => AppGlyphs.volume,
    display => AppGlyphs.subtitles,
  };
}

BindingVideoGroup bindingVideoGroup(String id) => switch (id) {
  'video.volume-up' ||
  'video.volume-down' ||
  'video.toggle-mute' ||
  'video.toggle-audio-only' => BindingVideoGroup.audio,
  'video.screenshot' ||
  'video.toggle-controls' ||
  'video.toggle-subtitle' ||
  'video.subtitle-delay-up' ||
  'video.subtitle-delay-down' ||
  'video.toggle-fullscreen' => BindingVideoGroup.display,
  _ => BindingVideoGroup.playback,
};

String bindingActionTitle(BindingActionInfo action) => actionLabel(
  action,
).replaceFirst(RegExp(r'^(视频：\s*|Video:\s*)', caseSensitive: false), '');

Glyph bindingActionIcon(String id) => switch (id) {
  'reader.previous-page' => AppGlyphs.chevronBack,
  'reader.next-page' => AppGlyphs.chevronForward,
  'reader.first-page' => AppGlyphs.chevronBack,
  'reader.last-page' => AppGlyphs.chevronForward,
  'reader.page-left' => AppGlyphs.arrowBack,
  'reader.page-right' => AppGlyphs.arrowForward,
  'reader.previous-book' ||
  'video.previous-chapter' => AppGlyphs.skipPrevious,
  'reader.next-book' || 'video.next-chapter' => AppGlyphs.skipNext,
  'reader.zoom-in' => AppGlyphs.zoomIn,
  'reader.zoom-out' => AppGlyphs.zoomIn,
  'reader.fit-window' => AppGlyphs.fitScreen,
  'reader.actual-size' => AppGlyphs.aspectRatio,
  'reader.reset-view' => AppGlyphs.reset,
  'reader.rotate-clockwise' => AppGlyphs.rotateRight,
  'reader.rotate-180' => AppGlyphs.flip,
  'reader.toggle-reading-direction' => AppGlyphs.flip,
  'reader.toggle-book-mode' => AppGlyphs.book,
  'reader.fullscreen' || 'video.toggle-fullscreen' => AppGlyphs.fullscreen,
  'reader.toggle-controls' || 'video.toggle-controls' => AppGlyphs.sliders,
  'reader.open-settings' => AppGlyphs.settings,
  'reader.toggle-library' => AppGlyphs.book,
  'radial.open-default' => AppGlyphs.donut,
  'radial.confirm' => AppGlyphs.checkCircle,
  'video.play-pause' => AppGlyphs.playCircle,
  'video.seek-backward' => AppGlyphs.skipPrevious,
  'video.seek-forward' => AppGlyphs.skipNext,
  'video.seek-mode-toggle' => AppGlyphs.skipNext,
  'video.frame-step' => AppGlyphs.skipNext,
  'video.frame-step-back' => AppGlyphs.skipPrevious,
  'video.speed-up' => AppGlyphs.skipNext,
  'video.speed-down' => AppGlyphs.skipPrevious,
  'video.toggle-speed' => AppGlyphs.speed,
  'video.volume-up' => AppGlyphs.volume,
  'video.volume-down' => AppGlyphs.volume,
  'video.toggle-mute' => AppGlyphs.volumeOff,
  'video.toggle-audio-only' => AppGlyphs.volume,
  'video.cycle-loop' => AppGlyphs.loop,
  'video.ab-loop-tap' => AppGlyphs.loop,
  'video.ab-loop-clear' => AppGlyphs.clearAll,
  'video.screenshot' => AppGlyphs.camera,
  'video.toggle-subtitle' => AppGlyphs.subtitles,
  'video.subtitle-delay-up' => AppGlyphs.hourglass,
  'video.subtitle-delay-down' => AppGlyphs.hourglass,
  _ => AppGlyphs.touch,
};
