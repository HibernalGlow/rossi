import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/expressive/expressive_icon_button.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';

/// 五个高频入口停靠在同一条浮动工具栏，设备与辅助动作收进菜单。
class ReaderBottomToolbar extends StatelessWidget {
  const ReaderBottomToolbar({
    super.key,
    required this.previousChapter,
    required this.nextChapter,
    required this.selectChapter,
    required this.openSettings,
    required this.goHome,
    required this.toggleThumbnails,
    required this.togglePinned,
    required this.thumbnailsVisible,
    required this.pinned,
  });

  final VoidCallback? previousChapter;
  final VoidCallback? nextChapter;
  final VoidCallback? selectChapter;
  final VoidCallback openSettings;
  final VoidCallback goHome;
  final VoidCallback? toggleThumbnails;
  final VoidCallback togglePinned;
  final bool thumbnailsVisible;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    Widget action(
      Glyph glyph,
      String label,
      VoidCallback? callback, {
      bool prominent = false,
    }) => ActionBubbleTarget(
      enabled: callback != null,
      child: ExpressiveIconButton(
        glyph: glyph,
        tooltip: label,
        onPressed: callback,
        size: 48,
        shape: prominent
            ? ExpressiveButtonShape.cookie4Sided
            : ExpressiveButtonShape.circle,
      ),
    );
    return ActionBubbleRegion(
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        elevation: 3,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              action(
                AppGlyphs.skipPrevious,
                t.reader.previousChapter,
                previousChapter,
              ),
              action(
                AppGlyphs.layoutList,
                t.reader.selectChapter,
                selectChapter,
              ),
              action(
                AppGlyphs.sliders,
                t.reader.settings,
                openSettings,
                prominent: true,
              ),
              action(AppGlyphs.skipNext, t.reader.nextChapter, nextChapter),
              CommonPopupBox<void>(
                targetBuilder: (open) =>
                    action(AppGlyphs.more, t.common.more, () => open()),
                popupBuilder: (context) => CommonPopupMenu(
                  items: [
                    CommonPopupMenuItem(
                      glyph: AppGlyphs.photos,
                      label: thumbnailsVisible
                          ? t.reader.thumbnailStripCollapse
                          : t.reader.thumbnailStripExpand,
                      checked: thumbnailsVisible,
                      onPressed: toggleThumbnails,
                    ),
                    CommonPopupMenuItem(
                      glyph: AppGlyphs.pin,
                      label: pinned
                          ? t.reader.unpinBottomBar
                          : t.reader.pinBottomBar,
                      checked: pinned,
                      onPressed: togglePinned,
                    ),
                    CommonPopupMenuItem(
                      glyph: AppGlyphs.home,
                      label: t.reader.backToHome,
                      onPressed: goHome,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
