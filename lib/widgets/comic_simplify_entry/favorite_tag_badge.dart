import 'package:flutter/material.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 封面左上角的「收藏 tag」角标。
///
/// 按 M3 的色调容器走：tag 用 `tertiaryContainer`/`onTertiaryContainer`，
/// 与 [FavoriteArtistBadge] 的 `errorContainer` 一家分家 —— 两个角标会同时
/// 出现在同一张卡上，靠**容器色 + 前面的 `#`** 两路信息分辨谁是谁，
/// 不再共用同一块琥珀底。
class FavoriteTagBadge extends StatelessWidget {
  final String? tagName;

  const FavoriteTagBadge({super.key, this.tagName});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '#',
            style: TextStyle(
              color: scheme.onTertiaryContainer,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const SizedBox(width: 2),
          ConstrainedBox(
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
                color: scheme.onTertiaryContainer,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
