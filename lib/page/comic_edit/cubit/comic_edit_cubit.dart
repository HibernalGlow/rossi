import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/comic_edit/method/comic_edit_document.dart';
import 'package:zephyr/page/comic_edit/method/comic_edit_service.dart';
import 'package:zephyr/widgets/toast.dart';

class ComicEditState {
  const ComicEditState({
    this.loading = true,
    this.busy = false,
    this.locked = false,
    this.error = '',
    this.record,
    this.document,
    this.selectedChapterId = '',
    this.selectedImagePaths = const <String>{},
  });

  final bool loading;
  final bool busy;
  final bool locked;
  final String error;
  final UnifiedComicDownload? record;
  final ComicEditDocument? document;
  final String selectedChapterId;
  final Set<String> selectedImagePaths;

  List<Map<String, dynamic>> get chapters =>
      document?.chapterMaps ?? const <Map<String, dynamic>>[];

  String get title => document?.title ?? record?.title ?? '';

  Map<String, dynamic> get cover =>
      document?.cover ?? const <String, dynamic>{};

  Map<String, dynamic>? get selectedChapter {
    final id = selectedChapterId;
    for (final chapter in chapters) {
      if (comicEditChapterId(chapter) == id) return chapter;
    }
    return chapters.isEmpty ? null : chapters.first;
  }

