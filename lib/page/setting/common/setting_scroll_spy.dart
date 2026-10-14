import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scroll_spy/scroll_spy.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/setting/common/setting_detail_scope.dart';
import 'package:zephyr/page/setting/common/setting_entry_list.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';

/// 请求跳转到某个设置页内的特定分组（或具体设置项锚点）。
class SettingSectionJumpTarget {
  const SettingSectionJumpTarget({
    required this.sectionId,
    this.pageId,
    this.entryId,
    this.serial = 0,
  });

  final String? pageId;
  final String sectionId;
  final String? entryId;
  final int serial;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingSectionJumpTarget &&
          other.pageId == pageId &&
          other.sectionId == sectionId &&
          other.entryId == entryId &&
          other.serial == serial;

  @override
  int get hashCode => Object.hash(pageId, sectionId, entryId, serial);
}

int _jumpSerial = 0;

/// 全局分组跳转信箱：供侧栏子树点击、搜索结果直达、移动端跨路由跳转认领。
final ValueNotifier<SettingSectionJumpTarget?> settingSectionJumpRequest =
    ValueNotifier<SettingSectionJumpTarget?>(null);

void requestSettingSectionJump({
  required String sectionId,
  String? pageId,
  String? entryId,
}) {
  _jumpSerial++;
  settingSectionJumpRequest.value = SettingSectionJumpTarget(
    pageId: pageId,
    sectionId: sectionId,
    entryId: entryId,
    serial: _jumpSerial,
  );
}

/// 页内 Scroll Spy 宿主控制器：封装 `scroll_spy` 包的 [ScrollSpyController]，
/// 管理分组自动发现、主分组稳定检测、点击跳转锁定与目标卡片脉冲高亮。
class SettingPageScrollSpyController extends ChangeNotifier {
  SettingPageScrollSpyController({
    this.pageId,
    List<SettingSectionSpec> declaredSections = const <SettingSectionSpec>[],
    this.bridge,
  }) : _declaredSections = declaredSections {
    _sections.value = List<SettingSectionSpec>.unmodifiable(declaredSections);
    if (declaredSections.isNotEmpty) {
      _activeSectionId.value = declaredSections.first.id;
    }
    spyController.primaryId.addListener(_onSpyPrimaryChanged);
    spyController.snapshot.addListener(_onSpySnapshotChanged);
  }

  final String? pageId;
  final SettingDetailBridge? bridge;
  List<SettingSectionSpec> _declaredSections;

  final ScrollSpyController<String> spyController =
      ScrollSpyController<String>();

  final ValueNotifier<List<SettingSectionSpec>> _sections =
      ValueNotifier<List<SettingSectionSpec>>(const []);
  final ValueNotifier<String?> _activeSectionId = ValueNotifier<String?>(null);
  final ValueNotifier<String?> _highlightedSectionId = ValueNotifier<String?>(
    null,
  );
  final ValueNotifier<double> _scrollProgress = ValueNotifier<double>(0.0);

  final Map<String, SettingSectionSpec> _discoveredSpecs = {};
  Timer? _highlightTimer;
  bool _syncScheduled = false;

  ValueListenable<List<SettingSectionSpec>> get sections => _sections;
  ValueListenable<String?> get activeSectionId => _activeSectionId;
  ValueListenable<String?> get highlightedSectionId => _highlightedSectionId;
  ValueListenable<double> get scrollProgress => _scrollProgress;

  List<SettingSectionSpec> get currentSections => _sections.value;
  String? get currentActiveSectionId => _activeSectionId.value;

  void updateDeclaredSections(List<SettingSectionSpec> next) {
    if (listEquals(_declaredSections, next)) return;
    _declaredSections = next;
    _scheduleSectionSync();
  }

