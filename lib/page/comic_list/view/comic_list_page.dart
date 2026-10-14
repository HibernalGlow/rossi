import 'package:auto_route/annotations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_list/view/discover_filter_fab.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation_button.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/page/comic_list/cubit/comic_list_cubit.dart';
import 'package:zephyr/page/comic_list/models/comic_list_scene.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_list/scene_filter/plugin_list_filter_dialog.dart';
import 'package:zephyr/page/comic_list/view/plugin_paged_comic_list_view.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/page/discover/service/discover_tab_toolbar.dart';

@RoutePage()
class ComicListPage extends StatelessWidget {
  const ComicListPage({
    super.key,
    this.title,
    this.scene,
    this.sceneSource,
    this.sceneBundleFnPath,
    this.sceneBundleFnPathFallback,
  });

  final String? title;
  final ComicListScene? scene;
  final String? sceneSource;
  final String? sceneBundleFnPath;
  final String? sceneBundleFnPathFallback;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ComicListCubit(
        initialScene: scene,
        sceneSource: sceneSource,
        sceneBundleFnPath: sceneBundleFnPath,
        sceneBundleFnPathFallback: sceneBundleFnPathFallback,
      ),
      child: _ComicListView(title: title),
    );
  }
}

class _ComicListView extends StatefulWidget {
  const _ComicListView({this.title});

  final String? title;

  @override
  State<_ComicListView> createState() => _ComicListViewState();
}

class _ComicListViewState extends State<_ComicListView>
    with AutomaticKeepAliveClientMixin {
  final _canvasKey = GlobalKey<LibraryEditorialCanvasState>();
  DiscoverTabToolbarController? _tabToolbar;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final toolbar = DiscoverTabToolbarScope.maybeOf(context);
    if (identical(toolbar, _tabToolbar)) return;
    _tabToolbar?.unregister(this);
    _tabToolbar = toolbar;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_tabToolbar, toolbar)) {
        toolbar?.register(
          this,
          (anchor) async {
            await _canvasKey.currentState?.openSettings(anchor);
          },
          // 长按工具栏那颗键 = 就地开关展墙；正文禁用（加载中/出错）时
          // 画布自己会挡下这次翻转。
          togglePresentation: () => _canvasKey.currentState?.toggleEditorial(),
        );
      }
    });
  }

  @override
  void dispose() {
    _tabToolbar?.unregister(this);
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocBuilder<ComicListCubit, ComicListState>(
      builder: (context, state) {
        final title =
            widget.title ?? (state.scene?.title ?? t.comicList.defaultTitle);
        // 与默认值不一致才算「筛选生效」，用它点亮角标。
        final filterDirty =
            state.hasResolvedFilter &&
            state.filterSelections.entries.any(
              (entry) =>
                  state.filterBundle?.defaultSelections[entry.key] !=
                  entry.value,
            );

        return Scaffold(
          appBar: _tabToolbar != null
              ? null
              : AppBar(
                  title: Text(title),
                  actions: [
                    LibraryPresentationButton(
                      canvasKey: _canvasKey,
                      enabled: !state.sceneLoading && state.sceneError == null,
                    ),
                  ],
                ),
          body: Stack(
            children: [
              Positioned.fill(child: _buildBody(context, state)),
              if (state.requiresFilter)
                Positioned(
                  // 挂 `floatingActionButton` 时 Scaffold 只按键盘高度定位，
                  // 看不见 Dock —— 底栏占位由外层写进 body 的 `padding.bottom`
                  // （`navigation_bar.dart` 的 `_buildDockLayout`），这里自己抬。
                  bottom: 16 + MediaQuery.paddingOf(context).bottom,
                  right: 16,
                  child: DiscoverFilterFab(
                    hasFilters: filterDirty,
                    onPressed: () => _openFilterDialog(context),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, ComicListState state) {
    final currentFrom = state.currentFrom;

    if (currentFrom.isEmpty) {
      return Center(child: Text(t.comicList.missingSource));
    }

    if (state.sceneLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.sceneError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.sceneError!),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => context.read<ComicListCubit>().reload(),
              child: Text(t.comicList.reload),
            ),
          ],
        ),
      );
    }

    if (state.requiresFilter &&
        state.filterLoading &&
        !state.hasResolvedFilter) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.requiresFilter &&
        state.filterError != null &&
        !state.hasResolvedFilter) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.filterError!),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => context.read<ComicListCubit>().loadFilter(),
              child: Text(t.comicList.reload),
            ),
          ],
        ),
      );
    }

    final scene = state.scene;
    if (scene != null) {
      return _buildSceneBody(state, scene);
    }

    return const SizedBox.shrink();
  }

  Widget _buildSceneBody(ComicListState state, ComicListScene scene) {
    final request = scene.body.request!;
    final filterCore = state.resolvedFilterCore;
    final filterExtern = state.resolvedFilterExtern;
    final listCore = <String, dynamic>{...request.core, ...filterCore};
    final listExtern = <String, dynamic>{...request.extern, ...filterExtern};
    final collectionTargetId = _resolveCollectionTargetId(
      request: request,
      core: listCore,
      extern: listExtern,
    );

    return PluginPagedComicListView(
      key: ValueKey('${request.fnPath}_${listCore}_$listExtern'),
      editorialKey: _canvasKey,
      pluginId: state.currentFrom,
      fnPath: request.fnPath,
      coreBuilder: (page) => {'page': page, ...listCore},
      externBuilder: (_) => listExtern,
      collectionTargetId: collectionTargetId,
    );
  }

  String? _resolveCollectionTargetId({
    required ComicListRequestConfig request,
    required Map<String, dynamic> core,
    required Map<String, dynamic> extern,
  }) {
    final isCloudFavoriteScene =
        request.fnPath == 'getCloudFavoriteData' ||
        extern['source']?.toString() == 'cloudFavorite';
    if (!isCloudFavoriteScene) {
      return null;
    }
    final targetId = core['folderId'] ?? extern['folderId'];
    final normalized = targetId?.toString().trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  Future<void> _openFilterDialog(BuildContext context) async {
    final cubit = context.read<ComicListCubit>();

    if (!cubit.state.hasResolvedFilter) {
      await cubit.loadFilter();
    }

    final bundle = cubit.state.filterBundle;
    if (!context.mounted || bundle == null) {
      return;
    }

    final result = await showPopupPanel<Map<String, String>>(
      presentation: PopupPresentation.relative,
      context: context,
      builder: (context) => PluginListFilterDialog(
        scheme: bundle.scheme,
        initialSelections: cubit.state.filterSelections.isNotEmpty
            ? cubit.state.filterSelections
            : bundle.defaultSelections,
      ),
    );

    if (result == null || !context.mounted) {
      return;
    }

    cubit.applyFilterSelections(result);
  }
}
