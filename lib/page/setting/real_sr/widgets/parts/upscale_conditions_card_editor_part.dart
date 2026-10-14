part of '../upscale_conditions_card.dart';

// 单条条件编辑器：当前条件取值、尺寸/正则匹配表单与动作表单、数字输入框
extension _UpscaleConditionsCardEditorPart on _UpscaleConditionsCardState {
  SuperResolutionCondition get _currentCondition {
    if (_conditions.isEmpty) {
      return SuperResolutionCondition.createDefault();
    }
    return _conditions[_selectedIndex.clamp(0, _conditions.length - 1)];
  }

  Widget _buildConditionEditor(
    BuildContext context,
    SuperResolutionCondition current,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final match = current.match;
    final action = current.action;

    // 底色与边框走 Material，不走 Container 的 BoxDecoration：
    // 这一格里的 `RadioListTile` 把背景与水波画在**最近的 Material 祖先**上，
    // 中间夹一层带色 DecoratedBox 就把它们全挡住（Flutter 直接抛
    // 「ListTile background color or ink splashes may be invisible」，
    // 而且这些选择行真的没有按压反馈）。
    // Material 没有 padding，所以多垫一层 Padding —— 这是这个文件里唯一
    // 为此让出的缩进，其余一律不动。
    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
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
                    decoration: InputDecoration(
                      labelText: t.realSr.conditionName,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    style: const TextStyle(fontSize: 12),
                    onChanged: (val) {
                      _updateCurrentCondition(
                        current.copyWith(name: val.trim()),
                      );
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
                    M3ESwitch(
                      semanticLabel: '启用此条件',
                      value: current.enabled,
                      selectedIcon: const Icon(Icons.check, size: 16),
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
                    label: t.realSr.minWidthPx,
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
                    label: t.realSr.maxWidthPx,
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
                    label: t.realSr.minHeightPx,
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
                    label: t.realSr.maxHeightPx,
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
                    label: t.realSr.minPixelsMpx,
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
                    label: t.realSr.maxPixelsMpx,
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
                Text(t.realSr.sizeMatchLogic, style: TextStyle(fontSize: 11)),
                const SizedBox(width: 8),
                Expanded(
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'and', label: Text(t.realSr.matchAllAnd)),
                      ButtonSegment(value: 'or', label: Text(t.realSr.matchAnyOr)),
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
              decoration: InputDecoration(
                labelText: t.realSr.bookPathRegex,
                hintText: r'例: (?:^|/)02COS(?:/|$)',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
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
              decoration: InputDecoration(
                labelText: t.realSr.imagePathRegex,
                hintText: r'例: ^chapter/ 或 \.webp$',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
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
                    title: const Text(
                      '匹配归档内部路径',
                      style: TextStyle(fontSize: 11),
                    ),
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
                    title: const Text(
                      '排除预超分队列',
                      style: TextStyle(fontSize: 11),
                    ),
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
                    : colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.3,
                      ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  GlyphIcon(
                    action.skip ? AppGlyphs.block : AppGlyphs.play,
                    size: 18,
                    color: action.skip
                        ? colorScheme.error
                        : colorScheme.primary,
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
                  // 这颗留在旧控件上：M3ESwitch 没有按处取色的入口（配色只从
                  // M3EColorScheme 解），而「跳过超分」这条要靠 errorContainer/error
                  // 的红色跟旁边两颗普通开关区分。换过去就得整页套一份改色的 M3ETheme。
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
                        Text(t.realSr.outputScaleLabel, style: TextStyle(fontSize: 11)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: FluentDropdown<int>(
                            value: action.scale ?? 2,
                            displayValue: '${action.scale ?? 2}x',
                            items: const {2: '2x', 3: '3x', 4: '4x'},
                            onChanged: (s) => _updateCurrentCondition(
                              current.copyWith(
                                action: action.copyWith(scale: s),
                              ),
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
                        Text(t.realSr.blockSizeLabel, style: TextStyle(fontSize: 11)),
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
                      title: const Text(
                        '写入结果缓存',
                        style: TextStyle(fontSize: 11),
                      ),
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
