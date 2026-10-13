import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_primitives.dart';

/// 横翻连续速度是唯一常用控件，启动延迟放在折叠的高级选项中。
class ReaderKeyboardRepeatSettings extends StatelessWidget {
  const ReaderKeyboardRepeatSettings({
    super.key,
    required this.pagesPerSecond,
    required this.holdDelayMs,
    required this.onSpeedChanged,
    required this.onDelayChanged,
  });

  final double pagesPerSecond;
  final int holdDelayMs;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<int> onDelayChanged;

  @override
  Widget build(BuildContext context) => SettingsCardGroup(
    children: [
      _NumberSlider(
        title: t.reader.keyboardPageTurnSpeed,
        description: t.reader.keyboardPageTurnSpeedSubtitle,
        value: pagesPerSecond.isFinite ? pagesPerSecond.clamp(0.5, 15) : 4,
        min: 0.5,
        max: 15,
        divisions: 29,
        suffix: t.reader.pagesPerSecond,
        decimals: 1,
        onChanged: onSpeedChanged,
      ),
      ExpansionTile(
        title: Text(t.reader.keyboardPageTurnAdvanced),
        children: [
          _NumberSlider(
            title: t.reader.keyboardPageTurnHoldDelay,
            description: t.reader.keyboardPageTurnHoldDelaySubtitle,
            value: holdDelayMs.clamp(100, 2000).toDouble(),
            min: 100,
            max: 2000,
            divisions: 38,
            suffix: 'ms',
            decimals: 0,
            onChanged: (value) => onDelayChanged(value.round()),
          ),
        ],
      ),
    ],
  );
}

/// 滑杆用于快速调节；数字输入保留用户给出的精确速度。
class _NumberSlider extends StatefulWidget {
  const _NumberSlider({
    required this.title,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.decimals,
    required this.onChanged,
  });

  final String title;
  final String description;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final int decimals;
  final ValueChanged<double> onChanged;

  @override
  State<_NumberSlider> createState() => _NumberSliderState();
}

class _NumberSliderState extends State<_NumberSlider> {
  late final _text = TextEditingController(text: _format(widget.value));
  final _focus = FocusNode();

  String _format(double value) => value.toStringAsFixed(widget.decimals);

  @override
  void didUpdateWidget(_NumberSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus) _text.text = _format(widget.value);
  }

  void _submit() {
    final parsed = double.tryParse(_text.text);
    if (parsed != null && parsed.isFinite) {
      final value = double.parse(_format(parsed.clamp(widget.min, widget.max)));
      _text.text = _format(value);
      if (value != widget.value) widget.onChanged(value);
    } else {
      _text.text = _format(widget.value);
    }
    _focus.unfocus();
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleSmall),
            SizedBox(
              width: 150,
              child: TextField(
                controller: _text,
                focusNode: _focus,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixText: widget.suffix,
                ),
                onSubmitted: (_) => _submit(),
                onTapOutside: (_) => _submit(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(widget.description, style: Theme.of(context).textTheme.bodySmall),
        Slider(
          value: widget.value.clamp(widget.min, widget.max),
          min: widget.min,
          max: widget.max,
          divisions: widget.divisions,
          label: '${_format(widget.value)} ${widget.suffix}',
          onChanged: widget.onChanged,
        ),
      ],
    ),
  );
}
