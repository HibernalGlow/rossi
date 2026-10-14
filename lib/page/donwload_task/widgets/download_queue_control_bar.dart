import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_primitives.dart';
import 'package:zephyr/page/donwload_task/models/download_queue_overview.dart';
import 'package:zephyr/page/donwload_task/models/download_task_comic_scope.dart';
import 'package:zephyr/page/donwload_task/models/download_task_view_filter.dart';
import 'package:zephyr/util/context/context_extensions.dart';

/// 队列剩余量 + 按漫画分组 + 状态筛选，一行胶囊，放不下就换行。
///
/// 概览说「这批还要跑多少」，分组说「先看哪一本」，筛选说「先只看哪一类」：
/// 80 章的队列里逐条滚到失败那几条，和关掉网络带宽前想一眼看清还剩几章，
/// 都是在这里办的事。
class DownloadQueueControlBar extends StatelessWidget {
  const DownloadQueueControlBar({
    super.key,
    required this.overview,
    required this.filter,
    required this.onFilterChanged,
    this.comics = const [],
    this.selectedComicId,
    this.onComicScopeChanged,
  });

  final DownloadQueueOverview overview;
  final DownloadTaskViewFilter filter;
  final ValueChanged<DownloadTaskViewFilter> onFilterChanged;

  /// 队列里出现的漫画；只有一本时不画这一排（那颗胶囊只会占位，不会帮你找到东西）。
  final List<DownloadTaskComicGroup> comics;
  final String? selectedComicId;
  final ValueChanged<String?>? onComicScopeChanged;

  @override
  Widget build(BuildContext context) {
    final showComicScope = comics.length > 1 && onComicScopeChanged != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        alignment: WrapAlignment.start,
        children: [
          _StatPill(
            text: t.download.overviewRemaining(count: overview.remainingTasks),
          ),
          if (overview.hasPageProgress)
            _StatPill(
              text: t.download.overviewPages(
                done: overview.completedImages,
                total: overview.totalImages,
              ),
            ),
          if (overview.failed > 0)
            _StatPill(
              text: t.download.overviewFailed(count: overview.failed),
              tone: _StatTone.error,
            ),
          if (showComicScope) ...[
            SettingsChoiceChip(
              title: t.download.comicScopeAll,
              selected: selectedComicId == null,
              onTap: () => onComicScopeChanged!(null),
            ),
            for (final comic in comics)
              SettingsChoiceChip(
                title: t.download.comicScopeCounted(
                  name: comic.comicName,
                  count: comic.taskCount,
                ),
                selected: comic.comicId == selectedComicId,
                onTap: () => onComicScopeChanged!(comic.comicId),
              ),
          ],
          for (final candidate in DownloadTaskViewFilter.values)
            SettingsChoiceChip(
              title: candidate.label,
              selected: candidate == filter,
              onTap: () => onFilterChanged(candidate),
            ),
        ],
      ),
    );
  }
}

enum _StatTone { neutral, error }

class _StatPill extends StatelessWidget {
  const _StatPill({required this.text, this.tone = _StatTone.neutral});

  final String text;
  final _StatTone tone;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;
    final isError = tone == _StatTone.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isError
            ? colorScheme.errorContainer
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isError
              ? colorScheme.onErrorContainer
              : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
