import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/download/models/download_chapter.dart';

/// 章节选择页的单行：左侧勾选状态、中间章节名、右侧「本地已有」标记。
///
/// 无内部状态，勾选态由页面持有，避免控件自己存一份导致和页面不同步。
class ChapterSelectTile extends StatelessWidget {
  const ChapterSelectTile({
    super.key,
    required this.chapter,
    required this.selected,
    required this.downloaded,
    required this.onTap,
  });

  final DownloadChapter chapter;
  final bool selected;
  final bool downloaded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.5)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
              size: 22,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                chapter.displayName,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (downloaded)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.cloud_done_outlined,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
