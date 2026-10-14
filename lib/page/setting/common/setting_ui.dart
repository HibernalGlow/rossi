import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scroll_spy/scroll_spy.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/setting/common/setting_detail_scope.dart';
import 'package:zephyr/page/setting/common/setting_group.dart';
import 'package:zephyr/page/setting/common/setting_scroll_spy.dart';

const EdgeInsets kSettingPagePadding = EdgeInsets.fromLTRB(16, 12, 16, 24);

/// 设置页统一外壳：可折叠大标题 + 居中限宽内容区 + 页内 Scroll Spy 与吸顶可展开目录胶囊。
///
/// 独立成页那一档用 `material_3_expressive` 的 flexible sliver 顶栏：进入页面先看到
/// 大标题与介绍，滚动时标题缩成顶部小栏并常驻（上游已有这条实现，不另写一遍
/// `SliverAppBar`）。双栏工作台的右栏（[SettingDetailScope.isEmbedded]）保持原来的
/// 实色小标题栏 —— 左栏选中项已经写着这一页的名字，右栏再挂一个大标题就是同屏两遍。
///
/// [description] 只放「这一项是干什么的」那种静态介绍；它排在**大标题下面、内容上面**
/// 的一条按内容定高的 sliver 里，所以长句子会自然换行、也跟随系统字号，滚动时和
/// 内容一起卷走（顶栏只留常驻的小标题）。各页目的地点开时看的是摘要
/// （语言 · 主题 那种），别拿它当介绍。
class SettingPageShell extends StatelessWidget {
  const SettingPageShell({
    super.key,
    required this.title,
    required this.child,
    this.maxWidth = 768,
    this.actions,
    this.description,
    this.collapsingTitle = true,
    this.pageId,
    this.sections = const <SettingSectionSpec>[],
  });

  final String title;
  final Widget child;
  final double maxWidth;
  final List<Widget>? actions;
  final String? description;
  final String? pageId;
  final List<SettingSectionSpec> sections;

  /// 折叠大标题是给**二级**页面的规矩（进入这一页先看清「这是哪一项、干什么用」）。
  /// 设置总入口是一级页，它下面已经有双栏浏览器自己的总览卡，再挂一个大标题就是
  /// 两遍强调 —— 那里传 false。
  final bool collapsingTitle;

  Widget _content(ThemeData theme) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: ListTileTheme(
        data: ListTileThemeData(
          minTileHeight: 64,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 4,
          ),
          titleTextStyle: theme.textTheme.titleMedium,
          subtitleTextStyle: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          iconColor: theme.colorScheme.primary,
        ),
        child: child,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final embedded = SettingDetailScope.isEmbedded(context);
    final description = this.description;

    if (!collapsingTitle) {
      return Scaffold(
        backgroundColor: embedded
            ? theme.colorScheme.surface
            : theme.colorScheme.surfaceContainerLowest,
        appBar: AppBar(
          automaticallyImplyLeading: !embedded,
          backgroundColor: embedded
              ? theme.colorScheme.surface
              : theme.colorScheme.surfaceContainerLowest,
          toolbarHeight: 72,
          title: Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          actions: actions,
          centerTitle: false,
          scrolledUnderElevation: 0,
        ),
        body: SafeArea(top: false, child: _content(theme)),
      );
    }

    if (embedded) {
      return SettingScrollSpyScope(
        pageId: pageId,
        declaredSections: sections,
        leadingInsetPx: 24.0,
        child: Builder(
          builder: (innerContext) {
            final spyController = SettingScrollSpyScope.maybeOf(innerContext);
            return Scaffold(
              backgroundColor: theme.colorScheme.surface,
              appBar: AppBar(
                automaticallyImplyLeading: false,
                backgroundColor: theme.colorScheme.surface,
                toolbarHeight: 72,
                title: Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                actions: [
                  if (spyController != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Center(
                        child: SettingStickyOutlineBar(
                          controller: spyController,
                          compact: true,
                        ),
                      ),
                    ),
                  ...?actions,
                ],
                centerTitle: false,
                scrolledUnderElevation: 0,
              ),
              body: SafeArea(top: false, child: _content(theme)),
            );
          },
        ),
      );
    }

    final pageBackground = theme.colorScheme.surfaceContainerLowest;
    final barScaler = MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.noScaling);
    return SettingScrollSpyScope(
      pageId: pageId,
      declaredSections: sections,
      leadingInsetPx: 128.0,
      child: Scaffold(
        backgroundColor: pageBackground,
        body: NestedScrollView(
          headerSliverBuilder: (headerContext, innerBoxIsScrolled) => [
            M3EAppBar.sliver(
              leading: const BackButton(),
              title: MediaQuery(
                data: barScaler,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              variant: M3EAppBarVariant.largeFlexible,
              pinned: true,
              backgroundColor: pageBackground,
              actions: actions,
            ),
            if (description != null && description.isNotEmpty)
              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Text(
                        description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            SettingStickyOutlineSliver(
              maxWidth: maxWidth,
              backgroundColor: pageBackground,
            ),
          ],
          body: SafeArea(top: false, child: _content(theme)),
        ),
      ),
    );
  }
}

Widget settingSectionTitle(
  BuildContext context,
  String title, {
  Glyph? icon,
  String? sectionId,
}) {
  final spyScope = SettingScrollSpyScope.maybeOf(context);
  final resolvedId = spyScope?.resolveAndRegisterGroup(
    explicitId: sectionId,
    title: title,
    icon: icon,
  );
  final header = Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
    child: Row(
      children: [
        if (icon != null) ...[
          GlyphIcon(
            icon,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      ],
    ),
  );
  if (resolvedId == null || spyScope == null) {
    return header;
  }
  return ScrollSpyItem<String>(
    key: ValueKey<String>('setting-spy-title:$resolvedId'),
    id: resolvedId,
    child: header,
  );
}

Widget settingCategoryTile({
  required Glyph icon,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
}) {
  return ListTile(
    leading: GlyphIcon(icon),
    title: Text(title),
    subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: const GlyphIcon(AppGlyphs.chevronForward),
    onTap: onTap,
  );
}

class SettingSectionCard extends StatelessWidget {
  const SettingSectionCard({
    super.key,
    this.sectionId,
    this.title,
    this.icon,
    required this.children,
  });

  final String? sectionId;

  /// 不给标题就是一张「无标题分组」：页面大标题已经说过这件事的，不必再报一遍。
  final String? title;
  final Glyph? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SettingGroup(
      sectionId: sectionId,
      title: title,
      icon: icon,
      children: children,
    );
  }
}

ButtonStyle settingDangerButtonStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(48),
    shape: const StadiumBorder(),
    backgroundColor: scheme.errorContainer,
    foregroundColor: scheme.onErrorContainer,
  );
}
