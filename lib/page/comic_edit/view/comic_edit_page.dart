import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pool/pool.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/network/http/picture/picture.dart';
import 'package:zephyr/page/comic_edit/cubit/comic_edit_cubit.dart';
import 'package:zephyr/page/comic_edit/method/comic_edit_debug.dart';
import 'package:zephyr/page/comic_edit/method/comic_edit_document.dart';
import 'package:zephyr/service/download/download_asset_store.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/widgets/toast.dart';

const double _kWideBreakpoint = 900;

@RoutePage()
class ComicEditPage extends StatelessWidget {
  const ComicEditPage({super.key, required this.from, required this.comicId});

  final String from;
  final String comicId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ComicEditCubit(from: from, comicId: comicId)..load(),
      child: const _ComicEditView(),
    );
  }
}

class _ComicEditView extends StatelessWidget {
  const _ComicEditView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ComicEditCubit, ComicEditState>(
      listenWhen: (previous, next) =>
          next.error.isNotEmpty && previous.error != next.error,
      listener: (context, state) => showErrorToast(state.error),
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(title: Text(t.comicEdit.title)),
          body: _buildBody(context, state),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, ComicEditState state) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.locked) {
      return const _LockedView();
    }
    if (state.document == null) {
      return Center(child: Text(t.comicEdit.loadFailed));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _kWideBreakpoint) {
          return _WideEditLayout(state: state);
        }
        return _CompactEditLayout(state: state);
      },
    );
  }
}

class _CompactEditLayout extends StatelessWidget {
  const _CompactEditLayout({required this.state});

  final ComicEditState state;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: t.comicEdit.basicInfo),
              Tab(text: t.comicEdit.chapters),
              Tab(text: t.comicEdit.images),
            ],
          ),
          if (state.busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: TabBarView(
              children: [
                _BasicInfoTab(state: state),
                _ChaptersTab(state: state),
                _ImagesTab(state: state),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WideEditLayout extends StatelessWidget {
  const _WideEditLayout({required this.state});

  final ComicEditState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 320, child: _ChapterListPane(state: state)),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            children: [
              if (state.busy) const LinearProgressIndicator(minHeight: 2),
              _BasicInfoPanel(state: state),
              const Divider(height: 1),
              Expanded(
                child: _ImageGridPane(state: state, showChapterTitle: true),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LockedView extends StatelessWidget {
  const _LockedView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 12),
            Text(
              t.comicEdit.lockedTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(t.comicEdit.lockedMessage, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(t.common.back),
            ),
          ],
        ),
      ),
    );
  }
}

class _BasicInfoTab extends StatelessWidget {
  const _BasicInfoTab({required this.state});

  final ComicEditState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComicEditCubit>();
    final cover = state.cover;
    final coverPath = cover['path']?.toString().trim() ?? '';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _TitleEditor(state: state),
        const SizedBox(height: 24),
        Text(
          t.comicEdit.changeCover,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Center(
          child: _CoverPreview(
            from: cubit.from,
            comicId: cubit.comicId,
            path: coverPath,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton.icon(
            onPressed: state.busy ? null : () => _pickCover(cubit),
            icon: const Icon(Icons.image_outlined),
            label: Text(t.comicEdit.changeCover),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: OutlinedButton.icon(
            onPressed: state.busy
                ? null
                : () => _pickCoverFromComic(context, cubit, state),
            icon: const Icon(Icons.collections_outlined),
            label: Text(t.comicEdit.chooseFromComic),
          ),
        ),
      ],
    );
  }
}

class _BasicInfoPanel extends StatelessWidget {
  const _BasicInfoPanel({required this.state});

