import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart';

/// 顶栏「版式」面板。
///
/// 装的是**neo 没有对应物**的那几项本仓自有开关：双页无缝、切页动画、侧边留白、
/// 护眼滤镜、自动滚屏速度。首页独立 neo 有同名项，已经并到缩放面板里去了；
/// 单双页与阅读方向是主行的常驻按钮，这里不再重复放一份（两个入口写同一个
/// 字段是本仓明确要避免的事，见 `ReadingModeCapsule` 的注释）。
class ReaderLayoutPanel extends StatelessWidget {
  const ReaderLayoutPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final readSetting = context.select(
      (GlobalSettingCubit c) => c.state.readSetting,
    );

    return ReaderToolbarPanelRow(
      children: [
        const ReaderToolbarLabel('双页'),
        ReaderToolbarPill(
          children: [
            _Toggle(
              icon: Icons.view_column_rounded,
              tooltip: '消除双页之间的拼接缝隙',
              selected: readSetting.doublePageSeamless,
              onTap: () => context.read<GlobalSettingCubit>().updateReadSetting(
                (s) => s.copyWith(doublePageSeamless: !s.doublePageSeamless),
              ),
            ),
          ],
        ),
        const ReaderToolbarSeparator(),
        const ReaderToolbarLabel('翻页'),
        ReaderToolbarPill(
          children: [
            _Toggle(
              icon: Icons.motion_photos_on_rounded,
              tooltip: readSetting.noAnimation
                  ? '当前已关闭翻页动画'
                  : '当前已开启平滑翻页动画',
              selected: !readSetting.noAnimation,
              onTap: () => context.read<GlobalSettingCubit>().updateReadSetting(
                (s) => s.copyWith(noAnimation: !s.noAnimation),
              ),
            ),
          ],
        ),
        const ReaderToolbarSeparator(),
        const ReaderToolbarLabel('留白'),
        ReaderToolbarPill(
          children: [
            _Toggle(
              icon: Icons.aspect_ratio_rounded,
              tooltip: '阅读器两侧是否保留适度安全边距',
              selected: readSetting.sidePaddingEnabled,
              onTap: () => context.read<GlobalSettingCubit>().updateReadSetting(
                (s) => s.copyWith(
                  sidePaddingEnabled: !s.sidePaddingEnabled,
                ),
              ),
            ),
            const _SidePaddingStepper(),
          ],
        ),
        const ReaderToolbarSeparator(),
        const ReaderToolbarLabel('滤镜'),
        ReaderToolbarPill(
          children: [
            _Toggle(
              icon: Icons.remove_red_eye_outlined,
              tooltip: '切换阅读滤镜与护眼遮罩',
              selected: readSetting.readFilterEnabled,
              onTap: () => context.read<GlobalSettingCubit>().updateReadSetting(
                (s) => s.copyWith(readFilterEnabled: !s.readFilterEnabled),
              ),
            ),
          ],
        ),
        const ReaderToolbarSeparator(),
        const ReaderToolbarLabel('滚屏'),
        _AutoScrollSpeedControl(readSetting: readSetting),
      ],
    );
  }
}

/// 面板里的一颗图标开关（与主行那颗同一外观，只是语义上是「开/关」而非「展开」）。
class _Toggle extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  const _Toggle({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primaryContainer.withValues(alpha: 0.8)
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 17,
            color: selected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 侧边留白的百分比微调（0~30，一次 2 个点）。
class _SidePaddingStepper extends StatelessWidget {
  const _SidePaddingStepper();

  @override
  Widget build(BuildContext context) {
    final percent = context.select(
      (GlobalSettingCubit c) => c.state.readSetting.sidePaddingPercent,
    );
    final enabled = context.select(
      (GlobalSettingCubit c) => c.state.readSetting.sidePaddingEnabled,
    );
    return _Stepper(
      label: '$percent%',
      enabled: enabled,
      onDecrement: () => context.read<GlobalSettingCubit>().updateReadSetting(
        (s) => s.copyWith(sidePaddingPercent: (s.sidePaddingPercent - 2).clamp(
          0,
          30,
        )),
      ),
      onIncrement: () => context.read<GlobalSettingCubit>().updateReadSetting(
        (s) => s.copyWith(sidePaddingPercent: (s.sidePaddingPercent + 2).clamp(
          0,
          30,
        )),
      ),
    );
  }
}

/// 自动滚屏速度：条漫按列距、横翻按页间隔，各自一套上下限。
class _AutoScrollSpeedControl extends StatelessWidget {
  final ReadSettingState readSetting;

  const _AutoScrollSpeedControl({required this.readSetting});

  @override
  Widget build(BuildContext context) {
    final isColumn = readSetting.readMode == 0;
    final intervalMs = isColumn
        ? readSetting.autoScrollColumnIntervalMs
        : readSetting.autoScrollPageIntervalMs;

    return ReaderToolbarPill(
      emphasized: true,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '间隔 ${(intervalMs / 1000).toStringAsFixed(1)}s',
            style: const TextStyle(fontSize: 11.5),
          ),
        ),
        _Stepper(
          label: '',
          enabled: true,
          onDecrement: () => context.read<GlobalSettingCubit>()
              .updateReadSetting((s) {
                if (isColumn) {
                  return s.copyWith(
                    autoScrollColumnIntervalMs: (s.autoScrollColumnIntervalMs +
                            200)
                        .clamp(400, 5000),
                  );
                }
                return s.copyWith(
                  autoScrollPageIntervalMs:
                      (s.autoScrollPageIntervalMs + 500).clamp(1000, 10000),
                );
              }),
          onIncrement: () => context.read<GlobalSettingCubit>()
              .updateReadSetting((s) {
                if (isColumn) {
                  return s.copyWith(
                    autoScrollColumnIntervalMs: (s.autoScrollColumnIntervalMs -
                            200)
                        .clamp(400, 5000),
                  );
                }
                return s.copyWith(
                  autoScrollPageIntervalMs:
                      (s.autoScrollPageIntervalMs - 500).clamp(1000, 10000),
                );
              }),
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _Stepper({
    required this.label,
    required this.enabled,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tint = enabled
        ? colorScheme.onSurfaceVariant
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.35);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              label,
              style: TextStyle(fontSize: 11.5, color: tint),
            ),
          ),
        _stepButton(Icons.remove_rounded, enabled ? onDecrement : null, tint),
        _stepButton(Icons.add_rounded, enabled ? onIncrement : null, tint),
      ],
    );
  }

  static Widget _stepButton(
    IconData icon,
    VoidCallback? onTap,
    Color color,
  ) => InkWell(
    borderRadius: BorderRadius.circular(999),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Icon(icon, size: 15, color: color),
    ),
  );
}
