// 「操作绑定 → 轮盘」编辑器（照 neoview 那一屏的形状复刻）。
//
// ## 为什么它不自己存东西
//
// 编辑器**不持有任何权威**：形状（几个轮盘 / 几层 / 半径）从核心的轮盘文档读、
// 改完写回工作副本；每一格「干什么」是绑定表里的一条 `radial` 绑定，下拉选项来自
// 核心注册表。所以这里既没有「有哪些动作」的第二份名单，也没有第二套角度算术 ——
// 预览用的 painter 与运行时浮层是同一个（`lib/widgets/radial/`）。
//
// ## 交互照截图
//
// 点轮盘上的空槽 → 选中它 → 下面的槽位区出现那一格的绑定下拉；点已有槽同理
// （「点空格添加，点已有槽编辑」）。改层数 / 格数 / 删轮盘会**剪掉**指向已不存在
// 槽位的绑定，那一步在核心做（`radial_prune_bindings`）——「哪些槽还存在」正是
// 核心的算术，外壳重算一遍迟早分叉。

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/service/operation_binding/action_labels.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';
import 'package:zephyr/service/operation_binding/radial_doc.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/radial/radial_wheel_painter.dart';
import 'package:zephyr/widgets/toast.dart';

/// 轮盘编辑器。
class RadialBindingEditor extends StatefulWidget {
  const RadialBindingEditor({
    super.key,
    required this.doc,
    required this.bindings,
    required this.catalog,
    required this.onChanged,
    required this.onSave,
  });

  /// 轮盘文档的工作副本（形状）。
  final RadialDoc doc;

  /// 绑定表的工作副本（槽位的动作住在里面）。
  final List<Map<String, dynamic>> bindings;

  /// 动作注册表（下拉框的选项，全部来自核心）。
  final List<BindingActionInfo> catalog;

  final void Function(RadialDoc doc, List<Map<String, dynamic>> bindings)
  onChanged;
  final VoidCallback onSave;

  @override
  State<RadialBindingEditor> createState() => _RadialBindingEditorState();
}

class _RadialBindingEditorState extends State<RadialBindingEditor> {
  /// 当前在轮盘上选中（要编辑）的那一格的 `itemId`。
  String? _selectedItem;

  bool _geometryOpen = false;

  RadialDoc get _doc => widget.doc;

  RadialMenuDoc? get _menu => _doc.activeMenu;

  /// 核心算出的槽位布局：预览的画法与点击命中都读它，两边不可能分叉。
  List<RadialSlotPaint> get _layout => OperationBindingStore.radialLayout(
    configJson: _doc.encode(),
    menuId: _menu?.id ?? '',
  );

  /// `itemId` → 显示文字。编辑区显示**已绑的**动作，连停用的也显示：
  /// 用户在这里要看的是「这一格我绑过什么」，不是运行时会不会触发。
  Map<String, String> _labelsFor(List<RadialSlotPaint> layout) {
    final byId = actionLabelsById();
    final out = <String, String>{};
    for (final slot in layout) {
      final actionId = actionForSlot(
        widget.bindings,
        (menuId: slot.menuId, itemId: slot.itemId),
      );
      if (actionId == null || actionId.isEmpty) continue;
      out[slot.itemId] = byId[actionId] ?? actionId;
    }
    return out;
  }

  void _emit(RadialDoc next) => widget.onChanged(next, widget.bindings);

  /// 改形状（层数 / 格数 / 半径 / 删轮盘）之后要剪枝。
  void _emitShape(RadialDoc next) {
    widget.onChanged(
      next,
      OperationBindingStore.radialPrune(
        configJson: next.encode(),
        bindings: widget.bindings,
      ),
    );
  }

  // ── 头部那一行 ────────────────────────────────────────────────────────────

  void _toggleEnabled(bool value) => _emit(_doc.copyWith(enabled: value));

  void _selectMenu(String id) {
    if (id.isEmpty || id == _doc.activeMenuId) return;
    setState(() => _selectedItem = null);
    _emit(_doc.copyWith(activeMenuId: id));
  }

  void _setLayers(String value) {
    final menu = _menu;
    final layers = int.tryParse(value);
    if (menu == null || layers == null) return;
    setState(() => _selectedItem = null);
    _emitShape(_doc.withMenuReplaced(menu.copyWith(layers: layers)));
  }

  void _addMenu() {
    final created = OperationBindingStore.radialNewMenu(_doc.menus.length);
    if (created == null) return;
    _emit(_doc.withMenu(created));
    showInfoToast(
      t.settings.operationBindingRadialEmptyWheel,
      context: context,
    );
  }

