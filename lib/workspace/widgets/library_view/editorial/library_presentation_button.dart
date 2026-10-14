import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/action_group.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';

/// 挂在宿主已有标题或工具栏上；展墙正文不再占用设置行。
///
/// 走 [ActionIconButton] 而不是裸 `IconButton`：工具条上它的邻居全是这一份几何与
/// 配色，裸的那颗不传 `style` 时图标色退回环境 `IconTheme`（在卡片里是白的），
/// 于是同一槽里只有它不跟着主题走。
class LibraryPresentationButton extends StatelessWidget {
  const LibraryPresentationButton({
    super.key,
    required this.canvasKey,
    this.enabled = true,
  });
  final GlobalKey<LibraryEditorialCanvasState> canvasKey;
  final bool enabled;

  /// 提示语把两种手势都写出来：桌面端悬停即见，触摸端没有右键可试。
  static const tooltip = '展墙设置 · 长按开关展墙';

  @override
  Widget build(BuildContext context) => ActionIconButton(
    // 不用 `palette`：那颗在 13 处里都是「外观/配色」，而这个入口管的是
    // 这一面墙怎么排版 —— `gradient`（框 + 斜纹铺陈）全仓没人用过。
    glyph: AppGlyphs.gradient,
    tooltip: tooltip,
    enabled: enabled,
    onPressed: () => canvasKey.currentState?.openSettings(context),
    // 展墙偏好评测要调十几滑杆，只想开关一面墙的人不该先点开面板再找那颗
    // toggle；长按直接在这颗键上完成翻转。
    onLongPress: () => canvasKey.currentState?.toggleEditorial(),
  );
}
