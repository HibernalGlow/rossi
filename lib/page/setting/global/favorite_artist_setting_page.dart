import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/util/comic/favorite_artist_matcher.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/toast.dart';

@RoutePage()
class FavoriteArtistSettingPage extends StatefulWidget {
  const FavoriteArtistSettingPage({super.key});

  @override
  State<FavoriteArtistSettingPage> createState() =>
      _FavoriteArtistSettingPageState();
}

class _FavoriteArtistSettingPageState extends State<FavoriteArtistSettingPage> {
  final TextEditingController _addController = TextEditingController();
  final TextEditingController _filterController = TextEditingController();
  String _filterKeyword = '';

  /// 社团名那一档的三档文案；`fallbackOnly` 是默认，也是「社团名最容易撞上汉化组」时的安全档。
  Map<FavoriteArtistCircleMode, String> get _circleModeLabels => {
    FavoriteArtistCircleMode.off: t.settings.favoriteArtistCircleOff,
    FavoriteArtistCircleMode.fallbackOnly:
        t.settings.favoriteArtistCircleFallback,
    FavoriteArtistCircleMode.independent:
        t.settings.favoriteArtistCircleIndependent,
  };

  @override
  void dispose() {
    _addController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  void _handleAdd(BuildContext context) {
    final text = _addController.text.trim();
    if (text.isEmpty) return;

    final cubit = context.read<GlobalSettingCubit>();
    cubit.addFavoriteArtist(text);
    _addController.clear();
    showSuccessToast(t.settings.addedToFavoriteArtist(name: text));
  }

  Future<void> _showBatchImportDialog(
    BuildContext context,
    List<String> currentArtists,
  ) async {
    final controller = TextEditingController(text: currentArtists.join('\n'));
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.settings.favoriteArtistBatchImport),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.settings.favoriteArtistBatchImportHint,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 10,
                minLines: 5,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: '武田弘光\n[circle (artist)]\n水龙敬',
                  filled: true,
                  fillColor: Theme.of(
                    dialogContext,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(t.common.confirm),
          ),
        ],
      ),
    );

    if (result != null && context.mounted) {
      // 原文照存：`[社团 (画师)]` 里两个名字都要参与匹配，
      // 在这里压成画师名就等于把社团名丢了。
      final parsed = result
          .split(RegExp(r'[\r\n,]+'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      context.read<GlobalSettingCubit>().setFavoriteArtists(parsed);
      showSuccessToast(
        t.settings.favoriteArtistImportSuccess(count: parsed.length),
      );
    }
  }

  Future<void> _importFromFile(BuildContext context) async {
    try {
      const typeGroup = XTypeGroup(
        label: 'text',
        extensions: ['txt', 'csv', 'json'],
      );
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;

      final content = await file.readAsString();
      final lines = <String>[];

      if (file.name.toLowerCase().endsWith('.json')) {
        try {
          final dynamic decoded = jsonDecode(content);
          if (decoded is List) {
            lines.addAll(decoded.map((e) => e.toString()));
          } else if (decoded is Map && decoded['artists'] is List) {
            lines.addAll((decoded['artists'] as List).map((e) => e.toString()));
          }
        } catch (_) {}
      }

      if (lines.isEmpty) {
        lines.addAll(content.split(RegExp(r'[\r\n,]+')));
      }

      final parsed = <String>[];
      for (final line in lines) {
        final trimmed = line.replaceFirst(RegExp(r'^\s*[-*•]\s*'), '').trim();
        if (trimmed.isEmpty) continue;
        parsed.add(trimmed);
      }

      if (context.mounted) {
        final cubit = context.read<GlobalSettingCubit>();
        final current = cubit.state.favoriteArtistSetting.artists;
        final merged = [...current, ...parsed];
        cubit.setFavoriteArtists(merged);
        showSuccessToast(
          t.settings.favoriteArtistImportSuccess(count: parsed.length),
        );
      }
    } catch (e) {
      showErrorToast('导入失败: $e');
    }
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.settings.favoriteArtistClear),
        content: Text(t.settings.favoriteArtistClearConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t.common.confirm),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final count = context
          .read<GlobalSettingCubit>()
          .state
          .favoriteArtistSetting
          .artists
          .length;
      context.read<GlobalSettingCubit>().setFavoriteArtists([]);
      showSuccessToast(t.bookshelf.deletedRecords(count: count));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final setting = cubit.state.favoriteArtistSetting;
    final artists = setting.artists;

    final filteredArtists = _filterKeyword.isEmpty
        ? artists
        : artists
              .where(
                (a) => a.toLowerCase().contains(_filterKeyword.toLowerCase()),
              )
              .toList();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SettingPageShell(
      title: t.settings.favoriteArtistManagement,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
            title: Text(t.settings.favoriteArtistHighlight),
            subtitle: Text(t.settings.favoriteArtistHighlightSubtitle),
            thumbIcon: kSettingSwitchThumbIcon,
            value: setting.highlightEnabled,
            onChanged: (value) {
              cubit.toggleHighlightFavoriteArtists(value);
            },
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(
              Icons.groups_outlined,
              color: Color(0xFFF59E0B),
            ),
            title: Text(t.settings.favoriteArtistCircleMode),
            subtitle: Text(t.settings.favoriteArtistCircleModeSubtitle),
            trailing: FluentDropdown<FavoriteArtistCircleMode>(
              value: setting.circleMode,
              displayValue: _circleModeLabels[setting.circleMode]!,
              items: _circleModeLabels,
              onChanged: (value) {
                if (value == setting.circleMode) return;
                cubit.setFavoriteArtistCircleMode(value);
              },
            ),
          ),
          const Divider(height: 1, thickness: 0.3),
          const SizedBox(height: 16),

          // 输入新画师
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _addController,
                  decoration: InputDecoration(
                    hintText: t.settings.favoriteArtistInputHint,
                    prefixIcon: const Icon(Icons.person_add_alt_1_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (_) => _handleAdd(context),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(Icons.add),
                label: Text(t.settings.favoriteArtistAdd),
                onPressed: () => _handleAdd(context),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 批量导入与文件导入栏
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.edit_note, size: 18),
                label: Text(t.settings.favoriteArtistBatchImport),
                onPressed: () => _showBatchImportDialog(context, artists),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('导入文件 (TXT/JSON)'),
                onPressed: () => _importFromFile(context),
              ),
              if (artists.isNotEmpty)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: Text(t.settings.favoriteArtistClear),
                  onPressed: () => _confirmClearAll(context),
                ),
            ],
          ),
          const SizedBox(height: 18),

          // 数量统计与搜索过滤
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${t.settings.favoriteArtistManagement} (${artists.length})',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (artists.length > 8)
                SizedBox(
                  width: 160,
                  height: 36,
                  child: TextField(
                    controller: _filterController,
                    decoration: InputDecoration(
                      hintText: '搜索画师...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _filterKeyword.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _filterController.clear();
                                setState(() => _filterKeyword = '');
                              },
                            )
                          : null,
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (val) =>
                        setState(() => _filterKeyword = val.trim()),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // 画师标签列表
          if (artists.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 48),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.favorite_border_rounded,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t.settings.favoriteArtistManagementSubtitleEmpty,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.7,
                      ),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          else if (filteredArtists.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 36),
              alignment: Alignment.center,
              child: Text(
                '未找到匹配的画师',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: filteredArtists.map((artist) {
                return Container(
                  padding: const EdgeInsets.only(
                    left: 10,
                    right: 4,
                    top: 4,
                    bottom: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF78350F).withValues(alpha: 0.3)
                        : const Color(0xFFFEF3C7),
                    border: Border.all(
                      color: const Color(
                        0xFFF59E0B,
                      ).withValues(alpha: isDark ? 0.7 : 0.9),
                      width: 1.2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.favorite,
                        size: 14,
                        color: Color(0xFFDC2626),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        artist,
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFFFDE68A)
                              : const Color(0xFF78350F),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          cubit.removeFavoriteArtist(artist);
                          showInfoToast(
                            t.settings.removedFromFavoriteArtist(name: artist),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(2.0),
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: isDark
                                ? const Color(0xFFFDE68A).withValues(alpha: 0.8)
                                : const Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
