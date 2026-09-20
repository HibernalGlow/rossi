import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/setting/operation_binding/radial_binding_editor.dart';
import 'package:zephyr/service/operation_binding/action_labels.dart';
import 'package:zephyr/page/setting/operation_binding/input_bindings_editor.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';
import 'package:zephyr/service/operation_binding/radial_doc.dart';
import 'package:zephyr/widgets/toast.dart';

/// 「操作绑定」设置页（ADR-0015 的外壳那一半）。
///
/// 三件事：① 列动作 —— 清单与「能不能用」全部取自 Rust 注册表
/// （[OperationBindingStore.actionCatalog]），这里不维护第二份名单；② 录制输入 ——
/// `LogicalKeyboardKey → code` 的翻译在 `binding_doc.dart`（映射归外壳，ADR-0015 §6）；
/// ③ **冲突阻止保存** —— 一个输入只许一条生效绑定，有冲突就列出并拒绝保存，
/// 不安静地取第一条（neoview 同语义）。
///
/// 宽屏采用左侧动作清单、右侧编辑区；窄屏以「动作列表 / 绑定详情」页签切换。
///
/// 编辑工作副本，合法且无冲突时防抖自动保存；有冲突时保留草稿供修正。
/// 落盘后运行时立刻生效、不需要重启 —— 绑定表是数据（判据 E2）。
@RoutePage()
class OperationBindingSettingPage extends StatefulWidget {
  const OperationBindingSettingPage({super.key});

  @override
  State<OperationBindingSettingPage> createState() =>
      _OperationBindingSettingPageState();
}

