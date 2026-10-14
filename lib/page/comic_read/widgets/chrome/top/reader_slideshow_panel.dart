import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/model/reader_slideshow.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 顶栏「幻灯片」面板。
///
/// 五组：播放/暂停 ┃ 间隔 ┃ 放完 ┃ 条漫推进距离 ┃ 驻留指示。分组、标签、分隔线的
/// 用法逐条照 `reader_layout_panel.dart`，这样 owner 把 `slideshow` 加进
/// [ReaderToolbarPanel] 之后不用适配第二种面板形状。
///
/// 每个字段各走一次 `context.select`，不整份订阅 `readSetting`：幻灯片这几项之外
/// 的任何设置变化（护眼、留白、超分……）都会连带重建整条面板，代价与收益不成比例。
class ReaderSlideshowPanel extends StatelessWidget {
  /// 放映此刻是不是真的在跑。设置里没有这一位（`slideshowEnabled` 只说开关），
  /// 所以由宿主从 `ReaderSlideshowController` 直接给，与自动滚屏那颗芯片同源。
  final bool isRunning;
  final bool isPaused;
  final VoidCallback onTogglePaused;

  const ReaderSlideshowPanel({
    super.key,
    required this.isRunning,
    required this.isPaused,
    required this.onTogglePaused,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = context.select(
      (GlobalSettingCubit c) => c.state.readSetting.slideshowEnabled,
    );
    final intervalMs = context.select(
      (GlobalSettingCubit c) => c.state.readSetting.slideshowIntervalMs,
    );
    final endAction = context.select(
      (GlobalSettingCubit c) => c.state.readSetting.slideshowEndAction,
    );
    final columnStepPercent = context.select(
      (GlobalSettingCubit c) => c.state.readSetting.slideshowColumnStepPercent,
    );
    final showProgress = context.select(
      (GlobalSettingCubit c) => c.state.readSetting.slideshowShowProgress,
    );

    return ReaderToolbarPanelRow(
      children: [
        ReaderToolbarToggleChip(
          icon: _toggleIcon,
          tooltip: _toggleTooltipFor(enabled),
          label: _toggleLabel,
          selected: isRunning,
          // 分派照自动滚屏那颗的口径：没开就是「开启放映」，开着才是暂停/继续。
          // 只给暂停的话，本仓再没有第二个入口能开启放映 —— 设置页里没有这一项，
          // 那颗芯片就会永远停在「点了不动」。
          onTap: () {
            final cubit = context.read<GlobalSettingCubit>();
            if (!enabled) {
              cubit.updateReadSetting(
                (s) => s.copyWith(slideshowEnabled: true),
              );
              return;
            }
            onTogglePaused();
          },
        ),
        const ReaderToolbarSeparator(),
        ReaderToolbarLabel(t.reader.intervalLabel),
        _IntervalStepper(intervalMs: intervalMs, enabled: true),
        const ReaderToolbarSeparator(),
        ReaderToolbarLabel(t.reader.slideshowFinished),
        ReaderToolbarPill(
          children: [
            for (final action in ReaderSlideshowEndAction.values)
              ReaderToolbarIconButton(
                icon: _endActionIcon(action),
                tooltip: _endActionTooltip(action),
                selected: endAction == action,
                onPressed: () =>
                    context.read<GlobalSettingCubit>().updateReadSetting(
                      (s) => s.copyWith(slideshowEndAction: action),
                    ),
              ),
          ],
        ),
        const ReaderToolbarSeparator(),
        const ReaderToolbarLabel('条漫'),
        _ColumnStepStepper(percent: columnStepPercent, enabled: true),
        const ReaderToolbarSeparator(),
        ReaderToolbarLabel(t.reader.readback),
        ReaderToolbarPill(
          children: [
            ReaderToolbarIconButton(
              icon: AppGlyphs.info,
              tooltip: showProgress
                  ? t.reader.slideshowDwellIndicator
                  : t.reader.dwellIndicatorOff,
              selected: showProgress,
              onPressed: () =>
                  context.read<GlobalSettingCubit>().updateReadSetting(
                    (s) => s.copyWith(
                      slideshowShowProgress: !s.slideshowShowProgress,
                    ),
                  ),
            ),
          ],
        ),
      ],
    );
  }

  /// 三态分开画：`slideshowEnabled` 为 false 时既没在放、也谈不上「暂停」，
  /// 这时候画暂停那颗是在骗人（它看起来像可以随时继续）。
  Glyph get _toggleIcon => isRunning ? AppGlyphs.pause : AppGlyphs.play;

  String get _toggleLabel => isPaused ? '继续' : (isRunning ? '暂停' : '播放');

  /// 三种状态各说一句，其中「没开」那一档要说清**点下去会发生什么**：
  /// 这一颗在没开的时候就是开启键，写成「先去设置里打开」会把人指向一个不存在的入口
  /// （幻灯片没有设置页条目，只有这块面板）。
  String _toggleTooltipFor(bool slideshowEnabled) {
    if (!slideshowEnabled) return t.reader.slideshowOffTapStart;
    if (isPaused) return t.reader.slideshowPausedTapResume;
    if (isRunning) return t.reader.slideshowPlayingTapPause;
    return t.reader.slideshowOnButIdle;
  }
}

Glyph _endActionIcon(ReaderSlideshowEndAction action) => switch (action) {
  ReaderSlideshowEndAction.stop => AppGlyphs.stopCircle,
  ReaderSlideshowEndAction.loopChapter => AppGlyphs.loop,
  ReaderSlideshowEndAction.nextChapter => AppGlyphs.skipNext,
};

String _endActionTooltip(ReaderSlideshowEndAction action) => switch (action) {
  ReaderSlideshowEndAction.stop => t.reader.slideshowStopAtChapterEnd,
  ReaderSlideshowEndAction.loopChapter => t.reader.slideshowLoopInChapter,
  ReaderSlideshowEndAction.nextChapter => t.reader.slideshowAdvanceChapter,
};

/// 每页驻留时长：一步一个 `kReaderSlideshowIntervalStepMs`，读写都过
/// `normalizeReaderSlideshowIntervalMs`，于是面板与控制器用的是同一份上下限
/// （下限不是摆设：非正周期会让 `Timer.periodic` 抛）。
class _IntervalStepper extends StatelessWidget {
  final int intervalMs;
  final bool enabled;

