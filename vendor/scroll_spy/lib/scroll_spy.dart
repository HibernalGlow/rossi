library;

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Anchor line inside the scrollable viewport used to evaluate item focus.
class ScrollSpyAnchor {
  /// Places the anchor at a normalized viewport fraction (`0.0` = leading/top,
  /// `0.5` = center, `1.0` = trailing/bottom).
  const ScrollSpyAnchor.fraction(double this.fraction)
    : pixels = null,
      assert(fraction >= 0.0 && fraction <= 1.0);

  /// Places the anchor at a fixed pixel offset from the viewport leading edge.
  const ScrollSpyAnchor.pixels(double this.pixels)
    : fraction = null,
      assert(pixels >= 0.0);

  final double? fraction;
  final double? pixels;

  /// Resolves the anchor offset in pixels within [viewportExtent] after
  /// accounting for [leadingInsetPx] and [trailingInsetPx].
  double resolve(
    double viewportExtent, {
    double leadingInsetPx = 0.0,
    double trailingInsetPx = 0.0,
  }) {
    final usable = math.max(
      0.0,
      viewportExtent - leadingInsetPx - trailingInsetPx,
    );
    if (pixels != null) {
      return (leadingInsetPx + pixels!).clamp(
        leadingInsetPx,
        leadingInsetPx + usable,
      );
    }
    return leadingInsetPx + usable * (fraction ?? 0.0);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScrollSpyAnchor &&
          other.fraction == fraction &&
          other.pixels == pixels;

  @override
  int get hashCode => Object.hash(fraction, pixels);
}

/// Defines the attention / focus region within the scrollable viewport.
class ScrollSpyRegion {
  /// A band of [extentPx] centered on [anchor] (or starting from [anchor]
  /// when clamped by viewport bounds).
  const ScrollSpyRegion.zone({
    required this.anchor,
    this.extentPx = 180.0,
    this.leadingInsetPx = 0.0,
    this.trailingInsetPx = 0.0,
    this.alignAnchorAtLeadingEdge = false,
  }) : assert(extentPx >= 0.0);

  /// A thin line at [anchor] inside the viewport.
  const ScrollSpyRegion.line({
    required this.anchor,
    this.leadingInsetPx = 0.0,
    this.trailingInsetPx = 0.0,
  }) : extentPx = 1.0,
       alignAnchorAtLeadingEdge = true;

  /// Reading-position / Table-of-Contents preset for long settings and
  /// document pages: places the focus band near the top of the viewport
  /// below any sticky header ([leadingInsetPx]).
  const ScrollSpyRegion.readingPosition({
    this.anchor = const ScrollSpyAnchor.pixels(28.0),
    this.extentPx = 160.0,
    this.leadingInsetPx = 0.0,
    this.trailingInsetPx = 0.0,
  }) : alignAnchorAtLeadingEdge = true;

  final ScrollSpyAnchor anchor;
  final double extentPx;
  final double leadingInsetPx;
  final double trailingInsetPx;
  final bool alignAnchorAtLeadingEdge;

