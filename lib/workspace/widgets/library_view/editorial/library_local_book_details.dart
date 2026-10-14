import 'dart:async';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/comic_info/widgets/comic_inline_details_surface.dart';
import 'package:zephyr/reader/local_page_source.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/service/reader/reader_thumbnail_service.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/i18n/strings.g.dart';

class LibraryLocalBookDetails extends StatefulWidget {
  const LibraryLocalBookDetails({
    super.key,
    required this.entry,
    required this.path,
    required this.onClose,
  });
  final LibraryEntry entry;
  final String path;
  final VoidCallback onClose;
  @override
  State<LibraryLocalBookDetails> createState() =>
      _LibraryLocalBookDetailsState();
}

class _LibraryLocalBookDetailsState extends State<LibraryLocalBookDetails> {
  PageSource? _source;
  String? _error;
  bool _loading = true;
  int _visible = 8;
  final Map<int, Future<Uint8List?>> _thumbnails = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await LocalPageSource.open(widget.path);
      if (!mounted) {
        if (result is PageSourceOpened) await result.source.close();
        return;
      }
      switch (result) {
        case PageSourceOpened(:final source):
          _source = source;
        case PageSourceRejected(:final message):
          _error = message;
      }
    } catch (error) {
      if (!mounted) return;
      _error = '无法加载本地预览：$error';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    if (_source != null) unawaited(_source!.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ComicInlineDetailsSurface(
    onClose: widget.onClose,
    operations: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonalIcon(
          onPressed: widget.entry.onRead,
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          icon: const GlyphIcon(AppGlyphs.openBook),
          label: Text(t.workspace.openReader),
        ),
        TextButton.icon(
          onPressed: () => Clipboard.setData(ClipboardData(text: widget.path)),
          icon: const GlyphIcon(AppGlyphs.copy),
          label: Text(t.workspace.copyPosition),
        ),
      ],
    ),
    metadata: Wrap(
      spacing: 8,
      children: [
        Chip(label: Text(t.workspace.localWorks)),
        if (_source != null) Chip(label: Text('${_source!.pageCount} 页')),
      ],
    ),
    description: SelectableText(
      widget.path,
      style: Theme.of(context).textTheme.bodySmall,
    ),
    preview: ComicInlinePreviewGallery(
      loading: _loading,
      error: _error,
      onRetry: _loading ? null : _load,
      count: _source == null ? 0 : _source!.pageCount.clamp(0, _visible),
      onMore: _source != null && _visible < _source!.pageCount
          ? () => setState(() => _visible += 12)
          : null,
      itemBuilder: (_, index) => FutureBuilder<Uint8List?>(
        future: _thumbnails.putIfAbsent(
          index,
          () => ReaderThumbnailService.instance.getLocalThumbnailBytes(
            source: _source!,
            index: index,
          ),
        ),
        builder: (context, snapshot) => Column(
          children: [
            Expanded(
              child: snapshot.hasData
                  ? Image.memory(snapshot.data!, fit: BoxFit.contain)
                  : Center(
                      child: snapshot.connectionState == ConnectionState.waiting
                          ? const CircularProgressIndicator()
                          : const GlyphIcon(AppGlyphs.brokenImage),
                    ),
            ),
            Text('${index + 1}', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    ),
  );
}
