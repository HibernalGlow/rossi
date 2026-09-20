import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';

Map<String, String> get bindingDeviceLabels => {
  'keyboard': t.bindingEditor.keyboard,
  'mouse': t.bindingEditor.mouse,
  'mouse-gesture': t.bindingEditor.mouseGesture,
  'wheel': t.bindingEditor.wheel,
  'touch': t.bindingEditor.touch,
  'gamepad': t.bindingEditor.gamepad,
  'area': t.bindingEditor.area,
};

Map<String, String> get bindingContextLabels => {
  'global': t.bindingEditor.global,
  'reader': t.bindingEditor.reader,
  'video': t.bindingEditor.video,
  'panel': t.bindingEditor.panel,
  'shell': t.bindingEditor.shell,
  'editor': t.bindingEditor.editor,
  'modal': t.bindingEditor.modal,
};

Map<String, String> get bindingAreaLabels => {
  'top-left': t.bindingEditor.topLeft,
  'top-center': t.bindingEditor.topCenter,
  'top-right': t.bindingEditor.topRight,
  'middle-left': t.bindingEditor.middleLeft,
  'middle-center': t.bindingEditor.middleCenter,
  'middle-right': t.bindingEditor.middleRight,
  'bottom-left': t.bindingEditor.bottomLeft,
  'bottom-center': t.bindingEditor.bottomCenter,
  'bottom-right': t.bindingEditor.bottomRight,
};

Map<String, String> get bindingPointerActions => {
  'click': t.bindingEditor.click,
  'double-click': t.bindingEditor.doubleClick,
  'press': t.bindingEditor.press,
  'hold': t.bindingEditor.hold,
};

Map<String, String> get bindingTouchGestures => {
  'swipe-left': t.bindingEditor.swipeLeft,
  'swipe-right': t.bindingEditor.swipeRight,
  'swipe-up': t.bindingEditor.swipeUp,
  'swipe-down': t.bindingEditor.swipeDown,
  'tap': t.bindingEditor.tap,
  'long-press': t.bindingEditor.longPress,
};

const bindingDirectionSymbols = {
  'left': '←',
  'right': '→',
  'up': '↑',
  'down': '↓',
};

IconData bindingDeviceIcon(String device) => switch (device) {
  'mouse' => Icons.mouse_outlined,
  'mouse-gesture' => Icons.gesture,
  'wheel' => Icons.swap_vert,
  'touch' => Icons.touch_app_outlined,
  'gamepad' => Icons.sports_esports_outlined,
  'area' => Icons.grid_on_outlined,
  'radial' => Icons.donut_large,
  'command' => Icons.terminal,
  _ => Icons.keyboard_outlined,
};

String bindingInputSummary(Map<String, dynamic> input) {
  final mods = [
    for (final key in ['ctrl', 'alt', 'shift', 'meta'])
      if (input[key] == true) '${key[0].toUpperCase()}${key.substring(1)}',
  ];
  final summary = switch (input['device']) {
    'keyboard' =>
      describeInput(input) +
          (input['trigger'] == 'hold' ? ' · ${t.bindingEditor.hold}' : ''),
    'mouse' =>
      '${t.bindingEditor.mouse} ${input['button']} · ${bindingPointerActions[input['action']] ?? input['action']}',
    'mouse-gesture' =>
      '${t.bindingEditor.mouseGesture} ${(input['directions'] as List? ?? []).map((d) => bindingDirectionSymbols[d] ?? d).join(' ')}',
    'wheel' => [
      ...mods,
      '${t.bindingEditor.wheel} ${input['direction'] == 'up' ? '↑' : '↓'}',
    ].join('+'),
    'touch' =>
      '${input['fingers']} · ${bindingTouchGestures[input['gesture']] ?? input['gesture']}',
    'gamepad' => '${t.bindingEditor.gamepad} ${input['button']}',
    'area' =>
      '${bindingAreaLabels[input['area']] ?? input['area']} · ${bindingPointerActions[input['action']] ?? input['action']}',
    'radial' =>
      '${t.bindingEditor.radial} ${input['menuId']} / ${input['itemId']}',
    'command' => '${input['command']}',
    _ => describeInput(input),
  };
  return summary;
}

/// 只缩短展示文字；录制、匹配和导出的 code 保持原样。
String bindingInputBadgeLabel(Map<String, dynamic> input) {
  final code = input['code'] as String? ?? '';
  final key = switch (code) {
    'ArrowLeft' => '←',
    'ArrowRight' => '→',
    'ArrowUp' => '↑',
    'ArrowDown' => '↓',
    'Space' => t.bindingEditor.spaceKey,
    'Enter' || 'NumpadEnter' => '↵',
    'Escape' => 'Esc',
    'Backspace' => '⌫',
    'Delete' => 'Del',
    'PageUp' => 'PgUp',
    'PageDown' => 'PgDn',
    'MediaTrackPrevious' => '⏮',
    'MediaTrackNext' => '⏭',
    'MediaPlayPause' => '⏯',
    _ => code.replaceFirst(RegExp(r'^(Key|Digit)'), ''),
  };
  final label = switch (input['device']) {
    'keyboard' => key,
    'wheel' => input['direction'] == 'up' ? '↑' : '↓',
    'mouse' => switch (input['button']) {
      0 => t.bindingEditor.leftButton,
      1 => t.bindingEditor.middleButton,
      2 => t.bindingEditor.rightButton,
      3 => t.bindingEditor.backButton,
      4 => t.bindingEditor.forwardButton,
      _ => '${input['button']}',
    },
    'area' => bindingAreaLabels[input['area']] ?? '${input['area']}',
    'mouse-gesture' =>
      (input['directions'] as List? ?? [])
          .map((d) => bindingDirectionSymbols[d] ?? d)
          .join(''),
    'touch' =>
      '${input['fingers']} · ${bindingTouchGestures[input['gesture']] ?? input['gesture']}',
    'gamepad' => '${input['button']}',
    'radial' => t.bindingEditor.radial,
    _ => bindingInputSummary(input),
  };
  return [
    for (final modifier in const {
      'ctrl': 'Ctrl',
      'alt': 'Alt',
      'shift': '⇧',
      'meta': '⌘',
    }.entries)
      if (input[modifier.key] == true) modifier.value,
    label,
    if (input['trigger'] == 'hold' || input['action'] == 'hold')
      t.bindingEditor.hold,
    if (input['action'] == 'double-click') '×2',
  ].join(' ');
}
