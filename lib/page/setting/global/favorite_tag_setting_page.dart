import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/util/comic/favorite_tag_matcher.dart';
import 'package:zephyr/util/text/tag_text.dart';
import 'package:zephyr/widgets/toast.dart';

/// 收藏 tag 管理页。
///
/// 与 `FavoriteArtistSettingPage` 同一档位，多出来的一件事是**别名**：
/// 一个 tag 在各个图源里拼法不同，只登记一个名字就会在别的站上不亮。
/// 输入语法统一为 `本名 | 别名 | 别名`，手动添加、批量导入、文件导入三处共用，
/// 避免出现第二套「用户以为能写、其实解析不出来」的格式。
@RoutePage()
class FavoriteTagSettingPage extends StatefulWidget {
  const FavoriteTagSettingPage({super.key});

  @override
  State<FavoriteTagSettingPage> createState() => _FavoriteTagSettingPageState();
}

/// 一行文本 → 一条收藏：`|` 前是本名，其后都是别名。
FavoriteTag? parseFavoriteTagLine(String line) {
  final parts = line.split('|').map((p) => p.trim()).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return null;
  final name = parts.first;
  if (TagText.normalize(name).isEmpty) return null;
  return FavoriteTag(name: name, aliases: parts.skip(1).toList());
}

/// 从文件、批量文本或 JSON 里解析出收藏列表。
///
/// 字符串按行（`|` 语法）、`List` 逐元素、`{"tags": [...]}` 与单条
/// `{name, aliases}` 对象也都吃。分行只在这里做一次：批量导入与文件导入共用，
/// 免得两处各写一份分隔符理解而漂开。
List<FavoriteTag> parseFavoriteTags(dynamic decoded) {
  final raw = <dynamic>[];
  if (decoded is String) {
    raw.addAll(decoded.split(RegExp(r'[\r\n]+')));
  } else if (decoded is List) {
    raw.addAll(decoded);
  } else if (decoded is Map && decoded['tags'] is List) {
    raw.addAll(decoded['tags'] as List);
  } else if (decoded is Map && decoded['aliases'] is List) {
    raw.add(decoded);
  }
  final tags = <FavoriteTag>[];
  for (final entry in raw) {
    if (entry is Map && entry['name'] is String) {
      final aliases = entry['aliases'];
      tags.add(
        FavoriteTag(
          name: (entry['name'] as String).trim(),
          aliases: aliases is List
              ? aliases.map((a) => a.toString()).toList()
              : const [],
        ),
      );
      continue;
    }
    final tag = parseFavoriteTagLine(entry.toString());
    if (tag != null) tags.add(tag);
  }
  return tags;
}

class _FavoriteTagSettingPageState extends State<FavoriteTagSettingPage> {
  final TextEditingController _addController = TextEditingController();
  final TextEditingController _filterController = TextEditingController();
  String _filterKeyword = '';

