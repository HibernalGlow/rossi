part of '../file_manager_card.dart';

// 从 class _FileManagerCardState 搬出的方法组；extension 与宿主类同库，可直接访问私有成员。
extension _FileManagerCardViewPart on _FileManagerCardState {
  Widget _buildInlineError(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 15,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 15),
            visualDensity: VisualDensity.compact,
            // ignore: invalid_use_of_protected_member
            onPressed: () => setState(() => _error = null),
          ),
        ],
      ),
    );
  }
  /// 封面列表的第二行带修改日期，横幅那一行不带 —— 沿用原来两档各自的写法。
  ///
  /// 搜索结果里的同名条目只能靠**来自哪个子目录**区分，所以那段相对路径排在
  /// 副标题最前面；普通浏览时它是 null，不会出现。
  String _subtitle(FileManagerEntry entry, LibraryViewMode mode) {
    final type = _formatType(entry);
    final hasSize = !entry.isDir && entry.size > BigInt.zero;
    final searchDirectory = entry.searchDirectory;
    final buffer = StringBuffer();
    if (searchDirectory != null && searchDirectory.isNotEmpty) {
      buffer.write('$searchDirectory · ');
    }
    if (mode != LibraryViewMode.coverList) {
      buffer.write(hasSize ? '$type · ${_formatSize(entry.size)}' : type);
      return buffer.toString();
    }
    buffer.write(type);
    if (hasSize) buffer.write(' · ${_formatSize(entry.size)}');
    if (entry.modifiedSecs.toInt() > 0) {
      buffer.write(' · ${_formatDate(entry.modifiedSecs.toInt())}');
    }
    return buffer.toString();
  }
  Widget? _trailing(
    BuildContext context,
    FileManagerEntry entry,
    LibraryViewMode mode,
  ) {
    if (mode == LibraryViewMode.compact) {
      if (!entry.isDir) return null;
      return IconButton(
        icon: const Icon(Icons.folder_open_rounded, size: 16),
        tooltip: '进入文件夹',
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        onPressed: _busy ? null : () => _openEntry(entry, forceEnter: true),
      );
    }
    if (mode == LibraryViewMode.coverList) {
      if (entry.isDir) {
        return IconButton(
          icon: const Icon(Icons.folder_open_rounded, size: 18),
          tooltip: '进入文件夹',
          visualDensity: VisualDensity.compact,
          onPressed: _busy ? null : () => _openEntry(entry, forceEnter: true),
        );
      }
      return const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Icon(Icons.play_circle_outline_rounded, size: 18),
      );
    }
    return null;
  }
  LibrarySubLine _subLine(FileManagerChild child) {
    return LibrarySubLine(
      label: child.name,
      icon: child.isDir
          ? Icons.folder_outlined
          : Icons.subdirectory_arrow_right,
      onTap: _busy ? null : () => _openChild(child),
      onDoubleTap: child.isArchive && !_busy
          ? () => _openArchiveChild(child)
          : null,
    );
  }
  /// 语义图标不带尺寸：每档视图要多大由 `LibraryViewLayout.badgeSize` 决定。
  Widget _semanticIcon(BuildContext context, FileManagerEntry entry) {
    final colors = Theme.of(context).colorScheme;
    final (IconData icon, Color color) = switch (entry) {
      _ when entry.isDir => (Icons.folder_rounded, colors.primary),
      _ when entry.isArchive => (Icons.auto_stories_rounded, colors.primary),
      _ when entry.isImage => (Icons.image_outlined, colors.secondary),
      _ when entry.isVideo => (Icons.movie_outlined, colors.secondary),
      _ when entry.isAudio => (Icons.audio_file_outlined, colors.secondary),
      _ => (Icons.insert_drive_file_outlined, colors.outline),
    };
    return Icon(icon, color: color);
  }
  Future<void> _toggleSort(
    FileManagerSnapshot snapshot,
    FileManagerSortField field,
  ) async {
    final order =
        snapshot.sortField == field &&
            snapshot.sortOrder == FileManagerSortOrder.ascending
        ? FileManagerSortOrder.descending
        : FileManagerSortOrder.ascending;
    await _apply(
      (id) => fileManagerSetSort(id: id, field: field, order: order),
    );
  }
  String _formatDate(int secs) {
    if (secs <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
    final year = dt.year.toString();
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$year/$month/$day $hour:$min';
  }
  String _formatType(FileManagerEntry entry) {
    if (entry.isDir) return '文件夹';
    final lower = entry.name.toLowerCase();
    if (entry.isArchive) {
      if (lower.endsWith('.zip')) return 'ZIP 归档';
      if (lower.endsWith('.cbz')) return 'CBZ 归档';
      if (lower.endsWith('.rar')) return 'RAR 归档';
      if (lower.endsWith('.cbr')) return 'CBR 归档';
      if (lower.endsWith('.7z')) return '7Z 归档';
      if (lower.endsWith('.tar') || lower.endsWith('.tar.gz')) return 'TAR 归档';
      return '压缩归档';
    }
    if (entry.isImage) return '图片';
    if (entry.isVideo) return '视频';
    if (entry.isAudio) return '音频';
    final dot = entry.name.lastIndexOf('.');
    if (dot != -1 && dot < entry.name.length - 1) {
      return '${entry.name.substring(dot + 1).toUpperCase()} 文件';
    }
    return '文件';
  }
  String _formatSize(BigInt bytes) {
    if (bytes <= BigInt.zero) return '';
    const suffixes = ['B', 'KiB', 'MiB', 'GiB'];
    var index = 0;
    var value = bytes.toDouble();
    while (value >= 1024 && index < suffixes.length - 1) {
      value /= 1024;
      index++;
    }
    return '${value.toStringAsFixed(index == 0 ? 0 : 1)} ${suffixes[index]}';
  }
}
