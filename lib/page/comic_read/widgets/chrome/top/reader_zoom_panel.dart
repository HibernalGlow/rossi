import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/cubit/reader_presentation_cubit.dart';
import 'package:zephyr/page/comic_read/model/reader_presentation.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart';

/// 缩放模式对应的图标与中文名（逐条照 neoview 的 `FIT_MODE_ICONS` / `FIT_MODES`）。
///
/// 顶栏主行那颗按钮也要按当前档位换图标，所以放在面板文件里对外暴露，
/// 而不是藏在私有实现中。
const Map<ReaderFitMode, IconData> kReaderFitModeIcons = {
  ReaderFitMode.fit: Icons.fit_screen_outlined,
  ReaderFitMode.fill: Icons.open_in_full_rounded,
  ReaderFitMode.fitWidth: Icons.width_full_outlined,
  ReaderFitMode.fitHeight: Icons.height_outlined,
  ReaderFitMode.original: Icons.crop_free_outlined,
  ReaderFitMode.fitLeft: Icons.format_align_left_rounded,
  ReaderFitMode.fitRight: Icons.format_align_right_rounded,
};

const Map<ReaderFitMode, String> kReaderFitModeLabels = {
  ReaderFitMode.fit: '适应窗口',
  ReaderFitMode.fill: '铺满整个窗口',
  ReaderFitMode.fitWidth: '适应宽度',
  ReaderFitMode.fitHeight: '适应高度',
  ReaderFitMode.original: '原始大小',
  ReaderFitMode.fitLeft: '居左适应窗口',
  ReaderFitMode.fitRight: '居右适应窗口',
};

/// 顶栏「缩放」面板 —— neoview `ZoomPanel` 的对应物。
///
/// 顺序与分组逐条照那边：百分比 → 手动缩放 → 缩放模式 ┃ 页面布局 ┃ 双页独立 ┃
/// 宽页策略 → 重置视图。窄屏靠外层 `Wrap` 换行摊开，不折叠成溢出菜单。
class ReaderZoomPanel extends StatelessWidget {
  const ReaderZoomPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final presentation = context.select((ReaderPresentationCubit c) => c.state);
    final readSetting = context.select(
      (GlobalSettingCubit c) => c.state.readSetting,
    );

    return ReaderToolbarPanelRow(
      children: [
        _ZoomPercentageControl(presentation: presentation),
        const ReaderToolbarSeparator(),
        const ReaderToolbarLabel('手动缩放'),
        _ManualZoomControl(presentation: presentation),
        const ReaderToolbarSeparator(),
        const ReaderToolbarLabel('缩放模式'),
        ReaderToolbarPill(
          children: [
            for (final mode in ReaderFitMode.values)
              ReaderToolbarIconButton(
                icon: kReaderFitModeIcons[mode]!,
                tooltip: kReaderFitModeLabels[mode]!,
                selected: presentation.fitMode == mode,
                onPressed: () =>
                    context.read<ReaderPresentationCubit>().setFitMode(mode),
              ),
          ],
        ),
        const ReaderToolbarSeparator(),
        const ReaderToolbarLabel('页面布局'),
        ReaderToolbarPill(
          children: [
            ReaderToolbarIconButton(
              icon: Icons.splitscreen_outlined,
              tooltip: readSetting.splitLandscapePages
                  ? '自动分割横向页：开'
                  : '自动分割横向页：关',
              selected: readSetting.splitLandscapePages,
              onPressed: () =>
                  context.read<GlobalSettingCubit>().updateReadSetting(
                    (s) =>
                        s.copyWith(splitLandscapePages: !s.splitLandscapePages),
                  ),
            ),
          ],
        ),
        const ReaderToolbarSeparator(),
        const ReaderToolbarLabel('双页独立'),
        ReaderToolbarPill(
          children: [
            ReaderToolbarIconButton(
              icon: Icons.skip_previous_outlined,
              tooltip: readSetting.doublePageLeadingBlank
                  ? '首页独立显示：开'
                  : '首页独立显示：关',
              selected: readSetting.doublePageLeadingBlank,
              onPressed: () =>
                  context.read<GlobalSettingCubit>().updateReadSetting(
                    (s) => s.copyWith(
                      doublePageLeadingBlank: !s.doublePageLeadingBlank,
                    ),
                  ),
            ),
          ],
        ),
        const ReaderToolbarSeparator(),
        const ReaderToolbarLabel('宽页策略'),
        ReaderToolbarPill(
          children: [
            for (final mode in ReaderWidePageStretch.values)
              ReaderToolbarIconButton(
                icon: _widePageStretchIcon(mode),
                tooltip: _widePageStretchLabel(mode),
                selected: presentation.widePageStretch == mode,
                onPressed: () => context
                    .read<ReaderPresentationCubit>()
                    .setWidePageStretch(mode),
              ),
          ],
        ),
        const ReaderToolbarSeparator(),
        _ResetViewButton(presentation: presentation),
      ],
    );
  }
}

IconData _widePageStretchIcon(ReaderWidePageStretch mode) => switch (mode) {
  ReaderWidePageStretch.none => Icons.equalizer_rounded,
  ReaderWidePageStretch.uniformHeight => Icons.align_vertical_center_rounded,
  ReaderWidePageStretch.uniformWidth => Icons.align_horizontal_center_rounded,
};

