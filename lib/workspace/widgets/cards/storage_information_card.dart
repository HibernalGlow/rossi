import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/src/rust/api/memory.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/cards/info_card_kit.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/i18n/strings.g.dart';

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
          title: t.workspace.storageInformation,
          icon: AppGlyphs.storage,
          expressive: true,
          isExpanded: widget.isExpanded,
          onToggle: widget.onToggle,
          onMoveUp: widget.onMoveUp,
          onMoveDown: widget.onMoveDown,
          onHide: widget.onHide,
          child: hasSession
              ? _buildRows(source)
              : InfoEmpty(
                  icon: AppGlyphs.box,
                  text: t.workspace.showStorageWhenOpen,
                  hint: t.workspace.rustMemoryPollHint,
                  fields: [
                    (t.workspace.sourceType, AppGlyphs.box),
                    (t.workspace.pageListTotal, AppGlyphs.storage),
                    (t.workspace.rustMemory, AppGlyphs.memory),
                  ],
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
        ? t.workspace.onlineLabel
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
      mainAxisSize: MainAxisSize.min,
      children: [
        ExpressiveTileGrid(
          minTileWidth: 104,
          children: [
            ExpressiveStatTile(
              value: source != null
                  ? '${source.pages.length}'
                  : '${coordinator.docs.length}',
              label: t.workspace.totalPagesLabel,
              icon: AppGlyphs.layers,
              highlight: true,
            ),
            ExpressiveStatTile(
              value: isLocal ? formatInfoBytes(total) : '—',
              label: t.workspace.pageListTotal,
              icon: AppGlyphs.storage,
              caption: isLocal ? kindLabel : t.workspace.onlineSourceNoArchive,
            ),
            ExpressiveStatTile(
              value: memory == null
                  ? (_memoryFailed ? '—' : '…')
                  : formatInfoBytes(memory.totalAllocated),
              label: t.workspace.rustMemory,
              icon: AppGlyphs.memory,
              caption: memory == null
                  ? t.workspace.polledEvery3s
                  : t.workspace.peakAllocated(
                      value: formatInfoBytes(memory.peakAllocated),
                    ),
              gauge: memory == null || memory.peakAllocated <= BigInt.zero
                  ? null
                  : memory.totalAllocated.toDouble() /
                        memory.peakAllocated.toDouble(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        InfoFacts(
          children: [
            InfoRow(
              label: t.workspace.sourceType,
              value: isLocal ? kindLabel : t.workspace.onlineSource,
              icon: AppGlyphs.box,
            ),
            if (isLocal)
              InfoRow(
                label: t.workspace.rootPath,
                value: path,
                icon: AppGlyphs.folder,
              ),
            InfoRow(
              label: t.workspace.totalPagesLabel,
              value: source != null
                  ? '${source.pages.length}'
                  : '${coordinator.docs.length}',
              icon: AppGlyphs.layers,
            ),
            if (isLocal)
              InfoRow(
                label: t.workspace.pageListTotal,
                value: formatInfoBytes(total),
                icon: AppGlyphs.storage,
              ),
            if (isLocal)
              InfoRow(
                label: t.workspace.currentPageSize,
                value: formatInfoBytes(currentPageSize),
                icon: AppGlyphs.cardMedium,
              ),
            InfoRow(
              label: t.workspace.rustMemory,
              value: memory == null
                  ? (_memoryFailed ? '—' : t.workspace.fetching)
                  : formatInfoBytes(memory.totalAllocated),
              emphasis: memory != null,
              icon: AppGlyphs.memory,
            ),
            if (memory != null)
              InfoRow(
                label: t.workspace.peakValue,
                value: formatInfoBytes(memory.peakAllocated),
                icon: AppGlyphs.trend,
              ),
            if (topTags != null)
              InfoRow(
                label: t.workspace.mainOccupancy,
                value: topTags,
                icon: AppGlyphs.equalizer,
              ),
          ],
        ),
      ],
    );
  }
}