  Future<void> _deleteMenu() async {
    final menu = _menu;
    if (menu == null) return;
    if (_doc.menus.length <= 1) {
      showErrorToast(
        t.settings.operationBindingRadialDeleteLast,
        context: context,
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.settings.operationBindingRadialDelete),
        content: Text(
          t.settings.operationBindingRadialDeleteConfirm(name: menu.name),
        ),
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
    if (confirmed != true || !mounted) return;
    setState(() => _selectedItem = null);
    _emitShape(_doc.withoutMenu(menu.id));
  }

  void _resetSlots() {
    final menu = _menu;
    if (menu == null) return;
    // 只重写这个轮盘的**预设**那几条（id 前缀 `preset-radial-{menuId}-`），
    // 用户在别的输入上自绑的一律不动。
    final rows = [
      for (final row in OperationBindingStore.radialPresetBindings(menu.id))
        if (menu.hasSlot(slotOfBinding(row)!)) row,
    ];
    widget.onChanged(
      _doc,
      resetRadialPresetSlots(widget.bindings, menu.id, rows),
    );
    showSuccessToast(
      t.settings.operationBindingRadialResetDone,
      context: context,
    );
  }

  Future<void> _preview() => showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _RadialPreviewDialog(doc: _doc, bindings: widget.bindings),
  );

  // ── 轮盘上的点击 ──────────────────────────────────────────────────────────

  void _onWheelTap(Size box, Offset local) {
    final menu = _menu;
    if (menu == null) return;
    final scale = radialFitScale(box: box, radius: menu.radius);
    final inputJson = OperationBindingStore.radialSlotInput(
      configJson: _doc.encode(),
      menuId: menu.id,
      // 命中判定读的是**未缩放**的几何，所以先把画布坐标换算回逻辑半径。
      dx: (local.dx - box.width / 2) / scale,
      dy: (local.dy - box.height / 2) / scale,
    );
    final itemId = _itemIdOf(inputJson);
    if (itemId == _selectedItem) return;
    setState(() => _selectedItem = itemId);
  }

  /// 核心回的那条 `radial` 输入里取出 `itemId`（就是喂给解析器的那份 JSON）。
  String? _itemIdOf(String? inputJson) {
    if (inputJson == null) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(inputJson);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    return decoded['itemId'] as String?;
  }

  // ── 槽位绑定 ──────────────────────────────────────────────────────────────

  RadialSlotRef? _slotOf(String itemId) {
    final menu = _menu;
    if (menu == null) return null;
    return (menuId: menu.id, itemId: itemId);
  }

  void _bindSelected(String actionId) {
    final item = _selectedItem;
    final slot = item == null ? null : _slotOf(item);
    if (slot == null) return;
    widget.onChanged(_doc, bindSlot(widget.bindings, slot, actionId));
  }

  void _unbind(String itemId) {
    final slot = _slotOf(itemId);
    if (slot == null) return;
    widget.onChanged(_doc, unbindSlot(widget.bindings, slot));
  }

  void _rename(String name) {
    final menu = _menu;
    if (menu == null || name == menu.name) return;
    _emit(_doc.withMenuReplaced(menu.copyWith(name: name)));
  }

