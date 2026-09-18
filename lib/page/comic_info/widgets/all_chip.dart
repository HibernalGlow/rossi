// 通用的标签/分类 Widget
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_info/json/normal/normal_comic_all_info.dart';
import 'package:zephyr/page/comic_info/models/comic_info_action.dart';
import 'package:zephyr/platform/desktop/window_logic.dart';
import 'package:zephyr/type/pipe.dart';
import 'package:zephyr/util/comic/favorite_artist_matcher.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/widgets/toast.dart';

class AllChipWidget extends StatefulWidget {
  final String comicId;
  final ComicInfoMetadata metadata;
  final String from;

  const AllChipWidget({
    super.key,
    required this.comicId,
    required this.metadata,
    required this.from,
  });

  @override
  State<AllChipWidget> createState() => _AllChipWidgetState();
}

class _AllChipWidgetState extends State<AllChipWidget> {
  List<ComicInfoActionItem> get items => widget.metadata.value;
  String get title => widget.metadata.name;

  @override
  Widget build(BuildContext context) {
    final runSpacings = isDesktop ? 5.0 : 8.0;
    final processedTitle = processText(title).let(convertChineseForDisplay);
    final globalSetting = context.watch<GlobalSettingCubit>().state;
    final favoriteSetting = globalSetting.favoriteArtistSetting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: runSpacings),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LabelChip(label: processedTitle),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: runSpacings,
                children: items.map((item) {
                  final norm = FavoriteArtistMatcher.normalizeArtist(item.name);
                  final isFavorite = favoriteSetting.highlightEnabled &&
                      favoriteSetting.artists.any(
                        (a) =>
                            FavoriteArtistMatcher.normalizeArtist(a) == norm,
                      );
                  return _ClickableChip(
                    label: processText(
                      item.name,
                    ).let(convertChineseForDisplay),
                    isFavorite: isFavorite,
                    onTap: () => _onTap(item),
                    onLongPress: () => _showChipMenu(context, item, isFavorite),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showChipMenu(
    BuildContext context,
    ComicInfoActionItem item,
    bool isFavorite,
  ) {
    final rawName = item.name.trim();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                isFavorite ? Icons.favorite_border : Icons.favorite,
                color: const Color(0xFFDC2626),
              ),
              title: Text(
                isFavorite
                    ? t.settings.removeFromFavoriteArtist
                    : t.settings.addToFavoriteArtist,
              ),
              subtitle: Text(rawName),
              onTap: () {
                Navigator.pop(sheetContext);
                final cubit = context.read<GlobalSettingCubit>();
                if (isFavorite) {
                  cubit.removeFavoriteArtist(rawName);
                  showInfoToast(
                    t.settings.removedFromFavoriteArtist(name: rawName),
                  );
                } else {
                  cubit.addFavoriteArtist(rawName);
                  showSuccessToast(
                    t.settings.addedToFavoriteArtist(name: rawName),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(t.common.copy),
              onTap: () {
                Navigator.pop(sheetContext);
                Clipboard.setData(ClipboardData(text: processText(item.name)));
                showSuccessToast(
                  t.comicInfo.copiedToClipboard(
                    name: item.name.let(convertChineseForDisplay),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String processText(String text) {
    if (text.contains('\r')) {
      text = text.replaceAll('\r', '');
    }

    if (text.contains(' ')) {
      text = text.replaceAll(' ', '');
    }

    return text;
  }

  void _onTap(ComicInfoActionItem item) {
    if (item.onTap.isNotEmpty) {
      handleComicInfoAction(context, item.onTap, fallbackPluginId: widget.from);
    }
  }
}

class _LabelChip extends StatelessWidget {
  final String label;

  const _LabelChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      margin: const EdgeInsets.only(top: 2),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: context.theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _ClickableChip extends StatefulWidget {
  final String label;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ClickableChip({
    required this.label,
    this.isFavorite = false,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_ClickableChip> createState() => _ClickableChipState();
}

class _ClickableChipState extends State<_ClickableChip> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final primary = context.theme.colorScheme.primary;
    final background = context.backgroundColor;
    final isDark = context.theme.brightness == Brightness.dark;

    final borderColor = widget.isFavorite
        ? const Color(0xFFF59E0B)
        : primary.withValues(alpha: _hovering ? 0.9 : 0.55);

    final chipBackground = widget.isFavorite
        ? (isDark
            ? const Color(0xFF78350F).withValues(alpha: 0.35)
            : const Color(0xFFFEF3C7))
        : (_hovering ? primary.withValues(alpha: 0.08) : background);

    final textColor = widget.isFavorite
        ? (isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E))
        : primary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: chipBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: borderColor,
              width: widget.isFavorite ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.isFavorite
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.25)
                    : context.textColor.withValues(
                        alpha: _hovering ? 0.28 : 0.18,
                      ),
                blurRadius: widget.isFavorite ? 6 : (_hovering ? 10 : 6),
                offset: const Offset(0, 2),
                spreadRadius: widget.isFavorite ? 0.5 : (_hovering ? 0.5 : 0),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isFavorite) ...[
                const Text(
                  '♥ ',
                  style: TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  color: textColor,
                  fontWeight: widget.isFavorite
                      ? FontWeight.w700
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
