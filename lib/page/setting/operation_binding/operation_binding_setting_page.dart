import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart'
    show
        Clipboard,
        ClipboardData,
        KeyEvent,
        KeyDownEvent,
        KeyRepeatEvent,
        LogicalKeyboardKey;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/setting/operation_binding/radial_binding_editor.dart';
import 'package:zephyr/service/operation_binding/action_labels.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';
import 'package:zephyr/service/operation_binding/radial_doc.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/toast.dart';

/// 「操作绑定」设置页（ADR-0015 的外壳那一半）。
///
/// 三件事：① 列动作 —— 清单与「能不能用」全部取自 Rust 注册表
/// （[OperationBindingStore.actionCatalog]），这里不维护第二份名单；② 录制输入 ——
/// `LogicalKeyboardKey → code` 的翻译在 `binding_doc.dart`（映射归外壳，ADR-0015 §6）；
/// ③ **冲突阻止保存** —— 一个输入只许一条生效绑定，有冲突就列出并拒绝保存，
/// 不安静地取第一条（neoview 同语义）。
///
/// 版式照 neoview 那一屏：**左侧动作清单 + 右侧编辑区**两栏；窄屏退化成单栏
/// （清单在上、选中的编辑区紧跟其下），不换第二套交互。
///
/// 编辑的是**工作副本**，按下「保存」才落盘：中途反悔不该影响正在读的那本书。
/// 落盘后运行时立刻生效、不需要重启 —— 绑定表是数据（判据 E2）。
@RoutePage()
class OperationBindingSettingPage extends StatefulWidget {
  const OperationBindingSettingPage({super.key});

  @override
  State<OperationBindingSettingPage> createState() =>
      _OperationBindingSettingPageState();
}

/// 左栏的一项：一个动作、一个点击分区、或「绑定包」那一组操作。
class _BindingEntry {
  const _BindingEntry({
    required this.id,
    this.action,
    this.area,
    this.isBundle = false,
  });

  @override
  String toString() => id;

  final String id;
  final BindingActionInfo? action;
  final String? area;
  final bool isBundle;
}

