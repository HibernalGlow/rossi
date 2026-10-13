part of '../file_manager_card.dart';

// 从 class _FileManagerCardState 搬出的方法组；extension 与宿主类同库，可直接访问私有成员。
extension _FileManagerCardOpenPart on _FileManagerCardState {
  Future<void> _openEntry(
    FileManagerEntry entry, {
    bool forceEnter = false,
  }) async {
    await _openAction(
      (id) => fileManagerOpenEntry(
        id: id,
        path: entry.path,
        forceEnter: forceEnter,
      ),
      requestedPath: entry.path,
    );
  }

  Future<void> _openArchive(FileManagerEntry entry) async {
    if (!entry.isArchive) return;
    await _openAction((id) => fileManagerOpenArchive(id: id, path: entry.path));
  }

  /// 双击一行。压缩包交给「不动位置直接开」的归档动作；目录只在**单击会被穿透劫走**
  /// 的那些行才轮得到双击（`canDoubleTap` 已按核心的 `penetratable` 夹过），所以这里
  /// 走核心的 `force_enter`，把「进这一层」还回来。
  Future<void> _onEntryDoubleTap(FileManagerEntry entry) =>
      entry.isDir ? _openEntry(entry, forceEnter: true) : _openArchive(entry);
  Future<void> _openAction(
    Future<FileManagerActionResult> Function(BigInt id) action, {
    String? requestedPath,
  }) async {
    final id = _sessionId;
    if (id == null || _busy) return;
    _cancelPendingSearch();
    final serial = ++_requestSerial;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await action(id);
      if (!mounted || serial != _requestSerial) return;
      // ignore: invalid_use_of_protected_member
      setState(() {
        _acceptSnapshot(result.snapshot);
      });
      final openedPath = result.openedPath;
      if (openedPath != null && mounted && serial == _requestSerial) {
        // Keep the card busy while the reader route is on top. This makes the
        // second pointer-up of a double-click unable to enqueue another route.
        // 核心把松散图片解析成了它所在的目录，此时点的哪一张只有这里知道。
        final entryHint = requestedPath != null && requestedPath != openedPath
            ? p.basename(requestedPath)
            : null;
        await _openReader(openedPath, result.bookNavigationJson, entryHint);
      }
      if (!mounted || serial != _requestSerial) return;
      // ignore: invalid_use_of_protected_member
      setState(() => _busy = false);
    } catch (error) {
      if (!mounted || serial != _requestSerial) return;
      _showError(error);
    }
  }

  Future<void> _openChild(FileManagerChild child) async {
    await _openEntry(_entryFromChild(child));
  }

  Future<void> _openArchiveChild(FileManagerChild child) async {
    if (!child.isArchive) return;
    await _openArchive(_entryFromChild(child));
  }

  FileManagerEntry _entryFromChild(FileManagerChild child) {
    return FileManagerEntry(
      path: child.path,
      name: child.name,
      isDir: child.isDir,
      isArchive: child.isArchive,
      isImage: child.isImage,
      isVideo: child.isVideo,
      isAudio: child.isAudio,
      size: BigInt.zero,
      modifiedSecs: 0,
      hasChildren: false,
      // 子行是核心的投影，不是列表里的一行：它没有「这一层会不会被穿透」的判决，
      // 所以这一族行不挂双击（与搜索命中页签同一口径）。
      penetratable: false,
      childNames: const [],
    );
  }

  Future<void> _openReader(
    String path,
    String? navigationJson,
    String? entryHint,
  ) async {
    if (!mounted) return;
    await context.pushRoute(
      ComicReadRoute(
        comicId: path,
        order: 0,
        from: 'local_file_manager',
        epsNumber: 1,
        type: ComicEntryType.normal,
        comicInfo: path,
        chapterExtern: {
          LocalBookNavigationController.contextKey: ?navigationJson,
          LocalBookNavigationController.entryHintKey: ?entryHint,
        },
        stringSelectCubit: StringSelectCubit(),
      ),
    );
  }
}
