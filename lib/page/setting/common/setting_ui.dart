import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/setting/common/setting_detail_scope.dart';
import 'package:zephyr/page/setting/common/setting_group.dart';

const EdgeInsets kSettingPagePadding = EdgeInsets.fromLTRB(16, 12, 16, 24);

// Switch.thumbIcon 的签名锁死 `WidgetStateProperty<Icon>`（Material Icon widget，
// 内部要 IconData）—— glyph 体系覆盖不到这个槽位，是框架 API 的硬限制，
// 这两颗保留 Material 图标（全仓仅此一处豁免）。
const WidgetStateProperty<Icon> kSettingSwitchThumbIcon =
    WidgetStateProperty<Icon>.fromMap(<WidgetStatesConstraint, Icon>{
      WidgetState.selected: Icon(Icons.check),
      WidgetState.any: Icon(Icons.close),
    });

/// 设置页统一外壳：AppBar + 居中限宽内容区。
class SettingPageShell extends StatelessWidget {
  const SettingPageShell({
    super.key,
    required this.title,
    required this.child,
    this.maxWidth = 768,
  });

  final String title;
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final embedded = SettingDetailScope.isEmbedded(context);
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
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: Align(
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
        ),
      ),
    );
  }
}

Widget settingSectionTitle(BuildContext context, String title, {Glyph? icon}) {
  return Padding(
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
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final Glyph icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SettingGroup(title: title, icon: icon, children: children);
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
