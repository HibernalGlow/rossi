import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/setting/real_sr/model/super_resolution_condition.dart';
import 'package:zephyr/page/setting/real_sr/model/upscale_condition_import.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/toast.dart';

// 条件条目的增删改、排序与导入导出对话框。
part 'parts/upscale_conditions_card_crud_part.dart';
// 单条条件的展开编辑器（匹配规则与动作表单）。
part 'parts/upscale_conditions_card_editor_part.dart';

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

  void _updateCurrentCondition(SuperResolutionCondition updated) {
    final list = List<SuperResolutionCondition>.from(_conditions);
    final idx = _selectedIndex.clamp(0, list.length - 1);
    list[idx] = updated.copyWith(priority: idx);
    _saveConditions(list);
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
                activeTrackColor: colorScheme.primary,
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

}
