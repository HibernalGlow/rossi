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
