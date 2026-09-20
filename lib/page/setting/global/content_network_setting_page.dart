import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/setting/global/widgets.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';

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
        children: [
          settingSectionTitle(
            context,
            t.settings.content,
            icon: Icons.filter_alt_outlined,
          ),
          editMaskedKeywords(context),
          ListTile(
            leading: const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
            title: Text(t.settings.favoriteArtistManagement),
            subtitle: Text(
              state.favoriteArtistSetting.artists.isEmpty
                  ? t.settings.favoriteArtistManagementSubtitleEmpty
                  : t.settings.favoriteArtistManagementSubtitle(
                      count: state.favoriteArtistSetting.artists.length,
                    ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              context.pushRoute(const FavoriteArtistSettingRoute());
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.highlight_outlined),
            title: Text(t.settings.favoriteArtistHighlight),
            subtitle: Text(t.settings.favoriteArtistHighlightSubtitle),
            thumbIcon: kSettingSwitchThumbIcon,
            value: state.favoriteArtistSetting.highlightEnabled,
            onChanged: (value) {
              cubit.toggleHighlightFavoriteArtists(value);
            },
          ),
          ListTile(
            leading: const Icon(Icons.sell, color: Color(0xFFF59E0B)),
            title: Text(t.settings.favoriteTagManagement),
            subtitle: Text(
              state.favoriteTagSetting.tags.isEmpty
                  ? t.settings.favoriteTagManagementSubtitleEmpty
                  : t.settings.favoriteTagManagementSubtitle(
                      count: state.favoriteTagSetting.tags.length,
                    ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              context.pushRoute(const FavoriteTagSettingRoute());
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.highlight_outlined),
            title: Text(t.settings.favoriteTagHighlight),
            subtitle: Text(t.settings.favoriteTagHighlightSubtitle),
            thumbIcon: kSettingSwitchThumbIcon,
            value: state.favoriteTagSetting.highlightEnabled,
            onChanged: (value) {
              cubit.toggleHighlightFavoriteTags(value);
            },
          ),
          _chineseConvertMode(state, cubit),

          const SizedBox(height: 8),
          const Divider(height: 1, thickness: 0.3),
          settingSectionTitle(
            context,
            t.settings.network,
            icon: Icons.wifi_outlined,
          ),
          proxyToggle(
            context,
            enabled: state.proxySetting.enabled,
            type: state.proxySetting.type,
            currentProxy: state.proxySetting.address,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.download_outlined),
            title: Text(t.settings.retryDownloadUntilSuccess),
            subtitle: Text(t.settings.retryDownloadUntilSuccessSubtitle),
            thumbIcon: kSettingSwitchThumbIcon,
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
      leading: const Icon(Icons.translate_outlined),
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
  //   return SwitchListTile(
  //     secondary: const Icon(Icons.rocket_launch_outlined),
  //     title: Text(t.settings.updateAccelerate),
  //     subtitle: Text(t.settings.updateAccelerateSubtitle),
  //     thumbIcon: kSettingSwitchThumbIcon,
  //     value: state.updateAccelerate,
  //     onChanged: (bool value) {
  //       cubit.updateState(
  //         (current) => current.copyWith(updateAccelerate: value),
  //       );
  //     },
  //   );
  // }
}
