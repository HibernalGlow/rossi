import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/widgets/popup_panel.dart';

/// 搜索语法速查。
///
/// 走弹层面板的默认形态（全屏遮罩 + 居中卡片）：这是「看一遍再回来」的须知，
/// 不是随手用一下的筛选面板，所以它不该从触发处飞出来。
void showSearchHelp(BuildContext context) {
  showPopupPanel<void>(
    context: context,
    builder: (ctx) => PopupPanel(
      title: Text(t.search.tipsTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTipCard(
            title: t.search.exactSearchTitle,
            example: t.search.exactSearchExample,
            desc: t.search.exactSearchDesc,
            color: Colors.blue[100]!,
          ),
          _buildTipCard(
            title: t.search.excludeSearchTitle,
            example: t.search.excludeSearchExample,
            desc: t.search.excludeSearchDesc,
            color: Colors.red[100]!,
          ),
          _buildTipCard(
            title: t.search.fuzzySearchTitle,
            example: t.search.fuzzySearchExample,
            desc: t.search.fuzzySearchDesc,
            color: Colors.green[100]!,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(t.common.gotIt),
        ),
      ],
    ),
  );
}

Widget _buildTipCard({
  required String title,
  required String example,
  required String desc,
  required Color color,
}) {
  return Container(
    margin: EdgeInsets.only(bottom: 12),
    padding: EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        SizedBox(height: 6),
        Text(
          example,
          style: TextStyle(backgroundColor: Colors.black12, fontSize: 15),
        ),
        SizedBox(height: 4),
        Text(desc, style: TextStyle(fontSize: 14, color: Colors.black87)),
      ],
    ),
  );
}
