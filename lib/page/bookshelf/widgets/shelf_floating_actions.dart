import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/bookshelf/models/shelf_page_mode.dart';
import 'package:zephyr/widgets/expressive/expressive_icon_button.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_menu_button.dart';

/// 书签 / 历史 / 下载共用的悬浮操作入口。菜单由锚点布局避开屏幕边缘。
class ShelfFloatingActions extends StatelessWidget {
  const ShelfFloatingActions({
    super.key,
    required this.mode,
    required this.onSelect,
    required this.onCreateFolder,
    required this.onImport,
    required this.onHelp,
  });
  final ShelfPageMode mode;
  final VoidCallback onSelect;
  final VoidCallback onCreateFolder;
  final VoidCallback onImport;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    if (mode == ShelfPageMode.history) {
      return ExpressiveIconButton(
        glyph: AppGlyphs.checklist,
        tooltip: t.bookshelf.multiSelect,
        size: 56,
        shape: ExpressiveButtonShape.arch,
        onPressed: onSelect,
      );
    }
    return ShelfMenuButton(
      glyph: AppGlyphs.menu,
      tooltip: t.common.more,
      size: 56,
      shape: mode == ShelfPageMode.download
          ? ExpressiveButtonShape.arrow
          : ExpressiveButtonShape.cookie6Sided,
      menuChildren: [
        ShelfMenuItem(
          label: t.bookshelf.multiSelect,
          glyph: AppGlyphs.checklist,
          onPressed: onSelect,
        ),
        ShelfMenuItem(
          label: t.bookshelf.newFolder,
          glyph: AppGlyphs.folderPlus,
          onPressed: onCreateFolder,
        ),
        if (mode == ShelfPageMode.download)
          ShelfMenuItem(
            label: t.bookshelf.importComic,
            glyph: AppGlyphs.download,
            onPressed: onImport,
          ),
        const ShelfMenuDivider(),
        ShelfMenuItem(
          label: t.common.help,
          glyph: AppGlyphs.info,
          onPressed: onHelp,
        ),
      ],
    );
  }
}