  /// Returns `(regionStart, anchorOffset, regionEnd)` in viewport coordinates.
  (double start, double anchorOffset, double end) resolveBounds(
    double viewportExtent,
  ) {
    final minBound = leadingInsetPx.clamp(0.0, viewportExtent);
    final maxBound = math.max(
      minBound,
      viewportExtent - trailingInsetPx.clamp(0.0, viewportExtent),
    );
    final anchorOffset = anchor
        .resolve(
          viewportExtent,
          leadingInsetPx: leadingInsetPx,
          trailingInsetPx: trailingInsetPx,
        )
        .clamp(minBound, maxBound);
    if (alignAnchorAtLeadingEdge) {
      final end = (anchorOffset + extentPx).clamp(minBound, maxBound);
      return (anchorOffset, anchorOffset, end);
    }
    final half = extentPx / 2.0;
    final start = (anchorOffset - half).clamp(minBound, maxBound);
    final end = (anchorOffset + half).clamp(minBound, maxBound);
    return (start, anchorOffset, end);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScrollSpyRegion &&
          other.anchor == anchor &&
          other.extentPx == extentPx &&
          other.leadingInsetPx == leadingInsetPx &&
          other.trailingInsetPx == trailingInsetPx &&
          other.alignAnchorAtLeadingEdge == alignAnchorAtLeadingEdge;

  @override
  int get hashCode => Object.hash(
    anchor,
    extentPx,
    leadingInsetPx,
    trailingInsetPx,
    alignAnchorAtLeadingEdge,
  );
}

enum _ScrollSpyPolicyKind {
  closestToAnchor,
  leadingEdge,
  largestVisibleFraction,
}

/// Strategy used to pick the single winning primary item among visible items.
class ScrollSpyPolicy {
  /// Selects the item whose focus point / bounds are closest to the anchor.
  const ScrollSpyPolicy.closestToAnchor({this.pinBoundaryEdges = true})
    : _kind = _ScrollSpyPolicyKind.closestToAnchor;

  /// Table-of-contents / reading-position policy: selects the section that
  /// currently spans the anchor or is the first visible section below it,
  /// pinning the first/last section at scroll extremes.
  const ScrollSpyPolicy.readingPosition({this.pinBoundaryEdges = true})
    : _kind = _ScrollSpyPolicyKind.leadingEdge;

  /// Selects the item with the largest visible fraction inside the viewport.
  const ScrollSpyPolicy.largestVisibleFraction({this.pinBoundaryEdges = true})
    : _kind = _ScrollSpyPolicyKind.largestVisibleFraction;

  final _ScrollSpyPolicyKind _kind;

  /// When true, scrolling all the way to the top selects the first visible
  /// item, and scrolling to `maxScrollExtent` selects the last visible item.
  final bool pinBoundaryEdges;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScrollSpyPolicy &&
          other._kind == _kind &&
          other.pinBoundaryEdges == pinBoundaryEdges;

  @override
  int get hashCode => Object.hash(_kind, pinBoundaryEdges);
}

/// Anti-flicker stabilization parameters.
class ScrollSpyStability {
  const ScrollSpyStability({
    this.hysteresisPx = 20.0,
    this.minPrimaryDuration = const Duration(milliseconds: 100),
  }) : assert(hysteresisPx >= 0.0);

  static const ScrollSpyStability none = ScrollSpyStability(
    hysteresisPx: 0.0,
    minPrimaryDuration: Duration.zero,
  );

  /// Pixel advantage a challenger must have over the current primary item
  /// before stealing primary focus during continuous scrolling.
  final double hysteresisPx;

  /// Minimum duration an incumbent primary item holds focus while still
  /// visible in the attention zone during active scrolling.
  final Duration minPrimaryDuration;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScrollSpyStability &&
          other.hysteresisPx == hysteresisPx &&
          other.minPrimaryDuration == minPrimaryDuration;

  @override
  int get hashCode => Object.hash(hysteresisPx, minPrimaryDuration);
}

/// Controls when [ScrollSpyScope] recomputes focus during scroll gestures.
enum ScrollSpyUpdatePolicy {
  /// Recomputes on every scroll frame.
  perFrame,

  /// Recomputes only when scrolling stops.
  scrollEnd,

  /// Recomputes every frame during drag/slow scroll and throttles fast ballistic
  /// flings until they slow down or settle.
  hybrid,
}

/// Per-item geometry and focus state computed by [ScrollSpyScope].
class ScrollSpyItemFocus<T> {
  const ScrollSpyItemFocus({
    required this.id,
    required this.isPrimary,
    required this.isVisible,
    required this.visibleFraction,
    required this.regionOverlapFraction,
    required this.distanceToAnchorPx,
    required this.leadingEdgePx,
    required this.trailingEdgePx,
  });

