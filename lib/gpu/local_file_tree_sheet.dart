import 'dart:io';

import 'package:flutter/material.dart';
import 'package:zephyr/src/rust/api/local.dart';

/// 记录最近一次访问的目录路径（应用生命周期内保持），方便连续调试与选漫画。
String? _lastVisitedDirectory;

/// 弹出跨平台本地文件树浏览面板（Modal Bottom Sheet 或弹窗）。
Future<String?> showLocalFileTreeSheet({
  required BuildContext context,
  String? initialPath,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF16161D),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => LocalFileTreePane(
        initialPath: initialPath ?? _lastVisitedDirectory,
        scrollController: scrollController,
        onSelect: (selectedPath) {
          _lastVisitedDirectory = File(selectedPath).parent.path;
          Navigator.of(context).pop(selectedPath);
        },
      ),
    ),
  );
}

class LocalFileTreePane extends StatefulWidget {
  final String? initialPath;
  final ScrollController? scrollController;
  final ValueChanged<String> onSelect;

  const LocalFileTreePane({
    super.key,
    this.initialPath,
    this.scrollController,
    required this.onSelect,
  });

  @override
  State<LocalFileTreePane> createState() => _LocalFileTreePaneState();
}

class _LocalFileTreePaneState extends State<LocalFileTreePane> {
  late List<LocalRootLocation> _roots;
  late String _currentPath;

  bool _loading = false;
  String? _errorMessage;
  List<LocalFileTreeNode> _nodes = [];

  @override
  void initState() {
    super.initState();
    // 同步获取系统根位置与驱动器
    _roots = localGetAvailableRoots();

    // 确定初始路径
    String target = widget.initialPath ?? '';
    if (target.isNotEmpty) {
      final f = File(target);
      if (f.existsSync() && !FileSystemEntity.isDirectorySync(target)) {
        target = f.parent.path;
      }
    }

    if (target.isEmpty || !Directory(target).existsSync()) {
      target = _roots.isNotEmpty ? _roots.first.path : '/';
    }
    _currentPath = target;
    _loadDirectory(_currentPath);
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _currentPath = path;
      _loading = true;
      _errorMessage = null;
    });

    try {
      final items = await localListDirectory(dirPath: path);
      if (mounted) {
        setState(() {
          _nodes = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _nodes = [];
          _loading = false;
        });
      }
    }
  }

  void _goUp() {
    final parent = Directory(_currentPath).parent;
    if (parent.path != _currentPath) {
      _loadDirectory(parent.path);
    }
  }

  String _formatSize(BigInt bytes) {
    if (bytes <= BigInt.zero) return '';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final segments = _currentPath
        .split(Platform.isWindows ? r'\' : '/')
        .where((s) => s.isNotEmpty)
        .toList();

    return Column(
      children: [
        // 顶部抓手条与标题
        Container(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.folder_open_rounded,
                      color: Color(0xFF8B5CF6),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '本地文件树浏览 (mImageViewer 核心)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    // 打开当前文件夹按钮（适用于散图包）
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF38BDF8),
                        side: const BorderSide(color: Color(0xFF0284C7)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('打开当前文件夹'),
                      onPressed: () => widget.onSelect(_currentPath),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: '关闭',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ① 快捷位置标签栏（驱动器 / 挂载卷 / 主目录）
        if (_roots.isNotEmpty)
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _roots.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final r = _roots[index];
                final isSelected = _currentPath.startsWith(r.path);
                return ActionChip(
                  label: Text(r.label),
                  avatar: Icon(
                    r.label.contains('卷') || r.label.contains('磁盘')
                        ? Icons.storage_rounded
                        : Icons.home_rounded,
                    size: 16,
                    color: isSelected
                        ? const Color(0xFF8B5CF6)
                        : Colors.white70,
                  ),
                  backgroundColor: isSelected
                      ? const Color(0xFF2E1065)
                      : const Color(0xFF1E1E28),
                  side: BorderSide(
                    color: isSelected
                        ? const Color(0xFF8B5CF6)
                        : Colors.white12,
                  ),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                  onPressed: () => _loadDirectory(r.path),
                );
              },
            ),
          ),

        const Divider(height: 12, color: Colors.white12),

        // ② 面包屑导航栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          color: const Color(0xFF0F0F14),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                color: Colors.white70,
                tooltip: '上一级',
                onPressed: _goUp,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                color: Colors.white70,
                tooltip: '刷新当前目录',
                onPressed: () => _loadDirectory(_currentPath),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () =>
                            _loadDirectory(Platform.isWindows ? 'C:\\' : '/'),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Icon(
                            Icons.dns_rounded,
                            size: 14,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                      for (int i = 0; i < segments.length; i++) ...[
                        const Icon(
                          Icons.chevron_right,
                          size: 14,
                          color: Colors.white24,
                        ),
                        InkWell(
                          onTap: () {
                            final targetSegs = segments.sublist(0, i + 1);
                            final targetPath =
                                (Platform.isWindows ? '' : '/') +
                                targetSegs.join(
                                  Platform.isWindows ? r'\' : '/',
                                );
                            _loadDirectory(targetPath);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Text(
                              segments[i],
                              style: TextStyle(
                                fontSize: 13,
                                color: i == segments.length - 1
                                    ? Colors.white
                                    : Colors.white60,
                                fontWeight: i == segments.length - 1
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // ③ 目录列表主体
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
                )
              : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Colors.amber,
                          size: 36,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '读取失败: $_errorMessage',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () => _loadDirectory(_currentPath),
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              : _nodes.isEmpty
              ? const Center(
                  child: Text(
                    '当前目录下没有发现子文件夹或漫画文件',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                )
              : ListView.separated(
                  controller: widget.scrollController,
                  itemCount: _nodes.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: Colors.white10),
                  itemBuilder: (context, index) {
                    final item = _nodes[index];

                    if (item.isDir) {
                      return ListTile(
                        leading: const Icon(
                          Icons.folder_rounded,
                          color: Color(0xFFFBBF24),
                          size: 24,
                        ),
                        title: Text(
                          item.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check, size: 16),
                              color: const Color(0xFF38BDF8),
                              tooltip: '直接打开此文件夹',
                              onPressed: () => widget.onSelect(item.path),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              color: Colors.white30,
                              size: 18,
                            ),
                          ],
                        ),
                        dense: true,
                        onTap: () => _loadDirectory(item.path),
                      );
                    } else if (item.isArchive) {
                      // 漫画归档（ZIP / CBZ / CBR / RAR 等）
                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF8B5CF6,
                            ).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.auto_stories_rounded,
                            color: Color(0xFFA78BFA),
                            size: 20,
                          ),
                        ),
                        title: Text(
                          item.name,
                          style: const TextStyle(
                            color: Color(0xFFF3F4F6),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '漫画归档 · ${_formatSize(item.size)}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.play_circle_fill_rounded,
                          color: Color(0xFF8B5CF6),
                          size: 24,
                        ),
                        dense: true,
                        onTap: () => widget.onSelect(item.path),
                      );
                    } else {
                      // 单张图片
                      return ListTile(
                        leading: const Icon(
                          Icons.image_outlined,
                          color: Color(0xFF34D399),
                          size: 20,
                        ),
                        title: Text(
                          item.name,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          _formatSize(item.size),
                          style: const TextStyle(
                            color: Colors.white30,
                            fontSize: 11,
                          ),
                        ),
                        dense: true,
                        onTap: () => widget.onSelect(item.path),
                      );
                    }
                  },
                ),
        ),
      ],
    );
  }
}
