import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_info/method/get_plugin_detail.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_primitives.dart';
import 'package:zephyr/page/download/method/comic_download_entry.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/toast.dart';
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
/// 默认行为：若未开启 [promptDownloadOptions] 或总章节数 <= 1（单集），直接下载整本。
/// 开启后且为多章节漫画时，弹窗提供三选（整本 / 最近 N 章 / 手动挑选）。
Future<void> promptAndRunComicDownload(
  BuildContext context, {
  required String from,
  required String comicId,
  required String comicName,
  dynamic comicInfo,
  int chapterCount = 0,
  required VoidCallback onOpenChapterPicker,
}) async {
  final promptSetting = globalSetting.promptDownloadOptions;

  // 1. 如果总开关未开启，或者已明确为单集（chapterCount == 1），直接整本下载，不打扰用户
  if (!shouldPromptComicDownloadOptions(
    promptDownloadOptions: promptSetting,
    chapterCount: chapterCount,
  )) {
    if (!promptSetting || chapterCount == 1) {
      await startComicDownloadAll(
        context: context,
        from: from,
        comicId: comicId,
        comicName: comicName,
        comicInfo: comicInfo,
      );
      return;
    }
  }

  // 2. 此时总开关已开启，但如果外部没有传入 chapterCount（例如卡片上的角标，chapterCount <= 0），
  // 需要先解析章节确认是否真的有多话。如果实际只有单集（<= 1），依然直接整本下载不弹窗。
  List<UnifiedComicChapterRef>? resolvedRefs;
  var effectiveCount = chapterCount;
  if (effectiveCount <= 0) {
    resolvedRefs = await resolveDownloadChapterRefs(
      from: from,
      comicId: comicId,
      comicInfo: comicInfo,
    );
    if (!context.mounted) return;
    if (resolvedRefs.isEmpty) {
      showErrorToast(t.error.operationFailed);
      return;
    }
    effectiveCount = resolvedRefs.length;
    if (!shouldPromptComicDownloadOptions(
      promptDownloadOptions: promptSetting,
      chapterCount: effectiveCount,
    )) {
      await startComicDownloadAll(
        context: context,
        from: from,
        comicId: comicId,
        comicName: comicName,
        comicInfo: comicInfo,
        chapterRefs: resolvedRefs,
      );
      return;
    }
  }

  final result = await showComicDownloadOptions(
    context,
    chapterCount: effectiveCount,
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
        chapterRefs: resolvedRefs,
      );
    case ComicDownloadChoice.latest:
      await startComicDownloadLatest(
        context: context,
        from: from,
        comicId: comicId,
        comicName: comicName,
        comicInfo: comicInfo,
        chapterRefs: resolvedRefs,
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
