import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';

/// 在现有卡片高度内分配文字行数，长路径不能把操作或摘要推出边界。
class LibraryEditorialSummary extends StatelessWidget {
  const LibraryEditorialSummary({
    super.key,
    required this.entry,
    required this.spotlight,
  });
  final LibraryEntry entry;
  final bool spotlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle =
        (spotlight
                ? theme.textTheme.headlineMedium
                : theme.textTheme.titleLarge)!
            .copyWith(fontWeight: FontWeight.w700);
    final subtitleStyle = theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final descriptionStyle = theme.textTheme.bodyMedium!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final metaStyle = theme.textTheme.labelMedium!.copyWith(
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
              locale: Localizations.maybeLocaleOf(context),
              maxLines: lines,
              ellipsis: '…',
            )..layout(maxWidth: constraints.maxWidth);
            final height = painter.height;
            painter.dispose();
            if (height <= budget - .5) return (lines: lines, height: height);
          }
          return (lines: 0, height: 0);
        }

        final height = constraints.maxHeight;
        final subtitleReserve = fit(entry.subtitle, subtitleStyle, 1, height);
        var title = fit(
          entry.title,
          titleStyle,
          3,
          height - (subtitleReserve.lines > 0 ? subtitleReserve.height + 8 : 0),
        );
        // 极短卡片优先留住标题，次级文字可以省略。
        if (title.lines == 0) title = fit(entry.title, titleStyle, 1, height);
        var remaining = math.max(0.0, height - title.height);
        final subtitle = fit(entry.subtitle, subtitleStyle, 1, remaining - 8);
        if (subtitle.lines > 0) remaining -= subtitle.height + 8;
        final showProgress = entry.progress != null && remaining >= 16;
        final progressHeight = showProgress ? 16.0 : 0.0;
        final meta = fit(
          entry.metaText,
          metaStyle,
          1,
          remaining - progressHeight,
        );
        final description = fit(
          spotlight ? entry.description : null,
          descriptionStyle,
          3,
          remaining - progressHeight - meta.height - 12,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.lines > 0)
              Text(
                entry.title,
                maxLines: title.lines,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            if (subtitle.lines > 0) ...[
              const SizedBox(height: 8),
              Text(
                entry.subtitle!,
                maxLines: subtitle.lines,
                overflow: TextOverflow.ellipsis,
                style: subtitleStyle,
              ),
            ],
            if (description.lines > 0) ...[
              const SizedBox(height: 12),
              Text(
                entry.description!,
                maxLines: description.lines,
                overflow: TextOverflow.ellipsis,
                style: descriptionStyle,
              ),
            ],
            if (showProgress) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: entry.progress!.clamp(0.0, 1.0),
                minHeight: 4,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
            const Spacer(),
            if (meta.lines > 0)
              Text(
                entry.metaText!,
                maxLines: meta.lines,
                overflow: TextOverflow.ellipsis,
                style: metaStyle,
              ),
          ],
        );
      },
    );
  }
}
