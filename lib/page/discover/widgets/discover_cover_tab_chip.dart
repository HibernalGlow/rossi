import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:plat/plat.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/discover/service/discover_tabs.dart';
import 'package:zephyr/page/discover/service/plugin_display_label.dart';
import 'package:zephyr/page/discover/service/plugin_function_kind.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/widgets/picture_bloc/bloc/picture_bloc.dart';
import 'package:zephyr/widgets/picture_bloc/models/picture_info.dart';

/// 封面标签模式下的标签 Chip（类似于 Book 封面，信息层叠在封面之上）。
class DiscoverCoverTabChip extends StatelessWidget {
  const DiscoverCoverTabChip({
    super.key,
    required this.leaf,
    required this.states,
    required this.side,
    required this.showPluginShort,
    this.onClose,
  });

  final DiscoverLeafSpec leaf;
  final Set<WidgetState> states;
  final TabBarSide side;
  final bool showPluginShort;
  final VoidCallback? onClose;

  bool get _selected => states.contains(WidgetState.selected);
  bool get _hovered => states.contains(WidgetState.hovered);
  bool get _pressed => states.contains(WidgetState.pressed);
  bool get _vertical => side.isVertical;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!_vertical) {
      return _buildHorizontalChip(context, colorScheme);
    }

    if (leaf.isHome) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 120.0;
          return Align(
            alignment: Alignment.center,
            child: Container(
              width: width,
              height: 38,
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: _buildHomeCompactChip(context, colorScheme, width),
            ),
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 垂直轨下根据当前轨道宽度自适应封面高度（书本比例约为 1:1.35）
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 120.0;
        final height = (width * 1.35).clamp(84.0, 240.0);

        return Align(
          alignment: Alignment.center,
          child: Container(
            width: width,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: _buildBookCoverCard(context, colorScheme, width, height),
          ),
        );
      },
    );
  }

  /// 发现首页：特殊紧凑项（只用普通 icon + 紧凑高度，不占用书本卡片高度）
  Widget _buildHomeCompactChip(
    BuildContext context,
    ColorScheme colorScheme,
    double width,
  ) {
    final primary = colorScheme.primary;
    final borderColor = _selected
        ? primary
        : (_hovered
              ? colorScheme.outline.withValues(alpha: 0.5)
              : colorScheme.outlineVariant.withValues(alpha: 0.25));
    final backgroundColor = _selected
        ? colorScheme.secondaryContainer
        : (_hovered
              ? colorScheme.surfaceContainerHigh
              : colorScheme.surfaceContainerLow);
    final foregroundColor = _selected
        ? colorScheme.onSecondaryContainer
        : (_hovered ? colorScheme.onSurface : colorScheme.onSurfaceVariant);

    return AnimatedScale(
      scale: _pressed ? 0.96 : (_hovered ? 1.02 : 1.0),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: _selected ? 2.0 : 1.0),
          boxShadow: _selected
              ? [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            GlyphIcon(AppGlyphs.compass, size: 18, color: foregroundColor),
            if (width >= 72) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  leaf.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: _selected ? FontWeight.w700 : FontWeight.w600,
                    color: foregroundColor,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 垂直轨：书本立体卡片形态
  Widget _buildBookCoverCard(
    BuildContext context,
    ColorScheme colorScheme,
    double width,
    double height,
  ) {
    final primary = colorScheme.primary;
    final isSpecial = leaf.isSpecialPage;

    // 选中与悬停的视觉状态
    final borderColor = _selected
        ? primary
        : (_hovered
              ? colorScheme.outline.withValues(alpha: 0.6)
              : Colors.transparent);
    final borderWidth = _selected ? 2.5 : (_hovered ? 1.5 : 0.0);

    return AnimatedScale(
      scale: _pressed ? 0.96 : (_hovered ? 1.02 : 1.0),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: borderColor,
            width: borderWidth,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
          boxShadow: [
            if (_selected)
              BoxShadow(
                color: primary.withValues(alpha: 0.35),
                blurRadius: 10,
                spreadRadius: 1,
                offset: const Offset(0, 2),
              )
            else if (_hovered)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 8,
                offset: const Offset(0, 3),
              )
            else
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8.5),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. 底层：封面图（或渐变底板）
              _buildCoverBackground(context, colorScheme, isSpecial),

              // 2. 拟真书脊立体装订光影（Book spine highlight & inner shadow）
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withValues(alpha: 0.35),
                        Colors.white.withValues(alpha: 0.12),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.25, 1.0],
                    ),
                  ),
                ),
              ),

              // 3. 特殊页面：醒目的中央特殊图标徽章
              if (isSpecial) _buildSpecialIconBadge(context, colorScheme),

              // 4. 未选中时的轻微暗化层（提高选中态对比度）
              if (!_selected && !_hovered)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.18),
                  ),
                ),

              // 5. 顶层信息层：叠加在封面之上的标题与插件信息
              _buildInfoLayer(context, colorScheme),

              // 6. 右上角：关闭按钮
              if (onClose != null)
                Positioned(
                  top: 5,
                  right: 5,
                  child: _buildCloseButton(colorScheme),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 水平横向顶栏：紧凑书卡形态
  Widget _buildHorizontalChip(BuildContext context, ColorScheme colorScheme) {
    final primary = colorScheme.primary;
    final isSpecial = leaf.isSpecialPage;

    final borderColor = _selected
        ? primary
        : (_hovered
              ? colorScheme.outline.withValues(alpha: 0.6)
              : Colors.transparent);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      padding: const EdgeInsets.only(left: 3, right: 6),
      decoration: BoxDecoration(
        color: _selected
            ? colorScheme.surfaceContainerHighest
            : (_hovered
                  ? colorScheme.surfaceContainerHigh
                  : colorScheme.surfaceContainerLow),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: _selected ? 2.0 : 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 左侧小封面 / 特殊图标
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              width: 26,
              height: 32,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCoverBackground(context, colorScheme, isSpecial),
                  if (isSpecial)
                    Center(
                      child: GlyphIcon(
                        leaf.specialIcon(
                          homeTitle: t.discover.title,
                          searchTitle: t.discover.search,
                        ),
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              DiscoverTabs.labelOf(leaf, showPluginShort: showPluginShort),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: _selected ? FontWeight.w700 : FontWeight.w500,
                color: _selected
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (onClose != null) ...[
            const SizedBox(width: 6),
            PlatTabCloseButton(size: 18, iconSize: 12),
          ],
        ],
      ),
    );
  }

  /// 封面底图（监听动态通知器与初始封面）
  Widget _buildCoverBackground(
    BuildContext context,
    ColorScheme colorScheme,
    bool isSpecial,
  ) {
    return ValueListenableBuilder<DiscoverCoverData?>(
      valueListenable: leaf.coverNotifier,
      builder: (context, liveCover, _) {
        final cover = liveCover ?? leaf.initialCover;
        if (cover != null &&
            (cover.url.isNotEmpty ||
                (cover.path != null && cover.path!.isNotEmpty))) {
          return Stack(
            fit: StackFit.expand,
            children: [
              _CoverImage(cover: cover, source: leaf.source),
              // 特殊页面在封面上覆盖微暗遮罩，让中央特殊图标与文字更加突显
              if (isSpecial)
                ColoredBox(color: Colors.black.withValues(alpha: 0.38)),
            ],
          );
        }

        // 无封面或加载中：优雅的主题渐变底板
        return _buildFallbackGradient(colorScheme, isSpecial);
      },
    );
  }

  /// 缺省渐变底板
  Widget _buildFallbackGradient(ColorScheme colorScheme, bool isSpecial) {
    final gradient = switch (leaf.functionKind) {
      PluginFunctionKind.ranking => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF5A3E1B), Color(0xFF26190B)],
      ),
      PluginFunctionKind.latest => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1B4E5A), Color(0xFF0B2126)],
      ),
      PluginFunctionKind.search => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2B3A52), Color(0xFF121924)],
      ),
      PluginFunctionKind.popular => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF5E242B), Color(0xFF260D11)],
      ),
      PluginFunctionKind.recommend => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF452857), Color(0xFF1B0E24)],
      ),
      _ => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isSpecial
            ? [
                colorScheme.primaryContainer,
                colorScheme.surfaceContainerHighest,
              ]
            : [
                colorScheme.surfaceContainerHigh,
                colorScheme.surfaceContainerLowest,
              ],
      ),
    };

    return Container(
      decoration: BoxDecoration(gradient: gradient),
      child: Center(
        child: Opacity(
          opacity: 0.15,
          child: GlyphIcon(
            isSpecial
                ? leaf.specialIcon(
                    homeTitle: t.discover.title,
                    searchTitle: t.discover.search,
                  )
                : AppGlyphs.book,
            size: 48,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  /// 特殊页面的醒目中心徽章（特殊图标）
  Widget _buildSpecialIconBadge(BuildContext context, ColorScheme colorScheme) {
    final icon = leaf.specialIcon(
      homeTitle: t.discover.title,
      searchTitle: t.discover.search,
    );

    return Align(
      alignment: const Alignment(0, -0.2),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.52),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.28),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(child: GlyphIcon(icon, size: 22, color: Colors.white)),
      ),
    );
  }

  /// 叠在封面之上的信息层（标题、插件来源）
  Widget _buildInfoLayer(BuildContext context, ColorScheme colorScheme) {
    final hasSource = leaf.source.isNotEmpty;
    final shortName = pluginShortName(leaf.pluginName);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(7, 24, 7, 7),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.65),
              Colors.black.withValues(alpha: 0.92),
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 插件来源标识（如果可用）
            if (hasSource && showPluginShort && shortName.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4.5,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  shortName,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 3),
            ],
            // 标题文本
            Text(
              leaf.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.2,
                shadows: [
                  Shadow(
                    color: Colors.black87,
                    offset: Offset(0, 1),
                    blurRadius: 3,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 右上角半透明关闭按钮
  Widget _buildCloseButton(ColorScheme colorScheme) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.55),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.22),
            width: 0.8,
          ),
        ),
        child: const Center(
          child: GlyphIcon(AppGlyphs.close, size: 12, color: Colors.white),
        ),
      ),
    );
  }
}

/// 封面图片加载与展示组件
class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.cover, required this.source});

  final DiscoverCoverData cover;
  final String source;

  @override
  Widget build(BuildContext context) {
    // 若本地文件路径有效且已存在，直接加载本地文件
    if (cover.path != null && cover.path!.isNotEmpty) {
      final file = File(cover.path!);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _networkCover(context),
        );
      }
    }

    return _networkCover(context);
  }

  Widget _networkCover(BuildContext context) {
    final pictureInfo = PictureInfo(
      from: cover.from?.isNotEmpty == true ? cover.from! : source,
      url: cover.url,
      path: cover.path ?? '',
      cartoonId: cover.cartoonId ?? '',
      pictureType: PictureType.cover,
    );

    return BlocProvider(
      create: (_) => PictureBloc()..add(GetPicture(pictureInfo)),
      child: BlocBuilder<PictureBloc, PictureLoadState>(
        builder: (context, state) {
          if (state.status == PictureLoadStatus.success &&
              state.imagePath != null) {
            final file = File(state.imagePath!);
            if (file.existsSync()) {
              return Image.file(file, fit: BoxFit.cover);
            }
          }

          // 加载中或失败：展示深色底板带微光
          return Container(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
      ),
    );
  }
}
