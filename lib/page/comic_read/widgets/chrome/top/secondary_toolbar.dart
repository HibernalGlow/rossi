import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reading_mode_capsule.dart';

/// NeoView 风格二级操作工具面板 (Sub-Toolbar Row)。
class ReaderSecondaryToolbar extends StatelessWidget {
  final ReadSettingState readSetting;
  final GlobalSettingCubit cubit;
  final ValueChanged<int> changePageIndex;

  const ReaderSecondaryToolbar({
    super.key,
    required this.readSetting,
    required this.cubit,
    required this.changePageIndex,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isColumn = readSetting.readMode == 0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.5),
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.18),
            width: 0.8,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. 移动端/窄屏模式胶囊与单双页切换 (提供二次快捷入口)
            ReadingModeCapsule(
              currentMode: readSetting.readMode,
              onModeChanged: (mode) {
                cubit.updateReadSetting((s) => s.copyWith(readMode: mode));
                changePageIndex(0);
              },
            ),
            const SizedBox(width: 8),
            DoublePageToggle(
              isDoublePage: readSetting.doublePageMode,
              onToggle: (isDouble) {
                cubit.updateReadSetting(
                  (s) => s.copyWith(doublePageMode: isDouble),
                );
                changePageIndex(0);
              },
              isWide: false,
            ),
            _buildVerticalDivider(context),

            // 2. 首页独立显示 (单封面)
            _buildQuickActionChip(
              context: context,
              icon: Icons.first_page_rounded,
              label: '首页独立',
              tooltip: '双页模式下第一页作为单独封面展示',
              isActive: readSetting.doublePageLeadingBlank,
              onTap: () {
                cubit.updateReadSetting(
                  (s) => s.copyWith(
                    doublePageLeadingBlank: !s.doublePageLeadingBlank,
                  ),
                );
                changePageIndex(0);
              },
            ),
            const SizedBox(width: 6),

            // 3. 双页无缝拼接
            _buildQuickActionChip(
              context: context,
              icon: Icons.view_column_outlined,
              label: '双页无缝',
              tooltip: '消除双页之间的拼接缝隙',
              isActive: readSetting.doublePageSeamless,
              onTap: () {
                cubit.updateReadSetting(
                  (s) => s.copyWith(doublePageSeamless: !s.doublePageSeamless),
                );
                changePageIndex(0);
              },
            ),
            const SizedBox(width: 6),

            // 4. 翻页动画 (平滑/直接)
            _buildQuickActionChip(
              context: context,
              icon: Icons.motion_photos_on_rounded,
              label: readSetting.noAnimation ? '切页:直接' : '切页:平滑',
              tooltip: readSetting.noAnimation ? '当前已关闭翻页动画' : '当前已开启平滑翻页动画',
              isActive: !readSetting.noAnimation,
              onTap: () {
                cubit.updateReadSetting(
                  (s) => s.copyWith(noAnimation: !s.noAnimation),
                );
              },
            ),
            const SizedBox(width: 6),

            // 5. 侧边安全留白
            _buildQuickActionChip(
              context: context,
              icon: Icons.aspect_ratio_rounded,
              label: readSetting.sidePaddingEnabled ? '留白:开' : '留白:关',
              tooltip: '阅读器两侧是否保留适度安全边距',
              isActive: readSetting.sidePaddingEnabled,
              onTap: () {
                cubit.updateReadSetting(
                  (s) => s.copyWith(sidePaddingEnabled: !s.sidePaddingEnabled),
                );
              },
            ),
            _buildVerticalDivider(context),

            // 6. 护眼滤镜开关
            _buildQuickActionChip(
              context: context,
              icon: Icons.remove_red_eye_outlined,
              label: readSetting.readFilterEnabled ? '护眼:开' : '护眼:关',
              tooltip: '切换阅读滤镜与护眼遮罩',
              isActive: readSetting.readFilterEnabled,
              onTap: () {
                cubit.updateReadSetting(
                  (s) => s.copyWith(readFilterEnabled: !s.readFilterEnabled),
                );
              },
            ),
            _buildVerticalDivider(context),

            // 7. 自动滚屏速度微调
            _buildAutoScrollSpeedControls(
              context: context,
              readSetting: readSetting,
              cubit: cubit,
              isColumn: isColumn,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionChip({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String tooltip,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
          decoration: BoxDecoration(
            color: isActive
                ? colorScheme.primaryContainer.withValues(alpha: 0.8)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive
                  ? colorScheme.primary.withValues(alpha: 0.45)
                  : colorScheme.outlineVariant.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isActive
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  color: isActive
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAutoScrollSpeedControls({
    required BuildContext context,
    required ReadSettingState readSetting,
    required GlobalSettingCubit cubit,
    required bool isColumn,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final intervalMs = isColumn
        ? readSetting.autoScrollColumnIntervalMs
        : readSetting.autoScrollPageIntervalMs;
    final displaySec = (intervalMs / 1000.0).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.speed_rounded,
            size: 14,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            '间隔 $displaySec s',
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 4),
          // 减速 (间隔加长)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              if (isColumn) {
                final next = (intervalMs + 200).clamp(400, 5000);
                cubit.updateReadSetting(
                  (s) => s.copyWith(autoScrollColumnIntervalMs: next),
                );
              } else {
                final next = (intervalMs + 500).clamp(1000, 10000);
                cubit.updateReadSetting(
                  (s) => s.copyWith(autoScrollPageIntervalMs: next),
                );
              }
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(Icons.remove_rounded, size: 14),
            ),
          ),
          // 加速 (间隔缩短)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              if (isColumn) {
                final next = (intervalMs - 200).clamp(400, 5000);
                cubit.updateReadSetting(
                  (s) => s.copyWith(autoScrollColumnIntervalMs: next),
                );
              } else {
                final next = (intervalMs - 500).clamp(1000, 10000);
                cubit.updateReadSetting(
                  (s) => s.copyWith(autoScrollPageIntervalMs: next),
                );
              }
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(Icons.add_rounded, size: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider(BuildContext context) {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(
        context,
      ).colorScheme.outlineVariant.withValues(alpha: 0.25),
    );
  }
}
