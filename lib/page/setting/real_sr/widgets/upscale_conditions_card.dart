import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/setting/real_sr/model/super_resolution_condition.dart';
import 'package:zephyr/page/setting/real_sr/model/upscale_condition_import.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/toast.dart';

/// neo (neoview / Xiranite) 条件超分卡片编辑器组件
class UpscaleConditionsCard extends StatefulWidget {
  final bool isReaderCompact;

  const UpscaleConditionsCard({super.key, this.isReaderCompact = false});

  @override
  State<UpscaleConditionsCard> createState() => _UpscaleConditionsCardState();
}

class _UpscaleConditionsCardState extends State<UpscaleConditionsCard> {
  bool _loading = true;
  bool _autoUpscale = false;
  bool _conditionalEnabled = false;
  List<SuperResolutionCondition> _conditions = [];
  int _selectedIndex = 0;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final autoUpscale = await RealSrSettings.loadAutoUpscale();
    final conditionalEnabled = await RealSrSettings.loadConditionalEnabled();
    final conditions = await RealSrSettings.loadConditions();
    if (!mounted) return;
    setState(() {
      _autoUpscale = autoUpscale;
      _conditionalEnabled = conditionalEnabled;
      _conditions = conditions.isEmpty
          ? [SuperResolutionCondition.createDefault()]
          : conditions;
      _selectedIndex = _selectedIndex.clamp(0, _conditions.length - 1);
      _loading = false;
    });
  }

  Future<void> _saveConditions(List<SuperResolutionCondition> list) async {
    setState(() {
      _conditions = list;
      _selectedIndex = _selectedIndex.clamp(0, _conditions.length - 1);
    });
    await RealSrSettings.saveConditions(list);
  }

  SuperResolutionCondition get _currentCondition {
    if (_conditions.isEmpty) {
      return SuperResolutionCondition.createDefault();
    }
    return _conditions[_selectedIndex.clamp(0, _conditions.length - 1)];
  }

  void _updateCurrentCondition(SuperResolutionCondition updated) {
    final list = List<SuperResolutionCondition>.from(_conditions);
    final idx = _selectedIndex.clamp(0, list.length - 1);
    list[idx] = updated.copyWith(priority: idx);
    _saveConditions(list);
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabledCount = _conditions.where((c) => c.enabled).length;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部主开关
          Row(
            children: [
              const Icon(Icons.rule_folder_outlined, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '条件超分 (neo)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '按图片尺寸、路径正则及元数据规则分派超分动作与跳过判定',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _conditionalEnabled,
                onChanged: (val) async {
                  setState(() => _conditionalEnabled = val);
                  await RealSrSettings.saveConditionalEnabled(val);
                },
              ),
            ],
          ),

          if (_conditionalEnabled && !_autoUpscale) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '需先在上方启用【自动超分】，条件超分才能在阅读与预加载时生效。',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),
          const Divider(height: 1, thickness: 0.4),
          const SizedBox(height: 10),

          // 统计与折叠操作条
          Row(
            children: [
              Text(
                '条件列表（共 ${_conditions.length} 条，启用 $enabledCount 条）',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                ),
                label: Text(
                  _expanded ? '收起编辑器' : '展开编辑器',
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // 水平条件选项条
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _conditions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final cond = _conditions[index];
                final isSelected = index == _selectedIndex;
                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cond.enabled
                              ? colorScheme.primary
                              : colorScheme.outline,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(cond.name),
                    ],
                  ),
                  selected: isSelected,
                  visualDensity: VisualDensity.compact,
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  onSelected: (_) {
                    setState(() => _selectedIndex = index);
                  },
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // 条件条目工具栏（上移、下移、复制、删除、新建、导入、导出、重置）
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 14),
                label: const Text('添加条件', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _addCondition,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('复制', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _duplicateCondition,
              ),
              IconButton.outlined(
                icon: const Icon(Icons.arrow_upward, size: 14),
                tooltip: '上移优先级',
                visualDensity: VisualDensity.compact,
                onPressed: _selectedIndex > 0 ? () => _moveCondition(-1) : null,
              ),
              IconButton.outlined(
                icon: const Icon(Icons.arrow_downward, size: 14),
                tooltip: '下移优先级',
                visualDensity: VisualDensity.compact,
                onPressed: _selectedIndex < _conditions.length - 1
                    ? () => _moveCondition(1)
                    : null,
              ),
              IconButton.outlined(
                icon: Icon(
                  Icons.delete_outline,
                  size: 14,
                  color: colorScheme.error,
                ),
                tooltip: '删除条件',
                visualDensity: VisualDensity.compact,
                onPressed: _conditions.length > 1 ? _removeCondition : null,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.file_upload_outlined, size: 14),
                label: const Text('导入', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _showImportDialog,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.file_download_outlined, size: 14),
                label: const Text('导出', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _showExportDialog,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('重置', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _resetConditions,
              ),
            ],
          ),

          // 展开的条件详细编辑器
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _buildConditionEditor(context, _currentCondition),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConditionEditor(
    BuildContext context,
    SuperResolutionCondition current,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final match = current.match;
    final action = current.action;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 条件名称与启用开关
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('cond_name_${current.id}'),
                  initialValue: current.name,
                  decoration: const InputDecoration(
                    labelText: '条件名称',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (val) {
                    _updateCurrentCondition(current.copyWith(name: val.trim()));
                  },
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    current.enabled ? '已启用' : '已停用',
                    style: TextStyle(
                      fontSize: 11,
                      color: current.enabled
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Switch.adaptive(
                    value: current.enabled,
                    onChanged: (val) {
                      _updateCurrentCondition(current.copyWith(enabled: val));
                    },
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),
          Text(
            '尺寸与规则匹配 (Match)',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),

          // 尺寸限制网格 (最小宽、最大宽、最小高、最大高)
          Row(
            children: [
              Expanded(
                child: _buildNumberInput(
                  label: '最小宽度 (px)',
                  value: match.minWidth,
                  onChanged: (v) => _updateCurrentCondition(
                    current.copyWith(
                      match: match.copyWith(
                        minWidth: v,
                        clearMinWidth: v == null,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildNumberInput(
                  label: '最大宽度 (px)',
                  value: match.maxWidth,
                  onChanged: (v) => _updateCurrentCondition(
                    current.copyWith(
                      match: match.copyWith(
                        maxWidth: v,
                        clearMaxWidth: v == null,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildNumberInput(
                  label: '最小高度 (px)',
                  value: match.minHeight,
                  onChanged: (v) => _updateCurrentCondition(
                    current.copyWith(
                      match: match.copyWith(
                        minHeight: v,
                        clearMinHeight: v == null,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildNumberInput(
                  label: '最大高度 (px)',
                  value: match.maxHeight,
                  onChanged: (v) => _updateCurrentCondition(
                    current.copyWith(
                      match: match.copyWith(
                        maxHeight: v,
                        clearMaxHeight: v == null,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildDoubleInput(
                  label: '最小像素 (MPx)',
                  value: match.minMegapixels,
                  onChanged: (v) => _updateCurrentCondition(
                    current.copyWith(
                      match: match.copyWith(
                        minMegapixels: v,
                        clearMinMegapixels: v == null,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDoubleInput(
                  label: '最大像素 (MPx)',
                  value: match.maxMegapixels,
                  onChanged: (v) => _updateCurrentCondition(
                    current.copyWith(
                      match: match.copyWith(
                        maxMegapixels: v,
                        clearMaxMegapixels: v == null,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          // 判定方式 SegmentedButton
          Row(
            children: [
              const Text('尺寸匹配逻辑：', style: TextStyle(fontSize: 11)),
              const SizedBox(width: 8),
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'and', label: Text('全部满足 (AND)')),
                    ButtonSegment(value: 'or', label: Text('任一满足 (OR)')),
                  ],
                  selected: {match.dimensionMode},
                  onSelectionChanged: (set) {
                    _updateCurrentCondition(
                      current.copyWith(
                        match: match.copyWith(dimensionMode: set.first),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          // 书籍与图片路径正则
          TextFormField(
            key: ValueKey('cond_book_regex_${current.id}'),
            initialValue: match.bookPathRegex ?? '',
            decoration: const InputDecoration(
              labelText: '书籍路径正则 (bookPathRegex)',
              hintText: r'例: (?:^|/)02COS(?:/|$)',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            onChanged: (v) => _updateCurrentCondition(
              current.copyWith(
                match: match.copyWith(
                  bookPathRegex: v.trim(),
                  clearBookPathRegex: v.trim().isEmpty,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey('cond_img_regex_${current.id}'),
            initialValue: match.imagePathRegex ?? '',
            decoration: const InputDecoration(
              labelText: '图片路径正则 (imagePathRegex)',
              hintText: r'例: ^chapter/ 或 \.webp$',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            onChanged: (v) => _updateCurrentCondition(
              current.copyWith(
                match: match.copyWith(
                  imagePathRegex: v.trim(),
                  clearImagePathRegex: v.trim().isEmpty,
                ),
              ),
            ),
          ),

          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  title: const Text('匹配归档内部路径', style: TextStyle(fontSize: 11)),
                  value: match.matchInnerPath,
                  onChanged: (v) => _updateCurrentCondition(
                    current.copyWith(
                      match: match.copyWith(matchInnerPath: v ?? false),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  title: const Text('排除预超分队列', style: TextStyle(fontSize: 11)),
                  value: match.excludeFromPreload,
                  onChanged: (v) => _updateCurrentCondition(
                    current.copyWith(
                      match: match.copyWith(excludeFromPreload: v ?? false),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(height: 1, thickness: 0.3),
          const SizedBox(height: 12),

          Text(
            '触发动作 (Action)',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),

          // 跳过开关
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: action.skip
                  ? colorScheme.errorContainer.withValues(alpha: 0.25)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  action.skip ? Icons.block : Icons.play_arrow_outlined,
                  size: 18,
                  color: action.skip ? colorScheme.error : colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    action.skip ? '命中此条件时：跳过超分（不处理）' : '命中此条件时：执行超分',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: action.skip ? colorScheme.error : null,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: action.skip,
                  activeTrackColor: colorScheme.errorContainer,
                  activeThumbColor: colorScheme.error,
                  onChanged: (val) {
                    _updateCurrentCondition(
                      current.copyWith(action: action.copyWith(skip: val)),
                    );
                  },
                ),
              ],
            ),
          ),

          if (!action.skip) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Text('输出倍率：', style: TextStyle(fontSize: 11)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: FluentDropdown<int>(
                          value: action.scale ?? 2,
                          displayValue: '${action.scale ?? 2}x',
                          items: const {2: '2x', 3: '3x', 4: '4x'},
                          onChanged: (s) => _updateCurrentCondition(
                            current.copyWith(action: action.copyWith(scale: s)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      const Text('分块大小：', style: TextStyle(fontSize: 11)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: FluentDropdown<int>(
                          value: action.tileSize ?? 512,
                          displayValue: '${action.tileSize ?? 512}',
                          items: const {
                            128: '128',
                            256: '256',
                            512: '512',
                            1024: '1024',
                          },
                          onChanged: (t) => _updateCurrentCondition(
                            current.copyWith(
                              action: action.copyWith(tileSize: t),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    title: const Text(
                      '启用分块 Tile',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: action.tileEnabled ?? true,
                    onChanged: (v) => _updateCurrentCondition(
                      current.copyWith(
                        action: action.copyWith(tileEnabled: v ?? true),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    title: const Text('写入结果缓存', style: TextStyle(fontSize: 11)),
                    value: action.useCache ?? true,
                    onChanged: (v) => _updateCurrentCondition(
                      current.copyWith(
                        action: action.copyWith(useCache: v ?? true),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    title: const Text(
                      '启用 TTA 增强',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: action.tta ?? false,
                    onChanged: (v) => _updateCurrentCondition(
                      current.copyWith(
                        action: action.copyWith(tta: v ?? false),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNumberInput({
    required String label,
    required int? value,
    required ValueChanged<int?> onChanged,
  }) {
    return TextFormField(
      key: ValueKey('num_${label}_$value'),
      initialValue: value != null ? '$value' : '',
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      style: const TextStyle(fontSize: 11),
      onChanged: (str) {
        final parsed = int.tryParse(str.trim());
        onChanged(parsed);
      },
    );
  }

  Widget _buildDoubleInput({
    required String label,
    required double? value,
    required ValueChanged<double?> onChanged,
  }) {
    return TextFormField(
      key: ValueKey('double_${label}_$value'),
      initialValue: value != null ? '$value' : '',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      style: const TextStyle(fontSize: 11),
      onChanged: (str) {
        final parsed = double.tryParse(str.trim());
        onChanged(parsed);
      },
    );
  }
}
