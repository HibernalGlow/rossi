import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_primitives.dart';
import 'package:zephyr/page/download/method/comic_download_entry.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/util/context/context_extensions.dart';

/// 首次点「下载」时要哪一批章节。
enum ComicDownloadChoice {
  /// 整本（本地已有的仍由闸门跳过）。
  wholeBook,

  /// 最近 N 章。
  latest,

  /// 进章节选择页逐章勾。
  picker,
}

/// 选择面板的一次结果：选了什么方式，以及「最近 N 章」里的 N。
class ComicDownloadOptionsResult {
  const ComicDownloadOptionsResult({
    required this.choice,
    this.latestCount = kDefaultLatestDownloadCount,
  });

  final ComicDownloadChoice choice;
  final int latestCount;
}

/// 问清楚「这次要下什么」再动手，并把选中的方式执行掉。
///
/// 旧行为是：新漫画第一次点下载 = 立刻把整本塞进队列，想挑章节得长按才能找到
/// 入口。100+ 章的本被误点一下就是 100 个任务，所以这里改成显式三选，
/// 详情页与列表卡片两个入口共用同一份。
Future<void> promptAndRunComicDownload(
  BuildContext context, {
  required String from,
  required String comicId,
  required String comicName,
  dynamic comicInfo,
  int chapterCount = 0,
  required VoidCallback onOpenChapterPicker,
}) async {
  final result = await showComicDownloadOptions(
    context,
    chapterCount: chapterCount,
  );
  if (result == null || !context.mounted) return;

  switch (result.choice) {
    case ComicDownloadChoice.wholeBook:
      await startComicDownloadAll(
        context: context,
        from: from,
        comicId: comicId,
        comicName: comicName,
        comicInfo: comicInfo,
      );
    case ComicDownloadChoice.latest:
      await startComicDownloadLatest(
        context: context,
        from: from,
        comicId: comicId,
        comicName: comicName,
        comicInfo: comicInfo,
        count: result.latestCount,
      );
    case ComicDownloadChoice.picker:
      onOpenChapterPicker();
  }
}

/// 弹出下载方式选择面板；用户取消时返回 null。
Future<ComicDownloadOptionsResult?> showComicDownloadOptions(
  BuildContext context, {
  int chapterCount = 0,
}) {
  return showPopupPanel<ComicDownloadOptionsResult>(
    context: context,
    presentation: PopupPresentation.modal,
    builder: (dialogContext) =>
        _ComicDownloadOptionsDialog(chapterCount: chapterCount),
  );
}

class _ComicDownloadOptionsDialog extends StatefulWidget {
  const _ComicDownloadOptionsDialog({required this.chapterCount});

  final int chapterCount;

  @override
  State<_ComicDownloadOptionsDialog> createState() =>
      _ComicDownloadOptionsDialogState();
}

class _ComicDownloadOptionsDialogState
    extends State<_ComicDownloadOptionsDialog> {
  int _latestCount = kDefaultLatestDownloadCount;

  void _pick(ComicDownloadChoice choice) {
    Navigator.of(context).pop(
      ComicDownloadOptionsResult(choice: choice, latestCount: _latestCount),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;

    return PopupPanel(
      title: Text(t.download.optionsTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OptionTile(
            title: t.download.optionWholeBook,
            subtitle: widget.chapterCount > 0
                ? t.download.optionWholeBookCounted(count: widget.chapterCount)
                : t.download.optionWholeBookPlain,
            onTap: () => _pick(ComicDownloadChoice.wholeBook),
          ),
          _OptionTile(
            title: t.download.optionLatest(count: _latestCount),
            subtitle: t.download.optionLatestSubtitle,
            onTap: () => _pick(ComicDownloadChoice.latest),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final count in kLatestDownloadCountChoices)
                  SettingsChoiceChip(
                    title: '$count',
                    selected: count == _latestCount,
                    onTap: () => setState(() => _latestCount = count),
                  ),
              ],
            ),
          ),
          _OptionTile(
            title: t.download.optionPicker,
            subtitle: t.download.optionPickerPlain,
            onTap: () => _pick(ComicDownloadChoice.picker),
          ),
          const SizedBox(height: 4),
          Text(
            t.download.optionSkipHint,
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            t.common.cancel,
            style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
      ),
      onTap: onTap,
    );
  }
}
