import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';

/// NeoView 风格阅读模式胶囊切换器 (条漫 / 单页横向)。
///
/// 只管**版式**（竖向连续滚动 还是 横向按页翻），不再管方向：方向是顶栏
/// [ReadingDirectionToggle] 的唯一职责。以前这里挂着 →/← 两格，与那颗按钮
/// 写同一个 `readMode` 1↔2，而且切完会把阅读位置清零 —— 同一个功能两个入口、
/// 行为还不一样。所以两格并成一格：从条漫切到单页时进入缺省方向（右开），
/// 要左开再点一下方向按钮。
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
            isSelected: currentMode == kReadModeColumn,
            onTap: () {
              if (currentMode != kReadModeColumn) {
                onModeChanged(kReadModeColumn);
              }
            },
          ),
          _buildItem(
            context: context,
            icon: Icons.menu_book_rounded,
            tooltip: t.reader.singlePageRow,
            isSelected: currentMode != kReadModeColumn,
            onTap: () {
              if (currentMode == kReadModeColumn) {
                onModeChanged(kReadModeRowLtr);
              }
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

/// 顶栏「阅读方向」切换按钮（neo 的左开/右开独立入口，也是本仓**唯一**的方向入口）。
///
/// 单击在右开（[kReadModeRowLtr]，下一页在右）⇄ 左开（[kReadModeRowRtl]，下一页
/// 在左）之间切换，**不动阅读位置** —— 两个模式同属 `RowModeWidget`，槽位含义不变，
/// 只是翻页语义反过来。旧实现（设置页里切方向跟着 `changePageIndex(0)`）会把位置
/// 清零跳回第一页。
///
/// 条漫（[kReadModeColumn]）没有左右翻页方向：按钮置灰（**置灰不隐藏** —— 隐藏等于
/// 让人以为没这功能）。整颗按钮由全局设置 `readingDirectionToggle` 控制，
/// 关掉后顶栏不再出现（用户约定：所有功能都要有开关、可随时关闭）。
class ReadingDirectionToggle extends StatelessWidget {
  final int currentMode;
  final ValueChanged<int> onModeChanged;

  const ReadingDirectionToggle({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 「左开」= 下一页在左 = RTL 推进；「右开」= 下一页在右 = LTR 推进。
    final isLeftOpen = currentMode == kReadModeRowRtl;
    final isHorizontal =
        currentMode == kReadModeRowLtr || currentMode == kReadModeRowRtl;

    final tooltip = !isHorizontal
        ? t.reader.readingDirectionToggleDisabled
        : isLeftOpen
        ? t.reader.readingDirectionToggleLeftOpen
        : t.reader.readingDirectionToggleRightOpen;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: isHorizontal
            ? () =>
                  onModeChanged(isLeftOpen ? kReadModeRowLtr : kReadModeRowRtl)
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
              Icon(
                isLeftOpen
                    ? Icons.arrow_back_rounded
                    : Icons.arrow_forward_rounded,
                size: 16,
                color: isHorizontal
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
              const SizedBox(width: 4),
              Text(
                t.reader.readingDirectionToggle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isHorizontal
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
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

    if (currentMode == kReadModeColumn) {
      icon = Icons.view_day_outlined;
      tooltip =
          '${t.reader.webtoon}（点击切为${t.reader.readingDirectionRightOpen}）';
      nextMode = kReadModeRowLtr;
    } else if (currentMode == kReadModeRowLtr) {
      icon = Icons.arrow_forward_rounded;
      tooltip =
          '${t.reader.readingDirectionRightOpen}（点击切为${t.reader.readingDirectionLeftOpen}）';
      nextMode = kReadModeRowRtl;
    } else {
      icon = Icons.arrow_back_rounded;
      tooltip = '${t.reader.readingDirectionLeftOpen}（点击切为${t.reader.webtoon}）';
      nextMode = kReadModeColumn;
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