  const ScrollSpyItemFocus.unmounted(this.id)
    : isPrimary = false,
      isVisible = false,
      visibleFraction = 0.0,
      regionOverlapFraction = 0.0,
      distanceToAnchorPx = double.infinity,
      leadingEdgePx = double.infinity,
      trailingEdgePx = double.infinity;

  final T id;
  final bool isPrimary;
  final bool isVisible;
  final double visibleFraction;
  final double regionOverlapFraction;
  final double distanceToAnchorPx;
  final double leadingEdgePx;
  final double trailingEdgePx;

  ScrollSpyItemFocus<T> copyWith({bool? isPrimary}) => ScrollSpyItemFocus<T>(
    id: id,
    isPrimary: isPrimary ?? this.isPrimary,
    isVisible: isVisible,
    visibleFraction: visibleFraction,
    regionOverlapFraction: regionOverlapFraction,
    distanceToAnchorPx: distanceToAnchorPx,
    leadingEdgePx: leadingEdgePx,
    trailingEdgePx: trailingEdgePx,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScrollSpyItemFocus<T> &&
          other.id == id &&
          other.isPrimary == isPrimary &&
          other.isVisible == isVisible &&
          (other.visibleFraction - visibleFraction).abs() < 1e-4 &&
          (other.regionOverlapFraction - regionOverlapFraction).abs() < 1e-4 &&
          (other.distanceToAnchorPx - distanceToAnchorPx).abs() < 0.5 &&
          (other.leadingEdgePx - leadingEdgePx).abs() < 0.5 &&
          (other.trailingEdgePx - trailingEdgePx).abs() < 0.5;

  @override
  int get hashCode => Object.hash(id, isPrimary, isVisible);
}

/// Immutable snapshot of all visible items and the primary winner.
class ScrollSpySnapshot<T> {
  const ScrollSpySnapshot({
    required this.primaryId,
    required this.visibleIds,
    required this.orderedIds,
    required this.items,
    this.scrollProgress = 0.0,
  });

  const ScrollSpySnapshot.empty()
    : primaryId = null,
      visibleIds = const {},
      orderedIds = const [],
      items = const {},
      scrollProgress = 0.0;

  final T? primaryId;
  final Set<T> visibleIds;
  final List<T> orderedIds;
  final Map<T, ScrollSpyItemFocus<T>> items;
  final double scrollProgress;

  ScrollSpyItemFocus<T>? operator [](T id) => items[id];
}

/// Controller that exposes the active primary item, visible items, and
/// targeted per-item focus listenables.
class ScrollSpyController<T> extends ChangeNotifier {
  final ValueNotifier<T?> _primaryId = ValueNotifier<T?>(null);
  final ValueNotifier<Set<T>> _visibleIds = ValueNotifier<Set<T>>(const {});
  final ValueNotifier<ScrollSpySnapshot<T>> _snapshot =
      ValueNotifier<ScrollSpySnapshot<T>>(const ScrollSpySnapshot.empty());
  final Map<T, ValueNotifier<ScrollSpyItemFocus<T>>> _itemNotifiers = {};
  final Map<T, Element> _registeredElements = LinkedHashMap<T, Element>();

  VoidCallback? _recomputeCallback;
  T? _lockedPrimaryId;
  Timer? _lockTimer;
  DateTime? _lastPrimaryChangeAt;

  /// Reactive listenable for the single winning primary item ID.
  ValueListenable<T?> get primaryId => _primaryId;

  /// Current primary item ID.
  T? get currentPrimaryId => _primaryId.value;

  /// Reactive listenable for currently visible item IDs.
  ValueListenable<Set<T>> get visibleIds => _visibleIds;

  /// Current set of visible item IDs.
  Set<T> get currentVisibleIds => _visibleIds.value;

  /// Reactive listenable for the full viewport focus snapshot.
  ValueListenable<ScrollSpySnapshot<T>> get snapshot => _snapshot;

  /// Currently mounted item IDs ordered from top to bottom.
  List<T> get orderedIds => _snapshot.value.orderedIds;