  @override
  void dispose() {
    _addController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  /// 已经收藏过了吗？本名与别名一起算（否则用户会以为「加了没反应」）。
  bool _alreadyFavorited(
    FavoriteTagSettingState setting,
    Iterable<String> keys,
  ) {
    final index = FavoriteTagMatcher.buildAliasIndex(setting.tags);
    return keys.any((key) => index.containsKey(key) && key.isNotEmpty);
  }

  void _handleAdd(BuildContext context) {
    final text = _addController.text.trim();
    if (text.isEmpty) return;

    final cubit = context.read<GlobalSettingCubit>();
    final setting = cubit.state.favoriteTagSetting;
    final parsed = parseFavoriteTagLine(text);
    if (parsed == null) return;

    final index = FavoriteTagMatcher.buildAliasIndex(setting.tags);
    final nameKey = TagText.normalize(parsed.name);
    // 本名撞上与别名撞上要分开说：本名撞上「不新建条目」是对的，
    // 别名撞上别人（或撞回本名）时只丢那个别名 —— 一起报「已收藏过」会让人
    // 以为整条都没存下，其实本名新建成功了、只是那个别名没并进。
    final collidedAliases = parsed.aliases
        .map(TagText.normalize)
        .where((k) => k.isNotEmpty && k != nameKey && index.containsKey(k))
        .toList();

    if (index.containsKey(nameKey)) {
      showInfoToast(t.settings.favoriteTagAlreadyAdded(name: parsed.name));
    } else {
      cubit.addFavoriteTag(parsed.name);
      showSuccessToast(t.settings.favoriteTagAdded(name: parsed.name));
    }
    for (final alias in parsed.aliases) {
      cubit.addFavoriteTagAlias(parsed.name, alias);
    }
    if (collidedAliases.isNotEmpty) {
      showInfoToast(t.settings.favoriteTagAliasDuplicate);
    }
    _addController.clear();
  }

  Future<void> _showBatchImportDialog(
    BuildContext context,
    List<FavoriteTag> current,
  ) async {
    final asText = current
        .map(
          (tag) => tag.aliases.isEmpty
              ? tag.name
              : '${tag.name} | ${tag.aliases.join(' | ')}',
        )
        .join('\n');
    final controller = TextEditingController(text: asText);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.settings.favoriteTagBatchImport),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.settings.favoriteTagBatchImportHint,
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
                  hintText: 'school_lolita | 学校萝莉 | School Lolita\nloli',
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

    if (result == null || !context.mounted) return;
    // 「批量导入/编辑」是**整表编辑**：弹窗里预填的就是当前全表，所以这里替换而不是合并。
    final tags = parseFavoriteTags(result);
    context.read<GlobalSettingCubit>().setFavoriteTags(tags);
    showSuccessToast(t.settings.favoriteTagImportSuccess(count: tags.length));
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
      List<FavoriteTag> imported = const [];
      if (file.name.toLowerCase().endsWith('.json')) {
        try {
          imported = parseFavoriteTags(jsonDecode(content));
        } catch (_) {}
      }
      // 不是 JSON（或 JSON 里啥也没解析出来）就按纯文本逐行读。
      if (imported.isEmpty) imported = parseFavoriteTags(content);
      if (!context.mounted) return;

      final cubit = context.read<GlobalSettingCubit>();
      cubit.setFavoriteTags([
        ...cubit.state.favoriteTagSetting.tags,
        ...imported,
      ]);
      showSuccessToast(
        t.settings.favoriteTagImportSuccess(count: imported.length),
      );
    } catch (e) {
      showErrorToast('导入失败: $e');
    }
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.settings.favoriteTagClear),
        content: Text(t.settings.favoriteTagClearConfirm),
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
      context.read<GlobalSettingCubit>().setFavoriteTags([]);
    }
  }

  Future<void> _showAliasDialog(BuildContext context, FavoriteTag tag) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${t.settings.favoriteTagAliasAdd} · ${tag.name}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.settings.favoriteTagAliasHint,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: t.settings.favoriteTagAliasInputHint,
                ),
                onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
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

    final alias = result?.trim() ?? '';
    if (alias.isEmpty || !context.mounted) return;
    final cubit = context.read<GlobalSettingCubit>();
    final setting = cubit.state.favoriteTagSetting;
    final key = TagText.normalize(alias);
    final entryKey = TagText.normalize(tag.name);
    // 与别人的本名/别名撞号，或与本名同形 ⇒ 加了也是白加，直接说清楚。
    if (key.isEmpty || key == entryKey || _alreadyFavorited(setting, [key])) {
      showInfoToast(t.settings.favoriteTagAliasDuplicate);
      return;
    }
    cubit.addFavoriteTagAlias(tag.name, alias);
    showSuccessToast(t.settings.favoriteTagAliasAdded(name: alias));
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final setting = cubit.state.favoriteTagSetting;
    final tags = setting.tags;

    final keyword = _filterKeyword.toLowerCase();
    final filtered = keyword.isEmpty
        ? tags
        : tags
              .where(
                (tag) =>
                    tag.name.toLowerCase().contains(keyword) ||
                    tag.aliases.any((a) => a.toLowerCase().contains(keyword)),
              )
              .toList();

    final theme = Theme.of(context);

    return SettingPageShell(
      title: t.settings.favoriteTagManagement,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.sell, color: Color(0xFFF59E0B)),
            title: Text(t.settings.favoriteTagHighlight),
            subtitle: Text(t.settings.favoriteTagHighlightSubtitle),
            thumbIcon: kSettingSwitchThumbIcon,
            value: setting.highlightEnabled,
            onChanged: cubit.toggleHighlightFavoriteTags,
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, thickness: 0.3),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _addController,
                  decoration: InputDecoration(
                    hintText: t.settings.favoriteTagInputHint,
                    prefixIcon: const Icon(Icons.sell_outlined),
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
                label: Text(t.settings.favoriteTagAdd),
                onPressed: () => _handleAdd(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t.settings.favoriteTagAliasHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),

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
                label: Text(t.settings.favoriteTagBatchImport),
                onPressed: () => _showBatchImportDialog(context, tags),
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
              if (tags.isNotEmpty)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: Text(t.settings.favoriteTagClear),
                  onPressed: () => _confirmClearAll(context),
                ),
            ],
          ),
          const SizedBox(height: 18),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${t.settings.favoriteTagManagement} (${tags.length})',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (tags.length > 8)
                SizedBox(
                  width: 160,
                  height: 36,
                  child: TextField(
                    controller: _filterController,
                    decoration: InputDecoration(
                      hintText: t.settings.favoriteTagSearchHint,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: keyword.isNotEmpty
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

          if (tags.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 48),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sell_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t.settings.favoriteTagManagementSubtitleEmpty,
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
          else if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 36),
              alignment: Alignment.center,
              child: Text(
                t.settings.favoriteTagNotFound,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            )
          else
            ...filtered.map(
              (tag) => _FavoriteTagRow(
                tag: tag,
                onAddAlias: () => _showAliasDialog(context, tag),
                onRemoveAlias: (alias) {
                  cubit.removeFavoriteTagAlias(tag.name, alias);
                  showInfoToast(
                    t.settings.favoriteTagAliasRemoved(name: alias),
                  );
                },
                onRemove: () {
                  cubit.removeFavoriteTag(tag.name);
                  showInfoToast(t.settings.favoriteTagRemoved(name: tag.name));
                },
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _FavoriteTagRow extends StatelessWidget {
  final FavoriteTag tag;
  final VoidCallback onAddAlias;
  final ValueChanged<String> onRemoveAlias;
  final VoidCallback onRemove;

  const _FavoriteTagRow({
    required this.tag,
    required this.onAddAlias,
    required this.onRemoveAlias,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF78350F).withValues(alpha: 0.22)
            : const Color(0xFFFEF3C7),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.7 : 0.9),
          width: 1.2,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sell, size: 16, color: Color(0xFFB45309)),
              const SizedBox(width: 6),
              // Flexible 而不是 Expanded：本名很长时也要给右边两颗按钮留出位置，
              // 但不能把按钮顶出屏幕。
              Flexible(
                child: Text(
                  tag.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFFFDE68A)
                        : const Color(0xFF78350F),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 16),
                tooltip: t.settings.favoriteTagAliasAdd,
                onPressed: onAddAlias,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: t.common.delete,
                onPressed: onRemove,
              ),
            ],
          ),
          if (tag.aliases.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 2),
              child: Text(
                t.settings.favoriteTagAliasEmpty,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: tag.aliases.map((alias) {
                  return Container(
                    padding: const EdgeInsets.only(
                      left: 8,
                      right: 2,
                      top: 2,
                      bottom: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(
                          0xFFF59E0B,
                        ).withValues(alpha: isDark ? 0.4 : 0.6),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          alias,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => onRemoveAlias(alias),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.close,
                              size: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