  /// 将分组卡片的 `sectionId` 或 `title` 解析为稳定的分组 ID，并登记到页内目录。
  String? resolveAndRegisterGroup({
    String? explicitId,
    String? title,
    Glyph? icon,
  }) {
    final cleanTitle = title?.trim() ?? '';
    if (explicitId != null && explicitId.isNotEmpty) {
      final declared = _declaredSections
          .where((s) => s.id == explicitId)
          .firstOrNull;
      _discoveredSpecs[explicitId] =
          declared ??
          SettingSectionSpec(
            id: explicitId,
            title: cleanTitle.isNotEmpty ? cleanTitle : explicitId,
            icon: icon,
          );
      _scheduleSectionSync();
      return explicitId;
    }

    if (cleanTitle.isEmpty) return null;

    // 优先匹配预设分组（按标题一致映射回稳定语义 ID，如 'appearance.theme'）
    for (final spec in _declaredSections) {
      if (spec.title == cleanTitle || spec.id == cleanTitle) {
        _discoveredSpecs[spec.id] = spec.icon != null || icon == null
            ? spec
            : SettingSectionSpec(
                id: spec.id,
                title: spec.title,
                subtitle: spec.subtitle,
                keywords: spec.keywords,
                icon: icon,
              );
        _scheduleSectionSync();
        return spec.id;
      }
    }

    final fallbackId = 'section:$cleanTitle';
    _discoveredSpecs[fallbackId] = SettingSectionSpec(
      id: fallbackId,
      title: cleanTitle,
      icon: icon,
    );
    _scheduleSectionSync();
    return fallbackId;
  }

  void _onSpyPrimaryChanged() {
    final primary = spyController.currentPrimaryId;
    if (primary == null) return;
    // 只接受属于章节目录的 ID
    final knownIds = _sections.value.map((s) => s.id).toSet();
    if (knownIds.isEmpty || knownIds.contains(primary)) {
      _setActiveSection(primary);
    }
  }

  void _onSpySnapshotChanged() {
    final snap = spyController.snapshot.value;
    if ((_scrollProgress.value - snap.scrollProgress).abs() > 0.005) {
      _scrollProgress.value = snap.scrollProgress;
    }
    _scheduleSectionSync();
  }

  void _setActiveSection(String? id) {
    if (_activeSectionId.value == id) return;
    _activeSectionId.value = id;
    if (pageId != null && bridge != null) {
      bridge!.updateActiveSection(pageId!, id);
    }
    notifyListeners();
  }