  /// Whether primary selection is temporarily locked during programmatic scroll.
  bool get isPrimaryLocked => _lockedPrimaryId != null;

  /// Targeted per-item focus listenable (only notifies when [id]'s focus state
  /// changes).
  ValueListenable<ScrollSpyItemFocus<T>> itemFocusOf(T id) {
    return _itemNotifiers.putIfAbsent(
      id,
      () => ValueNotifier<ScrollSpyItemFocus<T>>(
        _snapshot.value.items[id] ?? ScrollSpyItemFocus<T>.unmounted(id),
      ),
    );
  }

  /// Returns the mounted [BuildContext] for [id], if currently mounted.
  BuildContext? contextOf(T id) {
    final element = _registeredElements[id];
    if (element != null && element.mounted) {
      return element;
    }
    return null;
  }

  /// Temporarily locks [primaryId] to [id] for [duration] so programmatic
  /// scroll animations to an anchor do not flicker intermediate items.
  void lockPrimary(
    T id, {
    Duration duration = const Duration(milliseconds: 420),
  }) {
    _lockTimer?.cancel();
    _lockedPrimaryId = id;
    _setPrimaryImmediate(id);
    if (duration > Duration.zero) {
      _lockTimer = Timer(duration, unlockPrimary);
    }
  }

  /// Releases any programmatic primary lock and triggers a fresh recompute.
  void unlockPrimary() {
    _lockTimer?.cancel();
    _lockTimer = null;
    if (_lockedPrimaryId == null) return;
    _lockedPrimaryId = null;
    recompute();
  }

  /// Manually sets the primary item ID.
  void selectPrimary(T? id) {
    _setPrimaryImmediate(id);
  }

  /// Requests an immediate focus recomputation from the attached [ScrollSpyScope].
  void recompute() {
    _recomputeCallback?.call();
  }

  void _setPrimaryImmediate(T? id) {
    final prev = _primaryId.value;
    if (prev == id) return;
    _primaryId.value = id;
    _lastPrimaryChangeAt = DateTime.now();
    if (prev != null && _itemNotifiers.containsKey(prev)) {
      final prevFocus = _itemNotifiers[prev]!.value;
      if (prevFocus.isPrimary) {
        _itemNotifiers[prev]!.value = prevFocus.copyWith(isPrimary: false);
      }
    }
    if (id != null && _itemNotifiers.containsKey(id)) {
      final nextFocus = _itemNotifiers[id]!.value;
      if (!nextFocus.isPrimary) {
        _itemNotifiers[id]!.value = nextFocus.copyWith(isPrimary: true);
      }
    }
    notifyListeners();
  }

  void _registerItem(T id, Element element) {
    _registeredElements[id] = element;
  }

  void _unregisterItem(T id, Element element) {
    if (_registeredElements[id] == element) {
      _registeredElements.remove(id);
    }
  }

  void _commitSnapshot(ScrollSpySnapshot<T> next) {
    final prevSnapshot = _snapshot.value;
    final prevPrimary = _primaryId.value;
    _snapshot.value = next;

    if (!setEquals(_visibleIds.value, next.visibleIds)) {
      _visibleIds.value = next.visibleIds;
    }

    if (prevPrimary != next.primaryId) {
      _primaryId.value = next.primaryId;
      _lastPrimaryChangeAt = DateTime.now();
    }

    for (final entry in _itemNotifiers.entries) {
      final itemFocus =
          next.items[entry.key] ?? ScrollSpyItemFocus<T>.unmounted(entry.key);
      if (entry.value.value != itemFocus) {
        entry.value.value = itemFocus;
      }
    }

    if (prevPrimary != next.primaryId ||
        prevSnapshot.orderedIds.length != next.orderedIds.length ||
        (prevSnapshot.scrollProgress - next.scrollProgress).abs() > 0.005) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    _primaryId.dispose();
    _visibleIds.dispose();
    _snapshot.dispose();
    for (final notifier in _itemNotifiers.values) {
      notifier.dispose();
    }
    _itemNotifiers.clear();
    _registeredElements.clear();
    super.dispose();
  }
}

/// Scope widget that tracks descendant [ScrollSpyItem]s inside a scrollable
/// and computes the active primary item according to [region], [policy], and
/// [stability].
class ScrollSpyScope<T> extends StatefulWidget {
  const ScrollSpyScope({
    super.key,
    required this.controller,
    required this.child,
    this.region = const ScrollSpyRegion.readingPosition(),
    this.policy = const ScrollSpyPolicy.readingPosition(),
    this.stability = const ScrollSpyStability(),
    this.updatePolicy = ScrollSpyUpdatePolicy.perFrame,
    this.onPrimaryChanged,
    this.axis = Axis.vertical,
  });