  final ComicEditState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComicEditCubit>();
    final cover = state.cover;
    final coverPath = cover['path']?.toString().trim() ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CoverPreview(
            from: cubit.from,
            comicId: cubit.comicId,
            path: coverPath,
            width: 120,
            height: 165,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TitleEditor(state: state, horizontal: true),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: state.busy
                              ? null
                              : () => _pickCover(cubit),
                          icon: const Icon(Icons.image_outlined),
                          label: Text(t.comicEdit.changeCover),
                        ),
                        OutlinedButton.icon(
                          onPressed: state.busy
                              ? null
                              : () =>
                                    _pickCoverFromComic(context, cubit, state),
                          icon: const Icon(Icons.collections_outlined),
                          label: Text(t.comicEdit.chooseFromComic),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleEditor extends StatefulWidget {
  const _TitleEditor({required this.state, this.horizontal = false});

  final ComicEditState state;
  final bool horizontal;

  @override
  State<_TitleEditor> createState() => _TitleEditorState();
}

class _TitleEditorState extends State<_TitleEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.state.title);
  }

  @override
  void didUpdateWidget(covariant _TitleEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.title != oldWidget.state.title &&
        _controller.text != widget.state.title) {
      _controller.text = widget.state.title;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComicEditCubit>();
    final field = TextField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: t.comicEdit.comicTitle,
        hintText: t.comicEdit.titleHint,
        border: const OutlineInputBorder(),
      ),
      textInputAction: TextInputAction.done,
      onSubmitted: cubit.saveTitle,
    );
    final button = FilledButton.icon(
      onPressed: widget.state.busy
          ? null
          : () => cubit.saveTitle(_controller.text),
      icon: const Icon(Icons.save),
      label: Text(t.comicEdit.saveTitle),
    );

    if (widget.horizontal) {
      return Row(
        children: [
          Expanded(child: field),
          const SizedBox(width: 8),
          button,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        field,
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerRight, child: button),
      ],
    );
  }
}

class _CoverPreview extends StatelessWidget {
  const _CoverPreview({
    required this.from,
    required this.comicId,
    required this.path,
    this.width = 160,
    this.height = 220,
  });

  final String from;
  final String comicId;
  final String path;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        height: height,
        child: path.isEmpty
            ? const ColoredBox(
                color: Colors.black12,
                child: Icon(Icons.image_outlined, size: 48),
              )
            : FutureBuilder<String>(
                future: findCachedPicturePath(
                  from: from,
                  path: path,
                  cartoonId: comicId,
                  pictureType: PictureType.cover,
                ),
                builder: (context, snapshot) {
                  final local = snapshot.data ?? '';
                  if (local.isEmpty) {
                    return const ColoredBox(
                      color: Colors.black12,
                      child: Icon(Icons.image_outlined, size: 48),
                    );
                  }
                  return Image.file(File(local), fit: BoxFit.cover);
                },
              ),
      ),
    );
  }
}

class _ChaptersTab extends StatelessWidget {
  const _ChaptersTab({required this.state});

  final ComicEditState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComicEditCubit>();
    final chapters = state.chapters;
    return Scaffold(
      body: chapters.isEmpty
          ? Center(child: Text(t.comicEdit.noChapters))
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              itemCount: chapters.length,
              buildDefaultDragHandles: false,
              onReorderItem: (oldIndex, newIndex) =>
                  cubit.reorderChapters(oldIndex, newIndex),
              itemBuilder: (context, index) {
                final chapter = chapters[index];
                final id = comicEditChapterId(chapter);
                return _ChapterTile(
                  key: ValueKey(id),
                  chapter: chapter,
                  index: index,
                  selected: id == state.selectedChapterId,
                  onTap: () {
                    cubit.selectChapter(id);
                    DefaultTabController.of(context).animateTo(2);
                  },
                  onRename: () => _renameChapter(context, cubit, chapter),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addChapter(
          context,
          cubit,
          onAdded: () {
            if (context.mounted) {
              DefaultTabController.of(context).animateTo(2);
            }
          },
        ),
        icon: const Icon(Icons.add),
        label: Text(t.comicEdit.addChapter),
      ),
    );
  }
}

class _ChapterListPane extends StatelessWidget {
  const _ChapterListPane({required this.state});

  final ComicEditState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComicEditCubit>();
    final chapters = state.chapters;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t.comicEdit.chapters,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: t.comicEdit.addChapter,
                icon: const Icon(Icons.add),
                onPressed: () => _addChapter(context, cubit),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: chapters.isEmpty
              ? Center(child: Text(t.comicEdit.noChapters))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: chapters.length,
                  buildDefaultDragHandles: false,
                  onReorderItem: (oldIndex, newIndex) =>
                      cubit.reorderChapters(oldIndex, newIndex),
                  itemBuilder: (context, index) {
                    final chapter = chapters[index];
                    final id = comicEditChapterId(chapter);
                    return _ChapterTile(
                      key: ValueKey(id),
                      chapter: chapter,
                      index: index,
                      selected: id == state.selectedChapterId,
                      onTap: () => cubit.selectChapter(id),
                      onRename: () => _renameChapter(context, cubit, chapter),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    super.key,
    required this.chapter,
    required this.index,
    required this.selected,
    required this.onTap,
    required this.onRename,
  });

