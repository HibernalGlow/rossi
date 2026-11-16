import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 封面左上角的「喜欢画师」角标。
///
/// 次要色调与心形表达关注关系，避免把关注画师画成错误状态。
class FavoriteArtistBadge extends StatelessWidget {
  final String? artistName;

  const FavoriteArtistBadge({super.key, this.artistName});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 盖在迷你封面（展墙小格子、空隙预览）上的角标放不下：内边距 10 + 心形 10
    // 就已经超过可画宽度，硬画只会得到一条溢出条。这一档本来也读不出字，整颗让位。
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedWidth && constraints.maxWidth < 28) {
          return const SizedBox.shrink();
        }
        return _badge(scheme);
      },
    );
  }

  Widget _badge(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '♥',
            style: TextStyle(
              color: scheme.onSecondaryContainer,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              artistName?.isNotEmpty == true
                  ? artistName!
                  : t.settings.favoriteArtistBadge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSecondaryContainer,
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
