import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/setting/operation_binding/binding_action_presentation.dart';
import 'package:zephyr/service/operation_binding/radial_doc.dart';

/// 稳定的展示标识，不把 Glyph 或 Flutter 类型写入用户配置。
const radialIconActionIds = [
  'reader.previous-page',
  'reader.next-page',
  'reader.first-page',
  'reader.last-page',
  'reader.page-left',
  'reader.page-right',
  'reader.previous-book',
  'reader.next-book',
  'reader.zoom-in',
  'reader.zoom-out',
  'reader.fit-window',
  'reader.actual-size',
  'reader.reset-view',
  'reader.rotate-clockwise',
  'reader.rotate-180',
  'reader.toggle-reading-direction',
  'reader.toggle-book-mode',
  'reader.fullscreen',
  'reader.toggle-controls',
  'reader.open-settings',
  'reader.toggle-library',
  'video.play-pause',
  'video.screenshot',
  'video.toggle-subtitle',
  'video.toggle-mute',
  'video.cycle-loop',
];

Glyph radialActionGlyph({
  required String? action,
  String? overrideId,
  bool menuJump = false,
}) {
  if (overrideId != null && radialIconActionIds.contains(overrideId)) {
    return bindingActionIcon(overrideId);
  }
  return menuJump ? AppGlyphs.donut : bindingActionIcon(action ?? '');
}

/// 组合动作与子轮盘用附加标记，主图标仍表达主动作。
Widget radialActionIcon({
  required RadialItemDoc? item,
  required String? action,
  bool chained = false,
  bool menuJump = false,
}) => SizedBox.square(
  dimension: 28,
  child: Stack(
    clipBehavior: Clip.none,
    children: [
      Center(
        child: GlyphIcon(
          radialActionGlyph(
            action: action,
            overrideId: item?.iconId,
            menuJump: menuJump,
          ),
          size: 24,
        ),
      ),
      if (chained || menuJump)
        Positioned(
          right: -4,
          top: -4,
          child: GlyphIcon(
            menuJump ? AppGlyphs.chevronForward : AppGlyphs.layers,
            size: 12,
          ),
        ),
    ],
  ),
);