  const _IntervalStepper({required this.intervalMs, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: t.reader.slideshowDwellHint(
        step: _secondsLabel(kReaderSlideshowIntervalStepMs),
        min: _secondsLabel(kReaderSlideshowIntervalMinMs),
        max: _secondsLabel(kReaderSlideshowIntervalMaxMs),
      ),
      child: ReaderToolbarPill(
        emphasized: true,
        children: [
          _SlideshowStepper(
            label: _secondsLabel(intervalMs),
            enabled: enabled,
            onDecrement: () =>
                context.read<GlobalSettingCubit>().updateReadSetting(
                  (s) => s.copyWith(
                    slideshowIntervalMs: normalizeReaderSlideshowIntervalMs(
                      s.slideshowIntervalMs - kReaderSlideshowIntervalStepMs,
                    ),
                  ),
                ),
            onIncrement: () =>
                context.read<GlobalSettingCubit>().updateReadSetting(
                  (s) => s.copyWith(
                    slideshowIntervalMs: normalizeReaderSlideshowIntervalMs(
                      s.slideshowIntervalMs + kReaderSlideshowIntervalStepMs,
                    ),
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

/// 条漫一拍推进多少屏。
///
/// **常驻不折叠**：横翻模式下这一项确实无效，但把控件按阅读模式消失会让面板
/// 在两种模式之间跳形状；tooltip 里写清「只作用于条漫」比少一颗控件更省事。
class _ColumnStepStepper extends StatelessWidget {
  final int percent;
  final bool enabled;

  const _ColumnStepStepper({required this.percent, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: t.reader.webtoonStepScreens,
      child: ReaderToolbarPill(
        emphasized: true,
        children: [
          _SlideshowStepper(
            label: t.reader.oneScreenPercent(percent: percent),
            enabled: enabled,
            onDecrement: () =>
                context.read<GlobalSettingCubit>().updateReadSetting(
                  (s) => s.copyWith(
                    slideshowColumnStepPercent:
                        normalizeReaderSlideshowColumnStepPercent(
                          s.slideshowColumnStepPercent -
                              kReaderSlideshowColumnStepStepPercent,
                        ),
                  ),
                ),
            onIncrement: () =>
                context.read<GlobalSettingCubit>().updateReadSetting(
                  (s) => s.copyWith(
                    slideshowColumnStepPercent:
                        normalizeReaderSlideshowColumnStepPercent(
                          s.slideshowColumnStepPercent +
                              kReaderSlideshowColumnStepStepPercent,
                        ),
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

/// 数字标签：整秒不带小数（`4s`），半步带一位（`2.5s`）。
String _secondsLabel(int ms) => ms % 1000 == 0
    ? '${(ms / 1000).toStringAsFixed(0)}s'
    : '${(ms / 1000).toStringAsFixed(1)}s';

/// 步进器：与 `reader_layout_panel.dart` 里那颗同几何（15px 图标、4 内边距、999 圆角）。
///
/// 那边的是文件私有件，跨文件不可见；这里按同一份数复刻，而不是随手改成另一档尺寸
/// ——顶栏同排出现两种步进器就是「一坨挤在一起的图标」的复发。
class _SlideshowStepper extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _SlideshowStepper({
    required this.label,
    required this.enabled,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tint = enabled
        ? colorScheme.onSurfaceVariant
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.38);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              label,
              // 数字会随间隔变位数，等宽数字免得整条面板左右抖。
              style: theme.textTheme.labelSmall?.copyWith(
                color: tint,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        _stepButton(AppGlyphs.remove, enabled ? onDecrement : null, tint),
        _stepButton(AppGlyphs.add, enabled ? onIncrement : null, tint),
      ],
    );
  }

  static Widget _stepButton(Glyph icon, VoidCallback? onTap, Color color) =>
      InkWell(
        borderRadius: BorderRadius.circular(ReaderToolbarMetrics.fullRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: GlyphIcon(icon, size: 15, color: color),
        ),
      );
}
