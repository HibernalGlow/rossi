import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:zephyr/widgets/library_image_geometry.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/service/reader/reader_thumbnail_service.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';

/// Expressive 水平胶卷缩略图条（Thumbnail Strip）。
///
/// 保留虚拟化、当前页自动居中与点击跳转，选中形状和按压沿用公共动效。
class BottomThumbnailStrip extends StatefulWidget {
  final int totalPages;
  final int currentSlot;
  final String comicId;
  final String from;
  final PageSource? localSource;
  final List<Doc> docs;
  final ValueChanged<int> onSelectPage;
  final double height;
  final bool originalAspectRatio;

  /// 是否**从右往左**排 —— 跟着阅读方向走（左开时下页在左，第 1 页贴在右边）。
  ///
  /// 只影响这一条胶卷的排布与命中，不影响槽位含义：`index` 仍是全局槽位，
  /// 与 [currentSlot]、[onSelectPage] 同一套编号。
  final bool rightToLeft;

  /// 与进度条同处组合面板时，复用父级材质和圆角。
  final bool embedded;

  const BottomThumbnailStrip({
    super.key,
    required this.totalPages,
    required this.currentSlot,
    required this.comicId,
    required this.from,
    this.localSource,
    this.docs = const <Doc>[],
    required this.onSelectPage,
    this.height = 104,
    this.originalAspectRatio = false,
    this.rightToLeft = false,
    this.embedded = false,
  });

  @override
  State<BottomThumbnailStrip> createState() => _BottomThumbnailStripState();
}

class _BottomThumbnailStripState extends State<BottomThumbnailStrip> {
  late final ScrollController _scrollController;

  static const double _tileWidth = 72.0;
  static const double _tileSpacing = 8.0;
  final Map<int, double> _ratios = {};
  double _tileHeight = 92;
  double _maxTileWidth = 320;
  bool _followCurrent = true;
  bool _centerScheduled = false;
  bool _centerAnimate = false;

  double _widthFor(int index) => widget.originalAspectRatio
      ? (_tileHeight * (_ratios[index] ?? _tileWidth / _tileHeight)).clamp(
          40.0,
          _maxTileWidth,
        )
      : _tileWidth;