  final ScrollSpyController<T> controller;
  final Widget child;
  final ScrollSpyRegion region;
  final ScrollSpyPolicy policy;
  final ScrollSpyStability stability;
  final ScrollSpyUpdatePolicy updatePolicy;
  final ValueChanged<T?>? onPrimaryChanged;
  final Axis axis;

  static _ScrollSpyScopeState<T>? _maybeOf<T>(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_ScrollSpyInherited<T>>()
        ?.state;
  }

  @override
  State<ScrollSpyScope<T>> createState() => _ScrollSpyScopeState<T>();
}

class _ScrollSpyScopeState<T> extends State<ScrollSpyScope<T>> {
  bool _scheduled = false;
  ScrollMetrics? _lastMetrics;

  @override
  void initState() {
    super.initState();
    widget.controller._recomputeCallback = _scheduleCompute;
    _scheduleCompute();
  }

  @override
  void didUpdateWidget(covariant ScrollSpyScope<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._recomputeCallback = null;
      widget.controller._recomputeCallback = _scheduleCompute;
    }
    if (oldWidget.region != widget.region ||
        oldWidget.policy != widget.policy ||
        oldWidget.stability != widget.stability) {
      _scheduleCompute();
    }
  }

  @override
  void dispose() {
    if (widget.controller._recomputeCallback == _scheduleCompute) {
      widget.controller._recomputeCallback = null;
    }
    super.dispose();
  }

  void _register(T id, Element element) {
    widget.controller._registerItem(id, element);
    _scheduleCompute();
  }

  void _unregister(T id, Element element) {
    widget.controller._unregisterItem(id, element);
    _scheduleCompute();
  }

