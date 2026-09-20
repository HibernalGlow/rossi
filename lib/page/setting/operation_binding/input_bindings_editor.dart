import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/service/operation_binding/action_labels.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';
import 'package:zephyr/page/setting/operation_binding/binding_action_presentation.dart';
import 'package:zephyr/page/setting/operation_binding/binding_editor_labels.dart';
import 'package:zephyr/page/setting/operation_binding/binding_input_editor.dart';

/// 动作分类导航 + 绑定摘要；编辑时仍使用核心的同一份平面绑定表。
class InputBindingsEditor extends StatefulWidget {
  const InputBindingsEditor({
    super.key,
    required this.bindings,
    required this.catalog,
    required this.conflicts,
    required this.onChanged,
  });
  final List<Map<String, dynamic>> bindings;
  final List<BindingActionInfo> catalog;
  final List<BindingConflict> conflicts;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  @override
  State<InputBindingsEditor> createState() => _InputBindingsEditorState();
}

class _InputBindingsEditorState extends State<InputBindingsEditor>
    with SingleTickerProviderStateMixin {
  final _search = TextEditingController();
  BindingActionGroup? _group;
  BindingVideoGroup _videoGroup = BindingVideoGroup.playback;
  String _context = '';
  bool _boundOnly = false;
  String? _selected;
  String? _expandedId;
  final _detailScroll = ScrollController();
  final _listScroll = ScrollController();
  late final _compactTabs = TabController(length: 2, vsync: this);
  var _compactDetail = false;

  List<BindingActionGroup> get _groups => BindingActionGroup.values
      .where(
        (group) => widget.catalog.any((a) => bindingActionGroup(a) == group),
      )
      .toList();

  List<BindingVideoGroup> get _videoGroups => BindingVideoGroup.values
      .where(
        (group) => widget.catalog.any(
          (a) => a.id.startsWith('video.') && bindingVideoGroup(a.id) == group,
        ),
      )
      .toList();

  @override
  void initState() {
    super.initState();
    _group = _groups.firstOrNull;
    _videoGroup = _videoGroups.firstOrNull ?? BindingVideoGroup.playback;
  }

  @override
  void dispose() {
    _search.dispose();
    _detailScroll.dispose();
    _listScroll.dispose();
    _compactTabs.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _rows(String action) => widget.bindings
      .where(
        (row) =>
            row['action'] == action &&
            (_context.isEmpty || row['context'] == _context),
      )
      .toList();

  List<BindingActionInfo> get _visible {
    final query = _search.text.trim().toLowerCase();
    final actions = widget.catalog.where((action) {
      // 搜索始终跨分类，避免用户必须猜动作属于哪个分组。
      if (query.isEmpty && _group != null) {
        if (bindingActionGroup(action) != _group) return false;
        if (_group == BindingActionGroup.video &&
            bindingVideoGroup(action.id) != _videoGroup) {
          return false;
        }
      }
      final rows = _rows(action.id);
      if ((_boundOnly || _context.isNotEmpty) && rows.isEmpty) return false;
      return query.isEmpty ||
          [
            actionLabel(action),
            action.id,
            action.category,
            action.categoryLabel,
            bindingActionGroup(action).label,
            for (final row in rows)
              '${bindingContextLabels[row['context']]} ${row['context']} ${bindingInputSummary(Map<String, dynamic>.from(row['input'] as Map))} ${bindingInputBadgeLabel(Map<String, dynamic>.from(row['input'] as Map))} ${row['input']}',
          ].join(' ').toLowerCase().contains(query);
    }).toList();
    // 保留注册表组内顺序；未实现的动作放在最后并明确标注。
    return [
      ...actions.where((a) => a.implemented),
      ...actions.where((a) => !a.implemented),
    ];
  }

  void _update(Map<String, dynamic> row) =>
      widget.onChanged(updateBindingRow(widget.bindings, row));

  void _showList() {
    _compactDetail = false;
    _compactTabs.animateTo(0);
  }

  void _selectAction(String id, {required bool compact}) {
    setState(() {
      _selected = id;
      _compactDetail = true;
    });
    if (compact) _compactTabs.animateTo(1);
    if (_detailScroll.hasClients) _detailScroll.jumpTo(0);
  }

  void _selectGroup(BindingActionGroup? group) {
    setState(() {
      _group = group;
      _search.clear();
      _showList();
    });
    if (_listScroll.hasClients) _listScroll.jumpTo(0);
  }

  void _add(BindingActionInfo action, String device) {
    final id = newBindingId(action.id);
    setState(() => _expandedId = id);
    widget.onChanged([
      ...widget.bindings,
      {
        'id': id,
        'action': action.id,
        'context': _context.isEmpty
            ? defaultBindingContext(action.id)
            : _context,
        'enabled': true,
        'ignoreRepeat': false,
        'input': defaultBindingInput(device),
      },
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final selected =
        visible.where((a) => a.id == _selected).firstOrNull ??
        visible.firstOrNull;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolbar(),
            const SizedBox(height: 8),
            _groupNavigation(),
            if (_group == BindingActionGroup.video &&
                _search.text.trim().isEmpty)
              _videoNavigation(),
            const SizedBox(height: 8),
            if (selected == null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(Icons.search_off, size: 32),
                    const SizedBox(height: 12),
                    Text(t.bindingEditor.noResults),
                    TextButton(
                      onPressed: () => setState(() {
                        _search.clear();
                        _group = _groups.firstOrNull;
                        _context = '';
                        _boundOnly = false;
                        _showList();
                      }),
                      child: Text(t.bindingEditor.resetFilters),
                    ),
                  ],
                ),
              )
            else if (wide)
              SizedBox(
                height: (MediaQuery.sizeOf(context).height - 280).clamp(
                  480.0,
                  960.0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 330, child: _master(visible, selected.id)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        key: const PageStorageKey('binding-action-details'),
                        controller: _detailScroll,
                        child: _detail(selected),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              TabBar.secondary(
                controller: _compactTabs,
                onTap: (index) => setState(() => _compactDetail = index == 1),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.list_alt_outlined, size: 20),
                        const SizedBox(width: 8),
                        Flexible(child: Text(t.bindingEditor.actionList)),
                        const SizedBox(width: 8),
                        Text('${visible.length}'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.tune, size: 20),
                        const SizedBox(width: 8),
                        Flexible(child: Text(t.bindingEditor.bindingDetails)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: (MediaQuery.sizeOf(context).height - 360).clamp(
                  360.0,
                  960.0,
                ),
                child: _compactDetail
                    ? SingleChildScrollView(
                        key: const PageStorageKey('binding-action-details'),
                        controller: _detailScroll,
                        child: _detail(selected),
                      )
                    : _master(visible, selected.id, compact: true),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _toolbar() => Row(
    children: [
      Expanded(
        child: SearchBar(
          controller: _search,
          hintText: t.bindingEditor.searchAll,
          leading: const Icon(Icons.search),
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStatePropertyAll(
            Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          trailing: [
            if (_search.text.isNotEmpty)
              IconButton(
                tooltip: t.bindingEditor.resetFilters,
                onPressed: () => setState(() {
                  _search.clear();
                  _showList();
                }),
                icon: const Icon(Icons.close),
              ),
          ],
          onChanged: (_) => setState(_showList),
        ),
      ),
      const SizedBox(width: 4),
      PopupMenuButton<String>(
        tooltip: t.bindingEditor.allContexts,
        icon: Badge(
          isLabelVisible: _context.isNotEmpty || _boundOnly,
          child: const Icon(Icons.filter_list),
        ),
        onSelected: (value) => setState(() {
          if (value == 'bound-only') {
            _boundOnly = !_boundOnly;
          } else {
            _context = value;
          }
          _showList();
        }),
        itemBuilder: (_) => [
          CheckedPopupMenuItem(
            value: 'bound-only',
            checked: _boundOnly,
            child: Text(t.bindingEditor.boundOnly),
          ),
          const PopupMenuDivider(),
          for (final entry in {
            '': t.bindingEditor.allContexts,
            ...bindingContextLabels,
          }.entries)
            CheckedPopupMenuItem(
              value: entry.key,
              checked: _context == entry.key,
              child: Text(entry.value),
            ),
        ],
      ),
    ],
  );

  Widget _groupNavigation() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final group in [..._groups, null])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  key: ValueKey('action-group:${group?.name ?? 'all'}'),
                  avatar: Icon(group?.icon ?? Icons.apps, size: 18),
                  label: Text(group?.label ?? t.bindingEditor.allActions),
                  shape: const StadiumBorder(),
                  showCheckmark: false,
                  selected: _search.text.trim().isNotEmpty
                      ? group == null
                      : _group == group,
                  onSelected: (_) => _selectGroup(group),
                ),
              ),
          ],
        ),
      ),
      if (_context.isNotEmpty || _boundOnly)
        Wrap(
          spacing: 8,
          children: [
            if (_context.isNotEmpty)
              InputChip(
                label: Text(bindingContextLabels[_context] ?? _context),
                onDeleted: () => setState(() => _context = ''),
                shape: const StadiumBorder(),
              ),
            if (_boundOnly)
              InputChip(
                label: Text(t.bindingEditor.boundOnly),
                onDeleted: () => setState(() => _boundOnly = false),
                shape: const StadiumBorder(),
              ),
          ],
        ),
    ],
  );

  Widget _videoNavigation() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final group in _videoGroups)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              key: ValueKey('video-group:${group.name}'),
              avatar: Icon(group.icon, size: 16),
              label: Text(group.label),
              selected: _videoGroup == group,
              shape: const StadiumBorder(),
              showCheckmark: false,
              onSelected: (_) {
                setState(() {
                  _videoGroup = group;
                  _showList();
                });
                if (_listScroll.hasClients) _listScroll.jumpTo(0);
              },
            ),
          ),
      ],
    ),
  );

  Widget _master(
    List<BindingActionInfo> actions,
    String selectedId, {
    bool compact = false,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        key: const PageStorageKey('binding-action-list'),
        controller: _listScroll,
        padding: const EdgeInsets.all(8),
        itemCount: actions.length,
        itemBuilder: (context, index) {
          final action = actions[index];
          final rows = _rows(action.id);
          final selected =
              action.id == _selected || (!compact && action.id == selectedId);
          final conflict = rows.any(
            (row) =>
                widget.conflicts.any((c) => c.bindingIds.contains(row['id'])),
          );
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: selected
                  ? theme.colorScheme.secondaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                key: ValueKey('action:${action.id}'),
                borderRadius: BorderRadius.circular(20),
                onTap: () => _selectAction(action.id, compact: compact),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        bindingActionIcon(action.id),
                        size: 24,
                        color: selected
                            ? theme.colorScheme.onSecondaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bindingActionTitle(action),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 6),
                            if (rows.isEmpty)
                              Text(
                                t.bindingEditor.unassigned,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              )
                            else
                              Row(
                                children: [
                                  for (final row in rows.take(2))
                                    Flexible(
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: 4,
                                        ),
                                        child: _inputBadge(row),
                                      ),
                                    ),
                                  if (rows.length > 2)
                                    Tooltip(
                                      message: t.bindingEditor.moreBindings(
                                        count: rows.length - 2,
                                      ),
                                      child: Text(
                                        '+${rows.length - 2}',
                                        style: theme.textTheme.labelSmall,
                                      ),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      if (conflict || !action.implemented) ...[
                        const SizedBox(width: 4),
                        Tooltip(
                          message: conflict
                              ? t.bindingEditor.conflictHint
                              : t.settings.operationBindingUnimplemented,
                          child: Icon(
                            conflict
                                ? Icons.warning_amber_rounded
                                : Icons.hourglass_empty,
                            size: 18,
                            color: conflict
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (compact) const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _inputBadge(Map<String, dynamic> row, {bool showDevice = true}) {
    final input = Map<String, dynamic>.from(row['input'] as Map);
    final enabled = row['enabled'] == true;
    final theme = Theme.of(context);
    final description =
        '${bindingInputSummary(input)} · ${bindingContextLabels[row['context']] ?? row['context']}${enabled ? '' : ' · ${t.bindingEditor.disabled}'}';
    return Tooltip(
      message: description,
      child: Semantics(
        label: description,
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showDevice) ...[
                Icon(
                  bindingDeviceIcon(input['device'] as String),
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  bindingInputBadgeLabel(input),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    decoration: enabled ? null : TextDecoration.lineThrough,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(BindingActionInfo action) {
    final rows = _rows(action.id);
    final theme = Theme.of(context);
    return Card.filled(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  bindingActionIcon(action.id),
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bindingActionTitle(action),
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        '${bindingActionGroup(action).label} · ${rows.length} ${t.bindingEditor.bindings}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: t.bindingEditor.addBinding,
                  icon: const Icon(Icons.add),
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                  ),
                  onSelected: (device) => _add(action, device),
                  itemBuilder: (_) => [
                    for (final device in bindingDeviceLabels.entries)
                      PopupMenuItem(
                        value: device.key,
                        child: Row(
                          children: [
                            Icon(bindingDeviceIcon(device.key), size: 20),
                            const SizedBox(width: 12),
                            Text(device.value),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!action.implemented)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  t.settings.operationBindingUnimplemented,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Icon(
                      Icons.add_link,
                      size: 32,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      t.bindingEditor.noBindings,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            for (final row in rows) _bindingCard(row),
          ],
        ),
      ),
    );
  }

  Widget _bindingCard(Map<String, dynamic> row) {
    final id = row['id'] as String;
    final input = Map<String, dynamic>.from(row['input'] as Map);
    final device = input['device'] as String;
    final managed =
        device == InputDevice.radial || device == InputDevice.command;
    final conflicted = widget.conflicts.any((c) => c.bindingIds.contains(id));
    final expanded = _expandedId == id;
    final theme = Theme.of(context);
    final contextLabel =
        bindingContextLabels[row['context']] ?? '${row['context']}';
    final followUps = (row['followUpActions'] as List? ?? []).length;
    void toggle() => setState(() => _expandedId = expanded ? null : id);
    return Card.filled(
      key: ValueKey(id),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: conflicted
            ? BorderSide(color: theme.colorScheme.error)
            : BorderSide.none,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey('edit-binding:$id'),
            onTap: toggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  Icon(
                    bindingDeviceIcon(device),
                    size: 24,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _inputBadge(row, showDevice: false),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                contextLabel,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (followUps > 0) ...[
                              const SizedBox(width: 8),
                              Tooltip(
                                message: t.bindingEditor.followUps,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.format_list_numbered,
                                      size: 14,
                                    ),
                                    Text(
                                      ' +$followUps',
                                      style: theme.textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (conflicted) ...[
                              const SizedBox(width: 6),
                              Tooltip(
                                message: t.bindingEditor.conflictHint,
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  size: 16,
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Switch(
                    value: row['enabled'] == true,
                    onChanged: (value) => _update({...row, 'enabled': value}),
                  ),
                  IconButton(
                    tooltip: expanded
                        ? t.bindingEditor.collapse
                        : t.bindingEditor.expand,
                    onPressed: toggle,
                    icon: Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (conflicted)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        t.bindingEditor.conflictHint,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  if (!managed) ...[
                    BindingSelect<String>(
                      label: t.bindingEditor.context,
                      value: row['context'] as String,
                      options: bindingContextLabels,
                      onChanged: (value) => _update({...row, 'context': value}),
                    ),
                    const SizedBox(height: 12),
                  ],
                  BindingInputEditor(
                    key: ValueKey('$id:$device'),
                    input: input,
                    onChanged: (value) => _update({...row, 'input': value}),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      t.bindingEditor.ignoreRepeat,
                      style: theme.textTheme.bodySmall,
                    ),
                    value: row['ignoreRepeat'] == true,
                    onChanged: (value) =>
                        _update({...row, 'ignoreRepeat': value}),
                  ),
                  _followUps(row),
                  if (!managed) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        PopupMenuButton<String>(
                          tooltip: t.bindingEditor.copyTo,
                          onSelected: (target) => widget.onChanged([
                            ...widget.bindings,
                            copyBindingToContext(row, target),
                          ]),
                          itemBuilder: (_) => [
                            for (final target in bindingContextLabels.entries)
                              if (target.key != row['context'])
                                PopupMenuItem(
                                  value: target.key,
                                  child: Text(target.value),
                                ),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.copy_outlined, size: 18),
                                const SizedBox(width: 8),
                                Text(t.bindingEditor.copyTo),
                                const Icon(Icons.arrow_drop_down, size: 18),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: t.settings.operationBindingRemove,
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () => widget.onChanged(
                            removeBindingById(widget.bindings, id),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _followUps(Map<String, dynamic> row) {
    final actions = List<String>.from(row['followUpActions'] as List? ?? []);
    void change(List<String> next) =>
        _update({...row, 'followUpActions': next});
    void move(int index, int delta) {
      final next = [...actions];
      final value = next.removeAt(index);
      next.insert(index + delta, value);
      change(next);
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.format_list_numbered, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(t.bindingEditor.followUps)),
              Text('${actions.length}/7'),
              TextButton.icon(
                onPressed: actions.length >= 7
                    ? null
                    : () => change([...actions, BindingAction.nextPage]),
                icon: const Icon(Icons.add, size: 16),
                label: Text(t.bindingEditor.add),
              ),
            ],
          ),
          for (var i = 0; i < actions.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Text('${i + 2}'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: BindingSelect<String>(
                      label: '${t.bindingEditor.followUps} ${i + 1}',
                      value: actions[i],
                      options: {
                        for (final action in widget.catalog)
                          if (action.implemented || actions.contains(action.id))
                            action.id: actionLabel(action),
                      },
                      onChanged: (value) => change([...actions]..[i] = value),
                    ),
                  ),
                  IconButton(
                    tooltip: t.bindingEditor.moveUp,
                    onPressed: i == 0 ? null : () => move(i, -1),
                    icon: const Icon(Icons.arrow_upward, size: 16),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    tooltip: t.bindingEditor.moveDown,
                    onPressed: i == actions.length - 1
                        ? null
                        : () => move(i, 1),
                    icon: const Icon(Icons.arrow_downward, size: 16),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    tooltip: t.common.delete,
                    onPressed: () => change([...actions]..removeAt(i)),
                    icon: const Icon(Icons.close, size: 16),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
