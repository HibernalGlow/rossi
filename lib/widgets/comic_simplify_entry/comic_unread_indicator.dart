import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 封面右上角的「已下载但未读」标识，三档样式见 [ComicUnreadIndicatorStyle]。
///
/// 三档共用同一份浮起量（黑 35% / blur 3 / offset 0,1），与封面左上角的
/// 语言角标是同一套，扫一列卡片时不会觉得是两种来路不同的东西。
///
/// 纯展示：不挂手势，点击照常落到卡片本身。
class ComicUnreadIndicator extends StatelessWidget {
  const ComicUnreadIndicator({
    super.key,
    required this.style,
    this.compact = false,
  });

  final ComicUnreadIndicatorStyle style;

  /// 窄卡片（<110 逻辑像素）上收一号，理由同 `ComicTranslationBadge.compact`。
  final bool compact;

  static const List<BoxShadow> _lift = [
    BoxShadow(color: Color(0x59000000), blurRadius: 3, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return switch (style) {
      // 最轻的一档：只靠加厚的白环把自己从封面里择出来。
      ComicUnreadIndicatorStyle.dot => Container(
        width: compact ? 9 : 11,
        height: compact ? 9 : 11,
        decoration: BoxDecoration(
          color: scheme.tertiary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: compact ? 2 : 2.5),
          boxShadow: _lift,
        ),
      ),

      // 中间档：中性承底把颜色与封面彻底分开，代价是右上角多一枚实心圆盘。
      ComicUnreadIndicatorStyle.disc => Container(
        width: compact ? 19 : 22,
        height: compact ? 19 : 22,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          shape: BoxShape.circle,
          border: Border.all(color: scheme.outlineVariant, width: 1),
          boxShadow: _lift,
        ),
        child: Center(
          child: Container(
            width: compact ? 8 : 9,
            height: compact ? 8 : 9,
            decoration: BoxDecoration(
              color: scheme.tertiary,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),

      // 最重也最自解释的一档：与「生肉」同形状、同圆角，只是颜色走 token。
      ComicUnreadIndicatorStyle.label => Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 5, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.tertiary,
          borderRadius: BorderRadius.circular(4),
          boxShadow: _lift,
        ),
        child: Text(
          t.comicEntry.unread,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onTertiary,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
      ),
    };
  }
}
