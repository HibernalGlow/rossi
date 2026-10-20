import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/comic_list/cubit/plugin_paged_comic_list_cubit.dart';
import 'package:zephyr/page/comic_list/cubit/plugin_paged_comic_list_state.dart';
import 'package:zephyr/page/comic_list/service/plugin_list_navigation_controller.dart';
import 'package:zephyr/page/comic_list/service/plugin_list_position_store.dart';
import 'package:zephyr/widgets/library_viewport_anchor.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';

/// 页码按实际可见条目计算，持久化只发生在滚动结束/短暂停顿时。
class PluginListNavigationHost extends StatefulWidget {
  const PluginListNavigationHost({
    super.key,
    required this.navigation,
    required this.scope,
    required this.viewport,
    required this.scroll,
    required this.canvasKey,
    required this.child,
    this.positionStore,
  });
  final PluginListNavigationController navigation;
  final String scope;
  final LibraryViewportRegistry viewport;
  final ScrollController scroll;
  final GlobalKey<LibraryEditorialCanvasState>? canvasKey;
  final Widget child;
  final PluginListPositionStore? positionStore;

  @override
  State<PluginListNavigationHost> createState() =>
      _PluginListNavigationHostState();
}

class _PluginListNavigationHostState extends State<PluginListNavigationHost> {
  PluginListPosition? _resume;
  PluginListPosition? _current;
  Timer? _saveTimer;
  bool _navigating = false;
  bool _didBrowse = false;
  bool _reportScheduled = false;
  final _pages = <String, int>{};

  /// 到顶后继续上滚多少逻辑像素才翻到上一页。滚轮/触控板的单帧增量很小，
  /// 累加而不是一次触发，免得轻轻碰一下轨道就跳页。
  static const double _topPageTurnExtent = 48;
  static const int _topPageTurnCooldownMs = 600;
  double _topOverscroll = 0;
  DateTime? _lastTopPageTurnAt;

  PluginPagedComicListCubit get _cubit =>
      context.read<PluginPagedComicListCubit>();
  PluginListPositionStore get _positions =>
      widget.positionStore ?? PluginListPositionStore.instance;