  void _scheduleSectionSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      _rebuildSectionList();
    });
  }

  void _rebuildSectionList() {
    final orderedMounted = spyController.orderedIds;
    final merged = <SettingSectionSpec>[];
    final seen = <String>{};

    if (_declaredSections.isNotEmpty) {
      for (final spec in _declaredSections) {
        if (seen.add(spec.id)) {
          merged.add(_discoveredSpecs[spec.id] ?? spec);
        }
      }
      for (final id in orderedMounted) {
        final dynamicSpec = _discoveredSpecs[id];
        if (dynamicSpec != null && seen.add(id)) {
          merged.add(dynamicSpec);
        }
      }
    } else {
      for (final id in orderedMounted) {
        final spec = _discoveredSpecs[id];
        if (spec != null && seen.add(id)) {
          merged.add(spec);
        }
      }
      for (final entry in _discoveredSpecs.entries) {
        if (seen.add(entry.key)) {
          merged.add(entry.value);
        }
      }
    }

    if (!listEquals(_sections.value, merged)) {
      _sections.value = List<SettingSectionSpec>.unmodifiable(merged);
      if (pageId != null && bridge != null) {
        bridge!.updateSections(pageId!, _sections.value);
      }
    }

    final currentActive = _activeSectionId.value;
    final primary = spyController.currentPrimaryId;
    if (primary != null && seen.contains(primary)) {
      _setActiveSection(primary);
    } else if ((currentActive == null || !seen.contains(currentActive)) &&
        merged.isNotEmpty) {
      _setActiveSection(merged.first.id);
    }
  }

  bool canClaimJump(SettingSectionJumpTarget target) {
    if (target.pageId != null && pageId != null && target.pageId != pageId) {
      return false;
    }
    if (target.pageId != null && pageId == target.pageId) {
      return true;
    }
    if (_sections.value.any((s) => s.id == target.sectionId)) {
      return true;
    }
    if (_discoveredSpecs.containsKey(target.sectionId)) {
      return true;
    }
    if (spyController.contextOf(target.sectionId) != null) {
      return true;
    }
    return false;
  }

  Future<void> scrollToSection(
    String sectionId, {
    String? entryId,
    BuildContext? fallbackContext,
  }) async {
    spyController.lockPrimary(
      sectionId,
      duration: const Duration(milliseconds: 520),
    );
    _setActiveSection(sectionId);
    _triggerPulseHighlight(sectionId);

    // 若目标同时也是 SettingEntryList 里的行 ID，顺带触发行定位请求
    if (entryId != null && entryId.isNotEmpty) {
      settingFocusRequest.value = entryId;
    } else if (sectionId.contains('.')) {
      settingFocusRequest.value = sectionId;
    }

    var targetCtx = spyController.contextOf(sectionId);
    if (targetCtx == null && entryId != null) {
      targetCtx = spyController.contextOf(entryId);
    }

    // 若分组尚未挂载，先按下标估算滚动将它挂载出来
    if (targetCtx == null &&
        fallbackContext != null &&
        fallbackContext.mounted) {
      final idx = _sections.value.indexWhere((s) => s.id == sectionId);
      if (idx > 0) {
        final scrollable = Scrollable.maybeOf(fallbackContext);
        if (scrollable != null && scrollable.position.hasContentDimensions) {
          final pos = scrollable.position;
          final fraction = idx / math.max(1, _sections.value.length - 1);
          final targetPixels = (pos.maxScrollExtent * fraction).clamp(
            pos.minScrollExtent,
            pos.maxScrollExtent,
          );
          final disableAnim =
              eInkInstantRoutes ||
              MediaQuery.disableAnimationsOf(fallbackContext);
          if (disableAnim) {
            pos.jumpTo(targetPixels);
          } else {
            await pos.animateTo(
              targetPixels,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 16));
          targetCtx = spyController.contextOf(sectionId);
        }
      }
    }

    if (targetCtx != null && targetCtx.mounted) {
      final disableAnim =
          eInkInstantRoutes || MediaQuery.disableAnimationsOf(targetCtx);
      await Scrollable.ensureVisible(
        targetCtx,
        duration: disableAnim
            ? Duration.zero
            : const Duration(milliseconds: 320),
        curve: ExpressiveMotion.spatialCurve,
        alignment: 0.06,
      );
      spyController.recompute();
    }
  }

  void _triggerPulseHighlight(String sectionId) {
    _highlightTimer?.cancel();
    _highlightedSectionId.value = sectionId;
    _highlightTimer = Timer(const Duration(milliseconds: 950), () {
      if (_highlightedSectionId.value == sectionId) {
        _highlightedSectionId.value = null;
      }
    });
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    spyController.primaryId.removeListener(_onSpyPrimaryChanged);
    spyController.snapshot.removeListener(_onSpySnapshotChanged);
    spyController.dispose();
    _sections.dispose();
    _activeSectionId.dispose();
    _highlightedSectionId.dispose();
    _scrollProgress.dispose();
    super.dispose();
  }
}

/// 在 [SettingPageShell] 内部挂载的 Scroll Spy 作用域。
class SettingScrollSpyScope extends StatefulWidget {
  const SettingScrollSpyScope({
    super.key,
    required this.child,
    this.pageId,
    this.declaredSections = const <SettingSectionSpec>[],
    this.leadingInsetPx = 20.0,
  });

  final Widget child;
  final String? pageId;
  final List<SettingSectionSpec> declaredSections;
  final double leadingInsetPx;

  static SettingPageScrollSpyController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_SettingScrollSpyInherited>()
        ?.controller;
  }

  @override
  State<SettingScrollSpyScope> createState() => _SettingScrollSpyScopeState();
}

class _SettingScrollSpyScopeState extends State<SettingScrollSpyScope> {
  SettingPageScrollSpyController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final detailScope = SettingDetailScope.maybeOf(context);
    final effectivePageId = widget.pageId ?? detailScope?.pageId;
    final effectiveDeclared = widget.declaredSections.isNotEmpty
        ? widget.declaredSections
        : (detailScope?.declaredSections ?? const <SettingSectionSpec>[]);
    final bridge = detailScope?.bridge;

