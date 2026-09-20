import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/page/setting/operation_binding/binding_editor_labels.dart';
import 'package:zephyr/page/setting/operation_binding/binding_input_recorder.dart';

/// 描述符表单只编辑文档；匹配与冲突判定由核心处理。
class BindingInputEditor extends StatelessWidget {
  const BindingInputEditor({
    super.key,
    required this.input,
    required this.onChanged,
  });
  final Map<String, dynamic> input;
  final ValueChanged<Map<String, dynamic>> onChanged;

  void _patch(String key, dynamic value) => onChanged({...input, key: value});

  @override
  Widget build(BuildContext context) {
    final device = input['device'] as String;
    if (device == InputDevice.radial || device == InputDevice.command) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(bindingDeviceIcon(device)),
        title: Text(bindingInputSummary(input)),
        subtitle: Text(t.bindingEditor.managedInput),
      );
    }
    final hold =
        input['trigger'] == 'hold' ||
        input['action'] == 'hold' ||
        input['gesture'] == 'long-press';
    final selector = BindingSelect<String>(
      label: t.bindingEditor.device,
      value: device,
      options: bindingDeviceLabels,
      onChanged: (value) => onChanged(defaultBindingInput(value)),
    );
    final fields = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (device == InputDevice.keyboard)
          Row(
            children: [
              Expanded(child: _text(context, 'code', t.bindingEditor.keyCode)),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: _select('trigger', t.bindingEditor.trigger, {
                  'down': t.bindingEditor.down,
                  'hold': t.bindingEditor.hold,
                }, fallback: 'down'),
              ),
            ],
          ),
        if (device == InputDevice.mouse ||
            device == InputDevice.mouseGesture ||
            device == InputDevice.area) ...[
          BindingSelect<int>(
            label: t.bindingEditor.button,
            value: input['button'] as int? ?? 0,
            options: {
              0: t.bindingEditor.leftButton,
              1: t.bindingEditor.middleButton,
              2: t.bindingEditor.rightButton,
              if (device != InputDevice.area) 3: t.bindingEditor.backButton,
              if (device != InputDevice.area) 4: t.bindingEditor.forwardButton,
              if (device != InputDevice.area)
                for (var i = 5; i < 8; i++) i: '$i',
            },
            onChanged: (value) => _patch('button', value),
          ),
          const SizedBox(height: 8),
          if (device != InputDevice.mouseGesture)
            _select('action', t.bindingEditor.trigger, bindingPointerActions),
        ],
        if (device == InputDevice.area) ...[
          const SizedBox(height: 8),
          _select('area', t.bindingEditor.area, bindingAreaLabels),
        ],
        if (device == InputDevice.mouseGesture) ...[
          _select('trigger', t.bindingEditor.trigger, {
            'instant': t.bindingEditor.instant,
            'hold': t.bindingEditor.hold,
          }),
          const SizedBox(height: 8),
          Text(t.bindingEditor.directions),
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                (input['directions'] as List)
                    .map((d) => bindingDirectionSymbols[d])
                    .join(' '),
              ),
              for (final direction in bindingDirectionSymbols.entries)
                IconButton.outlined(
                  tooltip: direction.value,
                  onPressed:
                      (input['directions'] as List).length >= 16 ||
                          (input['directions'] as List).lastOrNull ==
                              direction.key
                      ? null
                      : () => _patch('directions', [
                          ...input['directions'] as List,
                          direction.key,
                        ]),
                  icon: Text(direction.value),
                ),
              IconButton(
                tooltip: t.bindingEditor.undoDirection,
                onPressed: (input['directions'] as List).length <= 1
                    ? null
                    : () => _patch(
                        'directions',
                        (input['directions'] as List).sublist(
                          0,
                          (input['directions'] as List).length - 1,
                        ),
                      ),
                icon: const Icon(Icons.undo),
              ),
            ],
          ),
        ],
        if (device == InputDevice.wheel)
          _select('direction', t.bindingEditor.wheel, {
            'up': t.bindingEditor.up,
            'down': t.bindingEditor.downDirection,
          }),
        if (device == InputDevice.keyboard || device == InputDevice.wheel)
          Wrap(
            spacing: 4,
            children: [
              for (final modifier in const {
                'ctrl': 'Ctrl',
                'alt': 'Alt',
                'shift': 'Shift',
                'meta': 'Meta',
              }.entries)
                FilterChip(
                  label: Text(modifier.value),
                  selected: input[modifier.key] == true,
                  onSelected: (value) => _patch(modifier.key, value),
                ),
            ],
          ),
        if (device == InputDevice.touch)
          Row(
            children: [
              Expanded(
                child: _select(
                  'gesture',
                  t.bindingEditor.gesture,
                  bindingTouchGestures,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: BindingSelect<int>(
                  label: t.bindingEditor.fingers,
                  value: input['fingers'] as int,
                  options: const {1: '1', 2: '2', 3: '3'},
                  onChanged: (value) => _patch('fingers', value),
                ),
              ),
            ],
          ),
        if (device == InputDevice.gamepad) ...[
          _number(context, 'button', t.bindingEditor.gamepadButton, 0, 31, 5),
          const SizedBox(height: 8),
          Text(
            t.bindingEditor.gamepadHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (hold) ...[
          const SizedBox(height: 8),
          _number(
            context,
            'durationMs',
            t.bindingEditor.duration,
            100,
            5000,
            device == InputDevice.keyboard ? 450 : 500,
          ),
          if (device != InputDevice.keyboard) ...[
            const SizedBox(height: 8),
            _number(
              context,
              'moveTolerancePx',
              t.bindingEditor.tolerance,
              0,
              200,
              12,
            ),
          ],
        ],
        if (device != InputDevice.area && device != InputDevice.gamepad) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final captured = await BindingInputRecorder.show(context, input);
              if (captured != null && context.mounted) onChanged(captured);
            },
            icon: const Icon(Icons.sensors, size: 18),
            label: Text(t.bindingEditor.record),
          ),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 620) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 150, child: selector),
              const SizedBox(width: 12),
              Expanded(child: fields),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [selector, const SizedBox(height: 12), fields],
        );
      },
    );
  }

  Widget _select(
    String field,
    String label,
    Map<String, String> options, {
    String? fallback,
  }) => BindingSelect<String>(
    label: label,
    value: input[field] as String? ?? fallback ?? options.keys.first,
    options: options,
    onChanged: (value) => _patch(field, value),
  );

  Widget _text(BuildContext context, String field, String label) =>
      _BindingTextField(
        key: ValueKey(field),
        value: input[field] as String? ?? '',
        decoration: bindingFieldDecoration(context, label),
        onChanged: (value) {
          _patch(field, value.trim());
        },
      );

  Widget _number(
    BuildContext context,
    String field,
    String label,
    int min,
    int max,
    int fallback,
  ) => _BindingTextField(
    key: ValueKey(field),
    value: '${input[field] ?? fallback}',
    keyboardType: TextInputType.number,
    decoration: bindingFieldDecoration(context, label),
    onChanged: (value) {
      final number = int.tryParse(value);
      if (number != null && number >= min && number <= max) {
        _patch(field, number);
      }
    },
  );
}

