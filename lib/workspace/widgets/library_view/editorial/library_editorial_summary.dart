import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';

/// 文字与标签融合在封面的渐变遮罩中；宽度增加信息容量，不放大标题。
class LibraryEditorialSummary extends StatelessWidget {
  const LibraryEditorialSummary({
    super.key,
    required this.entry,
    required this.spotlight,
    this.wide = false,
  });
  final LibraryEntry entry;
  final bool spotlight;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.labelLarge!.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurface,
    );
    final subtitleStyle = theme.textTheme.labelSmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        ({int lines, double height}) fit(
          String? text,
          TextStyle style,
          int limit,
          double budget,
        ) {
          if (text == null || text.isEmpty || budget <= 0) {
            return (lines: 0, height: 0);
          }
          for (var lines = limit; lines > 0; lines--) {
            final painter = TextPainter(
              text: TextSpan(text: text, style: style),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: lines,
              ellipsis: '…',
            )..layout(maxWidth: constraints.maxWidth);
            final height = painter.height;
            painter.dispose();
            if (height <= budget + .1) return (lines: lines, height: height);
          }
          return (lines: 0, height: 0);
        }

        final available = constraints.maxHeight;
        final secondary = [
          entry.subtitle,
          entry.metaText,
        ].whereType<String>().where((s) => s.isNotEmpty).toSet().join(' · ');
        final subtitle = fit(secondary, subtitleStyle, 1, available);
        final tags = wide
            ? entry.tags
                  .where((s) => s.trim().isNotEmpty)
                  .toSet()
                  .take(8)
                  .toList()
            : <String>[];
        final tagLine = fit(tags.join(' · '), subtitleStyle, 1, available);
        final tagHeight = tagLine.lines > 0 ? tagLine.height + 8 : 0.0;
        final subtitleHeight = subtitle.lines > 0 ? subtitle.height + 4 : 0.0;
        var title = fit(
          entry.title,
          titleStyle,
          wide ? 4 : 3,
          available - subtitleHeight - tagHeight,
        );
        // 字体放大后先保住标题与状态，标签让位。
        final showTags = title.lines > 0 && tagHeight > 0;
        if (title.lines == 0) {
          title = fit(
            entry.title,
            titleStyle,
            wide ? 4 : 3,
            available - subtitleHeight,
          );
        }
        if (title.lines == 0) {
          title = fit(entry.title, titleStyle, 1, available);
        }
        var remaining = math.max(0.0, available - title.height);
        final showSubtitle = subtitle.lines > 0 && remaining >= subtitleHeight;
        if (showSubtitle) remaining -= subtitleHeight;
        final showProgress =
            entry.progress != null &&
            remaining >= 8 + (showTags ? tagHeight : 0);
        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.lines > 0)
              Tooltip(
                message: entry.title,
                child: Text(
                  entry.title,
                  maxLines: title.lines,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
            if (showSubtitle) ...[
              const SizedBox(height: 4),
              Text(
                secondary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: subtitleStyle,
              ),
            ],
            if (showTags) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer.withValues(
                    alpha: .86,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  tags.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: subtitleStyle.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
            if (showProgress) ...[
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: entry.progress!.clamp(0.0, 1.0),
                minHeight: 3,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ],
        );
      },
    );
  }
}
