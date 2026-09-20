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
import 'package:zephyr/util/comic/favorite_tag_matcher.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/util/layout/quiet_flex.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/widgets/toast.dart';

/// 分组名（「其他 / 磁力 / 种子」）的最大宽度。
///
/// 它是外层 Row 里**不受约束**的那一项（`Expanded` 只护住了右边的 `Wrap`），
/// 插件把分组名写长一点就会让整个 Row 溢出 —— 超长分组名与超长 chip 是同一个
/// bug 的两半，所以两处都要夹住。
const double _labelChipMaxWidth = 120;

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
    final favoriteTagSetting = globalSetting.favoriteTagSetting;
    // 一整组胶囊共用同一张别名索引：每颗胶囊各建一次的话，一页几十个 tag 就要
    // 把收藏列表扫几十遍。
    final tagIndex = favoriteTagSetting.highlightEnabled
        ? FavoriteTagMatcher.buildAliasIndex(favoriteTagSetting.tags)
        : const <String, FavoriteTag>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: runSpacings),
        // QuietRow（不是 Row）：chip 的文案来自插件（种子标题、磁力串…），长度不可控，
        // 万一再溢出，宁可省略也不要在内容上盖一条黄黑斜纹。见 util/layout/。
        QuietRow(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LabelChip(label: processedTitle),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: runSpacings,
                children: items.map((item) {
                  final isFavorite =
                      favoriteSetting.highlightEnabled &&
                      FavoriteArtistMatcher.chipIsFavorite(
                        label: item.name,
                        namespaceType: widget.metadata.type,
                        namespaceName: widget.metadata.name,
                        favoriteArtists: favoriteSetting.artists,
                        circleMode: favoriteSetting.circleMode,
                      );
                  final isFavoriteTag = FavoriteTagMatcher.hitInIndex(
                    tagIndex,
                    item.name,
                  );
                  return AllChipItem(
                    label: processText(item.name).let(convertChineseForDisplay),
                    isFavorite: isFavorite,
                    isFavoriteTag: isFavoriteTag,
                    onTap: () => _onTap(item),
                    onLongPress: () => _showChipMenu(
                      context,
                      item,
                      isFavoriteArtist: isFavorite,
                      isFavoriteTag: isFavoriteTag,
                    ),
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
    ComicInfoActionItem item, {
    required bool isFavoriteArtist,
    required bool isFavoriteTag,
  }) {
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
                isFavoriteArtist ? Icons.favorite_border : Icons.favorite,
                color: const Color(0xFFDC2626),
              ),
              title: Text(
                isFavoriteArtist
                    ? t.settings.removeFromFavoriteArtist
                    : t.settings.addToFavoriteArtist,
              ),
              subtitle: Text(rawName),
              onTap: () {
                Navigator.pop(sheetContext);
                final cubit = context.read<GlobalSettingCubit>();
                if (isFavoriteArtist) {
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
            // 收藏 tag 与收藏画师是两件事：同一颗胶囊可以同时是「喜欢的画师」
            // 和「收藏的 tag」，所以两颗菜单项各自独立开关，互不覆盖。
            ListTile(
              leading: Icon(
                isFavoriteTag ? Icons.sell_outlined : Icons.sell,
                color: const Color(0xFFF59E0B),
              ),
              title: Text(
                isFavoriteTag
                    ? t.settings.removeFromFavoriteTag
                    : t.settings.addToFavoriteTag,
              ),
              subtitle: Text(rawName),
              onTap: () {
                Navigator.pop(sheetContext);
                final cubit = context.read<GlobalSettingCubit>();
                if (isFavoriteTag) {
                  cubit.removeFavoriteTag(rawName);
                  showInfoToast(t.settings.favoriteTagRemoved(name: rawName));
                } else {
                  cubit.addFavoriteTag(rawName);
                  showSuccessToast(t.settings.favoriteTagAdded(name: rawName));
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _labelChipMaxWidth),
      child: Container(
        decoration: BoxDecoration(
          color: context.theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        margin: const EdgeInsets.only(top: 2),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: context.theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

/// 一个可点可长按的胶囊，用于渲染插件给的**一段任意文本**（标签、磁力串、种子标题…）。
///
/// 刻意是 public 的（同文件其余都是 `_` 私有）：它是「插件文案再长也不能溢出」这条
/// 契约的落点，`test/comic_info/all_chip_item_test.dart` 直接拿它当判据渲染
/// —— `AllChipWidget` 自己拉不起（要 objectbox / bloc），拿它当被测对象才能把
/// 「超长文案 ⇒ 一行省略、不溢出」钉死。
class AllChipItem extends StatefulWidget {
  final String label;
  final bool isFavorite;

  /// 命中收藏 tag：与 [isFavorite]（喜欢画师）同一套琥珀色，靠前面的 `#` 区分。
  final bool isFavoriteTag;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const AllChipItem({
    super.key,
    required this.label,
    this.isFavorite = false,
    this.isFavoriteTag = false,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<AllChipItem> createState() => _AllChipItemState();
}

class _AllChipItemState extends State<AllChipItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final primary = context.theme.colorScheme.primary;
    final background = context.backgroundColor;
    final isDark = context.theme.brightness == Brightness.dark;
    // 画师与 tag 共用同一套琥珀色，只在前面那颗符号上分家。
    final highlighted = widget.isFavorite || widget.isFavoriteTag;
    final mark = widget.isFavorite
        ? '♥ '
        : (widget.isFavoriteTag ? '# ' : null);

    final borderColor = highlighted
        ? const Color(0xFFF59E0B)
        : primary.withValues(alpha: _hovering ? 0.9 : 0.55);

    final chipBackground = highlighted
        ? (isDark
              ? const Color(0xFF78350F).withValues(alpha: 0.35)
              : const Color(0xFFFEF3C7))
        : (_hovering ? primary.withValues(alpha: 0.08) : background);

    final textColor = highlighted
        ? (isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E))
        : primary;

    return Tooltip(
      // chip 的文案只占一行、超出省略（见下面的 Flexible）⇒ 悬停给全文。
      // name: manual —— 长按已经被「加收藏 / 复制」那个菜单占着，别让 tooltip 抢手势；
      // 触摸端本来就没有 hover，长按菜单里也已经能看到原文。
      message: widget.label,
      waitDuration: const Duration(milliseconds: 600),
      triggerMode: TooltipTriggerMode.manual,
      child: MouseRegion(
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
                width: highlighted ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: highlighted
                      ? const Color(0xFFF59E0B).withValues(alpha: 0.25)
                      : context.textColor.withValues(
                          alpha: _hovering ? 0.28 : 0.18,
                        ),
                  blurRadius: highlighted ? 6 : (_hovering ? 10 : 6),
                  offset: const Offset(0, 2),
                  spreadRadius: highlighted ? 0.5 : (_hovering ? 0.5 : 0),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: QuietRow(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (mark != null)
                  Text(
                    mark,
                    style: TextStyle(
                      color: widget.isFavorite
                          ? const Color(0xFFDC2626)
                          : const Color(0xFFB45309),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                // Flexible 是这里的**关键**：QuietRow/Row 给非弹性子节点的是
                // **无界**主轴约束，裸 Text 会按原文长度排版（种子标题能到 600+ px），
                // 于是 Row 自己溢出（截图那条 RIGHT OVERFLOWED BY 294 就是这么来的）。
                // Flexible 让它先拿到「chip 还剩多少宽」，再一行省略。
                //
                // 代价：Flexible 要求主轴**有界**，所以 chip 只能待在 `Wrap` /
                // `Expanded` / 定宽容器里。塞进横向滚动的 Row 会直接断言失败
                // （不是静默错位）—— 而那种用法本来也就不是胶囊该去的地方。
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: textColor,
                      fontWeight: highlighted
                          ? FontWeight.w700
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