class BindingSelect<T> extends StatelessWidget {
  const BindingSelect({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => DropdownMenu<T>(
    key: ValueKey('$label:$value'),
    initialSelection: value,
    expandedInsets: EdgeInsets.zero,
    requestFocusOnTap: false,
    label: Text(label),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: UnderlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: UnderlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: UnderlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
      ),
    ),
    menuStyle: MenuStyle(
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    dropdownMenuEntries: [
      for (final item in options.entries)
        DropdownMenuEntry<T>(value: item.key, label: item.value),
      if (!options.containsKey(value))
        DropdownMenuEntry<T>(value: value, label: '$value'),
    ],
    onSelected: (value) {
      if (value != null) onChanged(value);
    },
  );
}

/// 外部录制结果可以更新字段；普通输入时保留焦点与光标。
class _BindingTextField extends StatefulWidget {
  const _BindingTextField({
    super.key,
    required this.value,
    required this.decoration,
    required this.onChanged,
    this.keyboardType,
  });
  final String value;
  final InputDecoration decoration;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  @override
  State<_BindingTextField> createState() => _BindingTextFieldState();
}

class _BindingTextFieldState extends State<_BindingTextField> {
  late final _controller = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(covariant _BindingTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    decoration: widget.decoration,
    keyboardType: widget.keyboardType,
    onChanged: widget.onChanged,
  );
}

InputDecoration bindingFieldDecoration(BuildContext context, String label) =>
    InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: UnderlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: UnderlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: UnderlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
      ),
    );
