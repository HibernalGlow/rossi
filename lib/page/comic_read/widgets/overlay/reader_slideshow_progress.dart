import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/widgets/overlay/reader_progress_bar.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 放映时的驻留指示：本章第几页 + 是不是暂停了。
///
/// 构造参数只吃宿主算好的读数，不订阅任何 cubit：页码口径（双页/无缝拼接下的
/// 「本章显示页」）归宿主，芯片在这里现读 reader cubit 只会和左下角那颗信息胶囊
/// 各说各话（两颗同时开着时尤其明显，见 `overlay/page_count.dart` 的那段口径注释）。
class ReaderSlideshowProgress extends StatelessWidget {
  final int chapterPageNumber;
  final int chapterPageTotal;
  final bool isPaused;
  final bool isRunning;

  /// false = 只画图标与页码（窄屏/单页阅读时让位，与顶栏芯片的收缩口径一致）。
  final bool showLabel;

  const ReaderSlideshowProgress({
    super.key,
    required this.chapterPageNumber,
    required this.chapterPageTotal,
    required this.isPaused,
    required this.isRunning,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    // 宿主已经按 `slideshowEnabled && slideshowShowProgress` 决定在不在场；
    // 这里再判一次「是不是真的在飞」，为的是刚停表那一帧不留一颗孤儿读数。
    if (!isRunning && !isPaused) {
      return const Positioned(top: 0, left: 0, child: SizedBox.shrink());
    }
    if (chapterPageTotal <= 0) {
      return const Positioned(top: 0, left: 0, child: SizedBox.shrink());
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // 暂停不是错误：次要角色 + 「已暂停」文字，别借 error 色吓人。
    final foreground = isPaused
        ? colorScheme.onSurfaceVariant
        : colorScheme.onSurface;
    final number = chapterPageNumber.clamp(1, chapterPageTotal);

    return Positioned(
      left: 0,
      right: 0,
      // 贴在底边进度条**上方**：两者同开时读数要连着看，不能互相压住。
      bottom:
          MediaQuery.paddingOf(context).bottom +
          kReaderProgressBarTrackHeight +
          kReaderSlideshowProgressGap,
      child: Center(
        // 浮层一律吃掉指针：阅读页的单击/左右区域都靠命中测试落在漫画上，
        // 一颗只读数的芯片不该偷走一次翻页。
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              // 与顶栏容器同一档实色，不自己叠 alpha（信息那颗的透明度是用户可调的，
              // 这里没有那个设置项，就不该私造一份）。
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(
                kReaderSlideshowProgressRadius,
              ),
            ),
            child: Padding(
              padding: kReaderSlideshowProgressPadding,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlyphIcon(
                    isPaused ? AppGlyphs.pauseCircle : AppGlyphs.playCircle,
                    size: kReaderSlideshowProgressIconSize,
                    color: foreground,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$number/$chapterPageTotal',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: foreground,
                      // 每次推进都可能换位数，等宽数字保证芯片不左右抽动。
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (showLabel) ...[
                    const SizedBox(width: 6),
                    Text(
                      isPaused ? '已暂停' : t.reader.slideshowPlaying,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: foreground,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 与进度条轨道之间的气隙（逻辑像素）。
const double kReaderSlideshowProgressGap = 6;

/// 圆角与信息胶囊同一档（见 `overlay/page_count.dart` 的 `BorderRadius.circular(10)`）。
const double kReaderSlideshowProgressRadius = 10;

/// 内边距同样照信息胶囊，两颗浮层并排时才是同一个东西。
const EdgeInsets kReaderSlideshowProgressPadding = EdgeInsets.symmetric(
  horizontal: 10,
  vertical: 5,
);

/// 图标边长：与数字同档。信息胶囊那边按「字号 + 1」配图标（`page_count.dart`），
/// 这里的字号是固定的 `labelMedium`，所以把同一个关系落成一个常数。
const double kReaderSlideshowProgressIconSize = 16;
