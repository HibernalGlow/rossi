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
import 'package:zephyr/widgets/glass/liquid_glass.dart';

class SliderWidget extends StatefulWidget {
  final int Function()? getCurrentChapterSlotCount;
  final int Function(int globalSlot)? mapGlobalToLocalSlot;
  final int Function(int localSlot)? mapLocalToGlobalSlot;
  final bool Function(int globalSlot)? isTransitionSlot;
  final String transitionLabel;

  /// 提交跳页的唯一出口 —— 必须走阅读页那份带「跳完回读、没落地补一跳」的实现，
  /// 滑块自己 `jumpToPage` 会静默不落地（见 `didLandOnSlot`）。
  final ValueChanged<int>? onJumpToSlot;

  /// 是否嵌进**别人的**玻璃面板。
  ///
  /// `true` 时不套自己的 [LiquidGlassSurface]，只留内容 —— 底部控制栏把
  /// 缩略图条与进度条并成一块面板（见 `chrome/bottom.dart`）时必须这样，
  /// 否则玻璃叠玻璃、圆角互相切。
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
  OverlayEntry? _overlayEntry; // 用于存储 OverlayEntry
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

    // 已经被父级那块玻璃装着（缩略图条 + 进度条同一面板）时不再自带材质。
    if (widget.embedded) return Expanded(child: content);

    return Expanded(
      // 底部控制条主体：统一玻璃材质（贴在漫画上，走最实的一档）。
      child: LiquidGlassSurface(
        thickness: LiquidGlassThickness.thick,
        radius: 24,
        child: content,
      ),
    );
  }

  void _showOverlayToast(String message, {int? slotIndex}) {
    // 移除之前的 Overlay
    _overlayEntry?.remove();

    final coordinator = ReaderSessionCoordinator.instance;
    final hasThumbnail = slotIndex != null && coordinator.hasActiveSession;

    // 创建新的 OverlayEntry
    _overlayEntry = OverlayEntry(
      builder: (context) {
        if (hasThumbnail) {
          final docs = coordinator.docs;
          final doc = slotIndex < docs.length ? docs[slotIndex] : null;

          return Positioned(
            bottom: 84.0 + context.bottomSafeHeight,
            left: 0,
            right: 0,
            child: Center(
              // 缩略图预览窗走统一玻璃材质；primary 描边是「当前页」的
              // 功能性高亮，画在玻璃表面保留。
              child: LiquidGlassSurface(
                thickness: LiquidGlassThickness.thick,
                radius: 12,
                child: Container(
                  width: 104,
                  height: 148,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: context.theme.colorScheme.primary.withValues(
                        alpha: 0.6,
                      ),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: ReaderThumbnailWidget(
                            index: slotIndex,
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
                        message.startsWith('#') || message.contains('章')
                            ? message
                            : '第 $message 页',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: context.theme.colorScheme.primary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final isNumeric = int.tryParse(message) != null;
        final fontSize = isNumeric ? 60.0 : 34.0;
        return Stack(
          children: [
            Center(
              // 跳页大字提示：深色漫画上要压得住白字，走最实的一档。
              child: LiquidGlassSurface(
                thickness: LiquidGlassThickness.thick,
                radius: 10,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48.0,
                    vertical: 24.0,
                  ),
                  child: RichText(
                    text: TextSpan(
                      text: message,
                      style: TextStyle(
                        fontSize: fontSize,
                        color: context.textColor.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    // 插入 Overlay
    Overlay.of(context).insert(_overlayEntry!);
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
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 6,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        activeTrackColor: context.theme.colorScheme.primary,
        inactiveTrackColor: context.theme.colorScheme.primary.withValues(
          alpha: 0.22,
        ),
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
                  owner._overlayEntry?.remove();
                  owner._overlayEntry = null;
                },
              );
            },
            onExit: (_) {
              owner._overlayHideTimer?.cancel();
              owner._overlayEntry?.remove();
              owner._overlayEntry = null;
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
                          owner._overlayEntry?.remove();
                          owner._overlayEntry = null;
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
  }
}
