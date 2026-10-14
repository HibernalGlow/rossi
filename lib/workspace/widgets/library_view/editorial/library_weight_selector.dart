import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:zephyr/widgets/navigation/navigation_shape.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';

/// 复用工作台托盘的弹簧路由，选择菜单不走 Flutter 默认下拉路由。
class LibraryWeightSelector extends StatefulWidget {
  const LibraryWeightSelector({
    super.key,
    required this.value,
    required this.available,
    required this.onChanged,
  });
  final LibraryWeight value;
  final Set<LibraryWeight> available;
  final ValueChanged<LibraryWeight> onChanged;

  @override
  State<LibraryWeightSelector> createState() => _LibraryWeightSelectorState();
}

class _LibraryWeightSelectorState extends State<LibraryWeightSelector> {
  bool _open = false;

  Future<void> _show(PopupOpen<void> open) async {
    HapticFeedback.lightImpact();
    setState(() => _open = true);
    await open();
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('面积依据', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          CommonPopupBox<void>(
            targetBuilder: (open) => ElasticButton(
              enabled: !MediaQuery.disableAnimationsOf(context),
              child: FilledButton.tonal(
                key: const ValueKey('library-weight-selector'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 56),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  shape: _open ? AppShape.xl : AppShape.md,
                  backgroundColor: _open
                      ? scheme.primaryContainer
                      : scheme.secondaryContainer,
                  foregroundColor: _open
                      ? scheme.onPrimaryContainer
                      : scheme.onSecondaryContainer,
                ),
                onPressed: () => _show(open),
                child: Row(
                  children: [
                    GlyphIcon(_glyph(widget.value), size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(widget.value.label)),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _open ? .5 : 0,
                      duration: ExpressiveMotion.duration(
                        context,
                        ExpressiveMotion.spatialDuration,
                      ),
                      curve: ExpressiveMotion.spatialCurve,
                      child: const GlyphIcon(AppGlyphs.chevronDown, size: 20),
                    ),
                  ],
                ),
              ),
            ),
            popupBuilder: (_) => CommonPopupMenu(
              minWidth: 180,
              maxWidth: 320,
              items: [
                for (final weight in LibraryWeight.values)
                  CommonPopupMenuItem(
                    label:
                        '${weight.label}${widget.available.contains(weight) ? '' : ' · 暂无数据'}',
                    glyph: _glyph(weight),
                    checked: weight == widget.value,
                    onPressed: widget.available.contains(weight)
                        ? () {
                            HapticFeedback.selectionClick();
                            widget.onChanged(weight);
                          }
                        : null,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            switch (widget.value) {
              LibraryWeight.signals => '按自定义标签权重突出内容。',
              LibraryWeight.imageShape => '根据原图横竖比例分配卡片空间。',
              LibraryWeight.order => '优先突出当前排序靠前的内容。',
              LibraryWeight.count => '内容数量越多，展示面积越大。',
              LibraryWeight.bytes => '按文件占用空间分配展示面积。',
              LibraryWeight.recent => '突出最近使用的内容。',
              LibraryWeight.progress => '突出正在阅读的内容。',
              LibraryWeight.balanced => '综合内容数量、最近使用与阅读状态。',
            },
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Glyph _glyph(LibraryWeight weight) => switch (weight) {
    LibraryWeight.signals => AppGlyphs.sell,
    LibraryWeight.order => AppGlyphs.sort,
    LibraryWeight.count => AppGlyphs.layers,
    LibraryWeight.bytes => AppGlyphs.storage,
    LibraryWeight.recent => AppGlyphs.history,
    LibraryWeight.progress => AppGlyphs.openBook,
    LibraryWeight.imageShape => AppGlyphs.aspectRatio,
    LibraryWeight.balanced => AppGlyphs.equalizer,
  };
}
