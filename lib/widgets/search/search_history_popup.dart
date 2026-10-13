import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/search/search_history_panel.dart';

class SearchHistorySuggestions {
  const SearchHistorySuggestions({
    required this.queries,
    required this.onSelected,
    required this.onClear,
    this.highlighted = -1,
  });

  final List<String> queries;
  final ValueChanged<String> onSelected;
  final VoidCallback onClear;
  final int highlighted;
}

/// 只适配生命周期：定位、表面变形、进出场与减弱动画均交给统一弹层。
/// 官方 Autocomplete 会立即移除建议子树，路由仍保留完整的退出动画。
class SearchHistoryPopup {
  SearchHistoryPopup({required this.fieldKey, required this.onDismissed});

  final GlobalKey fieldKey;
  final VoidCallback onDismissed;
  _HistoryPopupSession? _session;

  Rect? _anchor(NavigatorState navigator, GlobalKey key) {
    final field = key.currentContext?.findRenderObject();
    final target = navigator.context.findRenderObject();
    if (field is! RenderBox ||
        !field.attached ||
        !field.hasSize ||
        target is! RenderBox) {
      return null;
    }
    return field.localToGlobal(Offset.zero, ancestor: target) & field.size;
  }

  void show(
    BuildContext context,
    SearchHistorySuggestions suggestions,
    Object owner, {
    GlobalKey? sourceKey,
  }) {
    final current = _session;
    if (current != null) {
      if (current.route.isCurrent) {
        current.owner = owner;
        current.sourceKey = sourceKey ?? fieldKey;
        current.data.value = suggestions;
      }
      return;
    }
    final navigator = Navigator.of(context, rootNavigator: true);
    final anchorKey = sourceKey ?? fieldKey;
    final anchor = _anchor(navigator, anchorKey);
    if (anchor == null) return;
    final media = MediaQuery.of(navigator.context);
    final availableWidth = math.max(0.0, media.size.width - 32.0);
    final panelWidth = math.min(
      420.0,
      math.min(availableWidth, math.max(280.0, anchor.width)),
    );
    final roomAbove = anchor.top - media.padding.top - 24;
    final roomBelow =
        media.size.height -
        math.max(media.padding.bottom, media.viewInsets.bottom) -
        anchor.bottom -
        24;
    final height = math.min(
      440.0,
      math.max(96.0, math.max(roomAbove, roomBelow)),
    );
    final data = ValueNotifier(suggestions);
    final themes = InheritedTheme.capture(from: context, to: navigator.context);
    late final _HistoryPopupSession session;
    final route = _HistoryPopupRoute(
      onCovered: () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (identical(_session, session)) dismiss();
        });
      },
      modal: false,
      anchorOf: () => _anchor(navigator, session.sourceKey) ?? anchor,
      placement: PopupPlacement.belowPoint,
      avoid: anchor,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      builder: (context) => themes.wrap(
        SizedBox(
          width: panelWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height),
            child: ValueListenableBuilder<SearchHistorySuggestions>(
              valueListenable: data,
              builder: (_, value, _) => SearchHistoryPanel(
                queries: value.queries,
                highlighted: value.highlighted,
                onSelected: (query) {
                  dismiss(owner: session.owner);
                  value.onSelected(query);
                },
                onClear: () {
                  dismiss(owner: session.owner);
                  value.onClear();
                },
              ),
            ),
          ),
        ),
      ),
    );
    session = _HistoryPopupSession(route, data, owner, sourceKey ?? fieldKey);
    _session = session;
    unawaited(
      navigator.push(route).then((_) {
        if (identical(_session, session)) {
          _session = null;
          onDismissed();
        }
      }),
    );
    // push 的 Future 在退出开始时完成；数据要等路由动画结束才可释放。
    unawaited(route.completed.then((_) => data.dispose()));
  }

  void dismiss({Object? owner}) {
    final session = _session;
    if (session == null ||
        (owner != null && !identical(owner, session.owner))) {
      return;
    }
    _session = null;
    void close() {
      final route = session.route;
      if (!route.isActive) return;
      if (route.isCurrent) {
        route.navigator?.pop();
      } else {
        // 页面已切换时移除本组件自己的路由，不能 pop 新页面。
        route.navigator?.removeRoute(route);
      }
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => close());
    } else {
      close();
    }
  }
}

/// 搜索历史随页面切换关闭，仍由统一路由负责表面与动画。
class _HistoryPopupRoute extends CommonPopupRoute<void> {
  _HistoryPopupRoute({
    required this.onCovered,
    required super.builder,
    required super.anchorOf,
    required super.barrierLabel,
    super.modal,
    super.placement,
    super.avoid,
  });

  final VoidCallback onCovered;

  @override
  void didChangeNext(Route<dynamic>? nextRoute) {
    super.didChangeNext(nextRoute);
    if (nextRoute != null) onCovered();
  }
}

class _HistoryPopupSession {
  _HistoryPopupSession(this.route, this.data, this.owner, this.sourceKey);
  final CommonPopupRoute<void> route;
  final ValueNotifier<SearchHistorySuggestions> data;
  Object owner;
  GlobalKey sourceKey;
}

/// 官方建议子树仅转发选项和键盘高亮，不创建另一套弹层或选择逻辑。
class SearchHistoryOptionsBridge extends StatefulWidget {
  const SearchHistoryOptionsBridge({
    super.key,
    required this.suggestions,
    required this.onShow,
    required this.onHide,
  });

  final SearchHistorySuggestions suggestions;
  final void Function(SearchHistorySuggestions, Object) onShow;
  final ValueChanged<Object> onHide;

  @override
  State<SearchHistoryOptionsBridge> createState() =>
      _SearchHistoryOptionsBridgeState();
}

class _SearchHistoryOptionsBridgeState
    extends State<SearchHistoryOptionsBridge> {
  final _owner = Object();
  bool _scheduled = false;
  int _highlighted = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _highlighted = AutocompleteHighlightedOption.of(context);
    _publish();
  }

  @override
  void didUpdateWidget(SearchHistoryOptionsBridge oldWidget) {
    super.didUpdateWidget(oldWidget);
    _publish();
  }

  void _publish() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final value = widget.suggestions;
      widget.onShow(
        SearchHistorySuggestions(
          queries: value.queries,
          highlighted: _highlighted,
          onSelected: value.onSelected,
          onClear: value.onClear,
        ),
        _owner,
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  @override
  void dispose() {
    widget.onHide(_owner);
    super.dispose();
  }
}
