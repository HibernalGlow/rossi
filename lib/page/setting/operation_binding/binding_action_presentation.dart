import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/service/operation_binding/action_labels.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';

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

  IconData get icon => switch (this) {
    navigation => Icons.auto_stories_outlined,
    view => Icons.crop_free,
    video => Icons.play_circle_outline,
    interface => Icons.dashboard_outlined,
    radial => Icons.donut_large,
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

  IconData get icon => switch (this) {
    playback => Icons.play_arrow_outlined,
    audio => Icons.volume_up_outlined,
    display => Icons.subtitles_outlined,
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

IconData bindingActionIcon(String id) => switch (id) {
  'reader.previous-page' => Icons.navigate_before,
  'reader.next-page' => Icons.navigate_next,
  'reader.first-page' => Icons.first_page,
  'reader.last-page' => Icons.last_page,
  'reader.page-left' => Icons.arrow_back,
  'reader.page-right' => Icons.arrow_forward,
  'reader.previous-book' ||
  'video.previous-chapter' => Icons.skip_previous_outlined,
  'reader.next-book' || 'video.next-chapter' => Icons.skip_next_outlined,
  'reader.zoom-in' => Icons.zoom_in,
  'reader.zoom-out' => Icons.zoom_out,
  'reader.fit-window' => Icons.fit_screen,
  'reader.actual-size' => Icons.aspect_ratio,
  'reader.reset-view' => Icons.restart_alt,
  'reader.rotate-clockwise' => Icons.rotate_right,
  'reader.rotate-180' => Icons.flip_camera_android_outlined,
  'reader.toggle-reading-direction' => Icons.swap_horiz,
  'reader.toggle-book-mode' => Icons.menu_book_outlined,
  'reader.fullscreen' || 'video.toggle-fullscreen' => Icons.fullscreen,
  'reader.toggle-controls' || 'video.toggle-controls' => Icons.tune,
  'reader.open-settings' => Icons.settings_outlined,
  'reader.toggle-library' => Icons.library_books_outlined,
  'radial.open-default' => Icons.donut_large,
  'radial.confirm' => Icons.check_circle_outline,
  'video.play-pause' => Icons.play_circle_outline,
  'video.seek-backward' => Icons.replay_10,
  'video.seek-forward' => Icons.forward_10,
  'video.seek-mode-toggle' => Icons.fast_forward_outlined,
  'video.frame-step' => Icons.keyboard_double_arrow_right,
  'video.frame-step-back' => Icons.keyboard_double_arrow_left,
  'video.speed-up' => Icons.fast_forward,
  'video.speed-down' => Icons.fast_rewind,
  'video.toggle-speed' => Icons.speed,
  'video.volume-up' => Icons.volume_up_outlined,
  'video.volume-down' => Icons.volume_down_outlined,
  'video.toggle-mute' => Icons.volume_off_outlined,
  'video.toggle-audio-only' => Icons.headphones_outlined,
  'video.cycle-loop' => Icons.repeat,
  'video.ab-loop-tap' => Icons.loop,
  'video.ab-loop-clear' => Icons.clear_all,
  'video.screenshot' => Icons.photo_camera_outlined,
  'video.toggle-subtitle' => Icons.subtitles_outlined,
  'video.subtitle-delay-up' => Icons.more_time,
  'video.subtitle-delay-down' => Icons.timer_outlined,
  _ => Icons.touch_app_outlined,
};
