part of '../upscale_conditions_card.dart';

// 条件条目操作：落盘保存、新增/复制/删除/移动、重置与导入导出对话框
extension _UpscaleConditionsCardCrudPart on _UpscaleConditionsCardState {
  Future<void> _saveConditions(List<SuperResolutionCondition> list) async {
    // ignore: invalid_use_of_protected_member
    setState(() {
      _conditions = list;
      _selectedIndex = _selectedIndex.clamp(0, _conditions.length - 1);
    });
    await RealSrSettings.saveConditions(list);
  }

  void _addCondition() {
    final newCondition = SuperResolutionCondition(
      id: 'condition-${DateTime.now().millisecondsSinceEpoch}',
      name: t.realSr.conditionN(index: _conditions.length + 1),
      enabled: true,
      priority: _conditions.length,
      match: const ConditionMatch(dimensionMode: 'and'),
      action: const ConditionAction(
        skip: false,
        scale: 2,
        tileEnabled: true,
        tileSize: 512,
        noise: 0,
      ),
    );
    final nextList = [..._conditions, newCondition];
    _saveConditions(nextList);
    // ignore: invalid_use_of_protected_member
    setState(() {
      _selectedIndex = nextList.length - 1;
      _expanded = true;
    });
    HapticFeedback.selectionClick();
  }

  void _duplicateCondition() {
    final current = _currentCondition;
    final copy = current.copyWith(
      id: '${current.id}-copy-${DateTime.now().millisecondsSinceEpoch}',
      name: t.realSr.conditionCopy(name: current.name),
      priority: _conditions.length,
    );
    final nextList = [..._conditions, copy];
    _saveConditions(nextList);
    // ignore: invalid_use_of_protected_member
    setState(() {
      _selectedIndex = nextList.length - 1;
    });
    HapticFeedback.selectionClick();
  }

  void _removeCondition() {
    if (_conditions.length <= 1) {
      showErrorToast(t.realSr.keepAtLeastOneCondition);
      return;
    }
    final nextList = List<SuperResolutionCondition>.from(_conditions)
      ..removeAt(_selectedIndex);
    _saveConditions(nextList);
    // ignore: invalid_use_of_protected_member
    setState(() {
      _selectedIndex = (_selectedIndex - 1).clamp(0, nextList.length - 1);
    });
    HapticFeedback.selectionClick();
  }

  void _moveCondition(int delta) {
    final target = _selectedIndex + delta;
    if (target < 0 || target >= _conditions.length) return;
    final nextList = List<SuperResolutionCondition>.from(_conditions);
    final item = nextList.removeAt(_selectedIndex);
    nextList.insert(target, item);
    _saveConditions(nextList);
    // ignore: invalid_use_of_protected_member
    setState(() {
      _selectedIndex = target;
    });
    HapticFeedback.selectionClick();
  }

  void _resetConditions() {
    showPopupPanel(
      context: context,
      presentation: PopupPresentation.modal,
      builder: (ctx) => PopupPanel(
        title: Text(t.realSr.resetConditions),
        content: Text(t.realSr.resetConditionsContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.common.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _saveConditions([SuperResolutionCondition.createDefault()]);
              // ignore: invalid_use_of_protected_member
              setState(() => _selectedIndex = 0);
              showSuccessToast(t.realSr.conditionsRestored);
            },
            child: Text(t.common.reset),
          ),
        ],
      ),
    );
  }

  void _showExportDialog() {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(
      _conditions.asMap().entries.map((e) {
        return e.value.copyWith(priority: e.key).toJson();
      }).toList(),
    );

    showPopupPanel(
      presentation: PopupPresentation.relative,
      context: context,
      builder: (ctx) => PopupPanel(
        title: Text(t.realSr.exportConditions),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: SelectableText(
              jsonStr,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.common.close),
          ),
          FilledButton.icon(
            icon: const GlyphIcon(AppGlyphs.copy, size: 16),
            label: Text(t.realSr.copyToClipboard),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonStr));
              Navigator.pop(ctx);
              showSuccessToast(t.realSr.conditionJsonCopied);
            },
          ),
        ],
      ),
    );
  }

  void _showImportDialog() {
    final controller = TextEditingController();
    showPopupPanel(
      presentation: PopupPresentation.relative,
      context: context,
      builder: (ctx) => PopupPanel(
        title: Text(t.realSr.importConditions),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.realSr.pasteExportedJson, style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 8,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                decoration: InputDecoration(
                  hintText: t.realSr.importJsonSample,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) {
                showErrorToast(t.realSr.importContentEmpty);
                return;
              }
              try {
                final result = parseUpscaleConditionImport(text);
                Navigator.pop(ctx);
                _saveConditions(result.conditions);
                // ignore: invalid_use_of_protected_member
                setState(() {
                  _selectedIndex = 0;
                  _expanded = true;
                });
                if (result.warnings.isNotEmpty) {
                  showSuccessToast(
                    t.realSr.importSuccessSkipped(
                      imported: result.conditions.length,
                      skipped: result.warnings.length,
                    ),
                  );
                } else {
                  showSuccessToast(
                    t.realSr.importConditionSuccess(
                      count: result.conditions.length,
                    ),
                  );
                }
              } catch (e) {
                showErrorToast('导入失败: $e');
              }
            },
            child: Text(t.realSr.applyImport),
          ),
        ],
      ),
    );
  }
}
