import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_primitives.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_tab_metrics.dart';
import 'package:zephyr/page/comic_read/widgets/settings/sections/image_tuning_section.dart';
import 'package:zephyr/page/comic_read/widgets/settings/sections/super_resolution_section.dart';
import 'package:zephyr/page/comic_read/widgets/settings/sections/translate_section.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/icons/icons.dart';

part 'reader_settings_gesture_tab.dart';
part 'reader_settings_picture_tab.dart';
part 'reader_settings_read_tab.dart';
part 'reader_settings_screen_tab.dart';
part 'reader_settings_translate_tab.dart';
part 'parts/reader_settings_media_format_part.dart';
part 'parts/reader_settings_outside_tap_part.dart';
part 'parts/reader_settings_tab_bar_part.dart';
part 'parts/reader_settings_video_part.dart';

Future<void> showReaderSettingsSheet(
  BuildContext context, {
  ValueChanged<int>? changePageIndex,
  ValueChanged<bool>? onLandscapeChanged,
  String source = '',
  String comicId = '',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierLabel: t.common.close,
    isDismissible: true,
    enableDrag: true,
    builder: (context) {
      return _ReaderSettingsSheetEscScope(
        child: _ReaderSettingsSheet(
          changePageIndex: changePageIndex ?? (_) {},
          onLandscapeChanged: onLandscapeChanged,
          source: source,
          comicId: comicId,
        ),
      );
    },
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
    final maxHeight = mediaSize.height * 0.7;
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
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Stack(
            children: [
              // 「点空白收回」在这里是**两棒接力**，分工的边界就是这条路由所在
              // Overlay 的矩形（工作台里 = 阅读器那条泳道，普通页面里 = 整个窗口）：
              // - 框体自身占满 Overlay，遮罩点不透，所以 Overlay 内、卡片外这一圈
              //   由下面这层透明点击层接手；
              // - Overlay **之外**的那一片（别的泳道、工作台顶栏、空画布）根本不在
              //   这条路由的命中范围内，由 [_ReaderSettingsOutsideTapScope] 用全局
              //   指针路由接手。
              // 两边必须按这条边界切死：同一一下被接两次就是 pop 两次，
              // 第二次退掉的不是面板，而是底下的阅读器页。
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const SizedBox.expand(),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: SizedBox(
                    height: maxHeight,
                    child: _ReaderSettingsCard(args: args),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderSettingsCard extends StatelessWidget {
  final _ReaderSettingsArgs args;

  const _ReaderSettingsCard({required this.args});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;
    final tabs = _visibleReaderSettingsTabs(
      translateAvailable: ocrSupportedHere,
    );

    return Material(
      color: colorScheme.surfaceContainerLow,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: DefaultTabController(
        length: tabs.length,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ReaderSettingsHeader(tabs: tabs),
            Expanded(
              child: TabBarView(
                children: [for (final tab in tabs) tab.body(args)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTabContent extends StatelessWidget {
  final Widget child;

  const _SettingsTabContent({required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: child,
    );
  }
}
