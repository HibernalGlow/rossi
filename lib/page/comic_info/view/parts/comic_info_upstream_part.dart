// ignore_for_file: invalid_use_of_protected_member
part of '../comic_info.dart';

extension _ComicInfoUpstreamPart on _ComicInfoState {
  String get _readChapterComicKey => '${widget.from.trim()}:${_comicId.trim()}';

  void _onReadChaptersChanged(String comicKey) {
    if (!mounted) return;
    if (comicKey != _readChapterComicKey) return;
    _reloadReadChapters();
  }

  void _reloadReadChapters() {
    final ids = ComicReadChapterRepository.instance.readChapterIds(
      source: widget.from,
      comicId: _comicId,
    );
    if (!mounted) return;
    setState(() {
      _readChapterKey = _readChapterComicKey;
      _readChapterIds = ids;
    });
  }

  /// 首次进入/切换漫画时同步加载已读集合；build 期只读，不触发 setState。
  void _loadReadChaptersIfNeeded() {
    final key = _readChapterComicKey;
    if (key == _readChapterKey) return;
    _readChapterKey = key;
    _readChapterIds = ComicReadChapterRepository.instance.readChapterIds(
      source: widget.from,
      comicId: _comicId,
    );
  }

  // 编辑逻辑
  Future<void> _handleEdit() async {
    const service = ComicEditService();
    if (service.hasIncompleteDownload(widget.from, _comicId)) {
      showErrorToast(t.comicEdit.lockedMessage);
      return;
    }

    await context.pushRoute(
      ComicEditRoute(from: widget.from, comicId: _comicId),
    );
    if (!mounted) return;
    context.read<GetComicInfoBloc>().add(
      GetComicInfoEvent(
        comicId: _comicId,
        from: widget.from,
        type: _type,
        extern: widget.extern,
      ),
    );
  }

  // 导出逻辑
  Future<void> _handleExport() async {
    try {
      if (!mounted) return;

      // iOS 不提供「导出后删除」：分享面板返回时文件是否已存下来并不可知。
      final choice = Platform.isIOS
          ? const ExportChoice(type: ExportType.zip, deleteAfterExport: false)
          : await showExportChoiceDialog(
              context,
              title: t.comicInfo.exportTitle,
              subtitle: t.comicInfo.exportSubtitle,
            );
      if (choice == null) return;
      final exportType = choice.type;

      final exportDir = await _resolveExportDirectory();
      if (exportDir == null) return;

      final zipFileName = _buildZipFileName();
      final targetZipPath = p.join(exportDir, zipFileName);

      if (Platform.isIOS) {
        // 不写入 cacheZipPath：open_file 在分享面板弹出后即返回，
        // finally 里删除会导致用户还没保存文件就被删掉。
        final iosZipPath = targetZipPath;
        final iosZipFile = File(iosZipPath);
        if (await iosZipFile.exists()) {
          await iosZipFile.delete();
        }

        await exportComic(
          _comicId,
          ExportType.zip,
          widget.from,
          path: iosZipPath,
        );

        // 弹出系统分享面板，用户可「存储到文件」
        await OpenFile.open(iosZipPath);
        showSuccessToast(t.comicInfo.exportSuccess);
        _logExportPath(iosZipPath);
        return;
      }

      final exportPath = exportType == ExportType.zip
          ? targetZipPath
          : exportDir;

      final result = await exportComicAndMaybeDelete(
        comicId: _comicId,
        type: exportType,
        from: widget.from,
        path: exportPath,
        deleteAfterExport: choice.deleteAfterExport,
      );
      _logExportPath(result.export.path);
      _showExportOutcome(result, exportType: exportType);
      if (result.deleted && _type == ComicEntryType.download && mounted) {
        actionBack(context);
      }
    } catch (e) {
      final errorMessage = e is StateError
          ? e.message.toString()
          : t.comicInfo.exportFailedWithError(
              error: normalizeSearchErrorMessage(e),
            );
      showErrorToast(errorMessage, duration: const Duration(seconds: 5));
    }
  }
}
