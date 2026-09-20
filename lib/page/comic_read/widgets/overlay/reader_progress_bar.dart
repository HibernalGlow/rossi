import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';

/// 视口底边的常驻翻页进度条（neo `ReaderProgressLayer` 的「翻页进度」那一轨）。
///
/// 与左下角那颗信息胶囊（`overlay/page_count.dart`）**各管各的开关**：两者都住在
/// 阅读页的 `Stack` 里，谁也不覆盖谁，可以同开、同关。
class ReaderProgressBarWidget extends StatelessWidget {
  final String epPages;
  final int Function()? getCurrentChapterStartSlot;
  final int Function()? getCurrentChapterSlotCount;

  const ReaderProgressBarWidget({
    super.key,
    required this.epPages,
    this.getCurrentChapterStartSlot,
    this.getCurrentChapterSlotCount,
  });

  @override
  Widget build(BuildContext context) {
    final readSetting = context.select<GlobalSettingCubit, ReadSettingState>(
      (cubit) => cubit.state.readSetting,
    );
    if (!readSetting.showBottomProgressBar) {
      return const Positioned(top: 0, left: 0, child: SizedBox.shrink());
    }

    final pageIndex = context.select<ReaderCubit, int>(
      (value) => value.state.currentSlot,
    );

    final parsedEpPages = int.tryParse(epPages);
    final totalPageCount = (parsedEpPages != null && parsedEpPages > 0)
        ? parsedEpPages
        : 0;
    if (totalPageCount <= 0) {
      return const Positioned(top: 0, left: 0, child: SizedBox.shrink());
    }

    // 页码口径与信息胶囊**完全一致**：都是「本章内的显示页 / 本章总页」，
    // 所以两颗同时开着时读数不会互相打脸（无缝连读时尤其明显）。
    final chapterStartSlot = getCurrentChapterStartSlot?.call() ?? 0;
    final chapterSlotCount =
        getCurrentChapterSlotCount?.call() ?? totalPageCount;
    final localSlotIndex = (pageIndex - chapterStartSlot).clamp(
      0,
      chapterSlotCount > 0 ? chapterSlotCount - 1 : 0,
    );
    final displayPage = getDisplayPageNumber(
      slotIndex: localSlotIndex,
      enableDoublePage: readSetting.doublePageMode,
      insertLeadingBlank:
          readSetting.doublePageMode && readSetting.doublePageLeadingBlank,
    ).clamp(1, totalPageCount);
    final progress = displayPage / totalPageCount;

    final fillColor = Theme.of(context).colorScheme.primary;
    final glow = readSetting.bottomProgressBarGlow;
    // 填充从哪头长出去跟着阅读方向镜像，与底栏那根可拖滑条同一判据：
    // 左开（下一页在左）时第 1 页在右端。
    final rightToLeft = isReverseRowReadMode(readSetting.readMode);

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        child: SizedBox(
          height: kReaderProgressBarTrackHeight,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Color(0x26FFFFFF), // 轨道：白 15%，压在漫画上要中性
            ),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: progress, end: progress),
              duration: kReaderAnimationDuration,
              curve: Curves.easeOut,
              builder: (context, value, _) {
                return Align(
                  alignment: rightToLeft
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: value.clamp(0.0, 1.0),
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: fillColor,
                        boxShadow: glow
                            ? [
                                BoxShadow(
                                  color: fillColor.withValues(alpha: 0.75),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 轨道高度（逻辑像素）。neo 那边是 `h-[3px]`。
const double kReaderProgressBarTrackHeight = 3;
