import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/search/search_history_popup.dart';
import 'package:zephyr/widgets/search/search_history_store.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';

typedef HistorySearchFieldBuilder =
    Widget Function(
      BuildContext context,
      TextEditingController controller,
      FocusNode focusNode,
      ValueChanged<String> onChanged,
      ValueChanged<String> onSubmitted,
      Widget historyButton,
    );

/// 官方 Autocomplete 管理建议和键盘选择，统一弹层呈现两个历史入口。
class SearchHistoryAutocomplete extends StatefulWidget {
  const SearchHistoryAutocomplete({
    super.key,
    required this.history,
    required this.fieldBuilder,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.recordOnBlur = true,
    this.enabled = true,
  });

  final SearchHistoryStore history;
  final HistorySearchFieldBuilder fieldBuilder;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final FutureOr<void> Function(String)? onSubmitted;
  final bool recordOnBlur;
  final bool enabled;

  @override
  State<SearchHistoryAutocomplete> createState() =>
      _SearchHistoryAutocompleteState();
}

class _SearchHistoryAutocompleteState extends State<SearchHistoryAutocomplete> {
  TextEditingController? _ownedController;
  FocusNode? _ownedFocus;
  TextEditingController get _controller =>
      widget.controller ?? (_ownedController ??= TextEditingController());
  FocusNode get _focus => widget.focusNode ?? (_ownedFocus ??= FocusNode());
  List<String> _history = const [];
  bool _edited = false;
  bool _keyboardSelection = false;
  bool _selectedOnSubmit = false;
  int _generation = 0;
  int _loadSerial = 0;
  final _fieldKey = GlobalKey();
  final _buttonKey = GlobalKey();
  final _buttonOwner = Object();
  late final _popup = SearchHistoryPopup(
    fieldKey: _fieldKey,
    onDismissed: () {
      _manualHistory = false;
      _dismissed = true;
    },
  );
  bool _manualHistory = false;
  bool _dismissed = false;
  SearchHistorySuggestions? _suggestions;
  Object? _suggestionsOwner;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant SearchHistoryAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownedFocus)?.removeListener(_focusChanged);
      _focus.addListener(_focusChanged);
    }
    if (oldWidget.history.scope != widget.history.scope) {
      _closeHistory();
      _suggestions = null;
      _dismissed = false;
      _edited = false;
      _history = const [];
      _generation++;
      unawaited(_reload());
    }
    if (!widget.enabled) _closeHistory();
  }

  void _focusChanged() {
    if (_focus.hasFocus) {
      _dismissed = false;
      _keyboardSelection = false;
      unawaited(_reload());
    } else {
      _closeHistory();
      if (widget.recordOnBlur && _edited) _record(_controller.text);
    }
  }

  Future<void> _reload() async {
    final serial = ++_loadSerial;
    try {
      final history = await widget.history.load();
      if (mounted && serial == _loadSerial) setState(() => _history = history);
    } catch (_) {
      // 历史不可用时仍允许正常搜索。
    }
  }

  void _record(String query) {
    _edited = false;
    final keyword = query.trim();
    if (keyword.isEmpty) return;
    final store = widget.history;
    unawaited(() async {
      try {
        await store.record(keyword);
        if (mounted && widget.history.scope == store.scope) await _reload();
      } catch (_) {
        // 存储失败不能中断搜索或弹窗关闭。
      }
    }());
  }

  void _changed(String value) {
    _manualHistory = false;
    _dismissed = false;
    _edited = true;
    _keyboardSelection = false;
    widget.onChanged?.call(value);
  }

  void _selected(String query) {
    _closeHistory();
    _selectedOnSubmit = true;
    _keyboardSelection = false;
    _record(query);
    widget.onChanged?.call(query);
    unawaited(_deliverSubmission(query));
  }

  Future<void> _deliverSubmission(String query) async {
    final scope = widget.history.scope;
    await widget.onSubmitted?.call(query);
    // 文件管理器在成功创建结果页签后才写 Rust 历史，此时刷新菜单。
    if (mounted && widget.history.scope == scope) await _reload();
  }

  void _submit(String query, VoidCallback selectHighlighted) {
    _selectedOnSubmit = false;
    // 普通回车仍搜索用户原词；方向键选中历史后回车才接受建议。
    if (_keyboardSelection) selectHighlighted();
    if (!_selectedOnSubmit) {
      _closeHistory();
      _record(query);
      unawaited(_deliverSubmission(query));
    }
    _keyboardSelection = false;
  }

  Future<void> _clearHistory() async {
    _closeHistory();
    _edited = false;
    try {
      await widget.history.clear();
      if (!mounted) return;
      setState(() {
        _history = const [];
        _generation++;
      });
    } catch (_) {
      // 与加载/写入一致，历史故障不影响当前输入。
    }
  }

  void _closeHistory() {
    _manualHistory = false;
    _dismissed = true;
    _popup.dismiss();
  }

  void _showSuggestions(SearchHistorySuggestions value, Object owner) {
    _suggestions = value;
    _suggestionsOwner = owner;
    if (!mounted ||
        !widget.enabled ||
        !_focus.hasFocus ||
        _manualHistory ||
        _dismissed) {
      return;
    }
    _popup.show(context, value, owner);
  }

  void _replay(String query) {
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _selected(query);
  }

  Future<void> _openHistory({bool filter = false}) async {
    _manualHistory = true;
    await _reload();
    if (!mounted || !widget.enabled || !_manualHistory) return;
    _popup.show(
      context,
      SearchHistorySuggestions(
        queries: _history
            .where(
              (entry) =>
                  !filter ||
                  entry.toLowerCase().contains(
                    _controller.text.trim().toLowerCase(),
                  ),
            )
            .take(filter ? 8 : 12)
            .toList(),
        onSelected: _replay,
        onClear: () => unawaited(_clearHistory()),
      ),
      _buttonOwner,
      sourceKey: filter ? _fieldKey : _buttonKey,
    );
  }

  void _fieldTapped(PointerDownEvent event) {
    final button = _buttonKey.currentContext?.findRenderObject();
    if (button is RenderBox &&
        (button.localToGlobal(Offset.zero) & button.size).contains(
          event.position,
        )) {
      return;
    }
    // 输入框已持有焦点时再次点击也应打开历史，不让用户先失焦再回来。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.enabled && _focus.hasFocus && _dismissed) {
        unawaited(_openHistory(filter: true));
      }
    });
  }

  Widget _historyButton() => Focus(
    canRequestFocus: false,
    descendantsAreTraversable: false,
    child: TextFieldTapRegion(
      child: ElasticPress(
        key: _buttonKey,
        enabled:
            widget.enabled &&
            !eInkInstantRoutes &&
            !MediaQuery.disableAnimationsOf(context),
        child: IconButton.filledTonal(
          tooltip: t.search.history,
          style: ElasticPress.buttonStyle.merge(
            IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              backgroundColor: Colors.transparent,
              foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
              shape: const StadiumBorder(),
            ),
          ),
          onPressed: widget.enabled ? () => unawaited(_openHistory()) : null,
          icon: const GlyphIcon(AppGlyphs.history, size: 18),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Autocomplete<String>(
    key: ValueKey((widget.history.scope, _generation)),
    textEditingController: _controller,
    focusNode: _focus,
    optionsViewOpenDirection: OptionsViewOpenDirection.mostSpace,
    optionsBuilder: (value) async {
      if (!widget.enabled) return const <String>[];
      try {
        final history = await widget.history.load();
        final query = value.text.trim().toLowerCase();
        return history
            .where((entry) => entry.toLowerCase().contains(query))
            .take(8);
      } catch (_) {
        return const <String>[];
      }
    },
    onSelected: _selected,
    optionsViewBuilder: (context, selected, options) =>
        SearchHistoryOptionsBridge(
          suggestions: SearchHistorySuggestions(
            queries: options.toList(),
            onSelected: selected,
            onClear: () => unawaited(_clearHistory()),
          ),
          onShow: _showSuggestions,
          onHide: (owner) {
            if (identical(owner, _suggestionsOwner)) _suggestions = null;
            _popup.dismiss(owner: owner);
          },
        ),
    fieldViewBuilder: (context, controller, focus, selectHighlighted) => Focus(
      key: _fieldKey,
      canRequestFocus: false,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _closeHistory();
        }
        if (event is KeyDownEvent &&
            const [
              LogicalKeyboardKey.arrowDown,
              LogicalKeyboardKey.arrowUp,
              LogicalKeyboardKey.pageDown,
              LogicalKeyboardKey.pageUp,
            ].contains(event.logicalKey)) {
          _keyboardSelection = true;
          if (_manualHistory && _suggestions != null) {
            _manualHistory = false;
            _dismissed = false;
            _popup.show(this.context, _suggestions!, _suggestionsOwner!);
          }
        }
        return KeyEventResult.ignored;
      },
      child: Listener(
        onPointerDown: _fieldTapped,
        child: widget.fieldBuilder(
          context,
          controller,
          focus,
          _changed,
          (value) => _submit(value, selectHighlighted),
          _historyButton(),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _popup.dismiss();
    if (widget.recordOnBlur && _edited) _record(_controller.text);
    _focus.removeListener(_focusChanged);
    _ownedController?.dispose();
    _ownedFocus?.dispose();
    super.dispose();
  }
}

/// 保留现有 TextField 参数，增加官方自动完成及 Expressive 历史弹层。
class SearchHistoryField extends StatelessWidget {
  const SearchHistoryField({
    super.key,
    required this.history,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.enabled = true,
    this.recordOnBlur = true,
    this.decoration = const InputDecoration(),
    this.style,
    this.minLines,
    this.maxLines = 1,
    this.inputFormatters,
    this.textAlignVertical,
  });

  final SearchHistoryStore history;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final FutureOr<void> Function(String)? onSubmitted;
  final bool autofocus;
  final bool enabled;
  final bool recordOnBlur;
  final InputDecoration decoration;
  final TextStyle? style;
  final int? minLines;
  final int? maxLines;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlignVertical? textAlignVertical;

  @override
  Widget build(BuildContext context) => SearchHistoryAutocomplete(
    history: history,
    controller: controller,
    focusNode: focusNode,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    recordOnBlur: recordOnBlur,
    enabled: enabled,
    fieldBuilder:
        (context, controller, focus, changed, submitted, historyButton) =>
            TextField(
              controller: controller,
              focusNode: focus,
              autofocus: autofocus,
              enabled: enabled,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.search,
              // 本地筛选允许提交后接着编辑；路由跳转仍可主动收起/失焦。
              onEditingComplete: () {},
              minLines: minLines,
              maxLines: maxLines,
              inputFormatters: inputFormatters,
              textAlignVertical: textAlignVertical,
              style: style,
              onChanged: changed,
              onSubmitted: submitted,
              decoration: decoration.copyWith(
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [historyButton, ?decoration.suffixIcon],
                ),
              ),
            ),
  );
}
