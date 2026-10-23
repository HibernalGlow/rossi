import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_info/comic_info.dart';
import 'package:zephyr/util/comic/favorite_artist_matcher.dart';
import 'package:zephyr/util/comic/favorite_tag_matcher.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry.dart';
import 'package:zephyr/widgets/comic_simplify_entry/favorite_tag_badge.dart';
import 'package:zephyr/page/comic_info/json/normal/normal_comic_all_info.dart'
    show ComicInfo, ComicInfoActionItem;
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/service/download/download_storage_layout.dart';
import 'package:zephyr/service/download/download_storage_summary.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/type/pipe.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/widgets/picture_bloc/models/picture_info.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/icons/icons.dart';

class ComicParticularsWidget extends StatelessWidget {
  final ComicInfo comicInfo;
  final String from;
  final ComicEntryType type;
  final VoidCallback? onContinueRead;
  final VoidCallback? onCoverTap;

  const ComicParticularsWidget({
    super.key,
    required this.comicInfo,
    required this.from,
    required this.type,
    this.onContinueRead,
    this.onCoverTap,
  });

  @override
  Widget build(BuildContext context) {
    final pictureInfo = PictureInfo(
      from: from,
      url: comicInfo.cover.url,
      path: comicInfo.cover.path,
      chapterId: '',
      pictureType: PictureType.cover,
      cartoonId: comicInfo.id,
    );

    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final info = _InfoColumn(
            comicInfo: comicInfo,
            from: from,
            type: type,
            onContinueRead: onContinueRead,
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  child: Cover(
                    pictureInfo: pictureInfo,
                    height: 220,
                    borderRadius: 14,
                    onTap: onCoverTap,
                  ),
                ),
                const SizedBox(height: 16),
                info,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Cover(
                pictureInfo: pictureInfo,
                height: 230,
                borderRadius: 14,
                onTap: onCoverTap,
              ),
              const SizedBox(width: 16),
              Expanded(child: info),
            ],
          );
        },
      ),
    );
  }
}

class _InfoColumn extends StatefulWidget {
  const _InfoColumn({
    required this.comicInfo,
    required this.from,
    required this.type,
    required this.onContinueRead,
  });

  final ComicInfo comicInfo;
  final String from;
  final ComicEntryType type;
  final VoidCallback? onContinueRead;

  @override
  State<_InfoColumn> createState() => _InfoColumnState();
}

class _InfoColumnState extends State<_InfoColumn> {
  int? _storageSize;

  @override
  void initState() {
    super.initState();
    if (widget.type == ComicEntryType.download) {
      _calculateStorageSize();
    }
  }