class _OperationBindingSettingPageState
    extends State<OperationBindingSettingPage> {
  var _bindings = const <Map<String, dynamic>>[];
  var _catalog = const <BindingActionInfo>[];
  var _dirty = false;
  String _selectedId = '';

  /// 轮盘的**形状**工作副本（槽位的动作在 `_bindings` 里，与运行时同一张表）。
  late RadialDoc _radialDoc;

  /// 顶部那一档：false = 快捷键（左清单右编辑），true = 轮盘。
  var _radialTab = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<GlobalSettingCubit>().state;
    // 表为空 / 读不出（比如还没播种）时，编辑区先摆一份出厂表 —— 但**不落盘**，
    // 用户不保存就什么都不变。
    _bindings =
        parseBindings(state.operationBindingSetting.bindingsJson) ??
        parseBindings(
          OperationBindingStore.factoryBindingsJson(
            tapMode: state.readSetting.tapPageTurnMode,
          ),
        ) ??
        const [];
    _radialDoc =
        parseRadialDoc(state.operationBindingSetting.radialJson) ??
        parseRadialDoc(OperationBindingStore.radialFactoryJson())!;
    _catalog = OperationBindingStore.actionCatalog();
    _selectedId = _entries.isEmpty ? '' : _entries.first.id;
  }

  void _edit(List<Map<String, dynamic>> next) {
    setState(() {
      _bindings = next;
      _dirty = true;
    });
  }

  /// 轮盘编辑器改了什么（形状、或某个槽绑到什么动作）都走这里。
  void _editRadial(RadialDoc doc, List<Map<String, dynamic>> bindings) {
    setState(() {
      _radialDoc = doc;
      _bindings = bindings;
      _dirty = true;
    });
  }

  // ── 清单 ──────────────────────────────────────────────────────────────────

  /// 左栏的项：注册表里的动作（按注册表的分类分组）+ 三个点击分区 + 绑定包。
  /// 顺序**跟着注册表**，引擎追加动作时这里不用改。
  List<_BindingEntry> get _entries => [
    for (final entry in _catalog)
      _BindingEntry(id: 'action:${entry.id}', action: entry),
    for (final area in TapArea.all) _BindingEntry(id: 'area:$area', area: area),
    const _BindingEntry(id: 'bundle', isBundle: true),
  ];

  /// `(分类显示名, 该分类的项)` —— 分组只为了画小标题，不改变注册表给的顺序。
  List<(String, List<_BindingEntry>)> get _groupedEntries {
    final groups = <(String, List<_BindingEntry>)>[];
    for (final entry in _entries) {
      final title = switch (entry) {
        _ when entry.isBundle => t.settings.operationBindingSectionBundle,
        _ when entry.area != null => t.settings.operationBindingSectionTap,
        _ => _categoryLabel(entry.action!.category),
      };
      final index = groups.indexWhere((group) => group.$1 == title);
      if (index < 0) {
        groups.add((title, [entry]));
      } else {
        groups[index] = (groups[index].$1, [...groups[index].$2, entry]);
      }
    }
    return groups;
  }

  _BindingEntry? get _selected {
    for (final entry in _entries) {
      if (entry.id == _selectedId) return entry;
    }
    return null;
  }

  // ── 保存：先校验、再问冲突，冲突非空就拒绝 ────────────────────────────────

  Future<void> _save() async {
    // 轮盘的形状先过一遍：形状不合法（层数越界、id 重复…）时连绑定表都不必问，
    // 而且**拒绝保存**而不是「存下去但画不出来」。
    if (!OperationBindingStore.radialIsValid(_radialDoc.encode())) {
      final problems = OperationBindingStore.radialProblems(_radialDoc.encode());
      showErrorToast(
        problems.isEmpty
            ? t.settings.operationBindingRadialInvalid
            : problems.first,
        context: context,
      );
      return;
    }
    if (!OperationBindingStore.isValid(_bindings)) {
      showErrorToast(t.settings.operationBindingInvalidTable, context: context);
      return;
    }
    final conflicts = OperationBindingStore.conflictsOf(_bindings);
    if (conflicts == null) {
      showErrorToast(t.settings.operationBindingInvalidTable, context: context);
      return;
    }
    if (conflicts.isNotEmpty) {
      // 冲突**挡住保存**，并把「是哪两条撞了」摊开给用户看 —— 禁用其中一条即可解开。
      await _showConflicts(conflicts);
      return;
    }
    context.read<GlobalSettingCubit>().updateOperationBindingSetting(
      (current) => current.copyWith(
        bindingsJson: encodeBindingsDoc(_bindings),
        radialJson: _radialDoc.encode(),
      ),
    );
    setState(() => _dirty = false);
    showSuccessToast(t.settings.operationBindingSaved, context: context);
  }

  void _discard() {
    final persisted = context
        .read<GlobalSettingCubit>()
        .state
        .operationBindingSetting;
    setState(() {
      _bindings = parseBindings(persisted.bindingsJson) ?? const [];
      _radialDoc =
          parseRadialDoc(persisted.radialJson) ??
          parseRadialDoc(OperationBindingStore.radialFactoryJson())!;
      _dirty = false;
    });
    showInfoToast(t.settings.operationBindingDiscarded, context: context);
  }

  Future<void> _restoreFactory() async {
    final confirmed = await _confirm(
      title: t.settings.operationBindingRestoreFactory,
      body: t.settings.operationBindingRestoreFactorySubtitle,
    );
    if (!confirmed) return;
    if (!mounted) return;
    final tapMode = context
        .read<GlobalSettingCubit>()
        .state
        .readSetting
        .tapPageTurnMode;
    _editRadial(
      parseRadialDoc(OperationBindingStore.radialFactoryJson())!,
      parseBindings(
        OperationBindingStore.factoryBindingsJson(tapMode: tapMode),
      ) ??
      const [],
    );
  }

  Future<void> _showConflicts(List<BindingConflict> conflicts) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.settings.operationBindingConflictTitle),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.settings.operationBindingConflictBody),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final conflict in conflicts) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            conflict.key,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                        for (final id in conflict.bindingIds)
                          Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Text(
                              _describeBinding(id),
                              style: Theme.of(dialogContext).textTheme
                                  .bodySmall,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(t.common.confirm),
          ),
        ],
      ),
    );
  }

  /// 冲突清单里要说清「是哪条」，而引擎只给 id：拿 id 回到表里查动作与输入。
  String _describeBinding(String id) {
    for (final binding in _bindings) {
      if (binding['id'] != id) continue;
      final actionId = binding['action'] as String? ?? '';
      final input = binding['input'];
      return '$id · ${_actionLabelById(actionId)} · '
          '${input is Map ? describeInput(Map<String, dynamic>.from(input)) : '?'}';
    }
    return id;
  }

  Future<bool> _confirm({required String title, required String body}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t.common.confirm),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _export() async {
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _JsonDialog(
        title: t.settings.operationBindingExport,
        initialText: prettyBindingsDoc(_bindings),
        readOnly: true,
        actionLabel: t.settings.operationBindingCopy,
      ),
    );
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      showSuccessToast(t.settings.operationBindingCopied, context: context);
    }
  }

  Future<void> _import() async {
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _JsonDialog(
        title: t.settings.operationBindingImport,
        initialText: prettyBindingsDoc(_bindings),
        actionLabel: t.settings.operationBindingImportConfirm,
      ),
    );
    if (text == null) return;
    final bindings = parseBindings(text);
    if (bindings == null || !OperationBindingStore.isValid(bindings)) {
      if (mounted) {
        showErrorToast(
          t.settings.operationBindingInvalidTable,
          context: context,
        );
      }
      return;
    }
    // 导入的表允许暂时带着冲突（用户可能只想先看一眼），但「保存」那一关照样挡。
    _edit(bindings);
    if (mounted) {
      showInfoToast(
        t.settings.operationBindingImportLoaded(count: bindings.length),
        context: context,
      );
    }
  }

  // ── 版式 ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SettingPageShell(
      title: t.settings.operationBinding,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          const SizedBox(height: 4),
          const _RuntimeSwitch(),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight, child: _tabToggle()),
          const SizedBox(height: 12),
          if (_radialTab)
            RadialBindingEditor(
              doc: _radialDoc,
              bindings: _bindings,
              catalog: _catalog,
              onChanged: _editRadial,
              onSave: _save,
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                // 两栏的门槛取 760：比 `SettingPageShell` 的限宽（768）略窄一点，
                // 于是手机上必然是单栏，桌面窗口拉窄时也自动退化 —— 不需要用户设置。
                if (constraints.maxWidth < 760) return _singleColumn();
                return _twoColumn();
              },
            ),
          const SizedBox(height: 16),
          _saveRow(),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _dirty
                  ? t.settings.operationBindingDirtyHint
                  : t.settings.operationBindingSubtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 「快捷键 / 轮盘」那一档（截图右上角的胶囊切换）。
  ///
  /// 两档编辑的是**同一份工作副本**（`_bindings`）：轮盘的槽位就是绑定表里的
  /// `radial` 行，所以不需要「先保存快捷键才能改轮盘」这种步骤。
  Widget _tabToggle() {
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: false,
          icon: const Icon(Icons.keyboard_outlined, size: 18),
          label: Text(t.settings.operationBindingTabKeyboard),
        ),
        ButtonSegment(
          value: true,
          icon: const Icon(Icons.gradient_outlined, size: 18),
          label: Text(t.settings.operationBindingTabRadial),
        ),
      ],
      selected: {_radialTab},
      onSelectionChanged: (selection) =>
          setState(() => _radialTab = selection.first),
    );
  }

  Widget _twoColumn() {
    return SizedBox(
      height: 520,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 250, child: _masterList()),
          const SizedBox(width: 12),
          Expanded(child: _detailCard()),
        ],
      ),
    );
  }

  Widget _singleColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _masterList(shrinkWrap: true),
        const SizedBox(height: 12),
        _detailCard(),
      ],
    );
  }

  Widget _masterList({bool shrinkWrap = false}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListView(
        shrinkWrap: shrinkWrap,
        physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
        padding: const EdgeInsets.symmetric(vertical: 6),
        children: [
          for (final group in _groupedEntries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text(
                group.$1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            for (final entry in group.$2) _masterTile(entry),
          ],
        ],
      ),
    );
  }

  Widget _masterTile(_BindingEntry entry) {
    final action = entry.action;
    final selected = entry.id == _selectedId;
    final boundCount = action == null
        ? (entry.area == null ? 0 : 1)
        : bindingsForAction(_bindings, action.id).length;
    return ListTile(
      selected: selected,
      // 未实现的动作置灰（能不能执行写在注册表的数据里，UI 不另立名单），
      // 但仍然**可以选中查看** —— 导入的表里可能就有它，看不见就没法解释。
      textColor: action != null && !action.implemented
          ? Theme.of(context).colorScheme.onSurfaceVariant
          : null,
      title: Text(_entryTitle(entry)),
      trailing: boundCount == 0
          ? null
          : Text(
              '$boundCount',
              style: Theme.of(context).textTheme.bodySmall,
            ),
      onTap: () => setState(() => _selectedId = entry.id),
    );
  }

  Widget _detailCard() {
    final entry = _selected;
    if (entry == null) return const SizedBox.shrink();
    return SettingSectionCard(
      title: _entryTitle(entry),
      icon: entry.isBundle
          ? Icons.data_object_outlined
          : entry.area != null
          ? Icons.touch_app_outlined
          : Icons.keyboard_outlined,
      children: [
        if (entry.isBundle)
          ..._bundleRows()
        else if (entry.area != null)
          ..._areaRows(entry.area!)
        else
          ..._actionRows(entry.action!),
      ],
    );
  }

  List<Widget> _actionRows(BindingActionInfo action) {
    if (!action.implemented) {
      return [
        ListTile(
          leading: const Icon(Icons.block_outlined),
          title: Text(t.settings.operationBindingUnimplemented),
          subtitle: Text(action.label),
        ),
      ];
    }
    final rows = bindingsForAction(_bindings, action.id);
    return [
      for (final row in rows)
        ListTile(
          dense: true,
          leading: Icon(
            (row['input'] as Map?)?['device'] == InputDevice.area
                ? Icons.touch_app_outlined
                : Icons.keyboard_outlined,
          ),
          title: Text(
            describeInput(Map<String, dynamic>.from(row['input'] as Map)),
          ),
          subtitle: row['enabled'] == true
              ? null
              : Text(t.settings.operationBindingDisabledRow),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                thumbIcon: kSettingSwitchThumbIcon,
                value: row['enabled'] == true,
                onChanged: (_) => _edit(
                  setBindingEnabled(
                    _bindings,
                    row['id'] as String,
                    row['enabled'] != true,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: t.settings.operationBindingRemove,
                onPressed: () =>
                    _edit(removeBindingById(_bindings, row['id'] as String)),
              ),
            ],
          ),
        ),
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(t.settings.operationBindingNoKeys),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.tonalIcon(
          onPressed: () => _recordFor(action),
          icon: const Icon(Icons.add),
          label: Text(t.settings.operationBindingAddKey),
        ),
      ),
    ];
  }

  Future<void> _recordFor(BindingActionInfo action) async {
    final inputJson = await _KeyRecorderDialog.show(context);
    if (inputJson == null || !mounted) return;
    _edit([
      ..._bindings,
      buildBinding(
        id: newBindingId(action.id),
        action: action.id,
        context: 'reader',
        inputJson: inputJson,
      ),
    ]);
  }

  List<Widget> _areaRows(String area) {
    final items = <String, String>{
      '': t.settings.operationBindingUnbound,
      for (final entry in _catalog)
        if (entry.implemented) entry.id: _actionLabel(entry),
    };
    final current = actionForArea(_bindings, area) ?? '';
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Text(t.settings.operationBindingTapSubtitle),
      ),
      ListTile(
        title: Text(t.settings.operationBindingBoundAction),
        trailing: SizedBox(
          width: 200,
          child: FluentDropdown<String>(
            value: items.containsKey(current) ? current : '',
            displayValue: items[current] ?? current,
            items: items,
            onChanged: (next) => _edit(bindArea(_bindings, area, next)),
          ),
        ),
      ),
    ];
  }

  List<Widget> _bundleRows() => [
    ListTile(
      leading: const Icon(Icons.upload_outlined),
      title: Text(t.settings.operationBindingImport),
      subtitle: Text(t.settings.operationBindingImportSubtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: _import,
    ),
    ListTile(
      leading: const Icon(Icons.download_outlined),
      title: Text(t.settings.operationBindingExport),
      subtitle: Text(t.settings.operationBindingExportSubtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: _export,
    ),
    ListTile(
      leading: const Icon(Icons.restart_alt_outlined),
      title: Text(t.settings.operationBindingRestoreFactory),
      subtitle: Text(t.settings.operationBindingRestoreFactorySubtitle),
      onTap: _restoreFactory,
    ),
  ];

  Widget _saveRow() {
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: _dirty ? _save : null,
            child: Text(t.settings.operationBindingSave),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            onPressed: _dirty ? _discard : null,
            child: Text(t.settings.operationBindingDiscard),
          ),
        ),
      ],
    );
  }

  String _entryTitle(_BindingEntry entry) {
    if (entry.isBundle) return t.settings.operationBindingSectionBundle;
    if (entry.area != null) return _areaLabel(entry.area!);
    return _actionLabel(entry.action!);
  }

  String _areaLabel(String area) => switch (area) {
    TapArea.middleLeft => t.settings.operationBindingAreaMiddleLeft,
    TapArea.middleCenter => t.settings.operationBindingAreaMiddleCenter,
    _ => t.settings.operationBindingAreaMiddleRight,
  };

  String _categoryLabel(String category) => switch (category) {
    'navigation' => t.settings.operationBindingCategoryNavigation,
    'zoom' => t.settings.operationBindingCategoryZoom,
    'view' => t.settings.operationBindingCategoryView,
    'session' => t.settings.operationBindingCategorySession,
    _ => category,
  };

  /// 动作显示名。映射本身住在 `action_labels.dart`：按键区、点击区、轮盘槽位、
  /// 冲突清单都要显示同一个名字，两处各写一份 switch 迟早分叉。
  String _actionLabelById(String actionId) {
    for (final entry in _catalog) {
      if (entry.id == actionId) return actionLabel(entry);
    }
    return actionId;
  }

  String _actionLabel(BindingActionInfo entry) => actionLabel(entry);
}