String _widePageStretchLabel(ReaderWidePageStretch mode) => switch (mode) {
  ReaderWidePageStretch.none => '无对齐（保持原始比例）',
  ReaderWidePageStretch.uniformHeight => '高度对齐（双页高度统一）',
  ReaderWidePageStretch.uniformWidth => '宽度对齐（双页宽度统一）',
};

/// 缩放百分比：短按回 100%，按住则就地换成一个数字输入框。
///
/// 输入框的口径照 neoview：范围 10~1000、Enter 提交、Esc 取消、失焦提交。
class _ZoomPercentageControl extends StatefulWidget {
  final ReaderPresentation presentation;

  const _ZoomPercentageControl({required this.presentation});

  @override
  State<_ZoomPercentageControl> createState() => _ZoomPercentageControlState();
}

class _ZoomPercentageControlState extends State<_ZoomPercentageControl> {
  bool _editing = false;
  TextEditingController? _controller;

  int get _percent => (widget.presentation.manualScale * 100).round();

  void _startEditing() {
    setState(() {
      _editing = true;
      _controller = TextEditingController(text: '$_percent');
    });
  }

  void _stopEditing() {
    _controller?.dispose();
    setState(() {
      _editing = false;
      _controller = null;
    });
  }

  void _commit() {
    final raw = int.tryParse(_controller?.text.trim() ?? '');
    if (raw != null) {
      context.read<ReaderPresentationCubit>().setManualScale(
        raw.clamp(10, 1000) / 100,
      );
    }
    _stopEditing();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (_editing) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _stopEditing,
        },
        child: Focus(
          autofocus: true,
          onFocusChange: (hasFocus) {
            // 点别处去 = 提交，与 neoview 的 blur 行为一致。
            if (!hasFocus && _editing) _commit();
          },
          child: SizedBox(
            width: 68,
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium,
              onSubmitted: (_) => _commit(),
              decoration: InputDecoration(
                counterText: '',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 7,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    ReaderToolbarMetrics.fullRadius,
                  ),
                  borderSide: BorderSide(color: colorScheme.primary),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    ReaderToolbarMetrics.fullRadius,
                  ),
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Tooltip(
      message: '短按重置为 100%；按住可输入百分比',
      child: InkWell(
        borderRadius: BorderRadius.circular(ReaderToolbarMetrics.fullRadius),
        onTap: () => context.read<ReaderPresentationCubit>().resetManualScale(),
        onLongPress: _startEditing,
        child: Container(
          constraints: const BoxConstraints(minWidth: 56),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              ReaderToolbarMetrics.fullRadius,
            ),
            border: Border.all(color: colorScheme.outline),
          ),
          child: Text(
            '$_percent%',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

/// 手动缩放滑条：10%~1000%，**松手才提交**。
///
/// 拖一下提交一次的做法在这里代价不对称：每一格都要重排整帧，
/// 拖动过程会一直掉帧；neoview 同样是 pointerup 才写回。
class _ManualZoomControl extends StatefulWidget {
  final ReaderPresentation presentation;

  const _ManualZoomControl({required this.presentation});

  @override
  State<_ManualZoomControl> createState() => _ManualZoomControlState();
}

class _ManualZoomControlState extends State<_ManualZoomControl> {
  double? _dragPercent;

  double get _committedPercent => widget.presentation.manualScale * 100;

  double get _percent => _dragPercent ?? _committedPercent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ReaderToolbarPill(
      emphasized: true,
      children: [
        SizedBox(
          width: 120,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: colorScheme.primary,
              // MD3 的未填充轨道取一个真实角色，而不是把主色调淡。
              inactiveTrackColor: colorScheme.secondaryContainer,
              thumbColor: colorScheme.primary,
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              value: _percent.clamp(10, 1000),
              min: 10,
              max: 1000,
              divisions: 99,
              onChanged: (value) => setState(() => _dragPercent = value),
              onChangeEnd: (value) {
                setState(() => _dragPercent = null);
                context.read<ReaderPresentationCubit>().setManualScale(
                  value / 100,
                );
              },
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${_percent.round()}%',
            textAlign: TextAlign.right,
            style: theme.textTheme.labelSmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// 「重置视图」：只清呈现层那一份，不动单双页与阅读方向。
class _ResetViewButton extends StatelessWidget {
  final ReaderPresentation presentation;

  const _ResetViewButton({required this.presentation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Tooltip(
      message: '重置缩放、旋转与宽页策略（保留单双页与阅读方向）',
      child: InkWell(
        borderRadius: BorderRadius.circular(ReaderToolbarMetrics.fullRadius),
        onTap: presentation.isDefault
            ? null
            : () => context.read<ReaderPresentationCubit>().resetView(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              ReaderToolbarMetrics.fullRadius,
            ),
            border: Border.all(
              color: presentation.isDefault
                  ? colorScheme.outlineVariant
                  : colorScheme.outline,
            ),
          ),
          child: Text(
            '重置视图',
            style: theme.textTheme.labelMedium?.copyWith(
              color: presentation.isDefault
                  ? colorScheme.onSurfaceVariant.withValues(alpha: 0.38)
                  : colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
