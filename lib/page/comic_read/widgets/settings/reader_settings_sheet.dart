import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_primitives.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_disclosure.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_3_expressive/components/bottom_sheets/controllers/m3e_bottom_sheet_scroll_controller.dart'
    show M3EBottomSheetDragTarget;
import 'package:zephyr/widgets/spring_lens/spring_lens_value.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/navigation/navigation_sidebar.dart';
import 'package:zephyr/widgets/navigation/navigation_dock.dart';
import 'package:zephyr/widgets/navigation/navigation_layout.dart';
import 'package:zephyr/widgets/motion/retained_panel_switcher.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/widgets/expressive/expressive_icon_button.dart';
import 'package:zephyr/page/comic_read/widgets/settings/sections/image_tuning_section.dart';
import 'package:zephyr/page/comic_read/widgets/settings/sections/super_resolution_section.dart';
import 'package:zephyr/page/comic_read/widgets/settings/sections/translate_section.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:zephyr/main.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/comic_read_preference_cubit.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/video/model/video_media_kind.dart';
import 'package:zephyr/video/view/active_video_scope.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/util/debouncer.dart';
import 'package:zephyr/util/reader/reader_top_bar_style.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_bar.dart';
import 'package:zephyr/icons/icons.dart';

part 'reader_settings_gesture_tab.dart';
part 'reader_settings_picture_tab.dart';
part 'reader_settings_read_tab.dart';
part 'reader_settings_read_extras.dart';
part 'reader_settings_info_tab.dart';
part 'reader_settings_per_comic_tab.dart';
part 'reader_settings_hover_section.dart';
part 'reader_settings_target.dart';
part 'reader_settings_screen_tab.dart';
part 'reader_settings_translate_tab.dart';
part 'parts/reader_settings_media_format_part.dart';
part 'parts/reader_settings_outside_tap_part.dart';
part 'parts/reader_settings_tab_bar_part.dart';
part 'parts/reader_settings_extent_part.dart';
part 'parts/reader_settings_video_part.dart';

Future<void> showReaderSettingsSheet(
  BuildContext context, {
  ValueChanged<int>? changePageIndex,
  ValueChanged<bool>? onLandscapeChanged,
  String source = '',
  String comicId = '',
}) {
  final navigator = Navigator.of(context);
  final renderObject = navigator.context.findRenderObject();
  final origin = PopupPointerOrigin.last;
  final size = MediaQuery.sizeOf(context);
  final anchor = origin != null && renderObject is RenderBox
      ? renderObject.globalToLocal(origin)
      : Offset(size.width / 2, size.height - 48);
  final setting = context.read<GlobalSettingCubit>().state;
  return navigator.push<void>(
    CommonPopupRoute<void>(
      anchorOf: () => Rect.fromCenter(center: anchor, width: 48, height: 48),
      placement: PopupPlacement.bottomCenter,
      barrierLabel: t.common.close,
      animate:
          !setting.readSetting.noAnimation &&
          !setting.eInkSetting.enabled &&
          !MediaQuery.disableAnimationsOf(context),
      builder: (context) => _ReaderSettingsSheetEscScope(
        child: _PerComicScope(
          perComic: false,
          child: _ReaderSettingsSheet(
            changePageIndex: changePageIndex ?? (_) {},
            onLandscapeChanged: onLandscapeChanged,
            source: source,
            comicId: comicId,
          ),
        ),
      ),
    ),
  );
}

/// 给面板一个自己的 Esc 出口：桌面端按 Esc 即可关闭面板。
///
/// 这个处理必须在面板子树内**先行消费**掉 Esc —— 否则按键会沿焦点树
/// 冒泡到工作台的 `CallbackShortcuts`（见 `breeze_workspace_page`），
/// 按一下退出的不是面板、而是整个工作台。
class _ReaderSettingsSheetEscScope extends StatefulWidget {
  final Widget child;

  const _ReaderSettingsSheetEscScope({required this.child});

  @override
  State<_ReaderSettingsSheetEscScope> createState() =>
      _ReaderSettingsSheetEscScopeState();
}

class _ReaderSettingsSheetEscScopeState
    extends State<_ReaderSettingsSheetEscScope> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'reader_settings_sheet');
  bool _closing = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (!_closing) {
      _closing = true;
      // 与 main.dart 的全局 Esc 处理同款顺序：先让焦点失焦，pop 推迟到
      // 下一帧，让失焦引发的重建在当前帧完成。
      FocusManager.instance.primaryFocus?.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: widget.child,
    );
  }
}

class _ReaderSettingsSheet extends StatelessWidget {
  final ValueChanged<int> changePageIndex;
  final ValueChanged<bool>? onLandscapeChanged;
  final String source;
  final String comicId;

  const _ReaderSettingsSheet({
    required this.changePageIndex,
    this.onLandscapeChanged,
    this.source = '',
    this.comicId = '',
  });

  @override
  Widget build(BuildContext context) {
    final mediaSize = MediaQuery.sizeOf(context);
    final isAndroidPhone =
        !kIsWeb && Platform.isAndroid && mediaSize.shortestSide < 600;
    final args = _ReaderSettingsArgs(
      changePageIndex: changePageIndex,
      isAndroidPhone: isAndroidPhone,
      onLandscapeChanged: onLandscapeChanged,
      source: source,
      comicId: comicId,
    );

    return _ReaderSettingsOutsideTapScope(
      child: _ReaderSettingsCard(args: args),
    );
  }
}

class _ReaderSettingsCard extends StatefulWidget {
  final _ReaderSettingsArgs args;

  const _ReaderSettingsCard({required this.args});

  @override
  State<_ReaderSettingsCard> createState() => _ReaderSettingsCardState();
}

