import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/src/rust/api/memory.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/cards/info_card_kit.dart';
import 'package:path/path.dart' as p;

/// 存储信息卡（对齐 Neo 的 `storage-information`）：
/// 来源根路径 / 归档类型 / 页表总量 + Rust 侧内存占用。
///
/// Rust 内存是 Neo「资源占用」那几行的本地等价物：分配与峰值都发生在
/// `windcore` 里（解码缓冲、归档读取），Dart 侧看不见，所以走
/// [getRustMemoryInfo] 定期取。面板不展开时不轮询 —— 一块收起来的卡片
/// 没有理由一直跨 FFI 要数。
class StorageInformationCard extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final bool isStandalone;

  const StorageInformationCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.isStandalone = false,
  });

  @override
  State<StorageInformationCard> createState() => _StorageInformationCardState();
}

class _StorageInformationCardState extends State<StorageInformationCard> {
  Timer? _timer;
  RustMemoryInfo? _memory;
  bool _memoryFailed = false;

  @override
  void initState() {
    super.initState();
    ReaderSessionCoordinator.instance.addListener(_onSessionChanged);
    _syncPolling();
  }

  @override
  void didUpdateWidget(StorageInformationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isExpanded != widget.isExpanded) _syncPolling();
  }

  @override
  void dispose() {
    ReaderSessionCoordinator.instance.removeListener(_onSessionChanged);
    _timer?.cancel();
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  void _syncPolling() {
    _timer?.cancel();
    _timer = null;
    if (!widget.isExpanded) return;
    unawaited(_refreshMemory());
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_refreshMemory()),
    );
  }

  Future<void> _refreshMemory() async {
    try {
      final info = await getRustMemoryInfo();
      if (!mounted) return;
      setState(() {
        _memory = info;
        _memoryFailed = false;
      });
    } on Object {
      // 测试环境 / RustLib 未初始化 / 平台不支持：显示「—」，不刷错误。
      if (!mounted) return;
      setState(() => _memoryFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final coordinator = ReaderSessionCoordinator.instance;
    return ListenableBuilder(
      listenable: coordinator,
      builder: (context, _) {
        final source = coordinator.localSource;
        final hasSession = coordinator.hasActiveSession;
        return CollapsibleCard(
          cardId: 'storage_information',
          title: '存储信息',
          icon: Icons.sd_storage_rounded,
          isExpanded: widget.isExpanded,
          onToggle: widget.onToggle,
          onMoveUp: widget.onMoveUp,
          onMoveDown: widget.onMoveDown,
          onHide: widget.onHide,
          child: hasSession
              ? _buildRows(source)
              : const InfoEmpty(
                  icon: Icons.inventory_2_outlined,
                  text: '打开书本后显示存储信息',
                ),
        );
      },
    );
  }

  Widget _buildRows(PageSource? source) {
    final coordinator = ReaderSessionCoordinator.instance;
    final isLocal = source != null;

    BigInt total = BigInt.zero;
    if (isLocal) {
      for (final page in source.pages) {
        total += page.size;
      }
    }
    final slot = coordinator.currentSlot;
    final currentPageSize = source != null && slot < source.pages.length
        ? source.pages[slot].size
        : null;

    final path = source?.path;
    final kindLabel = path == null
        ? '在线'
        : p.extension(path).toUpperCase().replaceFirst('.', '');

    final memory = _memory;
    final topTags = memory == null || memory.taggedAllocations.isEmpty
        ? null
        : () {
            final sorted = [...memory.taggedAllocations]
              ..sort((a, b) => b.size.compareTo(a.size));
            return sorted
                .take(3)
                .map((t) => '${t.tag} ${formatInfoBytes(t.size)}')
                .join(' · ');
          }();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoRow(label: '来源类型', value: isLocal ? kindLabel : '在线图源'),
        if (isLocal) InfoRow(label: '根路径', value: path),
        InfoRow(
          label: '总页数',
          value: source != null
              ? '${source.pages.length}'
              : '${coordinator.docs.length}',
        ),
        if (isLocal) InfoRow(label: '页表总量', value: formatInfoBytes(total)),
        if (isLocal)
          InfoRow(label: '当前页大小', value: formatInfoBytes(currentPageSize)),
        InfoRow(
          label: 'Rust 内存',
          value: memory == null
              ? (_memoryFailed ? '—' : '获取中…')
              : formatInfoBytes(memory.totalAllocated),
        ),
        if (memory != null)
          InfoRow(label: '峰值', value: formatInfoBytes(memory.peakAllocated)),
        if (topTags != null) InfoRow(label: '主要占用', value: topTags),
      ],
    );
  }
}
