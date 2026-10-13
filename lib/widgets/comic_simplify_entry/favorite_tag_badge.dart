import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 封面左上角的「收藏 tag」角标。
///
/// 中性色容器与 # 标记表达分类，让关注关系与阅读状态更容易识别。
class FavoriteTagBadge extends StatelessWidget {
  final String? tagName;

  const FavoriteTagBadge({super.key, this.tagName});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '#',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const SizedBox(width: 2),
          Flexible(
            child: ConstrainedBox(
              // 卡片宽度可以小到 60 多像素，而收藏的 tag 名字长度由用户决定：
              // 不限宽会把整张封面盖住，也会把同列的语言角标挤出去。
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(
                tagName?.isNotEmpty == true
                    ? tagName!
                    : t.settings.favoriteTagBadge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
