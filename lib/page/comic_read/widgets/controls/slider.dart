import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/cubit/comic_read_preference_cubit.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/service/reader/reader_thumbnail_service.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/config/global/global_setting.dart';

class SliderWidget extends StatefulWidget {
  final int Function()? getCurrentChapterSlotCount;
  final int Function(int globalSlot)? mapGlobalToLocalSlot;
  final int Function(int localSlot)? mapLocalToGlobalSlot;
  final bool Function(int globalSlot)? isTransitionSlot;
  final String transitionLabel;

  /// 提交跳页的唯一出口 —— 必须走阅读页那份带「跳完回读、没落地补一跳」的实现，
  /// 滑块自己 `jumpToPage` 会静默不落地（见 `didLandOnSlot`）。
  final ValueChanged<int>? onJumpToSlot;

  /// 嵌入底部缩略图/进度组合面板时，复用父级材质和圆角。
  final bool embedded;

  const SliderWidget({
    super.key,
    this.getCurrentChapterSlotCount,
    this.mapGlobalToLocalSlot,
    this.mapLocalToGlobalSlot,
    this.isTransitionSlot,
    this.transitionLabel = '',
    this.onJumpToSlot,
    this.embedded = false,
  });

  @override
  State<SliderWidget> createState() => _SliderWidgetState();
}

class _SliderWidgetState extends State<SliderWidget> {
  // 悬浮层的收起与跳页是两个互不相干的动作，必须各自一个 Timer：合成一个字段时，
  // 鼠标在轨道上移动会 cancel 掉「待跳页」那个 Timer，于是滑块动了、页面永远不跳。
  Timer? _overlayHideTimer; // 悬停提示的延时收起
  Timer? _jumpTimer; // 拖动防抖后提交跳页
  Timer? _comicRollingTimer; // 漫画本身是否在滚动
  OverlayEntry? _overlayEntry;
  String _previewMessage = '';
  int? _previewSlot;
  bool _previewVisible = false;
  int? _lastHapticStep;

  @override
  void dispose() {
    _overlayHideTimer?.cancel();
    _jumpTimer?.cancel();
    _comicRollingTimer?.cancel();
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: _SliderContents(configuration: widget, owner: this),
    );

    // 与缩略图同处一张面板时复用父级材质。
    if (widget.embedded) return Expanded(child: content);

    return Expanded(
      // 独立进度面板使用主题的 Expressive 实色表面。
      child: Material(
        key: const ValueKey('reader-progress-surface'),
        color: context.theme.colorScheme.surfaceContainerLow,
        elevation: 3,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );
  }

