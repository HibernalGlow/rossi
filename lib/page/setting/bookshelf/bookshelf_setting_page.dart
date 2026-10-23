import 'package:zephyr/page/setting/common/setting_group.dart';
import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/icons/icons.dart';

@RoutePage()
class BookshelfSettingPage extends StatefulWidget {
  const BookshelfSettingPage({super.key});

  @override
  State<BookshelfSettingPage> createState() => _BookshelfSettingPageState();
}

class _BookshelfSettingPageState extends State<BookshelfSettingPage> {
  late final List<String> _homePageLabels = [
    t.bookshelf.favorite,
    t.bookshelf.history,
    t.bookshelf.download,
  ];

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final state = cubit.state.bookshelfSetting;
    final cardSetting = cubit.state.comicCardSetting;

    return SettingPageShell(
      title: t.settings.bookshelf,
      description: t.settings.bookshelfSubtitle,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          SettingSectionCard(
            sectionId: 'bookshelf.general',
            children: [
              _homePageTile(state, cubit),
              _switchTile(
                icon: AppGlyphs.heart,
                title: t.settings.bookshelfRememberFavoriteSort,
                subtitle: t.settings.bookshelfRememberFavoriteSortSubtitle,
                value: state.rememberFavoriteSort,
                onChanged: (value) => cubit.updateBookshelfSetting(
                  (current) => current.copyWith(rememberFavoriteSort: value),
                ),
              ),
              _switchTile(
                icon: AppGlyphs.history,
                title: t.settings.bookshelfRememberHistorySort,
                subtitle: t.settings.bookshelfRememberHistorySortSubtitle,
                value: state.rememberHistorySort,
                onChanged: (value) => cubit.updateBookshelfSetting(
                  (current) => current.copyWith(rememberHistorySort: value),
                ),
              ),
              _switchTile(
                icon: AppGlyphs.download,
                title: t.settings.bookshelfRememberDownloadSort,
                subtitle: t.settings.bookshelfRememberDownloadSortSubtitle,
                value: state.rememberDownloadSort,
                onChanged: (value) => cubit.updateBookshelfSetting(
                  (current) => current.copyWith(rememberDownloadSort: value),
                ),
              ),
            ],
          ),
          SettingSectionCard(
            title: t.settings.cardBadges,
            icon: AppGlyphs.palette,
            children: [
              _switchTile(
                icon: AppGlyphs.cloudDownload,
                title: t.settings.cardDownloadBadge,
                subtitle: t.settings.cardDownloadBadgeSubtitle,
                value: cardSetting.downloadBadgeEnabled,
                onChanged: (value) => cubit.updateComicCardSetting(
                  (current) => current.copyWith(downloadBadgeEnabled: value),
                ),
              ),
              _switchTile(
                icon: AppGlyphs.translate,
                title: t.settings.cardTranslationBadge,
                subtitle: t.settings.cardTranslationBadgeSubtitle,
                value: cardSetting.translationBadgeEnabled,
                onChanged: (value) => cubit.updateComicCardSetting(
                  (current) => current.copyWith(translationBadgeEnabled: value),
                ),
              ),
              _switchTile(
                icon: AppGlyphs.playCircle,
                title: t.settings.cardReadButton,
                subtitle: t.settings.cardReadButtonSubtitle,
                value: cardSetting.readButtonEnabled,
                onChanged: (value) => cubit.updateComicCardSetting(
                  (current) => current.copyWith(readButtonEnabled: value),
                ),
              ),
              _switchTile(
                icon: AppGlyphs.sell,
                title: t.settings.cardFavoriteTagBadge,
                subtitle: t.settings.cardFavoriteTagBadgeSubtitle,
                value: cardSetting.favoriteTagBadgeEnabled,
                onChanged: (value) => cubit.updateComicCardSetting(
                  (current) => current.copyWith(favoriteTagBadgeEnabled: value),
                ),
              ),
              _switchTile(
                icon: AppGlyphs.ring,
                title: t.settings.cardUnreadIndicator,
                subtitle: t.settings.cardUnreadIndicatorSubtitle,
                value: cardSetting.unreadIndicatorEnabled,
                onChanged: (value) => cubit.updateComicCardSetting(
                  (current) => current.copyWith(unreadIndicatorEnabled: value),
                ),
              ),
              // 关掉总开关就没有标识可挑样式，这一行整个不画：
              // 留一行点不动的下拉，用户会以为它管的是别的东西。
              if (cardSetting.unreadIndicatorEnabled)
                _unreadIndicatorStyleTile(cardSetting, cubit),
            ],
          ),
          SettingSectionCard(
            title: t.settings.cardInteraction,
            icon: AppGlyphs.touch,
            children: [
              _switchTile(
                icon: AppGlyphs.unfold,
                title: t.settings.shelfCardContextMenu,
                subtitle: t.settings.shelfCardContextMenuSubtitle,
                value: state.shelfCardContextMenu,
                onChanged: (value) => cubit.updateBookshelfSetting(
                  (current) => current.copyWith(shelfCardContextMenu: value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _homePageTile(BookshelfSettingState state, GlobalSettingCubit cubit) {
    final index = state.homePageIndex.clamp(0, _homePageLabels.length - 1);
    final items = {
      for (var i = 0; i < _homePageLabels.length; i++) i: _homePageLabels[i],
    };

    return ListTile(
      leading: const GlyphIcon(AppGlyphs.home),
      title: Text(t.settings.bookshelfHomePage),
      subtitle: Text(t.settings.bookshelfHomePageSubtitle),
      trailing: FluentDropdown<int>(
        value: index,
        displayValue: _homePageLabels[index],
        items: items,
        onChanged: (int value) {
          if (value == index) return;
          cubit.updateBookshelfSetting(
            (current) => current.copyWith(homePageIndex: value),
          );
          showSuccessToast(t.common.settingSaved);
        },
      ),
    );
  }

  /// 「未读标识」画成哪一档。三档的差别全在封面上才看得出来，
  /// 所以选项名按形状给（圆点 / 圆片 / 文字），不给抽象词。
  Widget _unreadIndicatorStyleTile(
    ComicCardSettingState cardSetting,
    GlobalSettingCubit cubit,
  ) {
    final style = cardSetting.unreadIndicatorStyle;
    final labels = _unreadIndicatorStyleLabels;

    return ListTile(
      leading: const GlyphIcon(AppGlyphs.palette),
      title: Text(t.settings.cardUnreadIndicatorStyle),
      subtitle: Text(t.settings.cardUnreadIndicatorStyleSubtitle),
      trailing: FluentDropdown<ComicUnreadIndicatorStyle>(
        value: style,
        displayValue: labels[style]!,
        items: labels,
        onChanged: (value) {
          if (value == style) return;
          cubit.updateComicCardSetting(
            (current) => current.copyWith(unreadIndicatorStyle: value),
          );
          showSuccessToast(t.common.settingSaved);
        },
      ),
    );
  }

  Map<ComicUnreadIndicatorStyle, String> get _unreadIndicatorStyleLabels => {
    ComicUnreadIndicatorStyle.dot: t.settings.cardUnreadIndicatorStyleDot,
    ComicUnreadIndicatorStyle.disc: t.settings.cardUnreadIndicatorStyleDisc,
    ComicUnreadIndicatorStyle.label: t.settings.cardUnreadIndicatorStyleLabel,
  };

  /// 设置页统一的开关行。
  ///
  /// 本页所有开关都走这里：翻转即保存 + 弹「已保存」提示，
  /// 新增开关时不必再抄一遍 toast。
  Widget _switchTile({
    required Glyph icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SettingGroup.switchTile(
      leading: GlyphIcon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: (bool newValue) {
        onChanged(newValue);
        showSuccessToast(t.common.settingSaved);
      },
    );
  }
}
