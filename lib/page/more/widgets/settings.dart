import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/comic_follow/cubit/comic_follow_cubit.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/service/update/check_update.dart';
import 'package:zephyr/service/update/json/github_release_json.dart';

class SettingsWidget extends StatelessWidget {
  const SettingsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingSectionCard(
            title: t.more.common,
            icon: AppGlyphs.apps,
            children: [
              ListTile(
                leading: const GlyphIcon(AppGlyphs.download),
                title: Text(t.more.downloadTasks),
                trailing: const GlyphIcon(AppGlyphs.chevronForward),
                onTap: () => context.pushRoute(DownloadTaskRoute()),
              ),
              ListTile(
                leading: const GlyphIcon(AppGlyphs.sync),
                title: Text(t.more.sync),
                trailing: const GlyphIcon(AppGlyphs.chevronForward),
                onTap: () => context.pushRoute(SyncSettingRoute()),
              ),
              BlocSelector<ComicFollowCubit, ComicFollowState, int>(
                selector: (state) => state.updateCount,
                builder: (context, updateCount) {
                  return ListTile(
                    leading: const GlyphIcon(AppGlyphs.bell),
                    title: Text(t.more.comicFollow),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (updateCount > 0) _NewBadge(count: updateCount),
                        const GlyphIcon(AppGlyphs.chevronForward),
                      ],
                    ),
                    onTap: () => context.pushRoute(ComicFollowRoute()),
                  );
                },
              ),
              BlocSelector<GlobalSettingCubit, GlobalSettingState, bool>(
                selector: (state) => state.showSearchBookmark,
                builder: (context, showSearchBookmark) {
                  if (!showSearchBookmark) {
                    return const SizedBox.shrink();
                  }
                  return ListTile(
                    leading: const GlyphIcon(AppGlyphs.bookmark),
                    title: Text(t.searchBookmark.title),
                    trailing: const GlyphIcon(AppGlyphs.chevronForward),
                    onTap: () => context.pushRoute(const SearchBookmarkRoute()),
                  );
                },
              ),
              ListTile(
                leading: const GlyphIcon(AppGlyphs.settings),
                title: Text(t.settings.globalTitle),
                trailing: const GlyphIcon(AppGlyphs.chevronForward),
                onTap: () => context.pushRoute(GlobalSettingRoute()),
              ),
            ],
          ),
          SettingSectionCard(
            title: t.more.others,
            icon: AppGlyphs.more,
            children: [
              // 检测到可用更新时在「更新日志」条目挂 NEW 徽标；只做提示，不额外发通知。
              ValueListenableBuilder<GithubReleaseJson?>(
                valueListenable: pendingAppUpdate,
                builder: (context, pendingUpdate, _) {
                  return ListTile(
                    leading: const GlyphIcon(AppGlyphs.history),
                    title: Text(t.more.changelog),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (pendingUpdate != null) const _NewBadge(),
                        const GlyphIcon(AppGlyphs.chevronForward),
                      ],
                    ),
                    onTap: () => context.pushRoute(ChangelogRoute()),
                  );
                },
              ),
              ListTile(
                leading: const GlyphIcon(AppGlyphs.info),
                title: Text(t.about.title),
                trailing: const GlyphIcon(AppGlyphs.chevronForward),
                onTap: () => context.pushRoute(AboutRoute()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 本地化的 NEW 徽标：追更未读数达到 99 时显示 99+。
class _NewBadge extends StatelessWidget {
  const _NewBadge({this.count});

  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.error,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        (count ?? 0) >= 99 ? '99+' : t.more.newBadge,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onError,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
