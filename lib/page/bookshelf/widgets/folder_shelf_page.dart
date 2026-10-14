import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/bookshelf/bloc/folder_shelf_bloc.dart';
import 'package:zephyr/page/bookshelf/cubit/bookshelf_search_cubit.dart';
import 'package:zephyr/page/bookshelf/cubit/search_status.dart';
import 'package:zephyr/page/bookshelf/method/method.dart';
import 'package:zephyr/page/bookshelf/models/shelf_page_mode.dart';
import 'package:zephyr/page/bookshelf/service/comic_folder_service.dart';
import 'package:zephyr/page/bookshelf/service/comic_link_service.dart';
import 'package:zephyr/page/bookshelf/widgets/bookshelf_empty_view.dart';
import 'package:zephyr/page/bookshelf/widgets/bookshelf_grid_shimmer.dart';
import 'package:zephyr/page/bookshelf/widgets/bookshelf_loading_view.dart';
import 'package:zephyr/page/bookshelf/widgets/folder_shelf_item.dart';
import 'package:zephyr/page/bookshelf/widgets/shelf_floating_actions.dart';
import 'package:zephyr/widgets/expressive/shelf_list_editor.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_grid.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_info.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_book_details.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_legacy_focus.dart';
import 'package:zephyr/util/comic/comic_quick_read.dart';

part 'parts/folder_shelf_content_part.dart';
part 'parts/folder_shelf_editorial_part.dart';
part 'parts/folder_shelf_navigation_part.dart';

class FolderShelfPage extends StatelessWidget {
  const FolderShelfPage({
    super.key,
    required this.mode,
    this.refreshSignal = 0,
    this.isActive = true,
    this.editorialKey,
  });

  final GlobalKey<LibraryEditorialCanvasState>? editorialKey;
  final ShelfPageMode mode;
  final int refreshSignal;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final search = context.read<BookshelfSearchCubit>().state.stateOf(mode);
    return BlocProvider(
      create: (_) =>
          FolderShelfBloc(mode: mode)
            ..add(FolderShelfLoadRequested(search: search)),
      child: _FolderShelfPageContent(
        editorialKey: editorialKey,
        refreshSignal: refreshSignal,
        search: search,
        isActive: isActive,
      ),
    );
  }
}

class _FolderShelfPageContent extends StatefulWidget {
  const _FolderShelfPageContent({
    required this.refreshSignal,
    this.editorialKey,
    required this.search,
    required this.isActive,
  });

  final GlobalKey<LibraryEditorialCanvasState>? editorialKey;
  final int refreshSignal;
  final SearchStatusState search;
  final bool isActive;

  @override
  State<_FolderShelfPageContent> createState() =>
      _FolderShelfPageContentState();
}