class _OperationBindingSettingPageState
    extends State<OperationBindingSettingPage> {
  var _bindings = const <Map<String, dynamic>>[];
  var _catalog = const <BindingActionInfo>[];
  var _dirty = false;
  Timer? _autosave;
  var _conflicts = const <BindingConflict>[];
  String? _saveError;

  /// 轮盘的**形状**工作副本（槽位的动作在 `_bindings` 里，与运行时同一张表）。
  late RadialDoc _radialDoc;

  /// 顶部那一档：false = 快捷键（左清单右编辑），true = 轮盘。
  var _radialTab = false;
  var _inputEditorRevision = 0;

  @override
  void initState() {
    super.initState();
    final state = context.read<GlobalSettingCubit>().state;
    // 表为空 / 读不出（比如还没播种）时，编辑区先摆一份出厂表 —— 但**不落盘**，
    // 用户不保存就什么都不变。
    _bindings =
        parseBindings(state.operationBindingSetting.bindingsJson) ??
        parseBindings(OperationBindingStore.factoryBindingsJson()) ??
        const [];
    _radialDoc =
        parseRadialDoc(state.operationBindingSetting.radialJson) ??
        parseRadialDoc(OperationBindingStore.radialFactoryJson())!;
    _catalog = OperationBindingStore.actionCatalog();
    _refreshValidation();
  }

  @override
  void dispose() {
    _autosave?.cancel();
    super.dispose();
  }

  void _refreshValidation() {
    _conflicts = OperationBindingStore.conflictsOf(_bindings) ?? const [];
  }

  void _scheduleSave() {
    _autosave?.cancel();
    _autosave = Timer(
      const Duration(milliseconds: 220),
      () => _save(automatic: true),
    );
  }

  void _edit(List<Map<String, dynamic>> next) {
    setState(() {
      _bindings = next;
      _dirty = true;
      _saveError = null;
      _refreshValidation();
    });
    _scheduleSave();
  }

  void _editRadial(RadialDoc doc, List<Map<String, dynamic>> bindings) {
    _radialDoc = doc;
    _edit(bindings);
  }

  // ── 保存：先校验、再问冲突，冲突非空就拒绝 ────────────────────────────────

  Future<void> _save({bool automatic = false}) async {
    _autosave?.cancel();
    if (!mounted || !_dirty) return;
    if (automatic &&
        (!OperationBindingStore.radialIsValid(_radialDoc.encode()) ||
            !OperationBindingStore.isValid(_bindings))) {
      setState(() => _saveError = t.bindingEditor.invalid);
      return;
    }
    // 轮盘的形状先过一遍：形状不合法（层数越界、id 重复…）时连绑定表都不必问，
    // 而且**拒绝保存**而不是「存下去但画不出来」。
    if (!OperationBindingStore.radialIsValid(_radialDoc.encode())) {
      final problems = OperationBindingStore.radialProblems(
        _radialDoc.encode(),
      );
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
      if (!automatic) await _showConflicts(conflicts);
      return;
    }
    context.read<GlobalSettingCubit>().updateOperationBindingSetting(
      (current) => current.copyWith(
        bindingsJson: encodeBindingsDoc(_bindings),
        radialJson: _radialDoc.encode(),
      ),
    );
    setState(() => _dirty = false);
    if (!automatic) {
      showSuccessToast(t.settings.operationBindingSaved, context: context);
    }
  }

  void _discard() {
    _autosave?.cancel();
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
      _saveError = null;
      _refreshValidation();
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
    _inputEditorRevision++;
    _editRadial(
      parseRadialDoc(OperationBindingStore.radialFactoryJson())!,
      parseBindings(OperationBindingStore.factoryBindingsJson()) ?? const [],
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
                              style: Theme.of(
                                dialogContext,
                              ).textTheme.bodySmall,
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _save(automatic: true);
        if (!context.mounted) return;
        if (_dirty) {
          final discard = await _confirm(
            title: t.settings.operationBindingDiscard,
            body: t.settings.operationBindingDirtyHint,
          );
          if (!discard || !mounted) return;
          _discard();
        }
        if (context.mounted) Navigator.of(context).pop();
      },
      child: SettingPageShell(
        title: t.settings.operationBinding,
        maxWidth: 1600,
        child: ListView(
          padding: kSettingPagePadding,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BlocBuilder<GlobalSettingCubit, GlobalSettingState>(
                      builder: (context, state) => Switch(
                        value: state.operationBindingSetting.bindingsRuntime,
                        onChanged: (value) => context
                            .read<GlobalSettingCubit>()
                            .updateOperationBindingSetting(
                              (current) =>
                                  current.copyWith(bindingsRuntime: value),
                            ),
                      ),
                    ),
                    Text(t.settings.operationBindingRuntime),
                  ],
                ),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: false,
                      icon: const Icon(Icons.keyboard_outlined, size: 18),
                      label: Text(t.settings.operationBindingTabKeyboard),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.donut_large, size: 18),
                      label: Text(t.settings.operationBindingTabRadial),
                    ),
                  ],
                  selected: {_radialTab},
                  onSelectionChanged: (selection) =>
                      setState(() => _radialTab = selection.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  _saveError ??
                      (_conflicts.isNotEmpty
                          ? t.bindingEditor.conflict
                          : _dirty
                          ? t.bindingEditor.pending
                          : t.bindingEditor.saved),
                  style: TextStyle(
                    color: _saveError != null || _conflicts.isNotEmpty
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: _import,
                      icon: const Icon(Icons.upload_outlined, size: 16),
                      label: Text(t.settings.operationBindingImport),
                    ),
                    TextButton.icon(
                      onPressed: _export,
                      icon: const Icon(Icons.download_outlined, size: 16),
                      label: Text(t.settings.operationBindingExport),
                    ),
                    OutlinedButton.icon(
                      onPressed: _restoreFactory,
                      icon: const Icon(Icons.restart_alt, size: 16),
                      label: Text(t.bindingEditor.restore),
                    ),
                  ],
                ),
              ],
            ),
            if (_conflicts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.bindingEditor.conflictHint,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _showConflicts(_conflicts),
                      child: Text(t.bindingEditor.conflict),
                    ),
                    TextButton(
                      onPressed: _discard,
                      child: Text(t.settings.operationBindingDiscard),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            if (_radialTab)
              RadialBindingEditor(
                doc: _radialDoc,
                bindings: _bindings,
                catalog: _catalog,
                onChanged: _editRadial,
                onSave: _save,
              )
            else
              InputBindingsEditor(
                // 冲突提示插入 ListView 时仍保留编辑器状态与滚动位置。
                // 仅主动恢复默认时重建，清空筛选并返回动作列表。
                key: ValueKey('input-bindings-editor-$_inputEditorRevision'),
                bindings: _bindings,
                catalog: _catalog,
                conflicts: _conflicts,
                onChanged: _edit,
              ),
          ],
        ),
      ),
    );
  }

  /// 动作显示名。映射本身住在 `action_labels.dart`：按键区、点击区、轮盘槽位、
  /// 冲突清单都要显示同一个名字，两处各写一份 switch 迟早分叉。
  String _actionLabelById(String actionId) {
    for (final entry in _catalog) {
      if (entry.id == actionId) return actionLabel(entry);
    }
    return actionId;
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
                decoration: const InputDecoration(border: OutlineInputBorder()),
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
