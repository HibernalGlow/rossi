import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:zephyr/widgets/library_image_geometry.dart';

import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/library_presentation_preferences.dart';
import 'package:zephyr/workspace/service/library_presentation_store.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_fill.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_widgets.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_inline_expansion.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_tile.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_size_settings.dart';

typedef LibraryLegacyFocusBuilder =
    Widget Function(
      BuildContext,
      Map<String, Widget>,
      ValueChanged<LibraryEntry>,
      ValueChanged<LibraryEntry>,
    );

typedef LibraryDetailBuilder =
    Widget Function(BuildContext, LibraryEntry, VoidCallback);

/// 原位展开宿主：所有数据源都沿用自己的排序、手势和详情消费者。
class LibraryEditorialCanvas extends StatefulWidget {
  const LibraryEditorialCanvas({
    super.key,
    required this.scope,
    required this.entries,
    required this.legacyBuilder,
    required this.onTap,
    this.detailBuilder,
    this.wrapCard,
    this.standalone = false,
    this.tapOpensDetail = true,
    this.onDoubleTap,
    this.canDoubleTap,
    this.enabled = true,
    this.fileStats = false,
    this.onPresentationChanged,
    this.viewToken,
    this.padding = const EdgeInsets.all(10),
    this.onDetailChanged,
    this.cardBuilder,
    this.canShowDetail,
    this.legacyFocusBuilder,
    this.initialPresentation = const LibraryPresentation(),
    this.weightSignals = const [],
    this.gapWidgets,
    this.onReachEnd,
    this.footerBuilder,
  });
  final LibraryPresentation initialPresentation;
  final List<LibraryWeightSignal> weightSignals;

  /// 空隙小组件套件；null = 用通用套件。
  /// 宿主可以传自己的（书签墙加书签语义的组件），也可以传 `const []` 只留图形。
  final List<LibraryGapWidgetSpec>? gapWidgets;
  final VoidCallback? onReachEnd;
  final WidgetBuilder? footerBuilder;
  final String scope;
  final List<LibraryEntry> entries;
  final WidgetBuilder legacyBuilder;
  final LibraryLegacyFocusBuilder? legacyFocusBuilder;
  final ValueChanged<LibraryEntry> onTap;
  final LibraryDetailBuilder? detailBuilder;
  final bool Function(LibraryEntry)? canShowDetail;
  final Widget Function(BuildContext, LibraryEntry, Widget)? wrapCard;
  final Widget Function(BuildContext, LibraryEntry, VoidCallback)? cardBuilder;
  final bool standalone;
  final bool tapOpensDetail;
  final bool enabled;
  final bool fileStats;
  final Object? viewToken;
  final bool Function(LibraryEntry)? canDoubleTap;
  final ValueChanged<LibraryEntry>? onDoubleTap;
  final ValueChanged<LibraryPresentation>? onPresentationChanged;
  final ValueChanged<LibraryEntry?>? onDetailChanged;
  final EdgeInsets padding;

  @override
  State<LibraryEditorialCanvas> createState() => LibraryEditorialCanvasState();
}

class LibraryEditorialCanvasState extends State<LibraryEditorialCanvas> {
  LibraryPresentation _presentation = const LibraryPresentation();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final _expanded = <String, LibraryEntry>{};
  final _detailCache = <String, Widget>{};
  String? _entriesSignature;
  bool _touched = false;
  StreamSubscription<LibraryPresentationChange>? _preferenceSubscription;
  String? _planSignature;
  List<LibraryCanvasRow>? _plan;
  final _anchors = <String, GlobalKey>{};
  int _anchorSerial = 0;
  final Map<String, double> _aspectRatios = {};
  final Map<String, ValueChanged<double>> _ratioCallbacks = {};
  final Map<String, double> _pendingRatios = {};
  bool _ratioUpdateScheduled = false;

  final Map<String, double> _entryOffsets = {};
  final Map<String, double> _entryHeights = {};

