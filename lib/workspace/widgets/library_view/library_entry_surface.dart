import 'package:material_ui/material_ui.dart';

import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_read_button.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view_layout.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view_mode.dart';

/// 一行条目在某一档视图下的样子。
///
/// 对应 neoview 的 `ReaderEntrySurface`：它把「六种视图」收成同一个槽位
/// 契约（leading / media / primary / secondary / tertiary / trailing），
/// 各卡片的行只是填了不同的槽。这里同理，只是槽位名字跟着 rossi 的叫法走。
///
/// 手势全部由调用方决定并传进来（已经按 `_busy` 一类的条件夹过了），
/// 这一层不认识「忙不忙」「能不能双击」。
class LibraryEntrySurface extends StatelessWidget {
  const LibraryEntrySurface({
    super.key,
    required this.mode,
    required this.entry,
    this.onTap,
    this.onDoubleTap,
  });

  final LibraryViewMode mode;
  final LibraryEntry entry;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  static const _cardRadius = 8.0;

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      LibraryViewMode.compact => _buildCompact(context),
      LibraryViewMode.coverList => _buildCoverList(context),
      LibraryViewMode.mosaicList => _buildMosaicList(context),
      LibraryViewMode.details => _buildDetailsRow(context),
      LibraryViewMode.coverGrid => _buildCoverGrid(context),
      LibraryViewMode.mosaicGrid => _buildMosaicGrid(context),
    };
  }

  // ── 槽位 ──────────────────────────────────────────────────────────────────

  /// 缩略图槽：尺寸由布局给，内容由数据源给。该模式不画缩略图时为 null。
  ///
  /// 宽高必须是**有限值**。`CoverWidget` 会拿它算 `(width * dpr * 1.2).round()`，
  /// 传无限进去就是整块红色「Unsupported operation: Infinity or NaN toInt」；
  /// `FileManagerThumbnailWidget` 容忍无限，所以文件管理器一侧看不出问题。
  Widget? _media(
    BuildContext context, {
    required double width,
    required double height,
  }) {
    final media = entry.media;
    if (media == null || !entry.wantsThumb(mode)) return null;
    final geo = LibraryViewLayout.thumb(mode);
    return media(
      context,
      width: width,
      height: height,
      radius: geo.radius,
      fit: geo.fit,
    );
  }

  /// 封面档的「直接阅读」叠层（必须放进 Stack 里，所以返回的是 Positioned）。
  ///
  /// 三道闸门：数据源给了 [LibraryEntry.onRead]（目录、图片这类没有「阅读」可言的东西
  /// 不给）、用户的卡片总开关（设置 → 书架 → 卡片角标）、以及格子短边够不够 ——
  /// 最后那道由 `ComicReadButton` 自己把关，所以 coverList 那一档 44x44 的封面槽
  /// 自动不画，不必在这里再记一份尺寸。
  Widget? _readOverlay() {
    final onRead = entry.onRead;
    if (onRead == null) return null;
    if (!comicCardSetting.readButtonEnabled) return null;
    return Positioned.fill(child: ComicReadButton(onTap: onRead));
  }

  /// 语义图标。数据源给多大无所谓，这里按当前档位重画一遍尺寸 ——
  /// 同一个图标在紧凑列表里是 16，在封面网格旁边只有 12。
  Widget? _badge({double? size}) {
    final badge = entry.badge;
    if (badge == null) return null;
    final target = size ?? LibraryViewLayout.badgeSize(mode);
    if (badge is Icon) {
      return Icon(badge.icon, size: target, color: badge.color);
    }
    return badge;
  }

  /// 紧凑列表与详细信息行首的图标：有缩略图就用缩略图，否则退化到语义图标。
  Widget? _leading(BuildContext context) {
    final size = LibraryViewLayout.thumb(mode).size;
    if (size != null) {
      final thumb = _media(context, width: size.width, height: size.height);
      if (thumb != null) return thumb;
    }
    return _badge();
  }

  /// 格子里没有缩略图时居中放一个语义图标。尺寸口径照
  /// `FileManagerThumbnailWidget` 自己的兜底：格子短边的 52%，夹在 16~26。
  Widget _centeredBadge(double boxSide) {
    final size = (boxSide * 0.52).clamp(16.0, 26.0);
    return Center(child: _badge(size: size) ?? const SizedBox.shrink());
  }

  Widget _subLines(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in entry.subLines)
          InkWell(
            onTap: line.onTap,
            onDoubleTap: line.onDoubleTap,
            child: Row(
              children: [
                Icon(
                  line.icon,
                  size: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    line.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 行尾的定宽小字（文件大小 / 来源）。
  Widget? _metaText(BuildContext context, {double? fontSize}) {
    final text = entry.metaText;
    if (text == null || text.isEmpty) return null;
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontSize: fontSize,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  Widget? _trailing(BuildContext context) {
    final trailing = entry.trailing;
    if (trailing != null) return trailing;
    return _metaText(context);
  }

  BoxDecoration _cardDecoration(
    BuildContext context, {
    double radius = _cardRadius,
  }) {
    final theme = Theme.of(context);
    return BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      border: Border.all(
        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
      ),
      borderRadius: BorderRadius.circular(radius),
    );
  }

  // ── 1. 紧凑列表：单行 ~34px，语义图标 + 单行标题 ─────────────────────────
  Widget _buildCompact(BuildContext context) {
    final theme = Theme.of(context);
    final geometry = LibraryViewLayout.list(mode);
    final leading = _leading(context);
    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Container(
        constraints: BoxConstraints(minHeight: geometry.rowMinHeight ?? 34),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 8)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (entry.subLines.isNotEmpty) _subLines(context),
                ],
              ),
            ),
            const SizedBox(width: 6),
            ?_trailing(context),
          ],
        ),
      ),
    );
  }

  // ── 2. 封面列表：双行，封面方块 + 标题 + 子行/元信息 ─────────────────────
  Widget _buildCoverList(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = entry.subtitle;
    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _coverSlot(context),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (entry.subLines.isNotEmpty)
                    _subLines(context)
                  else if (subtitle != null && subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (entry.trailing != null) entry.trailing!,
          ],
        ),
      ),
    );
  }

  Widget _coverSlot(BuildContext context) {
    final geo = LibraryViewLayout.thumb(mode);
    final size = geo.size ?? const Size(44, 44);
    return _media(context, width: size.width, height: size.height) ??
        SizedBox(
          width: size.width,
          height: size.height,
          child: _centeredBadge(size.height),
        );
  }

  // ── 3. 横幅：宽卡片，左侧宽缩略图 + 右侧元数据 ───────────────────────────
  Widget _buildMosaicList(BuildContext context) {
    final theme = Theme.of(context);
    final geo = LibraryViewLayout.thumb(mode);
    final size = geo.size ?? const Size(88, 92);
    final subtitle = entry.subtitle ?? '';
    return InkWell(
      borderRadius: BorderRadius.circular(_cardRadius),
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Container(
        decoration: _cardDecoration(context),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: size.width,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _media(context, width: size.width, height: size.height) ??
                      _centeredBadge(size.width),
                  ?_readOverlay(),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (entry.subLines.isNotEmpty)
                      Expanded(
                        child: SingleChildScrollView(child: _subLines(context)),
                      )
                    else
                      Row(
                        children: [
                          if (_badge() != null) ...[
                            _badge()!,
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 4. 详细信息：表格行（表头由宿主画） ──────────────────────────────────
  Widget _buildDetailsRow(BuildContext context) {
    final theme = Theme.of(context);
    final geometry = LibraryViewLayout.list(mode);
    final leading = _leading(context);
    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Container(
        height: geometry.rowHeight ?? 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(
              flex: LibraryViewLayout.detailsTitleFlex,
              child: Row(
                children: [
                  if (leading != null) ...[leading, const SizedBox(width: 6)],
                  Expanded(
                    child: Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            for (var i = 0; i < entry.detailCells.length; i++) ...[
              const SizedBox(width: LibraryViewLayout.detailsColumnGap),
              SizedBox(
                width: _columnAt(context, i)?.width ?? 75,
                child: Text(
                  entry.detailCells[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: _columnAt(context, i)?.alignRight == true
                      ? TextAlign.right
                      : TextAlign.left,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 数据列由宿主给：表头与行必须用同一组宽度与对齐，否则列会错位。
  /// 宿主没给够列时兜一个常用宽度，免得布局越界。
  LibraryColumn? _columnAt(BuildContext context, int index) =>
      DetailsColumns.of(context)?.columns.elementAtOrNull(index);

  // ── 5. 封面网格：竖版海报 + 两行标题 ─────────────────────────────────────
  Widget _buildCoverGrid(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(_cardRadius),
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Container(
        decoration: _cardDecoration(context),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _cellMedia(context),
                  if (entry.overlayText != null)
                    Positioned(
                      left: 2,
                      right: 2,
                      bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          entry.overlayText!,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),
                  ?_readOverlay(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (_badge() != null) ...[
                        _badge()!,
                        const SizedBox(width: 3),
                      ],
                      Expanded(
                        child: Text(
                          entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  ?_metaText(context, fontSize: 9),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 6. 自由缩略图：1:1 高密度网格 + 单行居中标题 ─────────────────────────
  Widget _buildMosaicGrid(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Container(
        decoration: _cardDecoration(context, radius: 7),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [_cellMedia(context), ?_readOverlay()],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 网格档：缩略图吃掉整个格子剩下的地方。格子多大只有布局时才知道，
  /// 所以这里用 LayoutBuilder 把真实宽高交给数据源，而不是传无限过去。
  Widget _cellMedia(BuildContext context) {
    final media = entry.media;
    final geo = LibraryViewLayout.thumb(mode);
    if (media == null || !entry.wantsThumb(mode)) {
      return _centeredBadge(_cellFallbackSide);
    }
    return LayoutBuilder(
      builder: (context, constraints) => media(
        context,
        width: _finite(constraints.maxWidth, _cellFallbackSide),
        height: _finite(constraints.maxHeight, _cellFallbackSide),
        radius: geo.radius,
        fit: geo.fit,
      ),
    );
  }

  /// 父级给的是无界约束时兜一个常用值：宁可缩略图尺寸保守，
  /// 也不要整块渲染成红色异常。
  static double _finite(double value, double fallback) =>
      value.isFinite ? value : fallback;

  static const double _cellFallbackSide = 120;
}

/// 宿主下发的详细信息数据列。表头与行读同一份定义，列宽与对齐才不会走偏。
class DetailsColumns extends InheritedWidget {
  const DetailsColumns({
    super.key,
    required this.columns,
    required super.child,
  });

  final List<LibraryColumn> columns;

  static DetailsColumns? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DetailsColumns>();

  @override
  bool updateShouldNotify(DetailsColumns oldWidget) =>
      oldWidget.columns.length != columns.length;
}