  void _scheduleCompute() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      _computeNow(isSettled: false);
    });
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != widget.axis) return false;
    _lastMetrics = notification.metrics;

    if (notification is ScrollEndNotification) {
      _computeNow(isSettled: true);
      return false;
    }

    switch (widget.updatePolicy) {
      case ScrollSpyUpdatePolicy.perFrame:
        _computeNow(isSettled: false);
      case ScrollSpyUpdatePolicy.scrollEnd:
        break;
      case ScrollSpyUpdatePolicy.hybrid:
        if (notification is ScrollUpdateNotification) {
          final delta = notification.scrollDelta?.abs() ?? 0.0;
          if (delta <= 42.0 || notification.dragDetails != null) {
            _computeNow(isSettled: false);
          }
        }
    }
    return false;
  }

  bool _onMetricsNotification(ScrollMetricsNotification notification) {
    if (notification.metrics.axis != widget.axis) return false;
    _lastMetrics = notification.metrics;
    _scheduleCompute();
    return false;
  }

  void _computeNow({required bool isSettled}) {
    if (!mounted) return;
    final scopeBox = context.findRenderObject();
    if (scopeBox is! RenderBox || !scopeBox.hasSize) return;

    final viewportSize = scopeBox.size;
    final viewportExtent = widget.axis == Axis.vertical
        ? viewportSize.height
        : viewportSize.width;
    if (viewportExtent <= 0) return;

    final (regionStart, anchorOffset, regionEnd) = widget.region.resolveBounds(
      viewportExtent,
    );
    final regionExtent = math.max(1.0, regionEnd - regionStart);

    final rawItems = <_MeasuredItem<T>>[];
    final staleIds = <T>[];

    for (final entry in widget.controller._registeredElements.entries) {
      final id = entry.key;
      final element = entry.value;
      if (!element.mounted) {
        staleIds.add(id);
        continue;
      }
      final renderObject = element.renderObject;
      if (renderObject is! RenderBox ||
          !renderObject.hasSize ||
          !renderObject.attached) {
        continue;
      }
      final itemSize = renderObject.size;
      final itemExtent = widget.axis == Axis.vertical
          ? itemSize.height
          : itemSize.width;
      if (itemExtent <= 0) continue;

      final topLeft = renderObject.localToGlobal(
        Offset.zero,
        ancestor: scopeBox,
      );
      final leading = widget.axis == Axis.vertical ? topLeft.dy : topLeft.dx;
      final trailing = leading + itemExtent;

      final visibleStart = math.max(0.0, leading);
      final visibleEnd = math.min(viewportExtent, trailing);
      final visiblePx = math.max(0.0, visibleEnd - visibleStart);
      final isVisible = visiblePx > 0.5;
      final visibleFraction = (visiblePx / itemExtent).clamp(0.0, 1.0);

      final overlapStart = math.max(regionStart, leading);
      final overlapEnd = math.min(regionEnd, trailing);
      final overlapPx = math.max(0.0, overlapEnd - overlapStart);
      final regionOverlapFraction = (overlapPx / regionExtent).clamp(0.0, 1.0);

      final double distanceToAnchorPx;
      if (leading <= anchorOffset && trailing >= anchorOffset) {
        distanceToAnchorPx = 0.0;
      } else if (leading > anchorOffset) {
        distanceToAnchorPx = leading - anchorOffset;
      } else {
        distanceToAnchorPx = anchorOffset - trailing;
      }

      rawItems.add(
        _MeasuredItem<T>(
          id: id,
          isVisible: isVisible,
          visibleFraction: visibleFraction,
          regionOverlapFraction: regionOverlapFraction,
          distanceToAnchorPx: distanceToAnchorPx,
          leadingEdgePx: leading,
          trailingEdgePx: trailing,
        ),
      );
    }

    for (final id in staleIds) {
      widget.controller._registeredElements.remove(id);
    }

    rawItems.sort((a, b) => a.leadingEdgePx.compareTo(b.leadingEdgePx));
    final orderedIds = List<T>.unmodifiable(rawItems.map((e) => e.id));
    final visibleIds = Set<T>.unmodifiable(
      rawItems.where((e) => e.isVisible).map((e) => e.id),
    );

    T? winnerId;
    if (widget.controller._lockedPrimaryId != null &&
        orderedIds.contains(widget.controller._lockedPrimaryId)) {
      winnerId = widget.controller._lockedPrimaryId;
    } else if (rawItems.isNotEmpty) {
      winnerId = _selectWinner(
        rawItems: rawItems,
        anchorOffset: anchorOffset,
        regionStart: regionStart,
        regionEnd: regionEnd,
        viewportExtent: viewportExtent,
        isSettled: isSettled,
      );
    }

    final focusMap = <T, ScrollSpyItemFocus<T>>{
      for (final item in rawItems)
        item.id: ScrollSpyItemFocus<T>(
          id: item.id,
          isPrimary: item.id == winnerId,
          isVisible: item.isVisible,
          visibleFraction: item.visibleFraction,
          regionOverlapFraction: item.regionOverlapFraction,
          distanceToAnchorPx: item.distanceToAnchorPx,
          leadingEdgePx: item.leadingEdgePx,
          trailingEdgePx: item.trailingEdgePx,
        ),
    };

    double progress = 0.0;
    if (_lastMetrics != null && _lastMetrics!.maxScrollExtent > 0) {
      progress = (_lastMetrics!.pixels / _lastMetrics!.maxScrollExtent).clamp(
        0.0,
        1.0,
      );
    } else if (orderedIds.length > 1 && winnerId != null) {
      final idx = orderedIds.indexOf(winnerId);
      if (idx >= 0) {
        progress = idx / (orderedIds.length - 1);
      }
    }

    final prevPrimary = widget.controller.currentPrimaryId;
    widget.controller._commitSnapshot(
      ScrollSpySnapshot<T>(
        primaryId: winnerId,
        visibleIds: visibleIds,
        orderedIds: orderedIds,
        items: focusMap,
        scrollProgress: progress,
      ),
    );
    if (prevPrimary != winnerId) {
      widget.onPrimaryChanged?.call(winnerId);
    }
  }

  T? _selectWinner({
    required List<_MeasuredItem<T>> rawItems,
    required double anchorOffset,
    required double regionStart,
    required double regionEnd,
    required double viewportExtent,
    required bool isSettled,
  }) {
    final visible = rawItems.where((item) => item.isVisible).toList();
    if (visible.isEmpty) {
      return rawItems.first.id;
    }

    if (widget.policy.pinBoundaryEdges && _lastMetrics != null) {
      final metrics = _lastMetrics!;
      if (metrics.pixels <= metrics.minScrollExtent + 4.0) {
        return visible.first.id;
      }
      if (metrics.maxScrollExtent > 0 &&
          metrics.pixels >= metrics.maxScrollExtent - 4.0) {
        return visible.last.id;
      }
    }

    _MeasuredItem<T> candidate;
    switch (widget.policy._kind) {
      case _ScrollSpyPolicyKind.leadingEdge:
        // Reading-position / Table of Contents selection:
        // 1. If an item spans the anchor or its header is inside [regionStart, regionEnd],
        //    pick the latest item whose leadingEdgePx <= regionEnd (or spans anchor).
        final inOrAboveZone = visible
            .where((item) => item.leadingEdgePx <= regionEnd)
            .toList();
        if (inOrAboveZone.isNotEmpty) {
          // Prefer the last section whose heading has entered or passed the reading zone
          // and whose body is still visible in the viewport.
          candidate = inOrAboveZone.last;
        } else {
          candidate = visible.first;
        }
      case _ScrollSpyPolicyKind.closestToAnchor:
        candidate = visible.first;
        for (final item in visible.skip(1)) {
          if (item.distanceToAnchorPx < candidate.distanceToAnchorPx) {
            candidate = item;
          }
        }
      case _ScrollSpyPolicyKind.largestVisibleFraction:
        candidate = visible.first;
        for (final item in visible.skip(1)) {
          if (item.visibleFraction > candidate.visibleFraction) {
            candidate = item;
          }
        }
    }

    final incumbentId = widget.controller.currentPrimaryId;
    if (incumbentId == null || incumbentId == candidate.id) {
      return candidate.id;
    }

    final incumbent = visible
        .where((item) => item.id == incumbentId)
        .firstOrNull;
    if (incumbent == null) {
      return candidate.id;
    }

    // Apply anti-flicker stability rules during active scrolling.
    if (!isSettled) {
      final lastChange = widget.controller._lastPrimaryChangeAt;
      if (lastChange != null &&
          widget.stability.minPrimaryDuration > Duration.zero &&
          DateTime.now().difference(lastChange) <
              widget.stability.minPrimaryDuration &&
          incumbent.regionOverlapFraction > 0) {
        return incumbent.id;
      }

      if (widget.stability.hysteresisPx > 0) {
        final advantage =
            (incumbent.distanceToAnchorPx - candidate.distanceToAnchorPx).abs();
        if (advantage < widget.stability.hysteresisPx &&
            incumbent.regionOverlapFraction > 0) {
          return incumbent.id;
        }
      }
    }

    return candidate.id;
  }

  @override
  Widget build(BuildContext context) {
    return _ScrollSpyInherited<T>(
      state: this,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _onMetricsNotification,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: widget.child,
        ),
      ),
    );
  }
}

