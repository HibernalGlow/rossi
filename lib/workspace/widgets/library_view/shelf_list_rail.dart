import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/expressive/expressive_icon_button.dart';
import 'package:zephyr/widgets/navigation/navigation_shape.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 列表名横向滚动，管理入口固定在尾端；窄卡片仍然可以新增和编辑列表。
class ShelfListRail extends StatelessWidget {
  const ShelfListRail({
    super.key,
    required this.children,
    required this.onCreate,
    this.onEdit,
  });
  final List<Widget> children;
  final VoidCallback? onCreate;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    shape: AppShape.all(18),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: children),
              ),
            ),
          ),
          const SizedBox(width: 4),
          ExpressiveIconButton(
            glyph: AppGlyphs.listAdd,
            tooltip: t.workspace.newBookmarkList,
            shape: ExpressiveButtonShape.puffy,
            onPressed: onCreate,
          ),
          if (onEdit != null) ...[
            const SizedBox(width: 4),
            ExpressiveIconButton(
              glyph: AppGlyphs.edit,
              tooltip: t.workspace.renameDeleteList,
              shape: ExpressiveButtonShape.slanted,
              onPressed: onEdit,
            ),
          ],
        ],
      ),
    ),
  );
}
