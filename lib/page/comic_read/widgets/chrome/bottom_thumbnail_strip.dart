import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/service/reader/reader_thumbnail_service.dart';
import 'package:zephyr/widgets/glass/liquid_glass.dart';

/// NeoView 风格水平胶卷缩略图条（Thumbnail Strip）。
///
/// 具备高效虚拟化列表渲染、当前页自动居中对齐、高亮荧光环与点击跳转响应。
class BottomThumbnailStrip extends StatefulWidget {
  final int totalPages;
  final int currentSlot;
  final String comicId;
  final String from;
  final PageSource? localSource;
  final List<Doc> docs;
  final ValueChanged<int> onSelectPage;
  final double height;

  /// 是否嵌进**别人的**玻璃面板（底部控制栏把缩略图条与进度条并成一块）。
  ///
  /// `true` 时本组件**不再自带 [LiquidGlassSurface]**，只铺内容 —— 否则就是
  /// 「玻璃上再盖一层玻璃」，两层圆角还会互相切出一条缝。独立浮着用时
  /// （紧凑横屏布局）保持 `false`。
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
    this.embedded = false,
  });

  @override
  State<BottomThumbnailStrip> createState() => _BottomThumbnailStripState();
}

class _BottomThumbnailStripState extends State<BottomThumbnailStrip> {
  late final ScrollController _scrollController;

  static const double _tileWidth = 72.0;
  static const double _tileSpacing = 8.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSlot(widget.currentSlot, animate: false);
    });
  }

  @override
  void didUpdateWidget(covariant BottomThumbnailStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentSlot != widget.currentSlot) {
      _scrollToSlot(widget.currentSlot, animate: true);
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
    final itemExtent = _tileWidth + _tileSpacing;
    final targetOffset = (slot * itemExtent) - (viewportWidth - _tileWidth) / 2;
    final clampedOffset = targetOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    if (animate) {
      _scrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(clampedOffset);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.totalPages <= 0) return const SizedBox.shrink();

    final theme = Theme.of(context);

    final content = Container(
      height: widget.height,
      padding: widget.embedded
          // 嵌进父级面板：横向留出与父级圆角相称的边距，底部少留（下面就是进度条）。
          ? const EdgeInsets.fromLTRB(8, 8, 8, 2)
          : const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
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
          padding: const EdgeInsets.symmetric(horizontal: 4),
          itemBuilder: (context, index) {
            final isActive = index == widget.currentSlot;
            final doc = index < widget.docs.length ? widget.docs[index] : null;

            return Padding(
              padding: const EdgeInsets.only(right: _tileSpacing),
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
    );

    if (widget.embedded) return content;

    return LiquidGlassSurface(
      // 独立浮条：全档位阴影，让它明显悬在漫画之上。
      thickness: LiquidGlassThickness.thick,
      radius: 16,
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

    return Semantics(
      label: t.reader.thumbnailStripJumpToPage(page: index + 1),
      selected: isActive,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => widget.onSelectPage(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _tileWidth,
            height: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActive
                    ? activeBorderColor
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                width: isActive ? 2.2 : 1.0,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: activeBorderColor.withValues(alpha: 0.45),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ReaderThumbnailWidget(
                    index: index,
                    doc: doc,
                    localSource: widget.localSource,
                    comicId: widget.comicId,
                    from: widget.from,
                    fit: BoxFit.cover,
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
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  if (isActive)
                    Positioned(
                      top: 3,
                      right: 3,
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
    );
  }
}