class _ScrollSpyInherited<T> extends InheritedWidget {
  const _ScrollSpyInherited({required this.state, required super.child});

  final _ScrollSpyScopeState<T> state;

  @override
  bool updateShouldNotify(covariant _ScrollSpyInherited<T> oldWidget) =>
      oldWidget.state != state;
}

class _MeasuredItem<T> {
  const _MeasuredItem({
    required this.id,
    required this.isVisible,
    required this.visibleFraction,
    required this.regionOverlapFraction,
    required this.distanceToAnchorPx,
    required this.leadingEdgePx,
    required this.trailingEdgePx,
  });

  final T id;
  final bool isVisible;
  final double visibleFraction;
  final double regionOverlapFraction;
  final double distanceToAnchorPx;
  final double leadingEdgePx;
  final double trailingEdgePx;
}

typedef ScrollSpyItemBuilder<T> =
    Widget Function(
      BuildContext context,
      ScrollSpyItemFocus<T> focus,
      Widget? child,
    );

/// Registers a scrollable section or item with its enclosing [ScrollSpyScope].
class ScrollSpyItem<T> extends StatefulWidget {
  const ScrollSpyItem({super.key, required this.id, this.child, this.builder})
    : assert(child != null || builder != null);

  final T id;
  final Widget? child;
  final ScrollSpyItemBuilder<T>? builder;

