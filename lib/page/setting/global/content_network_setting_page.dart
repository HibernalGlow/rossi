import 'package:zephyr/page/setting/common/setting_group.dart';
import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/setting/global/widgets.dart';
import 'package:zephyr/util/network_policy.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/icons/icons.dart';

@RoutePage()
class ContentNetworkSettingPage extends StatelessWidget {
  const ContentNetworkSettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final state = cubit.state;

    return SettingPageShell(
      title: t.settings.contentAndNetwork,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          SettingSectionCard(
            title: t.settings.content,
            icon: AppGlyphs.sliders,
            children: [
              editMaskedKeywords(context),
              ListTile(
                leading: const GlyphIcon(
                  AppGlyphs.star,
                  color: Color(0xFFF59E0B),
                ),
                title: Text(t.settings.favoriteArtistManagement),
                subtitle: Text(
                  state.favoriteArtistSetting.artists.isEmpty
                      ? t.settings.favoriteArtistManagementSubtitleEmpty
                      : t.settings.favoriteArtistManagementSubtitle(
                          count: state.favoriteArtistSetting.artists.length,
                        ),
                ),
                trailing: const GlyphIcon(AppGlyphs.chevronForward),
                onTap: () {
                  context.pushRoute(const FavoriteArtistSettingRoute());
                },
              ),
              SettingGroup.switchTile(
                leading: const GlyphIcon(AppGlyphs.highlight),
                title: Text(t.settings.favoriteArtistHighlight),
                subtitle: Text(t.settings.favoriteArtistHighlightSubtitle),
                value: state.favoriteArtistSetting.highlightEnabled,
                onChanged: (value) {
                  cubit.toggleHighlightFavoriteArtists(value);
                },
              ),
              ListTile(
                leading: const GlyphIcon(
                  AppGlyphs.sell,
                  color: Color(0xFFF59E0B),
                ),
                title: Text(t.settings.favoriteTagManagement),
                subtitle: Text(
                  state.favoriteTagSetting.tags.isEmpty
                      ? t.settings.favoriteTagManagementSubtitleEmpty
                      : t.settings.favoriteTagManagementSubtitle(
                          count: state.favoriteTagSetting.tags.length,
                        ),
                ),
                trailing: const GlyphIcon(AppGlyphs.chevronForward),
                onTap: () {
                  context.pushRoute(const FavoriteTagSettingRoute());
                },
              ),
              SettingGroup.switchTile(
                leading: const GlyphIcon(AppGlyphs.highlight),
                title: Text(t.settings.favoriteTagHighlight),
                subtitle: Text(t.settings.favoriteTagHighlightSubtitle),
                value: state.favoriteTagSetting.highlightEnabled,
                onChanged: (value) {
                  cubit.toggleHighlightFavoriteTags(value);
                },
              ),
              _chineseConvertMode(state, cubit),
              if (state.showSearchBookmark)
                _searchBookmarkProbePages(state, cubit),
              SettingGroup.switchTile(
                leading: const GlyphIcon(AppGlyphs.shield),
                title: Text(t.settings.fullSourceList),
                subtitle: Text(t.settings.fullSourceListSubtitle),
                value: state.showRestrictedSources,
                onChanged: (value) {
                  cubit.updateState(
                    (current) => current.copyWith(showRestrictedSources: value),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, thickness: 0.3),
          settingSectionTitle(
            context,
            t.settings.network,
            icon: AppGlyphs.wifi,
          ),
          proxyToggle(
            context,
            enabled: state.proxySetting.enabled,
            type: state.proxySetting.type,
            currentProxy: state.proxySetting.address,
          ),
          settingCategoryTile(
            icon: AppGlyphs.router,
            title: t.settings.doh,
            subtitle: state.dohSetting.enabled
                ? t.settings.dohProviderCount(
                    count: state.dohSetting.providers.length,
                  )
                : t.common.disabled,
            onTap: () => context.pushRoute(const DohSettingRoute()),
          ),
          SettingGroup.switchTile(
            leading: const GlyphIcon(AppGlyphs.router),
            title: Text(t.settings.blockPrivateNetwork),
            subtitle: Text(t.settings.blockPrivateNetworkSubtitle),
            value: state.blockPrivateNetwork,
            onChanged: (value) {
              cubit.updateState(
                (current) => current.copyWith(blockPrivateNetwork: value),
              );
              // 立刻生效：配置变更会同步到已加载的插件。
              applyPrivateNetworkPolicy(blockPrivateNetwork: value);
            },
          ),
          SettingGroup.switchTile(
            leading: const GlyphIcon(AppGlyphs.download),
            title: Text(t.settings.retryDownloadUntilSuccess),
            subtitle: Text(t.settings.retryDownloadUntilSuccessSubtitle),
            value: state.retryDownloadUntilSuccess,
            onChanged: (value) {
              cubit.updateState(
                (current) => current.copyWith(retryDownloadUntilSuccess: value),
              );
            },
          ),
          // _updateAccelerate(state, cubit),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _searchBookmarkProbePages(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    const options = [0, 1, 2, 3, 5];
    final current = options.contains(state.searchBookmarkProbePages)
        ? state.searchBookmarkProbePages
        : 3;
    return ListTile(
      leading: const Icon(Icons.manage_search_outlined),
      title: Text(t.searchBookmark.probePages),
      subtitle: Text(t.searchBookmark.probePagesSubtitle),
      trailing: FluentDropdown<int>(
        value: current,
        displayValue: '$current',
        items: {for (final v in options) v: '$v'},
        onChanged: (int value) {
          cubit.updateState(
            (current) => current.copyWith(searchBookmarkProbePages: value),
          );
        },
      ),
    );
  }

  Widget _chineseConvertMode(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    final chineseConvertItems = <ChineseConvertMode, String>{
      ChineseConvertMode.off: t.settings.chineseConvertOff,
      ChineseConvertMode.simplified: t.settings.chineseConvertSimplified,
      ChineseConvertMode.traditional: t.settings.chineseConvertTraditional,
    };

    return ListTile(
      leading: const GlyphIcon(AppGlyphs.translate),
      title: Text(t.settings.chineseConvert),
      subtitle: Text(t.settings.chineseConvertSubtitle),
      trailing: FluentDropdown<ChineseConvertMode>(
        value: state.chineseConvertMode,
        displayValue: chineseConvertItems[state.chineseConvertMode]!,
        items: chineseConvertItems,
        onChanged: (ChineseConvertMode value) {
          if (value == state.chineseConvertMode) return;
          cubit.updateState(
            (current) => current.copyWith(chineseConvertMode: value),
          );
        },
      ),
    );
  }

  // Widget _updateAccelerate(GlobalSettingState state, GlobalSettingCubit cubit) {
  //   return SettingGroup.switchTile(
  //     leading: const GlyphIcon(AppGlyphs.rocket),
  //     title: Text(t.settings.updateAccelerate),
  //     subtitle: Text(t.settings.updateAccelerateSubtitle),
  //     value: state.updateAccelerate,
  //     onChanged: (bool value) {
  //       cubit.updateState(
  //         (current) => current.copyWith(updateAccelerate: value),
  //       );
  //     },
  //   );
  // }
}
