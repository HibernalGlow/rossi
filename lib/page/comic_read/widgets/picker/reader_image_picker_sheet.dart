import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/network/http/picture/picture.dart';
import 'package:zephyr/page/comic_info/method/get_plugin_detail.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/widgets/picker/reader_image_export_service.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/widgets/full_screen_image_view.dart';
import 'package:zephyr/widgets/toast.dart';

Future<void> showReaderImagePickerSheet(
  BuildContext context, {
  required String from,
  required String comicId,
  required String comicTitle,
  dynamic comicInfo,
  List<Doc>? docs,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return _ReaderImagePickerSheet(
        from: from,
        comicId: comicId,
        comicTitle: comicTitle,
        comicInfo: comicInfo,
        initialDocs: docs,
      );
    },
  );
}

class _ReaderImagePickerSheet extends StatefulWidget {
  final String from;
  final String comicId;
  final String comicTitle;
  final dynamic comicInfo;
  final List<Doc>? initialDocs;

  const _ReaderImagePickerSheet({
    required this.from,
    required this.comicId,
    required this.comicTitle,
    this.comicInfo,
    this.initialDocs,
  });

  @override
  State<_ReaderImagePickerSheet> createState() =>
      _ReaderImagePickerSheetState();
}

class _ReaderImagePickerSheetState extends State<_ReaderImagePickerSheet> {
  List<ReaderImageExportItem> _items = [];
  final Set<int> _selectedIndices = {};
  bool _isLoading = true;
  bool _isProcessing = false;
  int _processCurrent = 0;
  int _processTotal = 0;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    try {
      List<Doc> docs = widget.initialDocs ?? [];
      if (docs.isEmpty) {
        // 尝试从漫画详情中解析首话或全部页面
        final detail = await getComicDetailByPlugin(
          widget.comicId,
          widget.from,
          pluginId: widget.from,
        );
        final chapters = detail.normalInfo.eps;
        if (chapters.isNotEmpty) {
          final firstChapter = chapters.first;
          final chapterRes = await getComicChapterByPlugin(
            widget.comicId,
            firstChapter.requestId.isNotEmpty
                ? firstChapter.requestId
                : firstChapter.id,
            widget.from,
            pluginId: widget.from,
          );
          docs = chapterRes.chapter.docs
              .map(
                (d) => Doc(
                  originalName: d.name,
                  path: d.path,
                  fileServer: d.url,
                  id: d.id,
                  storageChapterId: '',
                  extern: d.extern,
                ),
              )
              .toList();
        }
      }

      final items = <ReaderImageExportItem>[];
      for (var i = 0; i < docs.length; i++) {
        final doc = docs[i];
        items.add(
          ReaderImageExportItem(
            index: i + 1,
            title: doc.originalName.isNotEmpty
                ? doc.originalName
                : '第 ${i + 1} 页',
            doc: doc,
            from: widget.from,
            comicId: widget.comicId,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _items = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      logger.e('加载选图列表失败', error: e);
      if (mounted) {
        setState(() => _isLoading = false);
        showErrorToast(t.error.loadFailed);
      }
    }
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedIndices.length == _items.length) {
        _selectedIndices.clear();
      } else {
        _selectedIndices.addAll(_items.map((e) => e.index));
      }
    });
  }

  void _invertSelection() {
    setState(() {
      final allIndices = _items.map((e) => e.index).toSet();
      final inverted = allIndices.difference(_selectedIndices);
      _selectedIndices
        ..clear()
        ..addAll(inverted);
    });
  }

  Future<void> _showRangeSelectDialog() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.reader.rangeSelect),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.reader.rangeSelectPrompt,
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.text,
              decoration: const InputDecoration(
                hintText: '1-5, 8, 12-15',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.common.confirm),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final input = controller.text.trim();
      final parsed = _parseRangeInput(input, _items.length);
      if (parsed.isNotEmpty) {
        setState(() {
          _selectedIndices.addAll(parsed);
        });
      }
    }
  }

  Set<int> _parseRangeInput(String input, int maxIndex) {
    final result = <int>{};
    final parts = input.split(RegExp(r'[,，\s]+'));
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.contains('-')) {
        final rangeParts = trimmed.split('-');
        if (rangeParts.length == 2) {
          final start = int.tryParse(rangeParts[0].trim());
          final end = int.tryParse(rangeParts[1].trim());
          if (start != null && end != null) {
            final from = start < end ? start : end;
            final to = start < end ? end : start;
            for (var i = from; i <= to; i++) {
              if (i >= 1 && i <= maxIndex) result.add(i);
            }
          }
        }
      } else {
        final single = int.tryParse(trimmed);
        if (single != null && single >= 1 && single <= maxIndex) {
          result.add(single);
        }
      }
    }
    return result;
  }

  Future<void> _executeExport(ReaderExportAction action) async {
    final selectedItems = _items
        .where((item) => _selectedIndices.contains(item.index))
        .toList();
    if (selectedItems.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _processCurrent = 0;
      _processTotal = selectedItems.length;
    });

    try {
      await ReaderImageExportService.exportImages(
        context: context,
        items: selectedItems,
        action: action,
        comicTitle: widget.comicTitle,
        onProgress: (cur, tot) {
          if (mounted) {
            setState(() {
              _processCurrent = cur;
              _processTotal = tot;
            });
          }
        },
      );
    } catch (e) {
      logger.e('执行导出失败', error: e);
      if (mounted) {
        showErrorToast(t.reader.extractFailed(error: e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.9;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 820,
              maxHeight: maxHeight,
            ),
            child: Material(
              color: colorScheme.surface,
              elevation: 8,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(context),
                  const Divider(height: 1),
                  Flexible(
                    child: _isLoading
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : _buildGrid(context),
                  ),
                  const Divider(height: 1),
                  _buildBottomBar(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isAllSelected =
        _items.isNotEmpty && _selectedIndices.length == _items.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          const Icon(Icons.checklist_rounded, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t.reader.pickAndExtract,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  t.reader.selectedCount(
                    selected: _selectedIndices.length,
                    total: _items.length,
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: isAllSelected ? t.reader.deselectAll : t.reader.selectAll,
            icon: Icon(
              isAllSelected
                  ? Icons.check_box_rounded
                  : Icons.select_all_rounded,
            ),
            onPressed: _items.isEmpty ? null : _toggleSelectAll,
          ),
          IconButton(
            tooltip: t.reader.invertSelection,
            icon: const Icon(Icons.flip_rounded),
            onPressed: _items.isEmpty ? null : _invertSelection,
          ),
          IconButton(
            tooltip: t.reader.rangeSelect,
            icon: const Icon(Icons.tune_rounded),
            onPressed: _items.isEmpty ? null : _showRangeSelectDialog,
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(t.download.noTasks),
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 600 ? 5 : 3;

    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.72,
      ),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        final isSelected = _selectedIndices.contains(item.index);

        return _PickerTile(
          item: item,
          isSelected: isSelected,
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedIndices.remove(item.index);
              } else {
                _selectedIndices.add(item.index);
              }
            });
          },
          onLongPress: () async {
            // 长按大图预览
            final navigator = Navigator.of(context);
            try {
              final path = await getCachePicture(
                from: item.from,
                url: item.doc.fileServer,
                path: item.doc.path,
                cartoonId: item.comicId,
                chapterId: item.doc.id,
                storageChapterId: item.doc.storageChapterId,
                pictureType: PictureType.page,
                extern: item.doc.extern,
                usePlugin: true,
              );
              if (path.isNotEmpty && path != '404' && mounted) {
                navigator.push(
                  MaterialPageRoute(
                    builder: (_) => FullScreenImagePage(imagePath: path),
                  ),
                );
              }
            } catch (e) {
              logger.w('预览大图失败', error: e);
            }
          },
        );
      },
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final hasSelection = _selectedIndices.isNotEmpty;

    if (_isProcessing) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t.reader.extractingProgress(
                current: _processCurrent,
                total: _processTotal,
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _processTotal > 0 ? _processCurrent / _processTotal : null,
            ),
          ],
        ),
      );
    }

    final isMobile = Platform.isAndroid || Platform.isIOS;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        alignment: WrapAlignment.end,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(t.reader.downloadSelected),
            onPressed: hasSelection
                ? () => _executeExport(ReaderExportAction.downloadSelected)
                : null,
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.archive_outlined, size: 18),
            label: Text(t.reader.exportZip),
            onPressed: hasSelection
                ? () => _executeExport(ReaderExportAction.exportZip)
                : null,
          ),
          FilledButton.icon(
            icon: Icon(
              isMobile
                  ? Icons.photo_library_outlined
                  : Icons.folder_open_outlined,
              size: 18,
            ),
            label: Text(
              isMobile ? t.reader.saveToAlbum : t.reader.saveToDirectory,
            ),
            onPressed: hasSelection
                ? () => _executeExport(ReaderExportAction.saveToAlbum)
                : null,
          ),
        ],
      ),
    );
  }
}