    if (_controller == null ||
        _controller!.pageId != effectivePageId ||
        _controller!.bridge != bridge) {
      _controller?.dispose();
      _controller = SettingPageScrollSpyController(
        pageId: effectivePageId,
        declaredSections: effectiveDeclared,
        bridge: bridge,
      );
      if (effectivePageId != null &&
          bridge != null &&
          effectiveDeclared.isNotEmpty) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          bridge.updateSections(effectivePageId, effectiveDeclared);
          bridge.updateActiveSection(
            effectivePageId,
            _controller?.currentActiveSectionId,
          );
        });
      }
    } else {
      _controller!.updateDeclaredSections(effectiveDeclared);
    }
  }

  @override
  void initState() {
    super.initState();
    settingSectionJumpRequest.addListener(_maybeClaimJump);
    SchedulerBinding.instance.addPostFrameCallback((_) => _maybeClaimJump());
  }

  @override
  void dispose() {
    settingSectionJumpRequest.removeListener(_maybeClaimJump);
    _controller?.dispose();
    super.dispose();
  }

  void _maybeClaimJump() {
    final target = settingSectionJumpRequest.value;
    final controller = _controller;
    if (target == null || controller == null || !mounted) return;
    if (!controller.canClaimJump(target)) return;

    settingSectionJumpRequest.value = null;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        controller.scrollToSection(
          target.sectionId,
          entryId: target.entryId,
          fallbackContext: context,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    return _SettingScrollSpyInherited(
      controller: controller,
      child: ScrollSpyScope<String>(
        controller: controller.spyController,
        region: ScrollSpyRegion.readingPosition(
          anchor: ScrollSpyAnchor.pixels(widget.leadingInsetPx),
          extentPx: 180.0,
        ),
        policy: const ScrollSpyPolicy.readingPosition(pinBoundaryEdges: true),
        stability: const ScrollSpyStability(
          hysteresisPx: 20.0,
          minPrimaryDuration: Duration(milliseconds: 90),
        ),
        child: widget.child,
      ),
    );
  }
}

class _SettingScrollSpyInherited extends InheritedWidget {
  const _SettingScrollSpyInherited({
    required this.controller,
    required super.child,
  });

  final SettingPageScrollSpyController controller;

  @override
  bool updateShouldNotify(_SettingScrollSpyInherited oldWidget) =>
      oldWidget.controller != controller;
}

/// 移动端与长设置页顶部的 MD3 Expressive「吸顶可展开目录胶囊（Sticky Outline Pill）」。
///
/// - 收起态：常驻展示当前 Scroll Spy 命中的分组序号与标题（如 `1/4 · 主题`）；
/// - 展开态：通过 [OverlayPortal] + [ExpressiveReveal] 弹出圆角容器目录，点击任意分组
///   立即平滑滚动至目标位置并触发脉冲高亮。
/// - 仅在当前页分组数 `>= 2` 时渲染，绝不给单分组短页增加多余高度，且不使用 `ListTile` / `Divider`。
class SettingStickyOutlineBar extends StatefulWidget {
  const SettingStickyOutlineBar({
    super.key,
    required this.controller,
    this.maxWidth = 768,
    this.compact = false,
  });

  final SettingPageScrollSpyController controller;
  final double maxWidth;
  final bool compact;

  @override
  State<SettingStickyOutlineBar> createState() =>
      _SettingStickyOutlineBarState();
}

class _SettingStickyOutlineBarState extends State<SettingStickyOutlineBar> {
  final OverlayPortalController _portalController = OverlayPortalController();
  final LayerLink _layerLink = LayerLink();
  bool _expanded = false;
  bool _pressed = false;
  double _triggerWidth = 320.0;