class _FolderShelfPageContentState extends State<_FolderShelfPageContent>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final _canvasKey =
      widget.editorialKey ?? GlobalKey<LibraryEditorialCanvasState>();

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    }
  }

  @override
  void dispose() {
    if (_isDesktop) {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    }
    super.dispose();
  }

  static bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    if (!mounted || !widget.isActive) return false;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;

    if (_canvasKey.currentState?.closeDetails() ?? false) return true;
    final bloc = context.read<FolderShelfBloc>();
    if (bloc.state.isRoot) return false;

    bloc.add(const FolderShelfGoBack());
    return true;
  }

  @override
  void didUpdateWidget(covariant _FolderShelfPageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      context.read<FolderShelfBloc>().add(
        FolderShelfLoadRequested(search: widget.search),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocConsumer<FolderShelfBloc, FolderShelfState>(
      listenWhen: (previous, current) =>
          current.error != null && current.error != previous.error,
      listener: (context, state) {
        final error = state.error;
        if (error != null && error.isNotEmpty) {
          showErrorToast(error, context: context);
        }
      },
      builder: (context, state) {
        return PopScope(
          canPop: state.isRoot,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && !state.isRoot) {
              context.read<FolderShelfBloc>().add(const FolderShelfGoBack());
            }
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: _onGridScroll,
            child: Stack(
              children: [
                Positioned.fill(child: _buildBody(context)),
                // 顶部悬浮导航：选择模式下隐藏，由底部悬浮操作条接管。
                if (!state.selectionMode) ..._buildFloatingNav(context, state),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 顶部悬浮物的显隐（滚动联动），变化时才 setState，避免逐帧重建。
  bool _navVisible = true;

  void _setNavVisible(bool visible) {
    if (_navVisible == visible || !mounted) {
      return;
    }
    setState(() => _navVisible = visible);
  }

  /// 列表滚动方向联动悬浮物：上滑浏览时隐藏，下滑/回顶时显示。
  /// 只处理垂直主列表的通知，底部横向操作条不参与；不吞通知，RefreshIndicator 照常工作。
  bool _onGridScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification.metrics.pixels <= notification.metrics.minScrollExtent) {
      _setNavVisible(true);
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      // 手指拖动中按手指方向直接判定（比 UserScroll 更跟手）；
      // 惯性/程序滚动（dragDetails 为空）不参与，避免回顶动画中途闪烁。
      final dy = notification.dragDetails!.delta.dy;
      if (dy < 0) {
        _setNavVisible(false);
      } else if (dy > 0) {
        _setNavVisible(true);
      }
    } else if (notification is UserScrollNotification) {
      switch (notification.direction) {
        case ScrollDirection.reverse:
          _setNavVisible(false);
        case ScrollDirection.forward:
          _setNavVisible(true);
        case ScrollDirection.idle:
          break;
      }
    }
    return false;
  }

  Future<void> _showShelfHelpDialog(BuildContext context) async {
    return showPopupPanel(
      context: context,
      builder: (dialogContext) => PopupPanel(
        title: Text(t.bookshelf.folderHint),
        content: Text(t.bookshelf.helpContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(t.common.gotIt),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateFolderDialog(BuildContext context) async {
    final name = await showPopupPanel<String>(
      presentation: PopupPresentation.relative,
      context: context,
      builder: (dialogContext) => ShelfListEditor(
        title: t.bookshelf.createFolder,
        label: t.bookshelf.folderName,
        description: '把相关漫画放在一起，方便下次找到。',
        onSave: (name) => Navigator.of(dialogContext).pop(name),
      ),
    );
    if (name != null && name.isNotEmpty && context.mounted) {
      context.read<FolderShelfBloc>().add(FolderShelfCreateFolder(name));
    }
  }

  void _showFolderActions(
    BuildContext context,
    ComicFolder folder,
    String folderPath,
    Offset position,
  ) {
    // 走 [showCommonPopupMenu]（[CommonPopupRoute] 那份 FlClash 动画）：
    // 托盘从右键 / 长按那一点长出来，与工作台那排「更多」菜单同一套，
    // 不再是 Fluent 的原地淡入缩放。
    unawaited(
      showCommonPopupMenu(
        context: context,
        position: position,
        items: [
          CommonPopupMenuItem(
            label: t.common.rename,
            glyph: AppGlyphs.edit,
            onPressed: () =>
                _showRenameFolderDialog(context, folder, folderPath),
          ),
          CommonPopupMenuItem(
            label: t.bookshelf.moveTo,
            glyph: AppGlyphs.folderCopy,
            onPressed: () => unawaited(
              _showTargetFolderDialog(
                context,
                selectedFolderPaths: {folderPath},
                onConfirmed: (targets) {
                  context.read<FolderShelfBloc>().add(
                    FolderShelfMoveSelected(
                      targets,
                      sourceFolderPaths: {folderPath},
                    ),
                  );
                },
              ),
            ),
          ),
          CommonPopupMenuItem(
            label: t.common.delete,
            glyph: AppGlyphs.delete,
            onPressed: () => _confirmDeleteSingleFolder(context, folderPath),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteSingleFolder(
    BuildContext context,
    String path,
  ) async {
    final confirmed = await showPopupPanel<bool>(
      context: context,
      presentation: PopupPresentation.modal,
      builder: (dialogContext) {
        return PopupPanel(
          title: Text(t.bookshelf.confirmDeleteFolderTitle),
          content: Text(t.bookshelf.confirmDeleteFolderContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(t.common.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(t.common.delete),
            ),
          ],
        );
      },
    );
    if (confirmed == true && context.mounted) {
      context.read<FolderShelfBloc>().add(FolderShelfDeleteFolder(path));
    }
  }

  Future<void> _showRenameFolderDialog(
    BuildContext context,
    ComicFolder folder,
    String folderPath,
  ) async {
    final controller = TextEditingController(text: folder.name);
    final name = await showPopupPanel<String>(
      presentation: PopupPresentation.relative,
      context: context,
      builder: (dialogContext) {
        return PopupPanel(
          title: Text(t.bookshelf.renameFolder),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: t.common.rename),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(t.common.cancel),
            ),
            TextButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  Navigator.of(dialogContext).pop(text);
                }
              },
              child: Text(t.common.ok),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (name != null && name.isNotEmpty && context.mounted) {
      context.read<FolderShelfBloc>().add(
        FolderShelfRenameFolder(folderPath, name),
      );
    }
  }

  static ComicEntryType _comicEntryTypeOf(ShelfPageMode mode) {
    return switch (mode) {
      ShelfPageMode.favorite => ComicEntryType.favorite,
      ShelfPageMode.history => ComicEntryType.history,
      ShelfPageMode.download => ComicEntryType.download,
    };
  }

  static String _normalizeSearchText(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) return '';
    try {
      return t2s(lower);
    } catch (_) {
      return lower;
    }
  }

  void _showComicActions(
    BuildContext context,
    ComicSimplifyEntryInfo info,
    Offset position,
  ) {
    final key = '${info.from.trim()}:${info.id}';
    // 与 _showFolderActions 同一套弹出动画（[showCommonPopupMenu]）。
    unawaited(
      showCommonPopupMenu(
        context: context,
        position: position,
        items: [
          CommonPopupMenuItem(
            label: t.bookshelf.multiSelect,
            glyph: AppGlyphs.checklist,
            onPressed: () => context.read<FolderShelfBloc>().add(
              FolderShelfToggleComicSelection(key),
            ),
          ),
          CommonPopupMenuItem(
            label: t.common.delete,
            glyph: AppGlyphs.delete,
            onPressed: () => _confirmRemoveComic(context, info),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemoveComic(
    BuildContext context,
    ComicSimplifyEntryInfo info,
  ) async {
    final confirmed = await showPopupPanel<bool>(
      context: context,
      presentation: PopupPresentation.modal,
      builder: (dialogContext) {
        return PopupPanel(
          title: Text(t.bookshelf.confirmRemoveComicTitle),
          content: Text(
            t.bookshelf.confirmRemoveComicContent(title: info.title),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(t.common.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(t.common.remove),
            ),
          ],
        );
      },
    );
    if (confirmed == true && context.mounted) {
      final uniqueKey = '${info.from.trim()}:${info.id}';
      final state = context.read<FolderShelfBloc>().state;
      // 历史无 ComicLink：直接软删除历史本体（与旧 LocalShelfPage 一致）。
      if (state.mode == ShelfPageMode.history) {
        final history = objectbox.unifiedHistoryBox
            .query(UnifiedComicHistory_.uniqueKey.equals(uniqueKey))
            .build()
            .findFirst();
        if (history != null) {
          history
            ..deleted = true
            ..updatedAt = DateTime.now().toUtc();
          objectbox.unifiedHistoryBox.put(history);
        }
        context.read<FolderShelfBloc>().add(const FolderShelfLoadRequested());
        return;
      }
      final folderType = switch (state.mode) {
        ShelfPageMode.favorite => ComicFolderType.favorite,
        ShelfPageMode.download => ComicFolderType.download,
        ShelfPageMode.history => ComicFolderType.history,
      };
      ComicLinkService.removeComic(
        uniqueKey,
        state.currentPath.isEmpty ? null : state.currentPath,
        folderType,
      );
      context.read<FolderShelfBloc>().add(const FolderShelfLoadRequested());
    }
  }
}

Future<void> _showTargetFolderDialog(
  BuildContext context, {
  Set<String>? selectedFolderPaths,
  required ValueChanged<Set<String>> onConfirmed,
}) async {
  final state = context.read<FolderShelfBloc>().state;
  final sourceFolderPaths = selectedFolderPaths ?? state.selectedFolderPaths;
  final allFolders = ComicFolderService.listAllFolders(
    _folderTypeOf(state.mode),
  );
  final syncIdMap = _buildSyncIdMap(state.mode);
  final pathMap = {
    for (final folder in allFolders)
      folder.syncId: ComicFolderService.folderPath(
        folder,
        syncIdMap: syncIdMap,
      ),
  };
  final forest = _buildFolderForest(allFolders, pathMap);

  // 排除当前所在文件夹（仅自身）、被选中的文件夹及其子树
  final forbiddenSyncIds = <String>{};
  for (final path in sourceFolderPaths) {
    final folder = allFolders.firstWhereOrNull(
      (f) => pathMap[f.syncId] == path,
    );
    if (folder != null) {
      _collectForbiddenSyncIds(folder.syncId, allFolders, forbiddenSyncIds);
    }
  }
  final currentPath = state.currentPath;
  final isRoot = currentPath.isEmpty;
  final currentFolder = isRoot
      ? null
      : allFolders.firstWhereOrNull((f) => pathMap[f.syncId] == currentPath);
  final currentSyncId = currentFolder?.syncId;

  final selectedPaths = <String>{};

  await showPopupPanel<void>(
    presentation: PopupPresentation.relative,
    context: context,
    builder: (dialogContext) {
      final expandedPaths = <String>{};
      return StatefulBuilder(
        builder: (ctx, setState) {
          void togglePath(String path) {
            setState(() {
              if (selectedPaths.contains(path)) {
                selectedPaths.remove(path);
              } else {
                selectedPaths.add(path);
              }
            });
          }

          return PopupPanel(
            title: Text(t.bookshelf.selectTargetFolder),
            content: SizedBox(
              width: 380,
              height: 400,
              child: ListView(
                children: [
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const SizedBox(width: 48),
                    title: Text(t.common.root),
                    trailing: Checkbox(
                      value: selectedPaths.contains(kComicFolderRootPath),
                      onChanged: isRoot
                          ? null
                          : (_) => togglePath(kComicFolderRootPath),
                    ),
                    onTap: isRoot
                        ? null
                        : () => togglePath(kComicFolderRootPath),
                  ),
                  const Divider(),
                  ...forest.map(
                    (node) => _buildFolderTreeTile(
                      context: ctx,
                      node: node,
                      pathMap: pathMap,
                      expandedPaths: expandedPaths,
                      forbiddenSyncIds: forbiddenSyncIds,
                      currentSyncId: currentSyncId,
                      selectedPaths: selectedPaths,
                      onToggleExpand: (path) => setState(() {
                        if (expandedPaths.contains(path)) {
                          expandedPaths.remove(path);
                        } else {
                          expandedPaths.add(path);
                        }
                      }),
                      onSelect: togglePath,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(t.common.cancel),
              ),
              FilledButton(
                onPressed: selectedPaths.isEmpty
                    ? null
                    : () {
                        Navigator.of(dialogContext).pop();
                        onConfirmed(selectedPaths);
                      },
                child: Text(t.common.ok),
              ),
            ],
          );
        },
      );
    },
  );
}

class _FolderNode {
  final ComicFolder folder;
  final List<_FolderNode> children;

  _FolderNode(this.folder) : children = [];
}

List<_FolderNode> _buildFolderForest(
  List<ComicFolder> folders,
  Map<String, String> pathMap,
) {
  final sorted = folders.toList()
    ..sort(
      (a, b) => (pathMap[a.syncId] ?? '').compareTo(pathMap[b.syncId] ?? ''),
    );
  final map = <String, _FolderNode>{};
  final roots = <_FolderNode>[];
  for (final folder in sorted) {
    final node = _FolderNode(folder);
    map[folder.syncId] = node;
    final parentSyncId = folder.parentSyncId;
    if (parentSyncId == null || parentSyncId.isEmpty) {
      roots.add(node);
    } else {
      map[parentSyncId]?.children.add(node);
    }
  }
  return roots;
}

Map<String, ComicFolder> _buildSyncIdMap(ShelfPageMode mode) {
  final allFolders = ComicFolderService.listAllFolders(_folderTypeOf(mode));
  return {for (final folder in allFolders) folder.syncId: folder};
}

void _collectForbiddenSyncIds(
  String syncId,
  List<ComicFolder> allFolders,
  Set<String> result,
) {
  if (!result.add(syncId)) return;
  for (final child in allFolders) {
    if (child.parentSyncId == syncId) {
      _collectForbiddenSyncIds(child.syncId, allFolders, result);
    }
  }
}

Widget _buildFolderTreeTile({
  required BuildContext context,
  required _FolderNode node,
  required Map<String, String> pathMap,
  required Set<String> expandedPaths,
  required Set<String> forbiddenSyncIds,
  required String? currentSyncId,
  required Set<String> selectedPaths,
  required ValueChanged<String> onToggleExpand,
  required ValueChanged<String> onSelect,
}) {
  final path = pathMap[node.folder.syncId] ?? '/${node.folder.name}';
  final syncId = node.folder.syncId;
  final isExpanded = expandedPaths.contains(path);
  final isCurrentPath = currentSyncId != null && syncId == currentSyncId;
  final isForbidden = isCurrentPath || forbiddenSyncIds.contains(syncId);
  final hasChildren = node.children.isNotEmpty;
  final theme = Theme.of(context);
  final isSelected = selectedPaths.contains(path) && !isForbidden;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: hasChildren
            ? IconButton(
                icon: GlyphIcon(
                  isExpanded ? AppGlyphs.chevronDown : AppGlyphs.chevronForward,
                ),
                onPressed: () => onToggleExpand(path),
              )
            : const SizedBox(width: 48),
        title: Text(
          node.folder.name,
          style: isForbidden ? TextStyle(color: theme.disabledColor) : null,
        ),
        trailing: Checkbox(
          value: isSelected,
          onChanged: isForbidden ? null : (_) => onSelect(path),
        ),
        onTap: isForbidden ? null : () => onSelect(path),
      ),
      if (isExpanded)
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: node.children
                .map(
                  (child) => _buildFolderTreeTile(
                    context: context,
                    node: child,
                    pathMap: pathMap,
                    expandedPaths: expandedPaths,
                    forbiddenSyncIds: forbiddenSyncIds,
                    currentSyncId: currentSyncId,
                    selectedPaths: selectedPaths,
                    onToggleExpand: onToggleExpand,
                    onSelect: onSelect,
                  ),
                )
                .toList(),
          ),
        ),
    ],
  );
}

ComicFolderType _folderTypeOf(ShelfPageMode mode) {
  return switch (mode) {
    ShelfPageMode.favorite => ComicFolderType.favorite,
    ShelfPageMode.download => ComicFolderType.download,
    ShelfPageMode.history => ComicFolderType.history,
  };
}

Future<void> _importComic(BuildContext context) async {
  String? importRoot;
  String? cleanupDir;
  try {
    if (Platform.isAndroid) {
      importRoot = await pickComicZipAndroid();
      if (importRoot != null) {
        cleanupDir = p.dirname(p.dirname(importRoot));
      }
    } else {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'zip',
            extensions: ['zip'],
            uniformTypeIdentifiers: ['public.zip-archive'],
          ),
        ],
      );
      importRoot = file?.path;
    }
    if (importRoot == null || importRoot.trim().isEmpty) return;

    if (!context.mounted) return;
    showSuccessToast(t.bookshelf.importStarted);

    final result = await importComicFromZip(
      importRoot,
      cleanupDir: cleanupDir,
      onConfirmOverwrite: (title) =>
          _confirmComicImportOverwrite(context, title),
    );

    if (!context.mounted) return;
    showSuccessToast(t.bookshelf.importCompleted(title: result.title));
    context.read<FolderShelfBloc>().add(const FolderShelfLoadRequested());
  } on ComicImportCancelledException catch (_) {
    if (!context.mounted) return;
    showErrorToast(t.common.cancelled);
  } catch (e) {
    if (!context.mounted) return;
    showErrorToast(t.error.importFailed(error: e.toString()));
  }
}

Future<bool> _confirmComicImportOverwrite(
  BuildContext context,
  String title,
) async {
  final result = await showPopupPanel<bool>(
    context: context,
    presentation: PopupPresentation.modal,
    builder: (dialogContext) => PopupPanel(
      title: Text(t.bookshelf.comicExists),
      content: Text(t.bookshelf.confirmOverwriteImport(title: title)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(t.common.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(t.common.overwrite),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<void> _batchExportSelected(
  BuildContext context,
  FolderShelfState state,
) async {
  final selectedComics = state.comics
      .where(
        (c) => state.selectedComicKeys.contains('${c.from.trim()}:${c.id}'),
      )
      .toList();

  if (selectedComics.isEmpty) {
    showInfoToast(t.bookshelf.noExportableComics, context: context);
    return;
  }

  final choice = await pickBatchExportChoice(context);
  if (choice == null) return;

  try {
    final result = await batchExportComics(
      comics: selectedComics,
      choice: choice,
    );
    if (!context.mounted) return;
    final lines = <String>[
      t.bookshelf.batchExportCompleted(
        success: result.success,
        total: selectedComics.length,
      ),
      if (result.deleted > 0)
        t.bookshelf.batchExportDeleted(count: result.deleted),
      if (result.keptForMissingPages > 0)
        t.bookshelf.batchExportKeptIncomplete(
          count: result.keptForMissingPages,
        ),
    ];
    final message = lines.join('\n');
    if (result.keptForMissingPages > 0) {
      showErrorToast(message, duration: const Duration(seconds: 6));
    } else {
      showSuccessToast(message);
    }
    context.read<FolderShelfBloc>().add(const FolderShelfExitSelectionMode());
    if (result.deleted > 0) {
      context.read<FolderShelfBloc>().add(const FolderShelfLoadRequested());
    }
  } catch (e) {
    if (!context.mounted) return;
    showErrorToast(t.bookshelf.batchExportFailed(error: e.toString()));
  }
}

Future<void> _confirmDeleteSelected(BuildContext context) async {
  final confirmed = await showPopupPanel<bool>(
    context: context,
    presentation: PopupPresentation.modal,
    builder: (dialogContext) {
      return PopupPanel(
        title: Text(t.bookshelf.confirmDeleteSelectedTitle),
        content: Text(t.bookshelf.confirmDeleteSelectedContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t.common.delete),
          ),
        ],
      );
    },
  );
  if (confirmed == true && context.mounted) {
    context.read<FolderShelfBloc>().add(const FolderShelfDeleteSelected());
  }
}