class _PickerTile extends StatefulWidget {
  final ReaderImageExportItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PickerTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_PickerTile> createState() => _PickerTileState();
}

class _PickerTileState extends State<_PickerTile> {
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _resolveThumbnail();
  }

  Future<void> _resolveThumbnail() async {
    try {
      final path = await getCachePicture(
        from: widget.item.from,
        url: widget.item.doc.fileServer,
        path: widget.item.doc.path,
        cartoonId: widget.item.comicId,
        chapterId: widget.item.doc.id,
        storageChapterId: widget.item.doc.storageChapterId,
        pictureType: PictureType.page,
        extern: widget.item.doc.extern,
        usePlugin: true,
      );
      if (mounted && path.isNotEmpty && path != '404') {
        setState(() {
          _localPath = path;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = widget.isSelected;

    return InkWell(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.dividerColor.withValues(alpha: 0.4),
            width: isSelected ? 2.5 : 1,
          ),
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_localPath != null && File(_localPath!).existsSync())
              Image.file(
                File(_localPath!),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
              )
            else
              const Center(
                child: Icon(Icons.image_outlined, size: 28, color: Colors.grey),
              ),
            if (isSelected)
              Container(
                color: theme.colorScheme.primary.withValues(alpha: 0.22),
              ),
            // 页码角标
            Positioned(
              left: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '#${widget.item.index}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            // 勾选图标
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.black.withValues(alpha: 0.4),
                ),
                padding: const EdgeInsets.all(2),
                child: Icon(
                  isSelected ? Icons.check : Icons.circle_outlined,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
