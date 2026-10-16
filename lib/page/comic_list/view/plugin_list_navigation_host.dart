import 'dart:async';

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
  PluginPagedComicListCubit get _cubit =>
      context.read<PluginPagedComicListCubit>();
  PluginListPositionStore get _positions =>
      widget.positionStore ?? PluginListPositionStore.instance;

  @override
  void initState() {
    super.initState();
    widget.navigation.attach(this, jump: _jump, restore: _restore);
    unawaited(_readResume());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onState(_cubit.state);
    });
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
    final page = anchor == null ? null : _pages[anchor.key];
    if (page == null) return;
    _current = PluginListPosition(
      page: page,
      entryKey: anchor!.key,
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

  @override
  void dispose() {
    _save(publish: false);
    widget.navigation.detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<PluginPagedComicListCubit, PluginPagedComicListState>(
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
      );
}
