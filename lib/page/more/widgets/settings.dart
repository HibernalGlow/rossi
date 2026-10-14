import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_follow/cubit/comic_follow_cubit.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/icons/icons.dart';

class SettingsWidget extends StatelessWidget {
  const SettingsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    // 「更多」页自己不是设置页（顶上还有头像区），所以这里只给分组卡留出
    // 与设置页同宽的左右边距，不换成 SettingPageShell。
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
                        if (updateCount > 0) _UpdateBadge(count: updateCount),
                        const GlyphIcon(AppGlyphs.chevronForward),
                      ],
                    ),
                    onTap: () => context.pushRoute(ComicFollowRoute()),
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
              ListTile(
                leading: const GlyphIcon(AppGlyphs.history),
                title: Text(t.more.changelog),
                trailing: const GlyphIcon(AppGlyphs.chevronForward),
                onTap: () => context.pushRoute(ChangelogRoute()),
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

class _UpdateBadge extends StatelessWidget {
  const _UpdateBadge({required this.count});

  final int count;

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
        count >= 99 ? '99+' : 'NEW',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onError,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
