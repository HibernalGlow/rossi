// 轮盘文档与动作绑定编辑；交互预览使用独立 flutter_ray_menu。

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/service/operation_binding/action_labels.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';
import 'package:zephyr/service/operation_binding/radial_doc.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:flutter_ray_menu/flutter_ray_menu.dart';
import 'package:zephyr/widgets/radial/reader_ray_menu_adapter.dart';
import 'package:zephyr/widgets/toast.dart';

/// 点空格时新建条目默认绑的动作（neoview `DEFAULT_NEW_ITEM_ACTION`）。
const String kRadialDefaultNewItemAction = BindingAction.nextPage;

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

  /// 轮盘文档的工作副本（形状与条目）。
  final RadialDoc doc;

  /// 绑定表的工作副本（条目的动作住在里面）。
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
  /// 选中的条目 id（检视器编辑的就是它）。
  String? _selectedItemId;

  bool _geometryOpen = false;

  RadialDoc get _doc => widget.doc;

  RadialMenuDoc? get _menu => _doc.activeMenu;

  List<RadialSlotPaint> get _layout => OperationBindingStore.radialLayout(
    configJson: _doc.encode(),
    menuId: _menu?.id ?? '',
  );

  /// 能绑到槽位上的动作：注册表里**已实现**且不属于 `radial` 分类的那些。
  ///
  /// 「已实现」写在注册表的数据里而不是这里另立名单（ADR-0015）；排除 `radial.*`
  /// 与 neoview 的编辑器同一判据。
  Map<String, String> get _actionItems => {
    '': t.settings.operationBindingUnbound,
    for (final entry in widget.catalog)
      if (entry.implemented && entry.category != 'radial')
        entry.id: actionLabel(entry),
  };

  void _emit(RadialDoc next) => widget.onChanged(next, widget.bindings);

  /// 改形状之后要剪枝：指向已不存在条目的绑定不能留着（否则设置页列出点不到的槽）。
  void _emitShape(RadialDoc next) {
    widget.onChanged(
      next,
      OperationBindingStore.radialPrune(
        configJson: next.encode(),
        bindings: widget.bindings,
      ),
    );
  }

  void _emitMenu(RadialMenuDoc menu, {bool prune = false}) {
    final next = _doc.withMenuReplaced(menu);
    if (prune) {
      _emitShape(next);
    } else {
      _emit(next);
    }
  }

  // ── 工具条 ────────────────────────────────────────────────────────────────

  void _toggleEnabled(bool value) => _emit(_doc.copyWith(enabled: value));

  void _selectMenu(String id) {
    if (id.isEmpty || id == _doc.activeMenuId) return;
    setState(() => _selectedItemId = null);
    _emit(_doc.copyWith(activeMenuId: id));
  }

  void _setLayerCount(String value) {
    final layers = int.tryParse(value);
    if (layers == null) return;
    _emit(_doc.copyWith(layerCount: layers));
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
    setState(() => _selectedItemId = null);
    _emitShape(_doc.withoutMenu(menu.id));
  }

  void _resetSlots() {
    final menu = _menu;
    if (menu == null) return;
    // 只重写这个轮盘的**预设**绑定（id 前缀 `preset-radial-{menuId}-`），
    // 用户在别的输入上自绑的一律不动。
    widget.onChanged(
      _doc,
      resetRadialPresetSlots(
        widget.bindings,
        menu.id,
        OperationBindingStore.radialPresetBindings(menu.id),
      ),
    );
    showSuccessToast(
      t.settings.operationBindingRadialResetDone,
      context: context,
    );
  }

  Future<void> _preview() => showDialog<void>(
    context: context,
    builder: (dialogContext) => RadialWheelPreviewDialog(doc: _doc),
  );

  // ── 轮盘上的点击：选中 / 就地添加 ─────────────────────────────────────────

  void _onWheelTap(RadialSlotPaint? slot) {
    final menu = _menu;
    if (menu == null || slot == null) return;
    final itemId = slot.itemId;
    if (itemId != null) {
      setState(() => _selectedItemId = itemId);
      return;
    }
    // 空格：就地造一个条目并绑到默认动作（neoview 的 `DEFAULT_NEW_ITEM_ACTION`）。
    // 条目进文档、绑定进行 —— 两样一起写回，中途不能只成功一半。
    final id = OperationBindingStore.radialNewItemId(_doc.itemCount);
    final created = RadialItemDoc.create(
      id: id,
      label:
          _actionItems[kRadialDefaultNewItemAction] ??
          kRadialDefaultNewItemAction,
      slotIndex: slot.index,
    );
    setState(() => _selectedItemId = id);
    widget.onChanged(
      _doc.withMenuReplaced(menu.withItem(created, level: slot.level)),
      bindSlot(widget.bindings, (
        menuId: menu.id,
        itemId: id,
      ), kRadialDefaultNewItemAction),
    );
  }

  // ── 检视器：改一个条目 ────────────────────────────────────────────────────

  RadialItemDoc? get _selected {
    final id = _selectedItemId;
    if (id == null) return null;
    return _menu?.item(id);
  }

  void _bindSelected(String actionId) {
    final menu = _menu;
    final item = _selected;
    if (menu == null || item == null) return;
    final slot = (menuId: menu.id, itemId: item.id);
    final previous = actionForSlot(widget.bindings, slot);
    // 显示文字跟着动作名走，但只在它没被用户改过的时候（neoview 同一手感：
    // 「下一页」改成「全屏」不该留下一行「下一页」）。
    final followsAction =
        item.label.isEmpty || item.label == _actionItems[previous ?? ''];
    final updatedMenu = followsAction
        ? menu.withItemReplaced(
            item.copyWith(label: _actionItems[actionId] ?? actionId),
          )
        : menu;
    widget.onChanged(
      _doc.withMenuReplaced(updatedMenu),
      bindSlot(widget.bindings, slot, actionId),
    );
  }

  void _patchItem(RadialItemDoc Function(RadialItemDoc) patch) {
    final menu = _menu;
    final item = _selected;
    if (menu == null || item == null) return;
    _emitMenu(menu.withItemReplaced(patch(item)));
  }

  void _deleteItem() {
    final menu = _menu;
    final item = _selected;
    if (menu == null || item == null) return;
    setState(() => _selectedItemId = null);
    _emitShape(_doc.withMenuReplaced(menu.withoutItem(item.id)));
  }

  /// 前移 / 后移：与同层里相邻的那一条换槽位（neoview 的 `swap slotIndex`）。
  void _shiftItem(int step) {
    final menu = _menu;
    final item = _selected;
    if (menu == null || item == null) return;
    final level =
        menu.layers.indexWhere((layer) => layer.any((e) => e.id == item.id)) +
        1;
    if (level <= 0) return;
    final siblings = List<RadialItemDoc>.from(menu.layer(level))
      ..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));
    final index = siblings.indexWhere((entry) => entry.id == item.id);
    final target = index + step;
    if (target < 0 || target >= siblings.length) return;
    final swap = siblings[target];
    final next = [
      for (final layer in menu.layers)
        [
          for (final entry in layer)
            entry.id == item.id
                ? entry.copyWith(slotIndex: swap.slotIndex)
                : (entry.id == swap.id
                      ? entry.copyWith(slotIndex: item.slotIndex)
                      : entry),
        ],
    ];
    _emitMenu(menu.copyWith(layers: next));
  }

  void _renameMenu(String name) {
    final menu = _menu;
    if (menu == null || name == menu.name) return;
    _emit(_doc.withMenuReplaced(menu.copyWith(name: name)));
  }

  @override
  Widget build(BuildContext context) {
    final menu = _menu;
    final layout = _layout;
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _headerRow(menu),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              _doc.enabled
                  ? t.settings.operationBindingRadialHint(
                      layers: _doc.layerCount,
                    )
                  : t.settings.operationBindingRadialHintDisabled,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          _wheelBox(menu, layout),
          const SizedBox(height: 8),
          _appearanceCard(),
          const SizedBox(height: 12),
          _inspectorCard(menu),
        ],
      ),
    );
  }

  Widget _headerRow(RadialMenuDoc? menu) {
    final menus = <String, String>{
      for (final entry in _doc.menus) entry.id: entry.name,
    };
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
          width: 150,
          child: FluentDropdown<String>(
            value: menus.containsKey(_doc.activeMenuId)
                ? _doc.activeMenuId
                : '',
            displayValue: menu?.name ?? '',
            items: menus,
            onChanged: _selectMenu,
          ),
        ),
        SizedBox(
          width: 110,
          child: FluentDropdown<String>(
            value: '${_doc.layerCount}',
            displayValue: t.settings.operationBindingRadialLayerUnit(
              count: _doc.layerCount,
            ),
            items: {
              for (var option = 1; option <= 3; option++)
                '$option': t.settings.operationBindingRadialLayerUnit(
                  count: option,
                ),
            },
            onChanged: _setLayerCount,
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

  /// 编辑与阅读使用相同的多层轮盘，空槽可以直接添加条目。
  Widget _wheelBox(RadialMenuDoc? menu, List<RadialSlotPaint> layout) {
    if (menu == null) return const SizedBox.shrink();
    return SizedBox(
      height: 480,
      child: RayMenu(
        rings: readerRayRings(layout, editing: true),
        geometry: readerRayGeometry(_doc),
        style: readerRayStyle(context, embedded: true),
        centerLabel: menu.name,
        cancelLabel: t.common.cancel,
        keyboardEnabled: false,
        onSelected: (item) =>
            _onWheelTap(layout.firstWhere((slot) => slot.itemId == item.id)),
        onEmptySelected: (ring, index) => _onWheelTap(
          layout.firstWhere(
            (slot) => slot.level == ring + 1 && slot.index == index,
          ),
        ),
        onDismiss: () {},
      ),
    );
  }

  Widget _appearanceCard() {
    return SettingSectionCard(
      title: t.settings.operationBindingRadialAppearance,
      icon: Icons.tune_outlined,
      children: [
        ListTile(
          title: Text(t.settings.operationBindingRadialAppearance),
          subtitle: Text(
            '${t.settings.operationBindingRadialRadius}: ${_doc.radius.round()}',
          ),
          trailing: Icon(_geometryOpen ? Icons.expand_less : Icons.expand_more),
          onTap: () => setState(() => _geometryOpen = !_geometryOpen),
        ),
        if (_geometryOpen) ...[
          _sliderTile(
            label: t.settings.operationBindingRadialRadius,
            value: _doc.radius,
            min: 60,
            max: 300,
            onChanged: (value) => _emit(_doc.copyWith(radius: value)),
          ),
          _sliderTile(
            label: t.settings.operationBindingRadialInnerRadius,
            value: _doc.innerRadius,
            min: 0,
            max: 100,
            onChanged: (value) => _emit(_doc.copyWith(innerRadius: value)),
          ),
          _sliderTile(
            label: t.settings.operationBindingRadialStartAngle,
            value: _doc.startAngle,
            min: -180,
            max: 180,
            onChanged: (value) => _emit(_doc.copyWith(startAngle: value)),
          ),
          _sliderTile(
            label: t.settings.operationBindingRadialSweepAngle,
            value: _doc.sweepAngle,
            min: 90,
            max: 360,
            onChanged: (value) => _emit(_doc.copyWith(sweepAngle: value)),
          ),
          ListTile(
            title: Text(t.settings.operationBindingRadialVariant),
            trailing: SizedBox(
              width: 160,
              child: FluentDropdown<String>(
                value: _doc.variant,
                displayValue: _doc.variant == 'bubble'
                    ? t.settings.operationBindingRadialVariantBubble
                    : t.settings.operationBindingRadialVariantSlice,
                items: {
                  'slice': t.settings.operationBindingRadialVariantSlice,
                  'bubble': t.settings.operationBindingRadialVariantBubble,
                },
                onChanged: (value) => _emit(_doc.copyWith(variant: value)),
              ),
            ),
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
  }) {
    return ListTile(
      title: Text(label),
      subtitle: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        label: value.round().toString(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _inspectorCard(RadialMenuDoc? menu) {
    final item = _selected;
    final boundAction = item == null || menu == null
        ? null
        : actionForSlot(widget.bindings, (menuId: menu.id, itemId: item.id));
    final others = <String, String>{
      for (final entry in _doc.menus)
        if (entry.id != menu?.id) entry.id: entry.name,
    };
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
        _NameTile(name: menu?.name ?? '', onRename: _renameMenu),
        if (item == null)
          ListTile(
            title: Text(t.settings.operationBindingRadialSelectedSlot),
            subtitle: Text(t.settings.operationBindingRadialPickHint),
          )
        else ...[
          ListTile(
            title: Text(
              t.settings.operationBindingRadialSlotLabel(
                layer:
                    menu!.layers.indexWhere(
                      (layer) => layer.any((e) => e.id == item.id),
                    ) +
                    1,
                sector: item.slotIndex + 1,
              ),
            ),
            subtitle: Text(actionLabelForId(boundAction ?? '')),
          ),
          ListTile(
            title: Text(t.settings.operationBindingRadialItemKind),
            trailing: SizedBox(
              width: 180,
              child: FluentDropdown<String>(
                value: item.isMoveTo ? 'move' : 'action',
                displayValue: item.isMoveTo
                    ? t.settings.operationBindingRadialKindMove
                    : t.settings.operationBindingRadialKindAction,
                items: {
                  'action': t.settings.operationBindingRadialKindAction,
                  if (others.isNotEmpty)
                    'move': t.settings.operationBindingRadialKindMove,
                },
                onChanged: (value) => _patchItem(
                  (entry) => entry.copyWith(
                    moveToMenuId: value == 'move' ? others.keys.first : '',
                  ),
                ),
              ),
            ),
          ),
          if (item.isMoveTo)
            ListTile(
              title: Text(t.settings.operationBindingRadialTargetWheel),
              trailing: SizedBox(
                width: 180,
                child: FluentDropdown<String>(
                  value: others.containsKey(item.moveToMenuId)
                      ? item.moveToMenuId!
                      : '',
                  displayValue: others[item.moveToMenuId] ?? '',
                  items: others,
                  onChanged: (value) => _patchItem(
                    (entry) => entry.copyWith(moveToMenuId: value),
                  ),
                ),
              ),
            )
          else
            ListTile(
              title: Text(t.settings.operationBindingRadialActionLabel),
              trailing: SizedBox(
                width: 220,
                child: FluentDropdown<String>(
                  value: _actionItems.containsKey(boundAction)
                      ? boundAction!
                      : '',
                  displayValue: _actionItems[boundAction ?? ''] ?? '',
                  items: _actionItems,
                  onChanged: _bindSelected,
                ),
              ),
            ),
          ListTile(
            title: Text(t.settings.operationBindingRadialLabel),
            trailing: SizedBox(
              width: 220,
              child: TextField(
                controller: TextEditingController(text: item.label),
                onSubmitted: (value) =>
                    _patchItem((entry) => entry.copyWith(label: value)),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ),
          ),
          ListTile(
            title: Text(t.settings.operationBindingRadialItemEnabled),
            trailing: Switch(
              thumbIcon: kSettingSwitchThumbIcon,
              value: !item.disabled,
              onChanged: (value) =>
                  _patchItem((entry) => entry.copyWith(disabled: !value)),
            ),
          ),
          ListTile(
            title: Text(t.settings.operationBindingRadialSlotIndex),
            subtitle: Text('${item.slotIndex}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: t.settings.operationBindingRadialMoveUp,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => _shiftItem(-1),
                ),
                IconButton(
                  tooltip: t.settings.operationBindingRadialMoveDown,
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _shiftItem(1),
                ),
                IconButton(
                  tooltip: t.settings.operationBindingRadialDeleteItem,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _deleteItem,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 交互预览与阅读器使用同一组件；选择仅关闭预览，不执行业务动作。
class RadialWheelPreviewDialog extends StatelessWidget {
  const RadialWheelPreviewDialog({super.key, required this.doc});

  final RadialDoc doc;

  @override
  Widget build(BuildContext context) {
    final menu = doc.activeMenu;
    final layout = OperationBindingStore.radialLayout(
      configJson: doc.encode(),
      menuId: menu?.id ?? '',
    );
    void close() => Navigator.of(context).pop();
    return AlertDialog(
      title: Text(t.settings.operationBindingRadialPreview),
      content: SizedBox(
        width: 460,
        height: 460,
        child: RayMenu(
          rings: readerRayRings(layout),
          geometry: readerRayGeometry(doc),
          style: readerRayStyle(context, embedded: true),
          centerLabel: menu?.name ?? '',
          cancelLabel: t.common.cancel,
          onSelected: (_) => close(),
          onDismiss: close,
        ),
      ),
      actions: [TextButton(onPressed: close, child: Text(t.common.confirm))],
    );
  }
}

/// 轮盘名：只在**提交**（回车 / 完成编辑）时写回，避免每敲一个字就重建一次轮盘。
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
          onEditingComplete: () => widget.onRename(_controller.text),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      ),
    );
  }
}
