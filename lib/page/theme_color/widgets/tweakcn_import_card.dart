// 「设置 → 外观与显示 → 导入 Tweakcn 主题」。
//
// 三件事：把粘贴的原文解析成 token 表存进**库**、在库里挑当前生效的那一项、
// 以及给一个看得见的回执（导入了几个 token、圆角多少、哪些读不出、哪些必需角色是补的）。
//
// 为什么吃**粘贴文本**而不是对接 tweakcn 的 registry URL：那要引一套网络与更新流
// （`npx shadcn add …` 是 Tailwind 项目的安装方式，对 Flutter 没有意义），
// 而用户在 tweakcn 上按「Copy CSS」拿到的东西已经足够表达一整套主题。
//
// 库与开关是两层：`tweakcnThemeJson` 存「有哪些 + 选哪个」，`tweakcnThemeEnabled`
// 存「要不要用导入的」。所以「换回内置配色」不必删主题。

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/util/theme/tweakcn_theme.dart';

@immutable
class TweakcnImportCard extends StatefulWidget {
  const TweakcnImportCard({super.key});

  @override
  State<TweakcnImportCard> createState() => _TweakcnImportCardState();
}

class _TweakcnImportCardState extends State<TweakcnImportCard> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _name = TextEditingController();

  /// 上一次操作的结果文案；null 表示没有要说的话。
  String? _notice;

  /// 回执做成**内联文案**而不是 toast：导入是低频、要看清结果的动作，
  /// 提示条飘过去就等于没说。
  @override
  void dispose() {
    _input.dispose();
    _name.dispose();
    super.dispose();
  }

  void _import(TweakcnThemeLibrary library) {
    final result = parseTweakcnTheme(_input.text);
    final theme = result.theme;
    if (theme == null) {
      setState(() => _notice = _failureText(result.failure!));
      return;
    }
    final typed = _name.text.trim();
    final next = library.withTheme(
      theme,
      name: typed.isEmpty ? defaultTweakcnThemeName(DateTime.now()) : typed,
    );
    _save(next, enabled: true);
    setState(() {
      _notice = result.skipped.isEmpty
          ? null
          : t.settings.tweakcnSkipped(keys: result.skipped.join(', '));
      _input.clear();
      _name.clear();
    });
  }

  void _save(TweakcnThemeLibrary library, {bool? enabled}) {
    context.read<GlobalSettingCubit>().updateState(
      (current) => current.copyWith(
        tweakcnThemeJson: library.encode(),
        tweakcnThemeEnabled: enabled ?? current.tweakcnThemeEnabled,
      ),
    );
  }

  String _failureText(TweakcnImportFailure failure) => switch (failure) {
    TweakcnImportFailure.empty => t.settings.tweakcnFailedEmpty,
    TweakcnImportFailure.unrecognized => t.settings.tweakcnFailedJson,
    TweakcnImportFailure.noColors => t.settings.tweakcnFailedNoColors,
  };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<GlobalSettingCubit>().state;
    final library = TweakcnThemeLibrary.decode(state.tweakcnThemeJson);
    final scheme = Theme.of(context).colorScheme;
    final active = library.activeTheme;
    final missing = _substituted(active);

    // 造型跟着设置页的既有口径：SettingSectionCard（elevation 0 + 18 圆角 +
    // 头部 ListTile + Divider）。自己再造一张 Card 就会和同页其它卡片两套样子。
    return SettingSectionCard(
      title: t.settings.tweakcnTitle,
      icon: Icons.colorize_outlined,
      children: [
        if (!library.isEmpty)
          _EntryList(
            library: library,
            onPick: (id) => _save(library.activated(id)),
            onDelete: (id) => setState(() {
              _notice = null;
              _save(library.removed(id));
            }),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.settings.tweakcnSubtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: t.settings.tweakcnNameField,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _input,
                minLines: 4,
                maxLines: 10,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: InputDecoration(
                  hintText: t.settings.tweakcnHint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton(
                    onPressed: () => _import(library),
                    child: Text(t.settings.tweakcnImport),
                  ),
                  if (active != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.settings.tweakcnApplied(
                          count: '${active.tokenCount}',
                          radius: _radiusText(active.radius),
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ],
              ),
              if (missing.isNotEmpty) ...[
                // 补值是静默的（缺 `--border` 就拿 `--input` 顶上去），不列出来的话
                // 用户只会觉得「描边怎么没了」而查不到原因。
                const SizedBox(height: 4),
                Text(
                  t.settings.tweakcnFallbackRoles(roles: missing.join(', ')),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (active != null) ...[
                const SizedBox(height: 8),
                _TokenSwatches(
                  theme: active,
                  brightness: Theme.of(context).brightness,
                ),
              ],
              if (_notice != null) ...[
                const SizedBox(height: 8),
                Text(
                  _notice!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: scheme.error),
                ),
              ],
            ],
          ),
        ),
        if (!library.isEmpty)
          SwitchListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            value: state.tweakcnThemeEnabled,
            title: Text(t.settings.tweakcnEnabled),
            onChanged: (enabled) => _save(library, enabled: enabled),
          ),
      ],
    );
  }

  String _radiusText(double? radius) => radius == null
      ? t.settings.tweakcnNoRadius
      : '${radius.toStringAsFixed(0)}px';

  /// 深浅两套里缺的必需角色取并集，按 [kTweakcnRequiredTokens] 的顺序。
  List<String> _substituted(TweakcnTheme? theme) {
    if (theme == null) return const [];
    final missing = {
      ...theme.missingRequiredTokens(Brightness.light),
      ...theme.missingRequiredTokens(Brightness.dark),
    };
    return [
      for (final key in kTweakcnRequiredTokens)
        if (missing.contains(key)) key, //
    ];
  }
}

/// 已保存的主题列表：一行一个，点一下即为当前生效项，尾部删除。
class _EntryList extends StatelessWidget {
  const _EntryList({
    required this.library,
    required this.onPick,
    required this.onDelete,
  });

  final TweakcnThemeLibrary library;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            t.settings.tweakcnPickHint,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        for (final entry in library.entries)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListTile(
              dense: true,
              selected: entry.id == library.activeId,
              leading: Icon(
                entry.id == library.activeId
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                color: entry.id == library.activeId ? scheme.primary : null,
              ),
              title: Text(entry.name),
              subtitle: Text(
                t.settings.tweakcnEntryMeta(
                  count: '${entry.theme.tokenCount}',
                  radius: entry.theme.radius == null
                      ? t.settings.tweakcnNoRadius
                      : '${entry.theme.radius!.toStringAsFixed(0)}px',
                ),
              ),
              trailing: IconButton(
                tooltip: t.settings.tweakcnDelete,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => onDelete(entry.id),
              ),
              onTap: () => onPick(entry.id),
            ),
          ),
      ],
    );
  }
}

/// 关键 token 的色卡：导入完一眼能看出「哪几个真的生效了」。
class _TokenSwatches extends StatelessWidget {
  const _TokenSwatches({required this.theme, required this.brightness});

  final TweakcnTheme theme;
  final Brightness brightness;

  static const List<String> _keys = [
    'background',
    'foreground',
    'primary',
    'secondary',
    'muted',
    'accent',
    'border',
    'destructive',
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = theme.tokensOrFallback(brightness);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final key in _keys)
          if (tokens[key] != null)
            Tooltip(
              message: key,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: tokens[key],
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
