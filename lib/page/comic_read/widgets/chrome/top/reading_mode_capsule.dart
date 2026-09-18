import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// NeoView 风格阅读模式胶囊切换器 (Webtoon / LTR / RTL)。
class ReadingModeCapsule extends StatelessWidget {
  final int currentMode;
  final ValueChanged<int> onModeChanged;

  const ReadingModeCapsule({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildItem(
            context: context,
            icon: Icons.view_day_outlined,
            tooltip: t.reader.webtoon,
            isSelected: currentMode == 0,
            onTap: () {
              if (currentMode != 0) onModeChanged(0);
            },
          ),
          _buildItem(
            context: context,
            icon: Icons.arrow_forward_rounded,
            tooltip: t.reader.singlePageLtr,
            isSelected: currentMode == 1,
            onTap: () {
              if (currentMode != 1) onModeChanged(1);
            },
          ),
          _buildItem(
            context: context,
            icon: Icons.arrow_back_rounded,
            tooltip: t.reader.singlePageRtl,
            isSelected: currentMode == 2,
            onTap: () {
              if (currentMode != 2) onModeChanged(2);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildItem({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 16,
            color: isSelected
                ? colorScheme.onPrimary
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 单/双页模式快速切换胶囊。
class DoublePageToggle extends StatelessWidget {
  final bool isDoublePage;
  final ValueChanged<bool> onToggle;
  final bool isWide;

  const DoublePageToggle({
    super.key,
    required this.isDoublePage,
    required this.onToggle,
    this.isWide = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: isDoublePage ? '双页模式 (点击切为单页)' : '单页模式 (点击切为双页)',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onToggle(!isDoublePage),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: isDoublePage
                ? colorScheme.primaryContainer.withValues(alpha: 0.8)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDoublePage
                  ? colorScheme.primary.withValues(alpha: 0.45)
                  : colorScheme.outlineVariant.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isDoublePage
                    ? Icons.auto_stories_rounded
                    : Icons.crop_portrait_rounded,
                size: 16,
                color: isDoublePage
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              if (isWide) ...[
                const SizedBox(width: 4),
                Text(
                  isDoublePage ? '双页' : '单页',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDoublePage
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 移动端/窄屏下的紧凑阅读模式循环切换按钮。
class CompactReadingModeButton extends StatelessWidget {
  final int currentMode;
  final ValueChanged<int> onModeChanged;

  const CompactReadingModeButton({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    IconData icon;
    String tooltip;
    int nextMode;

    if (currentMode == 0) {
      icon = Icons.view_day_outlined;
      tooltip = '当前条漫模式 (点击切为左开)';
      nextMode = 1;
    } else if (currentMode == 1) {
      icon = Icons.arrow_forward_rounded;
      tooltip = '当前左开模式 (点击切为右开)';
      nextMode = 2;
    } else {
      icon = Icons.arrow_back_rounded;
      tooltip = '当前右开模式 (点击切为条漫)';
      nextMode = 0;
    }

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onModeChanged(nextMode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.25),
            ),
          ),
          child: Icon(icon, size: 16, color: colorScheme.primary),
        ),
      ),
    );
  }
}
