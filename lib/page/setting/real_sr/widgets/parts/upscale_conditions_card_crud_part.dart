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
      name: '条件 ${_conditions.length + 1}',
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
      name: '${current.name} 副本',
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
      showErrorToast('至少保留一条超分条件');
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置条件超分'),
        content: const Text('确定将所有条件恢复为出厂默认设置吗？现有规则将被清除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _saveConditions([SuperResolutionCondition.createDefault()]);
              // ignore: invalid_use_of_protected_member
              setState(() => _selectedIndex = 0);
              showSuccessToast('已恢复默认条件');
            },
            child: const Text('重置'),
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

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出条件超分配置 (JSON)'),
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
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制到剪贴板'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonStr));
              Navigator.pop(ctx);
              showSuccessToast('已复制条件 JSON 到剪贴板');
            },
          ),
        ],
      ),
    );
  }

  void _showImportDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入条件超分配置'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '请粘贴导出的 JSON 数组或备份对象文本：',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 8,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                decoration: InputDecoration(
                  hintText: '[\n  {\n    "name": "示例条件",\n    ...\n  }\n]',
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
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) {
                showErrorToast('导入内容不能为空');
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
                    '导入成功（${result.conditions.length} 条），跳过 ${result.warnings.length} 条不兼容项',
                  );
                } else {
                  showSuccessToast('成功导入 ${result.conditions.length} 条条件');
                }
              } catch (e) {
                showErrorToast('导入失败: $e');
              }
            },
            child: const Text('应用导入'),
          ),
        ],
      ),
    );
  }
}
