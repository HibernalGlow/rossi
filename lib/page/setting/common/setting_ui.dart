import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

Widget settingSectionTitle(
  BuildContext context,
  String title, {
  Glyph? icon,
}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
    child: Row(
      children: [
        if (icon != null) ...[
          GlyphIcon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
        ],
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 0.5,
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
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          ListTile(
            leading: GlyphIcon(icon),
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const Divider(height: 1),
          ..._withDividers(children),
        ],
      ),
    );
  }

  List<Widget> _withDividers(List<Widget> children) {
    final widgets = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      widgets.add(children[i]);
      if (i != children.length - 1) {
        widgets.add(const Divider(height: 1));
      }
    }
    return widgets;
  }
}

ButtonStyle settingDangerButtonStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(44),
    backgroundColor: scheme.errorContainer,
    foregroundColor: scheme.onErrorContainer,
  );
}