class _ReaderSettingsCardState extends State<_ReaderSettingsCard>
    with SingleTickerProviderStateMixin {
  late final _extent = _ReaderSettingsExtent(this);
  final _panelsKey = GlobalKey(debugLabel: 'reader-settings-retained-panels');

  @override
  void dispose() {
    _extent.dispose();
    super.dispose();
  }

  bool _showDescriptions = false;
  bool _sidebarExpanded = true;
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final tabs = _visibleReaderSettingsTabs(
      translateAvailable: ocrSupportedHere,
      perComicAvailable: widget.args.perComicAvailable,
    );
    final setting = context.watch<GlobalSettingCubit>().state;
    final animate =
        !setting.readSetting.noAnimation &&
        !setting.eInkSetting.enabled &&
        !MediaQuery.disableAnimationsOf(context);
    final media = MediaQuery.of(context).copyWith(disableAnimations: !animate);
    return MediaQuery(
      data: media,
      child: SettingsPresentationScope(
        showDescriptions: _showDescriptions,
        animate: animate,
        child: M3ETheme(
          data: M3EThemeData.fromMaterial(theme),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 留足内容宽度才切侧栏；沿用全应用的侧栏 / Dock 判据。
              final wide =
                  resolveNavigationLayout(
                    sidebarCapable: true,
                    width: constraints.maxWidth,
                    autoSwitchOnNarrow: true,
                    narrowWidth: 720,
                  ) ==
                  NavigationLayout.sidebar;
              _extent.maxHeight = constraints.maxHeight;
              _extent.animate = animate;
              return AnimatedBuilder(
                animation: _extent.motion,
                builder: (context, _) {
                  final fraction = constraints.maxHeight < 480
                      ? 1.0
                      : _extent.fraction;
                  final fullProgress = ((fraction - .9) / .1).clamp(0.0, 1.0);
                  final cardWidth = constraints.maxWidth.clamp(0.0, 1120.0);
                  return _ReaderSettingsExtentScope(
                    extent: _extent,
                    child: SizedBox(
                      key: const ValueKey('reader-settings-panel'),
                      width:
                          cardWidth +
                          (constraints.maxWidth - cardWidth) * fullProgress,
                      height: constraints.maxHeight * fraction,
                      child: Material(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(
                          28 * (1 - fullProgress),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: SafeArea(
                          top: fraction > .95,
                          child: Column(
                            children: [
                              _ReaderSettingsHeader(
                                expanded: fraction > .97,
                                onToggleExpanded: () =>
                                    _extent.snapTo(fraction > .97 ? .72 : 1),
                                onDragUpdate: _extent.dragBy,
                                onDragEnd: _extent.settle,
                                showDescriptions: _showDescriptions,
                                onToggleDescriptions: () => setState(
                                  () => _showDescriptions = !_showDescriptions,
                                ),
                              ),
                              Expanded(
                                child: Row(
                                  children: [
                                    if (wide)
                                      NavigationSidebar(
                                        key: const ValueKey(
                                          'reader-settings-sidebar',
                                        ),
                                        destinations: [
                                          for (final tab in tabs)
                                            SidebarDestination(
                                              glyph: tab.icon,
                                              label: tab.label,
                                            ),
                                        ],
                                        selectedIndex: _selectedIndex,
                                        expanded: _sidebarExpanded,
                                        onSelected: (index) => setState(
                                          () => _selectedIndex = index,
                                        ),
                                        onToggle: () => setState(
                                          () => _sidebarExpanded =
                                              !_sidebarExpanded,
                                        ),
                                      ),
                                    Expanded(
                                      child: Column(
                                        children: [
                                          if (!wide)
                                            NavigationDock(
                                              key: const ValueKey(
                                                'reader-settings-dock',
                                              ),
                                              destinations: [
                                                for (final tab in tabs)
                                                  NavigationDockDestination(
                                                    glyph: tab.icon,
                                                    label: tab.label,
                                                  ),
                                              ],
                                              selectedIndex: _selectedIndex,
                                              onSelected: (index) => setState(
                                                () => _selectedIndex = index,
                                              ),
                                            ),
                                          Expanded(
                                            child: RetainedPanelSwitcher(
                                              key: _panelsKey,
                                              selectedId:
                                                  tabs[_selectedIndex].name,
                                              children: {
                                                for (final tab in tabs)
                                                  tab.name: tab.body(
                                                    widget.args,
                                                  ),
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SettingsTabContent extends StatefulWidget {
  final Widget child;

  const _SettingsTabContent({required this.child});

  @override
  State<_SettingsTabContent> createState() => _SettingsTabContentState();
}

class _SettingsTabContentState extends State<_SettingsTabContent> {
  _ReaderSettingsExtent? _extent;
  M3EBottomSheetScrollController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final extent = _ReaderSettingsExtentScope.of(context);
    if (identical(extent, _extent)) return;
    _controller?.dispose();
    _extent = extent;
    _controller = M3EBottomSheetScrollController(sheet: extent);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final extent = _extent!;
    final position = _controller!.position;
    final delta = event.scrollDelta.dy;
    // 鼠标滚轮和触控板也先扩面板；已滚进正文时仍交给原 ScrollPosition。
    if (!extent.canDrag ||
        position.pixels > position.minScrollExtent ||
        delta == 0 ||
        (delta > 0 && extent.isAtMax) ||
        (delta < 0 && extent.fraction <= .5)) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      extent.scrollBy(delta);
    });
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const ValueKey('reader-settings-content-scroll'),
    controller: _controller,
    physics: const ClampingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    ),
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: _onPointerSignal,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: widget.child,
        ),
      ),
    ),
  );
}
