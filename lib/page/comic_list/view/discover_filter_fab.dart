import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/expressive/expressive_icon_button.dart';

/// 漫画列表 / 发现的筛选入口。
///
/// 与书架右下角那颗同规格：56dp 的形变图标钮，**不带汉字** —— 这一颗常年挂在
/// 右下角，带文字就是一只占掉半屏宽的胶囊；「是哪件事」交给 tooltip 与图标形状，
/// 「筛选生没生效」交给角标。
class DiscoverFilterFab extends StatelessWidget {
  const DiscoverFilterFab({
    super.key,
    required this.onPressed,
    this.hasFilters = false,
  });
  final VoidCallback onPressed;

  /// 当前筛选与默认值不一致时点亮角标。
  final bool hasFilters;

  @override
  Widget build(BuildContext context) => Badge(
    isLabelVisible: hasFilters,
    child: ExpressiveIconButton(
      glyph: AppGlyphs.sliders,
      tooltip: t.comicList.filter,
      size: 56,
      shape: ExpressiveButtonShape.cookie6Sided,
      onPressed: () {
        HapticFeedback.lightImpact();
        onPressed();
      },
    ),
  );
}