  Future<void> _calculateStorageSize() async {
    final stat = await measureComicDownloadStorage(
      from: widget.from,
      comicId: widget.comicInfo.id,
    );
    // 一个目录都没找到时保持 null：显示「0 B」会被读成「这本没占地方」，
    // 而真实情况可能是布局换了或还没统计过。
    if (stat.measured && mounted) {
      setState(() => _storageSize = stat.bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displaySource = context.select<PluginRegistryCubit, String>(
      (cubit) => cubit.state.pluginName(_normalizePluginId(widget.from)),
    );
    final titleStyle = context.theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      height: 1.15,
      color: context.textColor,
    );

    final globalSetting = context.watch<GlobalSettingCubit>().state;
    final favoriteSetting = globalSetting.favoriteArtistSetting;
    // 详情页的 titleMeta 是「分类：／上传者：／语言：／页数：」这一排说明文字，
    // 它们**不是**标签；画师与社团只从 metadata 的命名空间分桶里拿。
    final buckets = FavoriteArtistBuckets();
    for (final group in widget.comicInfo.metadata) {
      buckets.addGroup(
        type: group.type,
        name: group.name,
        values: group.value.map((v) => v.name),
      );
    }
    final matchResult = favoriteSetting.highlightEnabled
        ? FavoriteArtistMatcher.match(
            title: widget.comicInfo.title,
            artistTags: buckets.artistTags,
            circleTags: buckets.circleTags,
            creator: widget.comicInfo.creator.name,
            favoriteArtists: favoriteSetting.artists,
            circleMode: favoriteSetting.circleMode,
          )
        : null;
    final isFavoriteArtist = matchResult?.isMatched ?? false;
    // 收藏 tag 只看 metadata 的分桶值（`titleMeta` 那一排是「分类：／语言：／页数：」
    // 这种说明文字，不是标签），外加标题括号里的写法。
    final favoriteTagSetting = globalSetting.favoriteTagSetting;
    final tagMatchResult = favoriteTagSetting.highlightEnabled
        ? FavoriteTagMatcher.match(
            tags: [
              for (final group in widget.comicInfo.metadata)
                ...group.value.map((v) => v.name),
            ],
            title: widget.comicInfo.title,
            favoriteTags: favoriteTagSetting.tags,
          )
        : FavoriteTagMatchResult.notMatched;
    final isFavoriteTag = tagMatchResult.isMatched;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: context.theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: context.theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                ),
              ),
              child: Text(
                displaySource,
                style: context.theme.textTheme.labelMedium?.copyWith(
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (isFavoriteArtist) ...[
              const SizedBox(width: 8),
              // 徽标显示漫画那一侧的写法（可能是社团名），不是喜欢项原文。
              FavoriteArtistBadge(artistName: matchResult?.matchedName),
            ],
            if (isFavoriteTag) ...[
              const SizedBox(width: 8),
              // Flexible：这一排还有来源pill、存储信息，tag 名长度由用户决定，
              // 不给弹性位就会把整行顶出去。
              Flexible(child: FavoriteTagBadge(tagName: tagMatchResult.label)),
            ],
            if (_storageSize != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: context.theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: context.theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.3,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GlyphIcon(
                      AppGlyphs.storage,
                      size: 14,
                      color: context.textColor.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      formatDownloadBytes(_storageSize!),
                      style: context.theme.textTheme.labelMedium?.copyWith(
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        SelectableText(
          widget.comicInfo.title.let(convertChineseForDisplay),
          style: titleStyle,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.comicInfo.titleMeta
              .map((item) => _MetaPill(item: item))
              .toList(),
        ),
        _ContinueReadingBanner(onContinueRead: widget.onContinueRead),
      ],
    );
  }

  String _normalizePluginId(String raw) {
    var value = raw.trim();
    while (value.length >= 2 && value.startsWith('(') && value.endsWith(')')) {
      value = value.substring(1, value.length - 1).trim();
    }
    return value;
  }
}

class _ContinueReadingBanner extends StatelessWidget {
  const _ContinueReadingBanner({required this.onContinueRead});

  final VoidCallback? onContinueRead;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<StringSelectCubit, String, String>(
      selector: (state) => state,
      builder: (context, stringSelectDate) {
        if (stringSelectDate.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onContinueRead,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: context.theme.colorScheme.primary.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: context.theme.colorScheme.primary.withValues(
                      alpha: 0.30,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: context.theme.colorScheme.primary.withValues(
                          alpha: 0.14,
                        ),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: GlyphIcon(
                        AppGlyphs.history,
                        size: 18,
                        color: context.theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            t.comicInfo.readHistory,
                            style: context.theme.textTheme.labelMedium
                                ?.copyWith(
                                  color: context.theme.colorScheme.primary,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            stringSelectDate,
                            style: context.theme.textTheme.bodyMedium?.copyWith(
                              color: context.textColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onContinueRead != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        t.comicInfo.continueRead,
                        style: context.theme.textTheme.labelLarge?.copyWith(
                          color: context.theme.colorScheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 4),
                      GlyphIcon(
                        AppGlyphs.play,
                        size: 20,
                        color: context.theme.colorScheme.primary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.item});

  final ComicInfoActionItem item;

  @override
  Widget build(BuildContext context) {
    final pill = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 38),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: context.theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.32,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Text(
              item.name.let(convertChineseForDisplay),
              textAlign: TextAlign.center,
              softWrap: true,
              style: context.theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onLongPress: () async {
        final copyText = item.onLongPress?.trim().isNotEmpty == true
            ? item.onLongPress!.trim()
            : item.name;
        await Clipboard.setData(ClipboardData(text: copyText));
        showSuccessToast(
          t.comicInfo.copied(label: item.name.let(convertChineseForDisplay)),
        );
      },
      child: pill,
    );
  }
}