  final Map<String, dynamic> chapter;
  final int index;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final name = chapter['name']?.toString() ?? '';
    final count = ((chapter['images'] as List?) ?? const []).length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          selected: selected,
          leading: CircleAvatar(child: Text('${index + 1}')),
          title: Text(name.isEmpty ? t.comicEdit.chapterName : name),
          subtitle: Text(t.comicEdit.pagesCount(count: count)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: t.comicEdit.renameChapter,
                onPressed: onRename,
              ),
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: Icon(Icons.drag_handle),
                ),
              ),
            ],
          ),
          onTap: onTap,
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _ImagesTab extends StatelessWidget {
  const _ImagesTab({required this.state});

  final ComicEditState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComicEditCubit>();
    final chapter = state.selectedChapter;
    if (state.chapters.isEmpty || chapter == null) {
      return Center(child: Text(t.comicEdit.noChapters));
    }
    final chapterId = comicEditChapterId(chapter);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: DropdownButtonFormField<String>(
            key: ValueKey(chapterId),
            initialValue: chapterId,
            decoration: InputDecoration(
              labelText: t.comicEdit.selectChapter,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: state.chapters.map((item) {
              final id = comicEditChapterId(item);
              final name = item['name']?.toString() ?? '';
              return DropdownMenuItem<String>(
                value: id,
                child: Text(
                  name.isEmpty ? t.comicEdit.chapterName : name,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: state.busy
                ? null
                : (value) {
                    if (value != null) cubit.selectChapter(value);
                  },
          ),
        ),
        Expanded(child: _ImageGridPane(state: state)),
      ],
    );
  }
}

class _ResolvedImage {
  const _ResolvedImage({required this.path, required this.localPath});

  final String path;
  final String localPath;
}

class _ImageGridPane extends StatefulWidget {
  const _ImageGridPane({required this.state, this.showChapterTitle = false});

  final ComicEditState state;
  final bool showChapterTitle;

  @override
  State<_ImageGridPane> createState() => _ImageGridPaneState();
}

class _ImageGridPaneState extends State<_ImageGridPane> {
  final ScrollController _scrollController = ScrollController();
  String _loadedChapterId = '';
  String _loadedSignature = '';
  Future<List<_ResolvedImage>> _imagesFuture = Future.value(const []);

  @override
  void initState() {
    super.initState();
    _startLoad();
  }

  @override
  void didUpdateWidget(covariant _ImageGridPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final chapter = widget.state.selectedChapter;
    if (chapter == null) {
      if (_loadedChapterId.isNotEmpty) {
        _loadedChapterId = '';
        _loadedSignature = '';
        _imagesFuture = Future.value(const []);
      }
      return;
    }
    final chapterId = comicEditChapterId(chapter);
    final signature = _signatureFor(chapter);
    if (chapterId != _loadedChapterId || signature != _loadedSignature) {
      _startLoad();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _startLoad() {
    final chapter = widget.state.selectedChapter;
    if (chapter == null) {
      _loadedChapterId = '';
      _loadedSignature = '';
      _imagesFuture = Future.value(const []);
      return;
    }
    _loadedChapterId = comicEditChapterId(chapter);
    _loadedSignature = _signatureFor(chapter);
    final cubit = context.read<ComicEditCubit>();
    _imagesFuture = _resolveImages(
      from: cubit.from,
      comicId: cubit.comicId,
      chapter: chapter,
      images: widget.state.selectedImages,
    );
  }

  String _signatureFor(Map<String, dynamic> chapter) {
    final paths =
        ((chapter['images'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((image) => image['path']?.toString() ?? '')
            .where((path) => path.isNotEmpty)
            .toList()
          ..sort();
    return paths.join('|');
  }

  Future<List<_ResolvedImage>> _resolveImages({
    required String from,
    required String comicId,
    required Map<String, dynamic> chapter,
    required List<Map<String, dynamic>> images,
  }) async {
    final storageId = comicEditChapterStorageId(chapter);
    final stopwatch = Stopwatch()..start();
    final pool = Pool(8);
    try {
      final resolved = await Future.wait(
        images.map(
          (image) => pool.withResource(() async {
            final path = image['path']?.toString() ?? '';
            var localPath = '';
            if (path.isNotEmpty) {
              try {
                final resolver = debugComicEditImagePathResolver;
                if (resolver != null) {
                  localPath = await resolver(
                    from: from,
                    comicId: comicId,
                    storageChapterId: storageId,
                    path: path,
                  );
                } else {
                  final store = DownloadAssetStore(
                    from: from,
                    path: path,
                    cartoonId: comicId,
                    chapterId: '',
                    storageChapterId: storageId,
                    pictureType: PictureType.page,
                  );
                  final existing = await store.findExistingDownload();
                  localPath = existing?.path ?? '';
                }
              } catch (_) {}
            }
            return _ResolvedImage(path: path, localPath: localPath);
          }),
        ),
      );
      final remaining = const Duration(milliseconds: 120) - stopwatch.elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
      return resolved;
    } finally {
      await pool.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final cubit = context.read<ComicEditCubit>();
    final chapter = state.selectedChapter;
    if (state.chapters.isEmpty || chapter == null) {
      return Center(child: Text(t.comicEdit.noChapters));
    }

    final chapterName = chapter['name']?.toString() ?? '';
    final images = state.selectedImages;
    final paths = images
        .map((image) => image['path']?.toString() ?? '')
        .where((path) => path.isNotEmpty)
        .toList();

    final hasSelection = state.selectedImagePaths.isNotEmpty;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  if (widget.showChapterTitle)
                    Expanded(
                      child: Text(
                        chapterName.isEmpty
                            ? t.comicEdit.chapterName
                            : chapterName,
                        style: Theme.of(context).textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      t.comicEdit.reorderHint,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: widget.showChapterTitle
                          ? TextAlign.end
                          : TextAlign.start,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: images.isEmpty
                  ? Center(child: Text(t.comicEdit.emptyChapter))
                  : FutureBuilder<List<_ResolvedImage>>(
                      future: _imagesFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          return Center(child: Text(t.comicEdit.loadFailed));
                        }
                        final resolvedByPath = {
                          for (final item
                              in snapshot.data ?? const <_ResolvedImage>[])
                            item.path: item,
                        };
                        return ReorderableBuilder<String>.builder(
                          itemCount: images.length,
                          scrollController: _scrollController,
                          onReorder: (reorderedListFunction) {
                            final ordered = reorderedListFunction(paths);
                            cubit.reorderImages(ordered);
                          },
                          childBuilder: (itemBuilder) {
                            return GridView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
                              itemCount: images.length,
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 160,
                                    mainAxisSpacing: 6,
                                    crossAxisSpacing: 6,
                                    childAspectRatio: 0.68,
                                  ),
                              itemBuilder: (context, index) {
                                final path = paths[index];
                                return itemBuilder(
                                  _ImageTile(
                                    key: ValueKey(path),
                                    localPath:
                                        resolvedByPath[path]?.localPath ?? '',
                                    index: index,
                                    selected: state.selectedImagePaths.contains(
                                      path,
                                    ),
                                    onTap: () => cubit.toggleImage(path),
                                  ),
                                  index,
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
        Positioned(
          bottom: 8 + bottomInset,
          left: 8,
          right: 8,
          child: IgnorePointer(
            ignoring: !hasSelection,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              offset: hasSelection ? Offset.zero : const Offset(0, 1),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                opacity: hasSelection ? 1 : 0,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: t.comicEdit.clearSelection,
                                onPressed: cubit.clearSelection,
                                icon: const Icon(Icons.close),
                              ),
                              Text(
                                t.comicEdit.selectedCount(
                                  count: state.selectedImagePaths.length,
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: state.busy
                                    ? null
                                    : cubit.selectAllImages,
                                child: Text(t.comicEdit.selectAll),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: t.common.delete,
                                onPressed: state.busy
                                    ? null
                                    : () => _deleteSelected(
                                        context,
                                        cubit,
                                        state,
                                      ),
                                icon: const Icon(Icons.delete_outline),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: t.comicEdit.moveToChapter,
                                onPressed: state.busy
                                    ? null
                                    : () =>
                                          _moveSelected(context, cubit, state),
                                icon: const Icon(Icons.drive_file_move_outline),
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
        ),
      ],
    );
  }

  Future<void> _deleteSelected(
    BuildContext context,
    ComicEditCubit cubit,
    ComicEditState state,
  ) async {
    final count = state.selectedImagePaths.length;
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.comicEdit.deleteImagesTitle),
        content: Text(t.comicEdit.deleteImagesMessage(count: count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.common.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await cubit.deleteSelectedImages();
  }

  Future<void> _moveSelected(
    BuildContext context,
    ComicEditCubit cubit,
    ComicEditState state,
  ) async {
    final targets = state.chapters
        .where(
          (chapter) => comicEditChapterId(chapter) != state.selectedChapterId,
        )
        .toList();
    if (targets.isEmpty) return;

    final target = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.comicEdit.moveToChapter),
        content: SizedBox(
          width: 380,
          height: 400,
          child: ListView(
            children: [
              for (final chapter in targets)
                ListTile(
                  title: Text(
                    chapter['name']?.toString() ?? t.comicEdit.chapterName,
                  ),
                  subtitle: Text(
                    t.comicEdit.pagesCount(
                      count: ((chapter['images'] as List?) ?? const []).length,
                    ),
                  ),
                  onTap: () =>
                      Navigator.of(context).pop(comicEditChapterId(chapter)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.common.cancel),
          ),
        ],
      ),
    );
    if (target == null) return;
    await cubit.moveSelectedToChapter(target);
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({
    super.key,
    required this.localPath,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final String localPath;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: localPath.isEmpty
                  ? const ColoredBox(
                      color: Colors.black12,
                      child: Icon(Icons.broken_image_outlined),
                    )
                  : Image.file(
                      File(localPath),
                      fit: BoxFit.cover,
                      cacheWidth: 360,
                    ),
            ),
            Positioned(
              left: 4,
              bottom: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ),
            if (selected)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: primary, width: 2),
                  ),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.check_circle, color: primary),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _pickCoverFromComic(
  BuildContext context,
  ComicEditCubit cubit,
  ComicEditState state,
) async {
  final selection = await showDialog<_CoverImageSelection>(
    context: context,
    builder: (context) => _CoverImagePickerDialog(
      from: cubit.from,
      comicId: cubit.comicId,
      chapters: state.chapters,
    ),
  );
  if (selection == null) return;
  await cubit.saveCoverFromImage(selection.chapterId, selection.imagePath);
}

class _CoverImageSelection {
  const _CoverImageSelection({
    required this.chapterId,
    required this.imagePath,
  });

  final String chapterId;
  final String imagePath;
}

class _CoverImagePickerDialog extends StatefulWidget {
  const _CoverImagePickerDialog({
    required this.from,
    required this.comicId,
    required this.chapters,
  });

  final String from;
  final String comicId;
  final List<Map<String, dynamic>> chapters;

  @override
  State<_CoverImagePickerDialog> createState() =>
      _CoverImagePickerDialogState();
}

class _CoverImagePickerDialogState extends State<_CoverImagePickerDialog> {
  String _chapterId = '';
  Future<Map<String, String>> _pathsFuture = Future.value(const {});

  @override
  void initState() {
    super.initState();
    _chapterId = widget.chapters.isEmpty
        ? ''
        : comicEditChapterId(widget.chapters.first);
    _startLoad();
  }

  Map<String, dynamic>? get _chapter {
    for (final chapter in widget.chapters) {
      if (comicEditChapterId(chapter) == _chapterId) return chapter;
    }
    return widget.chapters.isEmpty ? null : widget.chapters.first;
  }

  List<Map<String, dynamic>> get _images {
    final chapter = _chapter;
    if (chapter == null) return const [];
    return ((chapter['images'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((image) => Map<String, dynamic>.from(image))
        .toList();
  }

  void _startLoad() {
    final chapter = _chapter;
    if (chapter == null) {
      _pathsFuture = Future.value(const {});
      return;
    }
    _pathsFuture = _resolvePaths(chapter);
  }

  Future<Map<String, String>> _resolvePaths(
    Map<String, dynamic> chapter,
  ) async {
    final storageId = comicEditChapterStorageId(chapter);
    final images = ((chapter['images'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((image) => Map<String, dynamic>.from(image))
        .toList();
    final pool = Pool(8);
    try {
      final entries = await Future.wait(
        images.map(
          (image) => pool.withResource(() async {
            final path = image['path']?.toString() ?? '';
            var local = '';
            if (path.isNotEmpty) {
              try {
                final resolver = debugComicEditImagePathResolver;
                if (resolver != null) {
                  local = await resolver(
                    from: widget.from,
                    comicId: widget.comicId,
                    storageChapterId: storageId,
                    path: path,
                  );
                } else {
                  final store = DownloadAssetStore(
                    from: widget.from,
                    path: path,
                    cartoonId: widget.comicId,
                    chapterId: '',
                    storageChapterId: storageId,
                    pictureType: PictureType.page,
                  );
                  final existing = await store.findExistingDownload();
                  local = existing?.path ?? '';
                }
              } catch (_) {}
            }
            return MapEntry(path, local);
          }),
        ),
      );
      return Map.fromEntries(entries);
    } finally {
      await pool.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final images = _images;
    return AlertDialog(
      title: Text(t.comicEdit.chooseCoverImage),
      content: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey(_chapterId),
              initialValue: _chapterId,
              decoration: InputDecoration(
                labelText: t.comicEdit.selectChapter,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: widget.chapters.map((chapter) {
                final id = comicEditChapterId(chapter);
                final name = chapter['name']?.toString() ?? '';
                return DropdownMenuItem<String>(
                  value: id,
                  child: Text(
                    name.isEmpty ? t.comicEdit.chapterName : name,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _chapterId = value;
                  _startLoad();
                });
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: images.isEmpty
                  ? Center(child: Text(t.comicEdit.emptyChapter))
                  : FutureBuilder<Map<String, String>>(
                      future: _pathsFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final paths = snapshot.data ?? const <String, String>{};
                        return GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 140,
                                mainAxisSpacing: 6,
                                crossAxisSpacing: 6,
                                childAspectRatio: 0.68,
                              ),
                          itemCount: images.length,
                          itemBuilder: (context, index) {
                            final image = images[index];
                            final path = image['path']?.toString() ?? '';
                            final local = paths[path] ?? '';
                            return InkWell(
                              onTap: () => Navigator.of(context).pop(
                                _CoverImageSelection(
                                  chapterId: _chapterId,
                                  imagePath: path,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: local.isEmpty
                                    ? const ColoredBox(
                                        color: Colors.black12,
                                        child: Icon(
                                          Icons.broken_image_outlined,
                                        ),
                                      )
                                    : Image.file(
                                        File(local),
                                        fit: BoxFit.cover,
                                        cacheWidth: 280,
                                      ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.common.cancel),
        ),
      ],
    );
  }
}

Future<void> _pickCover(ComicEditCubit cubit) async {
  const typeGroup = XTypeGroup(
    label: 'images',
    extensions: <String>['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
  );
  final file = await openFile(acceptedTypeGroups: [typeGroup]);
  if (file == null) return;
  await cubit.saveCover(File(file.path));
}

Future<void> _renameChapter(
  BuildContext context,
  ComicEditCubit cubit,
  Map<String, dynamic> chapter,
) async {
  final value = await _showNameDialog(
    context,
    title: t.comicEdit.renameChapter,
    hint: t.comicEdit.chapterNameHint,
    initial: chapter['name']?.toString() ?? '',
  );
  if (value == null) return;
  await cubit.renameChapter(comicEditChapterId(chapter), value);
}

Future<void> _addChapter(
  BuildContext context,
  ComicEditCubit cubit, {
  VoidCallback? onAdded,
}) async {
  final value = await _showNameDialog(
    context,
    title: t.comicEdit.addChapter,
    hint: t.comicEdit.addChapterHint,
  );
  if (value == null) return;
  await cubit.addChapter(value);
  onAdded?.call();
}

Future<String?> _showNameDialog(
  BuildContext context, {
  required String title,
  required String hint,
  String initial = '',
}) async {
  var value = initial;
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextFormField(
        initialValue: initial,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onChanged: (next) => value = next,
        onFieldSubmitted: (next) => Navigator.of(context).pop(next),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.common.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(value),
          child: Text(t.common.ok),
        ),
      ],
    ),
  );
}
