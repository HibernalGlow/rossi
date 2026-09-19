// 「设置 → 主题颜色 → 导入 Tweakcn 主题」。
//
// 只做三件事：把粘贴的原文解析成 token 表、落地到 `GlobalSettingState`、
// 以及给一个**看得见的回执**（导入了几个 token、圆角多少、哪些被跳过）。
//
// 为什么吃**粘贴文本**而不是直接对接 tweakcn 的 registry URL：那要引一套网络与
// 更新流（`npx shadcn add …` 那套是 Tailwind 项目的安装方式，对 Flutter 没有意义），
// 而用户在 tweakcn 界面上按「Copy CSS」拿到的东西已经足够表达一整套主题。

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/util/theme/tweakcn_theme.dart';

@immutable
class TweakcnImportCard extends StatefulWidget {
  const TweakcnImportCard({super.key});

  @override
  State<TweakcnImportCard> createState() => _TweakcnImportCardState();
}

class _TweakcnImportCardState extends State<TweakcnImportCard> {
  final TextEditingController _input = TextEditingController();

  /// 上一次操作的结果文案；null 表示没有要说的话。
  String? _notice;

  /// 回执做成**内联文案**而不是 toast：导入是低频、要看清结果的动作，
  /// 提示条飘过去就等于没说。
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _import() {
    final result = parseTweakcnTheme(_input.text);
    final theme = result.theme;
    if (theme == null) {
      setState(() => _notice = _failureText(result.failure!));
      return;
    }
    context.read<GlobalSettingCubit>().updateState(
      (current) => current.copyWith(
        tweakcnThemeJson: theme.encode(),
        tweakcnThemeEnabled: true,
      ),
    );
    setState(() {
      _notice = result.skipped.isEmpty
          ? null
          : t.settings.tweakcnSkipped(keys: result.skipped.join(', '));
      _input.clear();
    });
  }

  void _clear() {
    context.read<GlobalSettingCubit>().updateState(
      (current) =>
          current.copyWith(tweakcnThemeJson: '', tweakcnThemeEnabled: false),
    );
    setState(() => _notice = null);
  }

  String _failureText(TweakcnImportFailure failure) => switch (failure) {
    TweakcnImportFailure.empty => t.settings.tweakcnFailedEmpty,
    TweakcnImportFailure.unrecognized => t.settings.tweakcnFailedJson,
    TweakcnImportFailure.noColors => t.settings.tweakcnFailedNoColors,
  };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<GlobalSettingCubit>().state;
    final theme = TweakcnTheme.decode(state.tweakcnThemeJson);
    final scheme = Theme.of(context).colorScheme;
    final hasTheme = theme != null && !theme.isEmpty;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.settings.tweakcnTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              t.settings.tweakcnSubtitle,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _input,
              minLines: 4,
              maxLines: 10,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: InputDecoration(
                hintText: t.settings.tweakcnHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  onPressed: _import,
                  child: Text(t.settings.tweakcnImport),
                ),
                if (hasTheme) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _clear,
                    child: Text(t.settings.tweakcnClear),
                  ),
                ],
              ],
            ),
            if (hasTheme) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: state.tweakcnThemeEnabled,
                title: Text(t.settings.tweakcnEnabled),
                onChanged: (enabled) =>
                    context.read<GlobalSettingCubit>().updateState(
                      (current) =>
                          current.copyWith(tweakcnThemeEnabled: enabled),
                    ),
              ),
              Text(
                t.settings.tweakcnApplied(
                  count: '${_tokenCount(theme)}',
                  radius: theme.radius == null
                      ? t.settings.tweakcnNoRadius
                      : '${theme.radius!.toStringAsFixed(0)}px',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              _TokenSwatches(
                theme: theme,
                brightness: Theme.of(context).brightness,
              ),
            ] else
              Text(
                t.settings.tweakcnNone,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
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
    );
  }

  /// 两套亮度里的 token 取并集 —— 只给了半套时不该显示成「一半没有」。
  int _tokenCount(TweakcnTheme theme) =>
      {...theme.light.keys, ...theme.dark.keys}.length;
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