  void _toggle() {
    HapticFeedback.selectionClick();
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      _triggerWidth = box.size.width;
    }
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _portalController.show();
      } else {
        _portalController.hide();
      }
    });
  }

  void _close() {
    if (!_expanded) return;
    setState(() {
      _expanded = false;
      _portalController.hide();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<SettingSectionSpec>>(
      valueListenable: widget.controller.sections,
      builder: (context, sections, _) {
        if (sections.length < 2) {
          return const SizedBox.shrink();
        }
        return ValueListenableBuilder<String?>(
          valueListenable: widget.controller.activeSectionId,
          builder: (context, activeId, _) {
            final theme = Theme.of(context);
            final scheme = theme.colorScheme;
            final activeIndex = math.max(
              0,
              sections.indexWhere((s) => s.id == activeId),
            );
            final activeSpec = sections[activeIndex];
            final animate =
                !eInkInstantRoutes && !MediaQuery.disableAnimationsOf(context);
            // 胶囊在按压与展开时按 MD3 Expressive 规范发生连续圆角形变（corner-full → 18px）
            final radius = BorderRadius.circular(
              _expanded
                  ? 18
                  : _pressed
                  ? 16
                  : 999,
            );
            final rawScale = MediaQuery.textScalerOf(context).scale(16) / 16;
            final pillMediaQuery = MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(rawScale.clamp(1.0, 1.15)),
            );

            final pill = MediaQuery(
              data: pillMediaQuery,
              child: CompositedTransformTarget(
                link: _layerLink,
                child: OverlayPortal(
                  controller: _portalController,
                  overlayChildBuilder: (overlayContext) => _buildOverlayMenu(
                    overlayContext,
                    sections: sections,
                    activeId: activeSpec.id,
                  ),
                  child: Semantics(
                    button: true,
                    expanded: _expanded,
                    label:
                        '${activeSpec.title} (${activeIndex + 1}/${sections.length})',
                    child: ElasticPress(
                      enabled: animate,
                      child: AnimatedContainer(
                        key: const ValueKey('setting-sticky-outline-pill'),
                        duration: ExpressiveMotion.duration(
                          context,
                          ExpressiveMotion.effectDuration,
                        ),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          color: _expanded
                              ? scheme.secondaryContainer
                              : scheme.surfaceContainerHigh,
                          borderRadius: radius,
                          border: Border.all(
                            color: _expanded
                                ? scheme.primary.withValues(alpha: 0.4)
                                : scheme.outlineVariant.withValues(alpha: 0.35),
                            width: 1,
                          ),
                        ),
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            borderRadius: radius,
                            onHighlightChanged: (v) {
                              if (_pressed != v) setState(() => _pressed = v);
                            },
                            onTap: _toggle,
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: widget.compact ? 10 : 14,
                                vertical: widget.compact ? 5 : 7,
                              ),
                              child: Row(
                                mainAxisSize: widget.compact
                                    ? MainAxisSize.min
                                    : MainAxisSize.max,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: ShapeDecoration(
                                      color: _expanded
                                          ? scheme.primary
                                          : scheme.primaryContainer,
                                      shape: const StadiumBorder(),
                                    ),
                                    child: Text(
                                      '${activeIndex + 1}/${sections.length}',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: _expanded
                                                ? scheme.onPrimary
                                                : scheme.onPrimaryContainer,
                                            fontWeight: FontWeight.w700,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (activeSpec.icon != null) ...[
                                    GlyphIcon(
                                      activeSpec.icon!,
                                      size: 15,
                                      color: _expanded
                                          ? scheme.onSecondaryContainer
                                          : scheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Flexible(
                                    fit: widget.compact
                                        ? FlexFit.loose
                                        : FlexFit.tight,
                                    child: AnimatedSwitcher(
                                      duration: ExpressiveMotion.duration(
                                        context,
                                        ExpressiveMotion.effectDuration,
                                      ),
                                      layoutBuilder: (current, previous) =>
                                          Stack(
                                            alignment: Alignment.centerLeft,
                                            children: [...previous, ?current],
                                          ),
                                      child: Text(
                                        '· ${activeSpec.title}',
                                        key: ValueKey<String>(activeSpec.id),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                              color: _expanded
                                                  ? scheme.onSecondaryContainer
                                                  : scheme.onSurface,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  AnimatedRotation(
                                    turns: _expanded ? 0.25 : 0.0,
                                    duration: ExpressiveMotion.duration(
                                      context,
                                      ExpressiveMotion.spatialDuration,
                                    ),
                                    curve: ExpressiveMotion.spatialCurve,
                                    child: GlyphIcon(
                                      AppGlyphs.chevronForward,
                                      size: 16,
                                      color: _expanded
                                          ? scheme.onSecondaryContainer
                                          : scheme.onSurfaceVariant,
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
                ),
              ),
            );

            if (widget.compact) {
              return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: pill,
              );
            }

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: widget.maxWidth),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                  child: pill,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildOverlayMenu(
    BuildContext overlayContext, {
    required List<SettingSectionSpec> sections,
    required String activeId,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final menuWidth = widget.compact
        ? math.min(280.0, MediaQuery.sizeOf(context).width - 32)
        : math.max(240.0, _triggerWidth);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: widget.compact
              ? Alignment.bottomRight
              : Alignment.bottomLeft,
          followerAnchor: widget.compact
              ? Alignment.topRight
              : Alignment.topLeft,
          offset: const Offset(0, 6),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: menuWidth,
              maxHeight: math.min(
                360.0,
                MediaQuery.sizeOf(context).height * 0.55,
              ),
            ),
            child: ExpressiveReveal(
              visible: _expanded,
              child: Container(
                key: const ValueKey('setting-sticky-outline-menu'),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: ActionBubbleRegion(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < sections.length; i++) ...[
                          if (i > 0) const SizedBox(height: 2),
                          _OutlineMenuItem(
                            index: i,
                            spec: sections[i],
                            selected: sections[i].id == activeId,
                            onTap: () {
                              final targetId = sections[i].id;
                              _close();
                              HapticFeedback.lightImpact();
                              unawaited(
                                widget.controller.scrollToSection(
                                  targetId,
                                  fallbackContext: context,
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OutlineMenuItem extends StatelessWidget {
  const _OutlineMenuItem({
    required this.index,
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final SettingSectionSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(selected ? 999 : 14);

    return ActionBubbleTarget(
      corner: 18,
      observeFocus: false,
      enabled: !eInkInstantRoutes,
      child: ElasticPress(
        enabled: !eInkInstantRoutes && !MediaQuery.disableAnimationsOf(context),
        child: AnimatedContainer(
          duration: ExpressiveMotion.duration(
            context,
            ExpressiveMotion.effectDuration,
          ),
          decoration: BoxDecoration(
            color: selected ? scheme.secondaryContainer : Colors.transparent,
            borderRadius: radius,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: ValueKey('outline-item:${spec.id}'),
              borderRadius: radius,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? scheme.primary
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(selected ? 11 : 7),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: selected
                              ? scheme.onPrimary
                              : scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (spec.icon != null) ...[
                      GlyphIcon(
                        spec.icon!,
                        size: 16,
                        color: selected
                            ? scheme.onSecondaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        spec.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: selected
                              ? scheme.onSecondaryContainer
                              : scheme.onSurface,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (selected)
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 独立设置页内用于吸顶展示 [SettingStickyOutlineBar] 的 Sliver。
class SettingStickyOutlineSliver extends StatelessWidget {
  const SettingStickyOutlineSliver({
    super.key,
    required this.maxWidth,
    required this.backgroundColor,
  });

  final double maxWidth;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final controller = SettingScrollSpyScope.maybeOf(context);
    if (controller == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return ValueListenableBuilder<List<SettingSectionSpec>>(
      valueListenable: controller.sections,
      builder: (context, sections, _) {
        if (sections.length < 2) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        return SliverPersistentHeader(
          pinned: true,
          delegate: _StickyOutlineHeaderDelegate(
            extent: 44.0,
            backgroundColor: backgroundColor,
            child: SettingStickyOutlineBar(
              controller: controller,
              maxWidth: maxWidth,
            ),
          ),
        );
      },
    );
  }
}

class _StickyOutlineHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _StickyOutlineHeaderDelegate({
    required this.extent,
    required this.backgroundColor,
    required this.child,
  });

  final double extent;
  final Color backgroundColor;
  final Widget child;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: backgroundColor,
      child: Align(alignment: Alignment.center, child: child),
    );
  }

  @override
  bool shouldRebuild(covariant _StickyOutlineHeaderDelegate oldDelegate) =>
      oldDelegate.extent != extent ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.child != child;
}
