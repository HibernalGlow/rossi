import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_read_button.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_cover_caption_scope.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_summary.dart';

class LibraryEditorialTile extends StatelessWidget {
  const LibraryEditorialTile({
    super.key,
    required this.entry,
    required this.onTap,
    this.onDoubleTap,
    this.onInfo,
    this.wide = false,
    this.selected = false,
    this.spotlight = false,
    this.nativeShape = false,
    this.imageScale = 1,
    this.mediaAspectRatio,
  });
  final LibraryEntry entry;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onInfo;
  final bool wide;
  final bool selected;
  final bool spotlight;
  final bool nativeShape;
  final double imageScale;
  final double? mediaAspectRatio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final radius = BorderRadius.circular(
      selected
          ? 30
          : wide
          ? 26
          : 18,
    );
    return Semantics(
      label: entry.title,
      button: true,
      selected: selected,
      child: Material(
        color: selected ? colors.secondaryContainer : colors.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2 : .5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final coverWidth = constraints.maxWidth;
              final coverHeight = constraints.maxHeight;
              // 任何比例的封面都放进一个等比 frame：卡片承接留白，图片本身不拉伸。
              final ratio = (mediaAspectRatio ?? entry.mediaAspectRatio)?.clamp(
                .18,
                6.0,
              );
              final frameWidth = ratio == null
                  ? coverWidth
                  : math.min(coverWidth, coverHeight * ratio);
              final frameHeight = ratio == null
                  ? coverHeight
                  : math.min(coverHeight, coverWidth / ratio);
              final media = entry.media?.call(
                context,
                width: frameWidth * imageScale,
                height: frameHeight * imageScale,
                radius: BorderRadius.zero,
                fit: BoxFit.contain,
              );
              final cover = SizedBox(
                width: coverWidth,
                height: coverHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    media == null
                        ? Center(
                            child:
                                entry.badge ??
                                const GlyphIcon(AppGlyphs.openBook, size: 44),
                          )
                        : ComicCoverCaptionScope(
                            trailingInset: onInfo == null ? 0 : 54,
                            child: Center(
                              child: SizedBox(
                                width: frameWidth,
                                height: frameHeight,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    media,
                                    if (entry.onRead != null)
                                      ComicReadButton(onTap: entry.onRead!),
                                  ],
                                ),
                              ),
                            ),
                          ),
                    if (!entry.mediaIncludesTitle)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  colors.surface.withValues(alpha: .94),
                                ],
                              ),
                            ),
                            child: SizedBox(
                              height: (coverHeight * .54).clamp(48.0, 200.0),
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  12,
                                  8,
                                  onInfo == null ? 12 : 64,
                                  8,
                                ),
                                child: LibraryEditorialSummary(
                                  entry: entry,
                                  spotlight: spotlight,
                                  wide: wide || coverWidth >= 320,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    // 所有书本沿用同一个中心阅读键，保留忙碌、悬停和焦点反馈。
                    if (entry.onRead != null && media == null)
                      Positioned.fill(
                        child: ComicReadButton(onTap: entry.onRead!),
                      ),
                    // 信息是封面上的次级悬浮动作，不能再形成独立操作底栏。
                    if (onInfo != null)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: IconButton.filledTonal(
                          tooltip: selected ? '收起信息' : '展开信息',
                          onPressed: onInfo,
                          style: IconButton.styleFrom(
                            backgroundColor: colors.surfaceContainerHigh
                                .withValues(alpha: .78),
                            foregroundColor: colors.onSurface,
                            minimumSize: const Size(48, 48),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          icon: GlyphIcon(
                            selected ? AppGlyphs.close : AppGlyphs.info,
                          ),
                        ),
                      ),
                  ],
                ),
              );
              return cover;
            },
          ),
        ),
      ),
    );
  }
}