  @override
  Widget build(BuildContext context) {
    final menu = _menu;
    final layout = _layout;
    final labels = _labelsFor(layout);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _headerRow(menu),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            _doc.enabled
                ? t.settings.operationBindingRadialHint(
                    layers: menu?.layers ?? 0,
                  )
                : t.settings.operationBindingRadialHintDisabled,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        _wheelBox(menu, layout, labels),
        const SizedBox(height: 8),
        _appearanceCard(menu),
        const SizedBox(height: 12),
        _slotsCard(menu, labels),
      ],
    );
  }

  Widget _headerRow(RadialMenuDoc? menu) {
    final menus = <String, String>{
      for (final entry in _doc.menus) entry.id: entry.name,
    };
    final layers = menu?.layers ?? 1;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              thumbIcon: kSettingSwitchThumbIcon,
              value: _doc.enabled,
              onChanged: _toggleEnabled,
            ),
            Text(t.settings.operationBindingRadialEnable),
          ],
        ),
        SizedBox(
          width: 160,
          child: FluentDropdown<String>(
            value: menus.containsKey(_doc.activeMenuId) ? _doc.activeMenuId : '',
            displayValue: menu?.name ?? '',
            items: menus,
            onChanged: _selectMenu,
          ),
        ),
        SizedBox(
          width: 110,
          child: FluentDropdown<String>(
            value: '$layers',
            displayValue: t.settings.operationBindingRadialLayerUnit(
              count: layers,
            ),
            items: {
              for (var option = 1; option <= 3; option++)
                '$option': t.settings.operationBindingRadialLayerUnit(
                  count: option,
                ),
            },
            onChanged: _setLayers,
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: _addMenu,
          icon: const Icon(Icons.add),
          label: Text(t.settings.operationBindingRadialNew),
        ),
        IconButton(
          tooltip: t.settings.operationBindingRadialDelete,
          icon: const Icon(Icons.delete_outline),
          onPressed: _deleteMenu,
        ),
        IconButton(
          tooltip: t.settings.operationBindingRadialPreview,
          icon: const Icon(Icons.visibility_outlined),
          onPressed: _preview,
        ),
        IconButton(
          tooltip: t.settings.operationBindingRadialReset,
          icon: const Icon(Icons.restart_alt_outlined),
          onPressed: _resetSlots,
        ),
        FilledButton.icon(
          onPressed: widget.onSave,
          icon: const Icon(Icons.save_outlined),
          label: Text(t.settings.operationBindingSave),
        ),
      ],
    );
  }

  /// 轮盘本体：与运行时浮层同一个 painter，点一格就选中它。
  Widget _wheelBox(
    RadialMenuDoc? menu,
    List<RadialSlotPaint> layout,
    Map<String, String> labels,
  ) {
    if (menu == null || layout.isEmpty) return const SizedBox(height: 120);
    return SizedBox(
      height: 380,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final box = constraints.biggest;
          final scale = radialFitScale(box: box, radius: menu.radius);
          return GestureDetector(
            onTapDown: (details) => _onWheelTap(box, details.localPosition),
            child: CustomPaint(
              size: box,
              painter: RadialWheelPainter(
                slots: layout,
                labels: labels,
                colors: Theme.of(context).colorScheme,
                hoveredItem: _selectedItem,
                scale: scale,
                centerLabel: menu.name,
                textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _appearanceCard(RadialMenuDoc? menu) {
    if (menu == null) return const SizedBox.shrink();
    return SettingSectionCard(
      title: t.settings.operationBindingRadialAppearance,
      icon: Icons.tune_outlined,
      children: [
        ListTile(
          title: Text(t.settings.operationBindingRadialAppearance),
          subtitle: Text(
            t.settings.operationBindingRadialGeometrySummary(
              radius: menu.radius.round(),
              inner: menu.innerRadius.round(),
              sectors: menu.sectors,
            ),
          ),
          trailing: Icon(
            _geometryOpen ? Icons.expand_less : Icons.expand_more,
          ),
          onTap: () => setState(() => _geometryOpen = !_geometryOpen),
        ),
        if (_geometryOpen) ...[
          _sliderTile(
            label: t.settings.operationBindingRadialRadius,
            value: menu.radius,
            min: 80,
            max: 240,
            onChanged: (value) =>
                _emitShape(_doc.withMenuReplaced(menu.copyWith(radius: value))),
          ),
          _sliderTile(
            label: t.settings.operationBindingRadialInnerRadius,
            value: menu.innerRadius,
            min: 0,
            max: math.max(1, menu.radius - 20),
            onChanged: (value) => _emitShape(
              _doc.withMenuReplaced(menu.copyWith(innerRadius: value)),
            ),
          ),
          _sliderTile(
            label: t.settings.operationBindingRadialSectors,
            value: menu.sectors.toDouble(),
            min: 4,
            max: 16,
            // 格数只能是整数，而格数决定槽位是否存在 ⇒ 拖动过程中也要剪枝。
            divisions: 12,
            onChanged: (value) {
              setState(() => _selectedItem = null);
              _emitShape(
                _doc.withMenuReplaced(menu.copyWith(sectors: value.round())),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _sliderTile({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    int? divisions,
  }) {
    return ListTile(
      title: Text(label),
      subtitle: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        label: value.round().toString(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _slotsCard(RadialMenuDoc? menu, Map<String, String> labels) {
    if (menu == null) return const SizedBox.shrink();
    final items = <String, String>{
      '': t.settings.operationBindingUnbound,
      for (final entry in widget.catalog)
        if (entry.implemented) entry.id: actionLabel(entry),
    };
    final selected = _selectedItem;
    final selectedAction = selected == null
        ? ''
        : actionForSlot(widget.bindings, (menuId: menu.id, itemId: selected)) ??
              '';
    final bound = radialBindingsForMenu(widget.bindings, menu.id)
        .where((row) {
          final slot = slotOfBinding(row);
          return slot != null && menu.hasSlot(slot);
        })
        .toList();
    return SettingSectionCard(
      title: t.settings.operationBindingRadialSlots,
      icon: Icons.radio_button_checked_outlined,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            t.settings.operationBindingRadialSlotsSubtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        _NameTile(name: menu.name, onRename: _rename),
        if (selected != null)
          ListTile(
            selected: true,
            title: Text(_slotLabel(selected)),
            subtitle: Text(
              labels[selected] ??
                  t.settings.operationBindingRadialEmptySlot,
            ),
            trailing: SizedBox(
              width: 220,
              child: FluentDropdown<String>(
                value: items.containsKey(selectedAction)
                    ? selectedAction
                    : '',
                displayValue: items[selectedAction] ?? selectedAction,
                items: items,
                onChanged: _bindSelected,
              ),
            ),
          ),
        for (final row in bound)
          Builder(
            builder: (context) {
              final slot = slotOfBinding(row)!;
              return ListTile(
                dense: true,
                title: Text(_slotLabel(slot.itemId)),
                subtitle: Text(actionLabelForId(row['action'] as String? ?? '')),
                selected: selected == slot.itemId,
                onTap: () => setState(() => _selectedItem = slot.itemId),
                trailing: IconButton(
                  tooltip: t.settings.operationBindingRadialUnbindSlot,
                  icon: const Icon(Icons.link_off),
                  onPressed: () => _unbind(slot.itemId),
                ),
              );
            },
          ),
      ],
    );
  }

  String _slotLabel(String itemId) {
    final parsed = parseSlotItemId(itemId);
    if (parsed == null) return itemId;
    return t.settings.operationBindingRadialSlotLabel(
      layer: parsed.$1,
      sector: parsed.$2 + 1,
    );
  }
}

/// 轮盘名：只在**提交**（回车 / 失焦）时写回，避免每敲一个字就重建一次轮盘。
class _NameTile extends StatefulWidget {
  const _NameTile({required this.name, required this.onRename});

  final String name;
  final ValueChanged<String> onRename;

  @override
  State<_NameTile> createState() => _NameTileState();
}

class _NameTileState extends State<_NameTile> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.name,
  );

  @override
  void didUpdateWidget(_NameTile old) {
    super.didUpdateWidget(old);
    // 外部换了轮盘（切换生效项）时要把输入框对齐到新名字。
    if (widget.name != old.name && widget.name != _controller.text) {
      _controller.text = widget.name;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(t.settings.operationBindingRadialName),
      trailing: SizedBox(
        width: 220,
        child: TextField(
          controller: _controller,
          onSubmitted: widget.onRename,
          onChanged: (value) {
            // 名字不进绑定包，改一个字就重建轮盘代价太大；失焦时提交。
            if (value.isEmpty) widget.onRename(value);
          },
          onEditingComplete: () => widget.onRename(_controller.text),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      ),
    );
  }
}

/// 「预览」对话框：把当前形状原样画大一遍（与编辑器、运行时同一 painter）。
class _RadialPreviewDialog extends StatelessWidget {
  const _RadialPreviewDialog({required this.doc, required this.bindings});

  final RadialDoc doc;
  final List<Map<String, dynamic>> bindings;

  @override
  Widget build(BuildContext context) {
    final menu = doc.activeMenu;
    final layout = OperationBindingStore.radialLayout(
      configJson: doc.encode(),
      menuId: menu?.id ?? '',
    );
    final byId = actionLabelsById();
    final labels = <String, String>{};
    for (final slot in layout) {
      final actionId = actionForSlot(
        bindings,
        (menuId: slot.menuId, itemId: slot.itemId),
      );
      if (actionId != null) labels[slot.itemId] = byId[actionId] ?? actionId;
    }
    return AlertDialog(
      title: Text(t.settings.operationBindingRadialPreview),
      content: SizedBox(
        width: 420,
        height: 420,
        child: menu == null
            ? const SizedBox.shrink()
            : LayoutBuilder(
                builder: (context, constraints) => CustomPaint(
                  size: constraints.biggest,
                  painter: RadialWheelPainter(
                    slots: layout,
                    labels: labels,
                    colors: Theme.of(context).colorScheme,
                    scale: radialFitScale(
                      box: constraints.biggest,
                      radius: menu.radius,
                      maxDiameter: 420,
                    ),
                    centerLabel: menu.name,
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.common.confirm),
        ),
      ],
    );
  }
}