  /// 变高展墙的阅读跟随：先定位远处页，再按实际渲染框居中。
  void revealEntry(String key) {
    var remaining = 5;
    void position(Duration _) {
      if (!mounted || !_scroll.hasClients || remaining-- <= 0) return;
      final anchor = _anchors['tile:$key']?.currentContext;
      if (anchor != null) {
        Scrollable.ensureVisible(
          anchor,
          alignment: .5,
          duration: ExpressiveMotion.duration(
            context,
            const Duration(milliseconds: 260),
          ),
        );
        return;
      }
      final top = _entryOffsets[key];
      if (top == null) return;
      final offset =
          top +
          (_entryHeights[key] ?? 200) / 2 -
          _scroll.position.viewportDimension / 2;
      _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
      WidgetsBinding.instance.addPostFrameCallback(position);
      WidgetsBinding.instance.scheduleFrame();
    }

    WidgetsBinding.instance.addPostFrameCallback(position);
    WidgetsBinding.instance.scheduleFrame();
  }

  ValueChanged<double> _ratioCallback(String key) =>
      _ratioCallbacks.putIfAbsent(
        key,
        () =>
            (ratio) => _reportRatio(key, ratio),
      );

  void _reportRatio(String key, double ratio) {
    // ResizeImage 解码尺寸取整后比例会有微小差异；同一来源只采用首个有效比例，
    // 不能让卡片高度 -> 解码尺寸 -> 比例回报形成持续反馈循环。
    if (!ratio.isFinite ||
        ratio <= 0 ||
        _aspectRatios.containsKey(key) ||
        _pendingRatios.containsKey(key)) {
      return;
    }
    _pendingRatios[key] = ratio;
    _scheduleRatios();
  }