  void _scheduleCenter({bool animate = false}) {
    _centerAnimate = _centerAnimate || animate;
    if (!_followCurrent || _centerScheduled) return;
    _centerScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerScheduled = false;
      final animate = _centerAnimate;
      _centerAnimate = false;
      if (mounted && _followCurrent) {
        _scrollToSlot(widget.currentSlot, animate: animate);
      }
    });
  }

  void _reportRatio(int index, double ratio) {
    if (!ratio.isFinite || ratio <= 0 || _ratios[index] == ratio) return;
    setState(() => _ratios[index] = ratio);
    if (widget.originalAspectRatio) _scheduleCenter();
  }

  Future<void> _loadCachedRatios() async {
    final source = widget.localSource;
    if (source == null) return;
    final dimensions = await ReaderThumbnailService.instance
        .getBookPageDimensions(bookPath: source.path);
    if (!mounted || widget.localSource != source) return;
    setState(() {
      for (final page in source.pages) {
        final size = dimensions[page.name];
        if (size != null && size.$1 > 0 && size.$2 > 0) {
          _ratios[page.index] = size.$1 / size.$2;
        }
      }
    });
    _scheduleCenter();
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    if (widget.originalAspectRatio) _loadCachedRatios();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSlot(widget.currentSlot, animate: false);
    });
  }

  @override
  void didUpdateWidget(covariant BottomThumbnailStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedBook =
        oldWidget.localSource != widget.localSource ||
        oldWidget.comicId != widget.comicId ||
        oldWidget.from != widget.from ||
        oldWidget.docs != widget.docs;
    if (changedBook) _ratios.clear();
    if (widget.originalAspectRatio &&
        (changedBook || !oldWidget.originalAspectRatio)) {
      _loadCachedRatios();
    }
    if (oldWidget.currentSlot != widget.currentSlot ||
        oldWidget.rightToLeft != widget.rightToLeft ||
        oldWidget.originalAspectRatio != widget.originalAspectRatio ||
        oldWidget.totalPages != widget.totalPages ||
        changedBook) {
      _followCurrent = true;
      _scheduleCenter(animate: oldWidget.currentSlot != widget.currentSlot);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSlot(int slot, {bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final viewportWidth = _scrollController.position.viewportDimension;
    if (slot < 0 || slot >= widget.totalPages) return;
    // 未测量页沿用竖屏估算；已加载尺寸只修正其前缀，不解码不可见页。
    var itemStart = 4.0 + slot * (_tileWidth + _tileSpacing);
    if (widget.originalAspectRatio) {
      for (final index in _ratios.keys) {
        if (index < slot) itemStart += _widthFor(index) - _tileWidth;
      }
    }
    final targetOffset = itemStart + _widthFor(slot) / 2 - viewportWidth / 2;
    final clampedOffset = targetOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    if (animate && !MediaQuery.disableAnimationsOf(context)) {
      _scrollController.animateTo(
        clampedOffset,
        duration: ExpressiveMotion.spatialDuration,
        curve: ExpressiveMotion.spatialCurve,
      );
    } else {
      _scrollController.jumpTo(clampedOffset);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.totalPages <= 0) return const SizedBox.shrink();

    final theme = Theme.of(context);

    // 换向走 Directionality 而不是 ListView(reverse:)：除了把整条胶卷镜像过来，
    // 它还会把格子里的 EdgeInsetsDirectional / PositionedDirectional 一起翻过去，
    // 于是「页往哪边走」和「角标在哪一角」都跟着阅读方向同构。
    final reel = NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        if (notification.direction != ScrollDirection.idle) {
          _followCurrent = false;
        }
        return false;
      },
      child: Directionality(
        textDirection: widget.rightToLeft
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
            },
          ),
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            itemCount: widget.totalPages,
            itemExtentBuilder: (index, _) => _widthFor(index) + _tileSpacing,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemBuilder: (context, index) {
              final isActive = index == widget.currentSlot;
              final doc = index < widget.docs.length
                  ? widget.docs[index]
                  : null;

              return Padding(
                padding: const EdgeInsetsDirectional.only(end: _tileSpacing),
                child: _buildTile(
                  theme: theme,
                  index: index,
                  doc: doc,
                  isActive: isActive,
                ),
              );
            },
          ),
        ),
      ),
    );

    final content = Container(
      height: widget.height,
      padding: widget.embedded
          // 嵌进父级面板：横向留出与父级圆角相称的边距，底部少留（下面就是进度条）。
          ? const EdgeInsets.fromLTRB(8, 8, 8, 2)
          : const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportWidth = constraints.maxWidth;
          final maxTileWidth = math.max(72.0, viewportWidth * .85);
          if (_tileHeight != constraints.maxHeight ||
              _maxTileWidth != maxTileWidth) {
            _tileHeight = constraints.maxHeight;
            _maxTileWidth = maxTileWidth;
            _scheduleCenter();
          }
          return ActionBubbleRegion(child: reel);
        },
      ),
    );

    if (widget.embedded) return content;

    return Material(
      key: const ValueKey('reader-thumbnail-surface'),
      color: theme.colorScheme.surfaceContainerLow,
      elevation: 3,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }

  Widget _buildTile({
    required ThemeData theme,
    required int index,
    required Doc? doc,
    required bool isActive,
  }) {
    final activeBorderColor = theme.colorScheme.primary;

    return ActionBubbleTarget(
      corner: 16,
      child: ElasticButton(
        enabled: !MediaQuery.disableAnimationsOf(context),
        child: Semantics(
          label: t.reader.thumbnailStripJumpToPage(page: index + 1),
          selected: isActive,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(isActive ? 20 : 12),
              onTap: () => widget.onSelectPage(index),
              child: AnimatedContainer(
                duration: ExpressiveMotion.duration(
                  context,
                  ExpressiveMotion.spatialDuration,
                ),
                curve: ExpressiveMotion.spatialCurve,
                key: ValueKey('reader-thumbnail-tile-$index'),
                width: _widthFor(index),
                height: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(isActive ? 20 : 12),
                  border: Border.all(
                    color: isActive
                        ? activeBorderColor
                        : theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.3,
                          ),
                    width: isActive ? 2.2 : 1.0,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(isActive ? 18 : 10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      LibraryImageGeometryScope(
                        onRatio: (ratio) => _reportRatio(index, ratio),
                        keepFullImage: widget.originalAspectRatio,
                        child: ReaderThumbnailWidget(
                          index: index,
                          doc: doc,
                          localSource: widget.localSource,
                          comicId: widget.comicId,
                          from: widget.from,
                          fit: widget.originalAspectRatio
                              ? BoxFit.contain
                              : BoxFit.cover,
                        ),
                      ),
                      // 底部页码条
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.82),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Text(
                            '${index + 1}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isActive
                                  ? theme.colorScheme.primaryContainer
                                  : Colors.white,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (isActive)
                        PositionedDirectional(
                          top: 3,
                          end: 3,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              t.reader.thumbnailStripCurrent,
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                    ],
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