  List<Map<String, dynamic>> get selectedImages {
    final chapter = selectedChapter;
    if (chapter == null) return const <Map<String, dynamic>>[];
    return ((chapter['images'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((image) => Map<String, dynamic>.from(image))
        .toList();
  }

  ComicEditState copyWith({
    bool? loading,
    bool? busy,
    bool? locked,
    String? error,
    UnifiedComicDownload? record,
    ComicEditDocument? document,
    String? selectedChapterId,
    Set<String>? selectedImagePaths,
  }) {
    return ComicEditState(
      loading: loading ?? this.loading,
      busy: busy ?? this.busy,
      locked: locked ?? this.locked,
      error: error ?? this.error,
      record: record ?? this.record,
      document: document ?? this.document,
      selectedChapterId: selectedChapterId ?? this.selectedChapterId,
      selectedImagePaths: selectedImagePaths ?? this.selectedImagePaths,
    );
  }
}

class ComicEditCubit extends Cubit<ComicEditState> {
  ComicEditCubit({required this.from, required this.comicId})
    : super(const ComicEditState());

  final String from;
  final String comicId;

  static const _service = ComicEditService();

  Future<void> load() async {
    emit(state.copyWith(loading: true, error: ''));
    try {
      final record = _service.findRecord(from, comicId);
      if (record == null) {
        emit(state.copyWith(loading: false, error: t.comicEdit.notFound));
        return;
      }
      if (_service.hasIncompleteDownload(from, comicId)) {
        emit(state.copyWith(loading: false, locked: true, record: record));
        return;
      }
      final document = _service.loadDocument(record);
      emit(
        state.copyWith(
          loading: false,
          locked: false,
          record: record,
          document: document,
          selectedChapterId: _resolveSelectedChapter(
            document,
            state.selectedChapterId,
          ),
          selectedImagePaths: const <String>{},
        ),
      );
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  Future<void> saveTitle(String value) async {
    if (value.trim().isEmpty) {
      emit(state.copyWith(error: t.comicEdit.titleEmpty));
      return;
    }
    await _run(
      () => _service.updateTitle(from: from, comicId: comicId, title: value),
      successMessage: t.comicEdit.saveSuccess,
    );
  }

  Future<void> saveCover(File file) {
    return _run(
      () => _service.updateCover(from: from, comicId: comicId, source: file),
      successMessage: t.comicEdit.coverUpdated,
    );
  }

  Future<void> saveCoverFromImage(String chapterId, String imagePath) {
    return _run(
      () => _service.updateCoverFromImage(
        from: from,
        comicId: comicId,
        chapterId: chapterId,
        imagePath: imagePath,
      ),
      successMessage: t.comicEdit.coverUpdated,
    );
  }

  Future<void> renameChapter(String chapterId, String name) async {
    if (name.trim().isEmpty) {
      emit(state.copyWith(error: t.comicEdit.chapterNameEmpty));
      return;
    }
    await _run(
      () => _service.renameChapter(
        from: from,
        comicId: comicId,
        chapterId: chapterId,
        name: name,
      ),
      successMessage: t.comicEdit.chapterRenamed,
    );
  }

  Future<void> addChapter(String name) async {
    if (name.trim().isEmpty) {
      emit(state.copyWith(error: t.comicEdit.chapterNameEmpty));
      return;
    }
    await _run(
      () => _service.addChapter(from: from, comicId: comicId, name: name),
      successMessage: t.comicEdit.chapterAdded,
      selectChapter: (document) => document.chapterMaps.isEmpty
          ? ''
          : comicEditChapterId(document.chapterMaps.last),
    );
  }

  Future<void> reorderChapters(int oldIndex, int newIndex) async {
    final chapters = state.chapters;
    if (oldIndex < 0 || oldIndex >= chapters.length) return;
    if (newIndex < 0 || newIndex >= chapters.length) return;

    final ordered = chapters.map(comicEditChapterId).toList();
    final moved = ordered.removeAt(oldIndex);
    ordered.insert(newIndex, moved);

    final document = state.document;
    if (document == null) return;
    emit(state.copyWith(document: document.reorderChapters(ordered)));
    await _run(
      () => _service.reorderChapters(
        from: from,
        comicId: comicId,
        orderedChapterIds: ordered,
      ),
    );
    if (state.error.isNotEmpty) {
      await load();
    }
  }

  void selectChapter(String chapterId) {
    emit(
      state.copyWith(
        selectedChapterId: chapterId,
        selectedImagePaths: const <String>{},
      ),
    );
  }

  void toggleImage(String path) {
    final next = Set<String>.from(state.selectedImagePaths);
    if (!next.add(path)) {
      next.remove(path);
    }
    emit(state.copyWith(selectedImagePaths: next));
  }

  void selectAllImages() {
    final paths = state.selectedImages
        .map((image) => image['path']?.toString() ?? '')
        .where((path) => path.isNotEmpty)
        .toSet();
    emit(state.copyWith(selectedImagePaths: paths));
  }

  void clearSelection() {
    emit(state.copyWith(selectedImagePaths: const <String>{}));
  }

  Future<void> reorderImages(List<String> orderedPaths) async {
    final document = state.document;
    if (document == null) return;
    final optimistic = document.reorderImages(
      state.selectedChapterId,
      orderedPaths,
    );
    emit(
      state.copyWith(
        document: optimistic,
        selectedImagePaths: const <String>{},
      ),
    );
    await _run(
      () => _service.reorderImages(
        from: from,
        comicId: comicId,
        chapterId: state.selectedChapterId,
        orderedPaths: orderedPaths,
      ),
    );
    if (state.error.isNotEmpty) {
      await load();
    }
  }

  Future<void> deleteSelectedImages() async {
    final paths = state.selectedImagePaths.toList();
    if (paths.isEmpty) return;
    final chapterId = state.selectedChapterId;
    await _run(
      () => _service.deleteImages(
        from: from,
        comicId: comicId,
        chapterId: chapterId,
        imagePaths: paths,
      ),
      successMessage: t.comicEdit.deletedCount(count: paths.length),
    );
  }

  Future<void> moveSelectedToChapter(String targetChapterId) async {
    final paths = state.selectedImagePaths.toList();
    if (paths.isEmpty) return;
    final sourceChapterId = state.selectedChapterId;
    await _run(
      () => _service.moveImages(
        from: from,
        comicId: comicId,
        sourceChapterId: sourceChapterId,
        targetChapterId: targetChapterId,
        imagePaths: paths,
      ),
      successMessage: t.comicEdit.movedCount(count: paths.length),
      selectChapter: (_) => targetChapterId,
    );
  }

  Future<void> _run(
    Future<ComicEditDocument> Function() action, {
    String? successMessage,
    String Function(ComicEditDocument document)? selectChapter,
  }) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, error: ''));
    try {
      final document = await action();
      final record = _service.findRecord(from, comicId);
      final selectedChapterId =
          selectChapter?.call(document) ??
          _resolveSelectedChapter(document, state.selectedChapterId);
      emit(
        state.copyWith(
          busy: false,
          record: record,
          document: document,
          selectedChapterId: selectedChapterId,
          selectedImagePaths: const <String>{},
        ),
      );
      if (successMessage != null) {
        showSuccessToast(successMessage);
      }
    } on ComicEditLockedException {
      emit(state.copyWith(busy: false, locked: true));
    } catch (e) {
      emit(state.copyWith(busy: false, error: e.toString()));
    }
  }

  String _resolveSelectedChapter(ComicEditDocument document, String current) {
    final chapters = document.chapterMaps;
    if (chapters.isEmpty) return '';
    for (final chapter in chapters) {
      if (comicEditChapterId(chapter) == current) return current;
    }
    return comicEditChapterId(chapters.first);
  }
}