  void _scheduleRatios() {
    if (_ratioUpdateScheduled || _pendingRatios.isEmpty) return;
    _ratioUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ratioUpdateScheduled = false;
      if (!mounted) return;
      // 手势滚动和展开详情期间不重排；空闲时批量应用并保留可见封面锚点。
      if (_expanded.isNotEmpty ||
          (_scroll.hasClients && _scroll.position.isScrollingNotifier.value)) {
        return;
      }
      final native =
          _presentation.asymmetric &&
          _presentation.weight == LibraryWeight.imageShape;
      String? anchor;
      double? top;
      if (native) {
        for (final key in _anchors.keys) {
          final y = _anchorTop(key);
          if (y != null &&
              y >= 80 &&
              y < MediaQuery.sizeOf(context).height &&
              (top == null || y < top)) {
            anchor = key;
            top = y;
          }
        }
      }
      setState(() {
        _aspectRatios.addAll(_pendingRatios);
        _pendingRatios.clear();
        if (native) _plan = null;
      });
      if (anchor != null && top != null) _holdAnchor(anchor, top);
    });
    // 图片回报可能发生在帧末尾；显式请求下一帧，不等用户滚动才应用比例。
    WidgetsBinding.instance.scheduleFrame();
  }

  double? _anchorTop(String key) {
    final box = _anchors[key]?.currentContext?.findRenderObject();
    return box is RenderBox && box.attached
        ? box.localToGlobal(Offset.zero).dy
        : null;
  }

  // 切换到下方作品时，收起上方详情不会把刚点的封面带走。
  void _holdAnchor(String key, double top) {
    final serial = ++_anchorSerial;
    final duration = ExpressiveMotion.duration(
      context,
      ExpressiveMotion.spatialDuration,
    );
    Duration? firstFrame;
    void correct(Duration frame) {
      firstFrame ??= frame;
      if (!mounted || serial != _anchorSerial || !_scroll.hasClients) return;
      final current = _anchorTop(key);
      if (current == null) return;
      final delta = current - top;
      if (delta.abs() > .5) {
        final position = _scroll.position;
        position.jumpTo(
          (position.pixels + delta).clamp(0.0, position.maxScrollExtent),
        );
      }
      if (frame - firstFrame! < duration) {
        WidgetsBinding.instance.addPostFrameCallback(correct);
        WidgetsBinding.instance.scheduleFrame();
      } else {
        // 锚点修正已完成。
      }
    }

    WidgetsBinding.instance.addPostFrameCallback(correct);
  }

  @override
  void initState() {
    super.initState();
    _presentation = _initialPresentation;
    _preferenceSubscription = LibraryPresentationStore.instance.changes.listen(
      _onPreferenceChanged,
    );
    _scroll.addListener(_onScroll);
    unawaited(_restore());
  }

  LibraryPresentation get _initialPresentation =>
      widget.initialPresentation.copyWith(
        signalWeights: {
          for (final signal in widget.weightSignals)
            signal.id: signal.defaultWeight,
          ...widget.initialPresentation.signalWeights,
        },
      );

  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 400) {
      widget.onReachEnd?.call();
    }
  }

  Future<void> _restore() async {
    final scope = widget.scope;
    try {
      final saved = await LibraryPresentationStore.instance.read(scope);
      if (!mounted || _touched || scope != widget.scope || saved == null) {
        return;
      }
      _adoptPresentation(saved);
    } on Object {
      /* 损坏的视图偏好不阻止打开藏书。 */
    }
  }

  void _onPreferenceChanged(LibraryPresentationChange change) {
    if (!mounted ||
        change.scope != widget.scope ||
        identical(change.origin, this)) {
      return;
    }
    _touched = true;
    final value = _adaptPresentation(change.presentation);
    if (LibraryPresentationPreferences.content(value) ==
        LibraryPresentationPreferences.content(_presentation)) {
      return;
    }
    _adoptPresentation(change.presentation);
  }

  LibraryPresentation _adaptPresentation(LibraryPresentation value) =>
      value.copyWith(
        weight:
            value.weight == LibraryWeight.signals &&
                widget.weightSignals.isEmpty
            ? widget.initialPresentation.weight
            : value.weight,
        signalWeights: {
          for (final signal in widget.weightSignals)
            signal.id: signal.defaultWeight,
          ...value.signalWeights,
        },
      );

  void _adoptPresentation(LibraryPresentation value) {
    final restored = _adaptPresentation(value);
    setState(() {
      _presentation = restored;
      _expanded.clear();
      _detailCache.clear();
    });
    widget.onDetailChanged?.call(null);
    widget.onPresentationChanged?.call(restored);
  }

  @override
  void didUpdateWidget(covariant LibraryEditorialCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) {
      _touched = false;
      _presentation = _initialPresentation;
      _expanded.clear();
      _detailCache.clear();
      unawaited(_restore());
    } else if (oldWidget.viewToken != widget.viewToken) {
      // 样式变化也可能来自启动恢复、目录记忆或同步；不能据此改写展墙开关。
      _expanded.clear();
      _detailCache.clear();
    }
    if (!identical(oldWidget.entries, widget.entries)) {
      _entriesSignature = null;
      final keys = widget.entries.map((e) => e.key).toSet();
      _expanded.removeWhere((_, e) => !keys.contains(e.key));
      _detailCache.removeWhere(
        (slot, _) => !keys.contains(slot.substring(slot.indexOf(':') + 1)),
      );
      _ratioCallbacks.removeWhere((key, _) => !keys.contains(key));
    }
  }

  Future<void> _save() async {
    try {
      await LibraryPresentationStore.instance.save(
        widget.scope,
        _presentation,
        origin: this,
      );
    } on Object {
      /* 展示状态可重建。 */
    }
  }

  Future<void> _change(LibraryPresentation value) async {
    _touched = true;
    setState(() {
      _presentation = value;
      _expanded.clear();
      _detailCache.clear();
    });
    widget.onDetailChanged?.call(null);
    widget.onPresentationChanged?.call(value);
    await _save();
  }

  /// 只由用户明确选择普通视图时调用；自动恢复底层样式不关闭展墙。
  void showLegacyView() {
    unawaited(_change(_presentation.copyWith(editorial: false)));
  }

  /// 工具条那颗键长按的快开关：只在展墙与普通视图之间翻转，尺寸、分区、
  /// 空隙小组件这些其余偏好原样留着（走的就是设置面板「应用」那一条落盘路径）。
  void toggleEditorial() {
    if (!widget.enabled) return;
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
      unawaited(HapticFeedback.lightImpact());
    }
    unawaited(
      _change(_presentation.copyWith(editorial: !_presentation.editorial)),
    );
  }

  List<LibraryEntry> get expandedEntries => List.unmodifiable(_expanded.values);

  void toggleDetails(LibraryEntry entry) => _toggle(entry);

  /// Escape / 返回逐个收起最近打开的详情，各条目的关闭按钮只收起自己。
  bool closeDetails() {
    if (_expanded.isEmpty) return false;
    _closeSlot(_expanded.keys.last);
    return true;
  }

  void _closeSlot(String slot) {
    if (!_expanded.containsKey(slot)) return;
    final top = _anchorTop(slot);
    setState(() => _expanded.remove(slot));
    if (top != null) _holdAnchor(slot, top);
    _trimDetailCache();
    widget.onDetailChanged?.call(_expanded.values.lastOrNull);
    _scheduleRatios();
  }

  void _trimDetailCache() {
    // 打开的数量不设上限；只限制已收起详情的缓存数量。
    final closed = _detailCache.keys
        .where((k) => !_expanded.containsKey(k))
        .toList();
    for (final slot in closed.take(math.max(0, closed.length - 8))) {
      _detailCache.remove(slot);
    }
  }

  void _toggle(LibraryEntry entry, {bool hero = false}) {
    if (!widget.enabled) return;
    final slot = '${hero ? 'hero' : 'tile'}:${entry.key}';
    if (_expanded.containsKey(slot)) {
      _closeSlot(slot);
      return;
    }
    setState(() => _expanded[slot] = entry);
    _focus.requestFocus();
    widget.onDetailChanged?.call(entry);
    if (Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS) {
      unawaited(HapticFeedback.lightImpact());
    }
  }

  @override
  void dispose() {
    unawaited(_preferenceSubscription?.cancel());
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = _presentation.editorial
        ? _wall(context)
        : widget.legacyFocusBuilder?.call(
                context,
                {
                  for (final entry in widget.entries)
                    if (_expanded.containsKey('tile:${entry.key}') ||
                        _detailCache.containsKey('tile:${entry.key}'))
                      entry.key: _detail(context, entry),
                },
                (entry) => _toggle(entry),
                handleCoverTap,
              ) ??
              widget.legacyBuilder(context);
    return PopScope(
      canPop: _expanded.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) closeDetails();
      },
      child: Focus(
        focusNode: _focus,
        onKeyEvent: (_, event) =>
            event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape &&
                closeDetails()
            ? KeyEventResult.handled
            : KeyEventResult.ignored,
        child: widget.standalone ? body : SizedBox(height: 440, child: body),
      ),
    );
  }

  /// 本面墙可用的小组件套件（**含被单项开关关掉的那些** —— 设置页要能把它们
  /// 再打开，所以列表本身不能被偏好过滤掉）。
  List<LibraryGapWidgetSpec> get _gapKit =>
      widget.gapWidgets ?? defaultLibraryGapWidgets();

  Future<void> openSettings(BuildContext anchorContext) async {
    final box = context.findRenderObject();
    final result = await showLibrarySizeSettings(
      anchorContext,
      _presentation,
      widget.weightSignals,
      availableWidth: box is RenderBox && box.hasSize
          ? math.max(1.0, box.size.width - widget.padding.horizontal)
          : null,
      defaults: widget.initialPresentation,
      gapWidgets: _gapKit,
      fileStats: widget.fileStats,
      hasReading: widget.entries.any((e) => e.onRead != null),
      defaultCoverTapAction: widget.detailBuilder == null
          ? null
          : widget.tapOpensDetail
          ? LibraryCoverTapAction.expandDetails
          : LibraryCoverTapAction.openDetails,
      availableWeights: {
        LibraryWeight.order,
        LibraryWeight.balanced,
        LibraryWeight.imageShape,
        if (widget.weightSignals.isNotEmpty) LibraryWeight.signals,
        if (widget.fileStats || widget.entries.any((e) => e.itemCount != null))
          LibraryWeight.count,
        if (widget.fileStats || widget.entries.any((e) => e.byteSize != null))
          LibraryWeight.bytes,
        if (widget.entries.any((e) => e.timestamp != null))
          LibraryWeight.recent,
        if (widget.entries.any((e) => e.progress != null || e.reading == true))
          LibraryWeight.progress,
      },
    );
    if (mounted && result != null) await _change(result);
  }

  /// 普通网格、自定义封面与展墙共用同一份点击行为，次级详情键独立展开。
  void handleCoverTap(LibraryEntry entry, {bool hero = false}) {
    if (!widget.enabled) return;
    if (_presentation.expandsOnCoverTap(defaultValue: widget.tapOpensDetail) &&
        widget.detailBuilder != null &&
        (widget.canShowDetail?.call(entry) ?? true)) {
      _toggle(entry, hero: hero);
    } else {
      widget.onTap(entry);
    }
  }

  Widget _tile(
    BuildContext context,
    LibraryEntry entry, {
    bool wide = false,
    bool hero = false,
    bool nativeShape = false,
  }) {
    void tap() => handleCoverTap(entry, hero: hero);

    final custom = widget.cardBuilder;
    final tile = custom != null
        ? custom(context, entry, tap)
        : LibraryEditorialTile(
            entry: entry,
            wide: wide,
            spotlight: hero,
            nativeShape: nativeShape,
            imageScale: _presentation.imageScale,
            mediaAspectRatio: _aspectRatios[entry.key],
            selected: _expanded.containsKey(
              '${hero ? 'hero' : 'tile'}:${entry.key}',
            ),
            onTap: widget.enabled ? tap : null,
            onDoubleTap:
                widget.enabled && (widget.canDoubleTap?.call(entry) ?? false)
                ? () => widget.onDoubleTap?.call(entry)
                : null,
            onInfo:
                widget.detailBuilder == null ||
                    !widget.enabled ||
                    !(widget.canShowDetail?.call(entry) ?? true)
                ? null
                : () => _toggle(entry, hero: hero),
          );
    final wrapped = widget.wrapCard?.call(context, entry, tile) ?? tile;
    return LibraryInlineDetailScope(
      onDetails: () => _toggle(entry, hero: hero),
      onCoverTap: tap,
      child: KeyedSubtree(
        key: _anchors.putIfAbsent(
          '${hero ? 'hero' : 'tile'}:${entry.key}',
          GlobalKey.new,
        ),
        child: LibraryImageGeometryScope(
          onRatio: _ratioCallback(entry.key),
          keepFullImage: true,
          imageScale: _presentation.imageScale,
          child: wrapped,
        ),
      ),
    );
  }

  Widget _detail(
    BuildContext context,
    LibraryEntry entry, {
    bool hero = false,
  }) {
    final slot = '${hero ? 'hero' : 'tile'}:${entry.key}';
    final visible = _expanded.containsKey(slot);
    if (widget.detailBuilder == null ||
        (!visible && !_detailCache.containsKey(slot))) {
      return const SizedBox.shrink();
    }
    Widget buildDetail() => Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: widget.detailBuilder!(context, entry, () => _closeSlot(slot)),
    );
    // 文件树、统计快照会继续更新；其宿主保留 State，但需要消费最新参数。
    final child = widget.fileStats
        ? (_detailCache[slot] = buildDetail())
        : _detailCache.putIfAbsent(slot, buildDetail);
    return LibraryInlineExpansion(
      key: ValueKey('library-focus:$slot'),
      visible: visible,
      child: child,
    );
  }

  Widget _wall(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.max(
        1.0,
        constraints.maxWidth - widget.padding.horizontal,
      );
      final columns = libraryCanvasColumns(width, _presentation);
      if (widget.entries.isEmpty) return widget.legacyBuilder(context);
      final entriesSignature = _entriesSignature ??= widget.entries
          .map((e) => '${e.key}:${e.section}:${jsonEncode(e.weightSignals)}')
          .join('|');
      final signature =
          '$columns:${jsonEncode(_presentation.toJson())}:$entriesSignature';
      // 后台统计完成时，已经滚动的画布保持原有几何；下次改变展示设置才重算。
      if (_planSignature != signature || _plan == null) {
        _plan = libraryCanvasRows(
          entries: widget.entries,
          columns: columns,
          presentation: _presentation,
          aspectRatios: _aspectRatios,
        );
        _planSignature = signature;
      }
      final rows = _plan!;
      LibraryEntry? hero;
      for (final e in widget.entries) {
        if (e.onRead != null &&
            (hero == null ||
                (e.timestamp?.millisecondsSinceEpoch ?? 0) >
                    (hero.timestamp?.millisecondsSinceEpoch ?? 0))) {
          hero = e;
        }
      }
      final heroVisible = _presentation.hero && hero != null;
      final tileHeight = _presentation.cardHeight;
      final heroHeight = math.max(238.0, _presentation.cardHeight);
      final gap = _presentation.gap;
      final signalScores = _presentation.weight == LibraryWeight.signals
          ? libraryWeights(
              widget.entries,
              LibraryWeight.signals,
              signalWeights: _presentation.signalWeights,
            )
          : null;
      final unit = (width - (columns - 1) * gap) / columns;
      final native =
          _presentation.asymmetric &&
          _presentation.weight == LibraryWeight.imageShape;
      double heightOf(LibraryCanvasRow row, int j) {
        if (!native) {
          final score = signalScores?[row.indices[j]] ?? 0;
          return tileHeight *
              (1 +
                  (_presentation.asymmetric
                      ? score * _presentation.emphasis * .32
                      : 0));
        }
        final e = widget.entries[row.indices[j]];
        final ratio = _aspectRatios[e.key] ?? e.mediaAspectRatio ?? .72;
        final w = unit * row.spans[j] + (row.spans[j] - 1) * gap;
        final safeRatio = ratio.isFinite && ratio > 0 ? ratio : .72;
        return (w / safeRatio).clamp(150.0, 560.0);
      }

      final rowHeights = [
        for (final row in rows)
          List.generate(row.indices.length, (j) => heightOf(row, j)),
      ];
      final rowMax = [
        for (final heights in rowHeights) heights.fold(0.0, math.max),
      ];

      _entryOffsets.clear();
      _entryHeights.clear();
      var offset = widget.padding.top + (heroVisible ? heroHeight + 52 : 0);
      for (var r = 0; r < rows.length; r++) {
        final row = rows[r];
        if (row.section != null &&
            (r == 0 || rows[r - 1].section != row.section)) {
          offset += 48;
        }
        for (var j = 0; j < row.indices.length; j++) {
          final key = widget.entries[row.indices[j]].key;
          _entryOffsets[key] = offset;
          _entryHeights[key] = rowHeights[r][j];
        }
        offset += rowMax[r] + gap;
      }

      // 不规则轮廓之间剩下的空白：矮卡下方的竖向余量 + 行尾没排满的横向余量。
      // 单项开关：被关掉的组件不进候选；图形单独关掉时口径降级
      // （both → 只剩组件，shapes → 等于不填）。
      final gapKit = libraryGapKit(_gapKit, _presentation.gapWidgets);
      final gapMode = libraryGapMode(
        fill: _presentation.gapFill,
        shapes: _presentation.gapShapes,
      );
      final gapSlots = gapMode == LibraryGapFill.off
          ? const <LibraryGapSlot>[]
          : libraryGapSlots(
              rows: rows,
              heights: rowHeights,
              unit: unit,
              gap: gap,
              columns: columns,
            );
      final gapFills = libraryGapChoices(
        slots: gapSlots,
        mode: gapMode,
        widgets: gapKit,
        entries: widget.entries,
        scope: widget.scope,
      );
      final gapById = {for (final slot in gapSlots) slot.id: slot};
      ({Widget widget, double height})? gapFiller(String id) {
        final slot = gapById[id];
        final choice = slot == null ? null : gapFills[id];
        if (slot == null || choice == null) return null;
        return (
          height: slot.height,
          widget: LibraryGapFiller(
            choice: choice,
            sample: LibraryGapSample(
              entries: widget.entries,
              slot: slot,
              seed: choice.seed,
            ),
            widgets: gapKit,
          ),
        );
      }

      return NotificationListener<UserScrollNotification>(
        onNotification: (notification) {
          if (notification.direction != ScrollDirection.idle) {
            _anchorSerial++;
          } else {
            _scheduleRatios();
          }
          return false;
        },
        child: ListView.builder(
          key: PageStorageKey('library-wall:${widget.scope}'),
          controller: _scroll,
          padding: widget.padding,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount:
              rows.length +
              (heroVisible ? 1 : 0) +
              (widget.footerBuilder == null ? 0 : 1),
          itemBuilder: (context, index) {
            if (heroVisible && index == 0) {
              return LibraryDetailRetention(
                keep:
                    _expanded.containsKey('hero:${hero!.key}') ||
                    _detailCache.containsKey('hero:${hero.key}'),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          hero.reading == true ? '继续阅读' : '阅读中枢',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      SizedBox(
                        height: heroHeight,
                        child: _tile(context, hero, wide: true, hero: true),
                      ),
                      _detail(context, hero, hero: true),
                    ],
                  ),
                ),
              );
            }
            final ri = index - (heroVisible ? 1 : 0);
            if (ri == rows.length) return widget.footerBuilder!(context);
            final row = rows[ri];
            final occupied = row.spans.fold<int>(0, (a, b) => a + b);
            final rowHeight = rowMax[ri];
            final tileFills = [
              for (var j = 0; j < row.indices.length; j++)
                gapFiller('r${ri}t$j'),
            ];
            final trailingFill = gapFiller('r${ri}x');
            final detailEntries = [
              for (final i in row.indices)
                if (_expanded.containsKey('tile:${widget.entries[i].key}') ||
                    _detailCache.containsKey('tile:${widget.entries[i].key}'))
                  widget.entries[i],
            ];
            return LibraryDetailRetention(
              keep: detailEntries.isNotEmpty,
              child: Padding(
                padding: EdgeInsets.only(bottom: gap),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (row.section != null &&
                        (ri == 0 || rows[ri - 1].section != row.section))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 12, 2, 12),
                        child: Text(
                          row.section!,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    SizedBox(
                      height: rowHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var j = 0; j < row.indices.length; j++) ...[
                            if (j > 0) SizedBox(width: gap),
                            SizedBox(
                              width:
                                  unit * row.spans[j] +
                                  (row.spans[j] - 1) * gap,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    height: rowHeights[ri][j],
                                    child: _tile(
                                      context,
                                      widget.entries[row.indices[j]],
                                      wide: row.spans[j] > 1,
                                      nativeShape: native,
                                    ),
                                  ),
                                  // 矮卡下方的余量：填充物自己带 gap 间距。
                                  if (tileFills[j] != null)
                                    SizedBox(
                                      height: tileFills[j]!.height,
                                      child: tileFills[j]!.widget,
                                    ),
                                ],
                              ),
                            ),
                          ],
                          if (occupied < columns) ...[
                            SizedBox(width: gap),
                            if (trailingFill != null)
                              SizedBox(
                                width:
                                    unit * (columns - occupied) +
                                    (columns - occupied - 1) * gap,
                                height: rowHeight,
                                child: trailingFill.widget,
                              ),
                            const Spacer(),
                          ],
                        ],
                      ),
                    ),
                    for (final entry in detailEntries) _detail(context, entry),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

/// 封面自身的下载/长按手势保留；信息点击由当前槽位接管，包括主视觉。
class LibraryInlineDetailScope extends InheritedWidget {
  const LibraryInlineDetailScope({
    super.key,
    required this.onDetails,
    required this.onCoverTap,
    required super.child,
  });
  final VoidCallback onDetails;
  final VoidCallback onCoverTap;
  static LibraryInlineDetailScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LibraryInlineDetailScope>();
  @override
  bool updateShouldNotify(covariant LibraryInlineDetailScope oldWidget) =>
      oldWidget.onDetails != onDetails || oldWidget.onCoverTap != onCoverTap;
}