  @override
  void initState() {
    super.initState();
    widget.navigation.attach(this, jump: _jump, restore: _restore);
    // 页码不靠 ScrollNotification：`Plat` 的页签内容、嵌套滚动都会改 depth，
    // 而滚轮在顶部干脆不发滚动通知（Scrollable 认为目标位置没变，直接不处理）。
    // 直接听控制器是唯一不受这两件事影响的来源。
    widget.scroll.addListener(_onScrollOffset);
    unawaited(_readResume());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onState(_cubit.state);
    });
  }

  @override
  void didUpdateWidget(PluginListNavigationHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scroll != widget.scroll) {
      oldWidget.scroll.removeListener(_onScrollOffset);
      widget.scroll.addListener(_onScrollOffset);
    }
  }

  @override
  void dispose() {
    widget.scroll.removeListener(_onScrollOffset);
    _save(publish: false);
    widget.navigation.detach(this);
    super.dispose();
  }

  void _onScrollOffset() {
    if (!mounted || _navigating) return;
    _reportAfterLayout();
  }

  Future<void> _readResume() async {
    try {
      final saved = await _positions.read(widget.scope);
      if (!mounted) return;
      _resume = saved;
      _publish();
    } on Object catch (error) {
      logger.w('读取发现浏览位置失败', error: error);
    }
  }

  void _onState(PluginPagedComicListState state) {
    if (state.status == PluginPagedComicListStatus.initial) {
      _save();
      _current = null;
      _didBrowse = false;
      _saveTimer?.cancel();
    }
    _pages.clear();
    _pages.addAll(_cubit.entryPages);
    _publish();
    if (state.status == PluginPagedComicListStatus.success) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_navigating) _reportVisible();
      });
    }
  }

  void _publish() {
    final state = _cubit.state;
    widget.navigation.update(
      this,
      page: _current?.page ?? state.page,
      total: _cubit.totalPages,
      saved: _resume?.page,
      loading:
          _navigating || state.status == PluginPagedComicListStatus.initial,
    );
  }

  void _reportVisible() {
    if (_navigating) return;
    final anchor = widget.viewport.firstVisible();
    if (anchor == null) return;
    // 有下标就按下标算页：key 在「同一本漫画出现在相邻两页」时会重复，
    // 反查一个 `Map<String,int>` 只会一直读到后一页（页码看着不跟手）。
    final page = anchor.index == null
        ? _pages[anchor.key]
        : _cubit.pageForIndex(anchor.index!);
    if (page == null) return;
    _current = PluginListPosition(
      page: page,
      entryKey: anchor.key,
      offset: anchor.offset,
    );
    _publish();
  }

  void _save({bool publish = true}) {
    _saveTimer?.cancel();
    final position = _current;
    if (!_didBrowse || position == null) return;
    unawaited(
      _positions
          .save(widget.scope, position)
          .catchError((Object error) => logger.w('保存发现浏览位置失败', error: error)),
    );
    if (_resume == null) {
      _resume = position;
      if (publish && mounted) _publish();
    }
  }

  void _reportAfterLayout({bool save = false}) {
    if (save) {
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 500), _save);
    }
    if (_reportScheduled) return;
    _reportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportScheduled = false;
      if (mounted && !_navigating) {
        _reportVisible();
        if (save) _save();
      }
    });
  }

  Future<void> _restore() async {
    final saved = _resume;
    if (saved != null) await _navigate(saved.page, saved);
  }

  Future<void> _jump(int page) => _navigate(page, null);

  Future<void> _navigate(int page, PluginListPosition? saved) async {
    if (_navigating) return;
    _topOverscroll = 0;
    final total = _cubit.totalPages;
    if (total != null && page > total) page = total;
    _save();
    _navigating = true;
    _publish();
    try {
      await _cubit.jumpToPage(page);
      if (!mounted ||
          _cubit.state.status != PluginPagedComicListStatus.success) {
        return;
      }
      _current = PluginListPosition(page: page);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      if (widget.scroll.hasClients) widget.scroll.jumpTo(0);
      if (saved?.entryKey != null) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        final key = saved!.entryKey!;
        final entries = _cubit.state.list;
        final index = entries.indexWhere(
          (item) => '${item.source.trim()}:${item.id}' == key,
        );
        if (index >= 0 && widget.scroll.hasClients) {
          final prepared =
              widget.canvasKey?.currentState?.jumpToEntry(key) ?? false;
          if (!prepared) {
            final position = widget.scroll.position;
            widget.scroll.jumpTo(
              ((position.maxScrollExtent + position.viewportDimension) *
                      index /
                      entries.length)
                  .clamp(0.0, position.maxScrollExtent),
            );
          }
          for (var attempt = 0; attempt < 6; attempt++) {
            await WidgetsBinding.instance.endOfFrame;
            if (!mounted || !widget.scroll.hasClients) return;
            if (widget.viewport.align(key, saved.offset)) break;
            // 变高行的滚动范围为估算值；只在本页内逐屏定位，不补拉之前的页。
            final visible = widget.viewport.firstVisible();
            final currentIndex = visible == null
                ? 0
                : entries.indexWhere(
                    (item) => '${item.source.trim()}:${item.id}' == visible.key,
                  );
            final position = widget.scroll.position;
            widget.scroll.jumpTo(
              (position.pixels +
                      (currentIndex < index ? 1 : -1) *
                          position.viewportDimension *
                          .7)
                  .clamp(0.0, position.maxScrollExtent),
            );
          }
        }
      }
      _didBrowse = true;
    } finally {
      if (mounted) {
        _navigating = false;
        _reportVisible();
        _save();
        _publish();
      }
    }
  }

  /// 列表已经在顶部时，滚轮/触控板继续向上滚不会产生任何滚动通知
  /// （`Scrollable` 发现目标位置没变就不处理这次信号），所以只能自己接。
  /// 累加到阈值再翻页，连续的高频增量不会一次跳好几页。
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _accumulateTopScroll(event.scrollDelta.dy);
    }
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _accumulateTopScroll(event.panDelta.dy);
  }

  void _accumulateTopScroll(double dy) {
    if (_navigating) return;
    if (!widget.scroll.hasClients) return;
    final position = widget.scroll.position;
    final atTop = position.pixels <= position.minScrollExtent + 0.5;
    if (!atTop || dy >= 0) {
      _topOverscroll = 0;
      return;
    }
    final now = DateTime.now();
    final last = _lastTopPageTurnAt;
    if (last != null &&
        now.difference(last) <
            const Duration(milliseconds: _topPageTurnCooldownMs)) {
      return;
    }
    _topOverscroll += -dy;
    if (_topOverscroll < _topPageTurnExtent) return;
    _topOverscroll = 0;
    _lastTopPageTurnAt = now;
    _turnToPreviousPage();
  }

  /// 顶部继续上滚 = 回到上一页。跳页后列表里只有目标页，向上没有内容可滚，
  /// 这条手势就是「跳过去之后怎么退回前一页」的入口。
  void _turnToPreviousPage() {
    if (_navigating) return;
    final current = _current?.page ?? _cubit.state.page;
    if (current <= 1) return;
    unawaited(_navigate(current - 1, null));
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: _onPointerSignal,
    onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
    child: BlocListener<PluginPagedComicListCubit, PluginPagedComicListState>(
      listener: (_, state) => _onState(state),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth != 0 ||
              notification.metrics.axis != Axis.vertical ||
              _navigating) {
            return false;
          }
          if (notification is ScrollUpdateNotification) {
            _didBrowse = true;
            _reportAfterLayout();
            _saveTimer?.cancel();
            _saveTimer = Timer(const Duration(milliseconds: 500), _save);
          } else if (notification is ScrollEndNotification) {
            _reportAfterLayout(save: true);
          }
          return false;
        },
        child: widget.child,
      ),
    ),
  );
}
