import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';

class BookshelfEmptyView extends StatelessWidget {
  const BookshelfEmptyView({
    super.key,
    this.title = '',
    this.icon = AppGlyphs.folder,
    this.onRefresh,
  });

  final String title;
  final Glyph icon;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () async => onRefresh?.call(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GlyphIcon(
                      icon,
                      size: 72,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title.isEmpty ? t.comicList.nothingHere : title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (onRefresh != null) ...[
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: onRefresh,
                        icon: const GlyphIcon(AppGlyphs.refresh),
                        label: Text(t.common.refresh),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
