part of '../workspace_layout_setting_page.dart';
// 驻留延时条目（_DelayTile）与整数数字框（_NumberBox / _NumberBoxState）


/// 一个毫秒级的驻留延时：标题 + 数字框（+ 可选的启用开关）。
///
/// 用数字框而不是滑块是**照抄 neoview**：这些值是「180 还是 250 毫秒」这种
/// 要精确对表的手感量，滑块把 100..5000 压到 700px 上，一格就是 50ms 起步，
/// 想复现另一个候选的取值反而做不到。
class _DelayTile extends StatelessWidget {
  const _DelayTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
    this.switchValue,
    this.onSwitchChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final int value;
  final int min;
  final int max;
  final bool enabled;
  final bool? switchValue;
  final ValueChanged<bool>? onSwitchChanged;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: enabled ? null : Theme.of(context).disabledColor,
      ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onSwitchChanged != null)
            Switch(
              value: switchValue ?? false,
              thumbIcon: kSettingSwitchThumbIcon,
              onChanged: onSwitchChanged,
            ),
          _NumberBox(
            key: ValueKey('$title-$value-$enabled'),
            value: value,
            min: min,
            max: max,
            step: 50,
            enabled: enabled,
            onCommit: onChanged,
          ),
        ],
      ),
    );
  }
}


/// 整数数字框：**回车或失焦才提交**，边打字边提交会让延时这种值每敲一下
/// 就生效一次（100 → 1 → 10 → 100 中间那几步都是无意义的抖动）。
class _NumberBox extends StatefulWidget {
  const _NumberBox({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onCommit,
    this.step = 1,
    this.enabled = true,
  });

  final int value;
  final int min;
  final int max;
  final int step;
  final bool enabled;
  final ValueChanged<int> onCommit;

  @override
  State<_NumberBox> createState() => _NumberBoxState();
}


class _NumberBoxState extends State<_NumberBox> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.value}',
  );
  late final FocusNode _focus = FocusNode()..addListener(_onFocusChanged);
  bool _editing = false;

  void _onFocusChanged() {
    final focused = _focus.hasFocus;
    if (!focused) _commit();
    if (focused != _editing) setState(() => _editing = focused);
  }

  @override
  void didUpdateWidget(covariant _NumberBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部值变了（重置、联动）时跟着改；正在打字时**不改**，
    // 否则光标会跳走、用户敲到一半的数字被覆盖。
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

  void _commit() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = '${widget.value}';
      return;
    }
    // 对齐到 step 再夹取：`min` 是这一项的下限（100 / 200 毫秒），
    // 而 step 是它的刻度 —— 两者不夹清楚会让「输入 137」留下一个
    // 界面上再也调不回去的取值。
    final stepped = (parsed / widget.step).round() * widget.step;
    final next = stepped < widget.min
        ? widget.min
        : (stepped > widget.max ? widget.max : stepped);
    _controller.text = '$next';
    if (next != widget.value) widget.onCommit(next);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        enabled: widget.enabled,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(signed: false),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))],
        style: const TextStyle(fontSize: 13),
        decoration: const InputDecoration(isDense: true, isCollapsed: true),
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}