  @override
  State<ScrollSpyItem<T>> createState() => _ScrollSpyItemState<T>();
}

class _ScrollSpyItemState<T> extends State<ScrollSpyItem<T>> {
  _ScrollSpyScopeState<T>? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextScope = ScrollSpyScope._maybeOf<T>(context);
    if (_scope != nextScope) {
      _scope?._unregister(widget.id, context as Element);
      _scope = nextScope;
      _scope?._register(widget.id, context as Element);
    }
  }

  @override
  void didUpdateWidget(covariant ScrollSpyItem<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _scope?._unregister(oldWidget.id, context as Element);
      _scope?._register(widget.id, context as Element);
    }
  }

  @override
  void deactivate() {
    _scope?._unregister(widget.id, context as Element);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _scope = ScrollSpyScope._maybeOf<T>(context);
    _scope?._register(widget.id, context as Element);
  }

  @override
  Widget build(BuildContext context) {
    final builder = widget.builder;
    if (builder == null || _scope == null) {
      return widget.child ?? const SizedBox.shrink();
    }
    return ValueListenableBuilder<ScrollSpyItemFocus<T>>(
      valueListenable: _scope!.widget.controller.itemFocusOf(widget.id),
      builder: (context, focus, child) => builder(context, focus, child),
      child: widget.child,
    );
  }
}

/// Convenience widget combining [ScrollSpyScope] with a [ListView].
class ScrollSpyListView<T> extends StatelessWidget {
  const ScrollSpyListView.builder({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    this.scrollController,
    this.padding,
    this.region = const ScrollSpyRegion.readingPosition(),
    this.policy = const ScrollSpyPolicy.readingPosition(),
    this.stability = const ScrollSpyStability(),
    this.updatePolicy = ScrollSpyUpdatePolicy.perFrame,
    this.onPrimaryChanged,
  });

  final ScrollSpyController<T> controller;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? scrollController;
  final EdgeInsetsGeometry? padding;
  final ScrollSpyRegion region;
  final ScrollSpyPolicy policy;
  final ScrollSpyStability stability;
  final ScrollSpyUpdatePolicy updatePolicy;
  final ValueChanged<T?>? onPrimaryChanged;

  @override
  Widget build(BuildContext context) {
    return ScrollSpyScope<T>(
      controller: controller,
      region: region,
      policy: policy,
      stability: stability,
      updatePolicy: updatePolicy,
      onPrimaryChanged: onPrimaryChanged,
      child: ListView.builder(
        controller: scrollController,
        padding: padding,
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      ),
    );
  }
}