  void _showOverlayToast(String message, {int? slotIndex}) {
    _previewMessage = message;
    _previewSlot = slotIndex;
    _previewVisible = true;
    if (_overlayEntry != null) {
      // 悬停/拖动只更新内容，保留正在进行的托盘入场和物理速度。
      _overlayEntry!.markNeedsBuild();
      return;
    }
    _overlayEntry = OverlayEntry(builder: _buildPreviewOverlay);
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hidePreview() {
    if (_overlayEntry == null) return;
    _previewVisible = false;
    _overlayEntry!.markNeedsBuild();
  }

  void _removeHiddenPreview() {
    if (_previewVisible || !mounted) return;
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
  }

  Widget _buildPreviewOverlay(BuildContext overlayContext) {
    final coordinator = ReaderSessionCoordinator.instance;
    final slot = _previewSlot;
    final thumbnail = slot != null && coordinator.hasActiveSession;
    final size = thumbnail ? const Size(104, 148) : const Size(280, 128);
    final overlayBox =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final sourceBox = context.findRenderObject()! as RenderBox;
    final source = overlayBox.globalToLocal(
      sourceBox.localToGlobal(sourceBox.size.center(Offset.zero)),
    );
    final bottom = 84.0 + overlayContext.bottomSafeHeight;
    final previewOrigin = Offset(
      (overlayBox.size.width - size.width) / 2,
      overlayBox.size.height - bottom - size.height,
    );
    final setting = context.read<GlobalSettingCubit>().state;
    final reduced =
        setting.readSetting.noAnimation ||
        setting.eInkSetting.enabled ||
        MediaQuery.disableAnimationsOf(context);
    // 预览要的是「这一格显示的那一页」，所以按显示顺序取，不是按页表下标取
    // （开了页面排序之后两者不等价）。
    final ordered = coordinator.orderedDocs;
    final doc = thumbnail && slot < ordered.length ? ordered[slot] : null;
    return Positioned(
      bottom: bottom,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: MediaQuery(
            data: MediaQuery.of(
              overlayContext,
            ).copyWith(disableAnimations: reduced),
            child: CommonPopupOverlayMotion(
              size: size,
              anchor: Rect.fromCenter(
                center: source - previewOrigin,
                width: 48,
                height: 24,
              ),
              visible: _previewVisible,
              onDismissed: _removeHiddenPreview,
              child: Material(
                color: overlayContext.theme.colorScheme.surfaceContainerHigh,
                elevation: 3,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: thumbnail
                      ? Column(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: ReaderThumbnailWidget(
                                  index: slot,
                                  doc: doc,
                                  localSource: coordinator.localSource,
                                  comicId: coordinator.comicId ?? '',
                                  from: coordinator.from ?? '',
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _previewMessage.startsWith('#') ||
                                      _previewMessage.contains(
                                        t.reader.chapterShort,
                                      )
                                  ? _previewMessage
                                  : '第 $_previewMessage 页',
                              style: overlayContext.theme.textTheme.labelSmall
                                  ?.copyWith(
                                    color: overlayContext
                                        .theme
                                        .colorScheme
                                        .primary,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                          ],
                        )
                      : Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Text(
                                _previewMessage,
                                style: TextStyle(
                                  fontSize:
                                      int.tryParse(_previewMessage) != null
                                      ? 60
                                      : 34,
                                  color: overlayContext
                                      .theme
                                      .colorScheme
                                      .onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SliderContents extends StatelessWidget {
  const _SliderContents({required this.configuration, required this.owner});

  final SliderWidget configuration;
  final _SliderWidgetState owner;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ReaderCubit>();
    final totalSlots = context.select(
      (ReaderCubit cubit) => cubit.state.totalSlots,
    );
    // 只订阅有效 readMode：RTL 翻转只跟它有关，需同时监听全局与本漫覆盖。
    final effectiveReadMode = context.watchEffectiveReadMode();
    final isRtl = isReverseRowReadMode(effectiveReadMode);
    final sliderValue = context.select(
      (ReaderCubit cubit) => cubit.state.sliderValue,
    );
    final globalMaxValue = totalSlots > 0 ? totalSlots.toDouble() - 1 : 0;
    final safeGlobalSliderValue = sliderValue
        .clamp(0.0, globalMaxValue)
        .toDouble();
    final currentChapterSlotCount =
        configuration.getCurrentChapterSlotCount?.call() ?? totalSlots;
    final localMaxValue = currentChapterSlotCount > 0
        ? currentChapterSlotCount.toDouble() - 1
        : 0.0;
    final mappedLocalSliderValue =
        configuration.mapGlobalToLocalSlot?.call(
          safeGlobalSliderValue.round(),
        ) ??
        safeGlobalSliderValue.round();
    final safeSliderValue = mappedLocalSliderValue.toDouble().clamp(
      0.0,
      localMaxValue,
    );

    final effective = context.watchEffectiveReadSetting();
    final doublePageMode = effective.doublePageMode;
    final doublePageLeadingBlank = effective.doublePageLeadingBlank;
    final insertLeadingBlank = doublePageMode && doublePageLeadingBlank;
    final sliderDisplayPage = getDisplayPageNumber(
      slotIndex: safeSliderValue.round(),
      enableDoublePage: doublePageMode,
      insertLeadingBlank: insertLeadingBlank,
    );
    final currentGlobalSlot = safeGlobalSliderValue.round();
    final isCurrentTransitionSlot =
        configuration.isTransitionSlot?.call(currentGlobalSlot) ?? false;
    final effectiveTransitionLabel = configuration.transitionLabel.isEmpty
        ? t.reader.chapterTransition
        : configuration.transitionLabel;
    final sliderLabelText = isCurrentTransitionSlot
        ? effectiveTransitionLabel
        : sliderDisplayPage.toString();

    if (safeGlobalSliderValue != sliderValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!owner.mounted) return;
        cubit.updateSliderChanged(safeGlobalSliderValue);
      });
    }

    // 从右到左阅读时反转滑杆：起始页落在右侧，拖动方向与翻页方向一致。
    final track = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 16,
        thumbShape: const HandleThumbShape(),
        thumbSize: const WidgetStatePropertyAll(Size(4, 36)),
        trackShape: const GappedSliderTrackShape(),
        trackGap: 6,
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        activeTrackColor: context.theme.colorScheme.primary,
        inactiveTrackColor: context.theme.colorScheme.secondaryContainer,
        thumbColor: context.theme.colorScheme.primary,
        overlayColor: context.theme.colorScheme.primary.withValues(alpha: 0.16),
        showValueIndicator: ShowValueIndicator.never,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return MouseRegion(
            onHover: (event) {
              if (localMaxValue <= 0 || constraints.maxWidth <= 0) return;
              final rawPercent = (event.localPosition.dx / constraints.maxWidth)
                  .clamp(0.0, 1.0);
              // 镜像之后物理左端对应的是**最大**那一页 —— 悬停取页要按方向翻一次。
              final percent = isRtl ? 1.0 - rawPercent : rawPercent;
              final hoverStep = (percent * localMaxValue).round();
              final targetGlobalSlot =
                  configuration.mapLocalToGlobalSlot?.call(hoverStep) ??
                  hoverStep;
              final displayPage = getDisplayPageNumber(
                slotIndex: hoverStep,
                enableDoublePage: doublePageMode,
                insertLeadingBlank: insertLeadingBlank,
              );
              final toastMessage =
                  configuration.isTransitionSlot?.call(targetGlobalSlot) ??
                      false
                  ? effectiveTransitionLabel
                  : displayPage.toString();
              owner._showOverlayToast(
                toastMessage,
                slotIndex: targetGlobalSlot,
              );
              owner._overlayHideTimer?.cancel();
              owner._overlayHideTimer = Timer(
                const Duration(milliseconds: 1400),
                () {
                  owner._hidePreview();
                },
              );
            },
            onExit: (_) {
              owner._overlayHideTimer?.cancel();
              owner._hidePreview();
            },
            // 镜像轨道与命中：Slider 自己认 Directionality（轨道从哪头填、拖拽
            // 坐标怎么换算都在内部反好），所以这里只换方向，不动 value。
            child: Directionality(
              textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
              child: Slider(
                value: safeSliderValue,
                min: 0,
                max: localMaxValue,
                divisions: localMaxValue > 0 ? localMaxValue.toInt() : null,
                label: sliderLabelText,
                onChangeStart: (value) {
                  owner._lastHapticStep = value.round();
                },
                onChanged: (double newValue) {
                  final clampedLocalValue = newValue.clamp(0.0, localMaxValue);
                  final currentStep = clampedLocalValue.round();
                  final targetGlobalSlot =
                      configuration.mapLocalToGlobalSlot?.call(currentStep) ??
                      currentStep;
                  final targetGlobalValue = targetGlobalSlot.toDouble();
                  if (owner._lastHapticStep != currentStep) {
                    HapticFeedback.selectionClick();
                    owner._lastHapticStep = currentStep;
                  }

                  if (sliderValue != targetGlobalValue) {
                    cubit.updateSliderChanged(targetGlobalValue);
                  }

                  // 拖动标记要在第一次 onChanged 就立起来：等防抖 Timer 里才置位的话，
                  // 中间这 300ms 里 onPageChanged 会把滑块拽回画面当前那一页。
                  cubit.updateSliderRolling(true);
                  cubit.updateIsComicRolling(true);
                  owner._jumpTimer?.cancel();

                  final displayPage = getDisplayPageNumber(
                    slotIndex: currentStep,
                    enableDoublePage: doublePageMode,
                    insertLeadingBlank: insertLeadingBlank,
                  );
                  final toastMessage =
                      configuration.isTransitionSlot?.call(targetGlobalSlot) ??
                          false
                      ? effectiveTransitionLabel
                      : displayPage.toString();
                  owner._showOverlayToast(
                    toastMessage,
                    slotIndex: targetGlobalSlot,
                  );

                  owner._jumpTimer = Timer(
                    const Duration(milliseconds: 300),
                    () {
                      final commit = configuration.onJumpToSlot;
                      if (commit != null) {
                        commit(targetGlobalSlot);
                      } else {
                        // 没接线也不能只动滑块：协调器上登记的就是同一个跳页回调。
                        unawaited(
                          ReaderSessionCoordinator.instance.jumpTo(
                            targetGlobalSlot,
                          ),
                        );
                      }
                      owner._comicRollingTimer?.cancel();
                      owner._comicRollingTimer = Timer(
                        const Duration(milliseconds: 350),
                        () {
                          cubit.updateSliderRolling(false);
                          cubit.updateIsComicRolling(false);
                          owner._hidePreview();
                        },
                      );
                    },
                  );
                },
                onChangeEnd: (_) {
                  owner._lastHapticStep = null;
                },
              ),
            ),
          );
        },
      ),
    );
    return Row(
      children: [
        Expanded(child: track),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 100),
          child: Container(
            key: const ValueKey('reader-progress-count'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: context.theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$sliderLabelText / $currentChapterSlotCount',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.theme.textTheme.labelMedium?.copyWith(
                color: context.theme.colorScheme.onSecondaryContainer,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
