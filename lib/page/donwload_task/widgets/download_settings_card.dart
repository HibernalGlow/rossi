import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/service/download/image_download.dart';

/// 下载管理页顶部的并发与节流设置。
///
/// 放在这里而不是全局设置页：调这些值的人正站在「下载慢 / 被风控」的现场，
/// 让他跑去设置翻完再回来，等于每试一个取值都要多走两步。
class DownloadSettingsCard extends StatelessWidget {
  const DownloadSettingsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final state = cubit.state;
    final theme = Theme.of(context);
    final chapters = state.downloadTaskConcurrency.clamp(
      1,
      kMaxParallelChapters,
    );
    final images = state.downloadConcurrency.clamp(1, kMaxImageConcurrency);
    final delayMs = state.downloadDelayMs.clamp(0, kMaxDownloadDelayMs);

    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  t.download.settingsTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          ListTile(
            dense: true,
            title: Text(t.settings.downloadTaskConcurrency),
            subtitle: Text(t.settings.downloadTaskConcurrencySubtitle),
            trailing: _NumberField(
              value: chapters,
              min: 1,
              max: kMaxParallelChapters,
              onCommit: (value) {
                cubit.updateState(
                  (current) => current.copyWith(downloadTaskConcurrency: value),
                );
              },
            ),
          ),
          ListTile(
            dense: true,
            title: Text(t.settings.downloadConcurrency),
            subtitle: Text(t.settings.downloadConcurrencySubtitle),
            trailing: _NumberField(
              value: images,
              min: 1,
              max: kMaxImageConcurrency,
              onCommit: (value) {
                cubit.updateState(
                  (current) => current.copyWith(downloadConcurrency: value),
                );
              },
            ),
          ),
          ListTile(
            dense: true,
            title: Text(t.settings.downloadDelay),
            subtitle: Text(t.settings.downloadDelaySubtitle),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _NumberField(
                  value: delayMs,
                  min: 0,
                  max: kMaxDownloadDelayMs,
                  onCommit: (value) {
                    cubit.updateState(
                      (current) => current.copyWith(downloadDelayMs: value),
                    );
                  },
                ),
                const SizedBox(width: 6),
                Text('ms', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              t.download.settingsBudgetHint(count: chapters * images),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 整数输入框：回车或失焦才提交，避免「100 → 1 → 10 → 100」这种边打字边生效的抖动。
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.value,
    required this.min,
    required this.max,
    required this.onCommit,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onCommit;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.value}',
  );
  late final FocusNode _focus = FocusNode()..addListener(_onFocusChanged);
  bool _editing = false;

  @override
  void didUpdateWidget(covariant _NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部值变了要跟上；正在打字时不改，否则光标跳走、半截数字被覆盖。
    if (!_editing && _controller.text != '${widget.value}') {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    final focused = _focus.hasFocus;
    if (!focused) _commit();
    if (focused != _editing) setState(() => _editing = focused);
  }

  void _commit() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = '${widget.value}';
      return;
    }
    final next = parsed.clamp(widget.min, widget.max);
    _controller.text = '$next';
    if (next != widget.value) widget.onCommit(next);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(signed: false),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))],
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          isCollapsed: true,
          hintText: '${widget.min}-${widget.max}',
        ),
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}