/// 总开关：运行时到底查不查这张表。
class _RuntimeSwitch extends StatelessWidget {
  const _RuntimeSwitch();

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final setting = cubit.state.operationBindingSetting;
    return SettingSectionCard(
      title: t.settings.operationBindingSectionSwitch,
      icon: Icons.toggle_on_outlined,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.bolt_outlined),
          title: Text(t.settings.operationBindingRuntime),
          subtitle: Text(t.settings.operationBindingRuntimeSubtitle),
          thumbIcon: kSettingSwitchThumbIcon,
          value: setting.bindingsRuntime,
          onChanged: (value) => cubit.updateOperationBindingSetting(
            (current) => current.copyWith(bindingsRuntime: value),
          ),
        ),
      ],
    );
  }
}

/// 按键录入框：按下即产出 descriptor，Esc 取消。
class _KeyRecorderDialog extends StatefulWidget {
  const _KeyRecorderDialog();

  static Future<String?> show(BuildContext context) => showDialog<String>(
    context: context,
    builder: (dialogContext) => const _KeyRecorderDialog(),
  );

  @override
  State<_KeyRecorderDialog> createState() => _KeyRecorderDialogState();
}

class _KeyRecorderDialogState extends State<_KeyRecorderDialog> {
  String? _unboundable;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    final inputJson = keyboardInputJsonOf(event);
    if (inputJson == null) {
      // 认不出平台无关名字的键（重音字母、未命名键码）：说清楚为什么录不进去，
      // 而不是让用户反复按 —— 静默失败最难查。
      setState(() => _unboundable = event.logicalKey.keyLabel);
      return KeyEventResult.handled;
    }
    Navigator.of(context).pop(inputJson);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.settings.operationBindingRecordTitle),
      content: Focus(
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.settings.operationBindingRecordHint),
            if (_unboundable != null) ...[
              const SizedBox(height: 8),
              Text(
                t.settings.operationBindingRecordUnsupported(
                  label: _unboundable!,
                ),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.common.cancel),
        ),
      ],
    );
  }
}

/// 一个多行 JSON 文本框（导出用只读 + 复制；导入用可编辑）。
class _JsonDialog extends StatefulWidget {
  const _JsonDialog({
    required this.title,
    required this.initialText,
    required this.actionLabel,
    this.readOnly = false,
  });

  final String title;
  final String initialText;
  final String actionLabel;
  final bool readOnly;

  @override
  State<_JsonDialog> createState() => _JsonDialogState();
}

class _JsonDialogState extends State<_JsonDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.settings.operationBindingJsonHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                readOnly: widget.readOnly,
                maxLines: 14,
                minLines: 8,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.common.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}
