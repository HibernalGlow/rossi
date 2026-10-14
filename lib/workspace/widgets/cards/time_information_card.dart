import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/cards/info_card_kit.dart';
import 'package:zephyr/icons/icons.dart';

/// 时间信息卡（对齐 Neo 的 `time-information`）：
/// 来源文件与当前页文件的修改 / 访问 / 变更时间。
///
/// 每一项都**量得到才写**：`dart:io` 量不到创建时间（只有 ctime），
/// 在线图源没有本地文件，这些格子显示 `—` 而不是编一个数
/// （Neo 同款纪律：时间的**来源**比时间本身重要）。
class TimeInformationCard extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final bool isStandalone;

  const TimeInformationCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.isStandalone = false,
  });

  @override
  State<TimeInformationCard> createState() => _TimeInformationCardState();
}

class _TimeFacts {
  const _TimeFacts({
    this.rootPath,
    this.rootModified,
    this.rootAccessed,
    this.rootChanged,
    this.pagePath,
    this.pageModified,
  });

  final String? rootPath;
  final DateTime? rootModified;
  final DateTime? rootAccessed;

  /// 元数据变更时间（inode ctime）。`dart:io` 的量具表里没有**创建时间**
  /// （`FileStat` 只有 changed / modified / accessed），所以这里报 ctime
  /// 而不是编一个「创建」—— Neo 的「时间来源」那一行说的就是这件事。
  final DateTime? rootChanged;
  final String? pagePath;
  final DateTime? pageModified;
}

class _TimeInformationCardState extends State<TimeInformationCard> {
  _TimeFacts? _facts;
  String _factsKey = '';
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    ReaderSessionCoordinator.instance.addListener(_onSessionChanged);
    _refresh();
  }

  @override
  void dispose() {
    ReaderSessionCoordinator.instance.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() => _refresh();

  /// 只在「来源路径或当前页」真的换了时才重新 stat ——
  /// 协调器每次翻页都会通知，而同一本书换页时根路径的 stat 是同一份。
  void _refresh() {
    final coordinator = ReaderSessionCoordinator.instance;
    final source = coordinator.localSource;
    final key = '${source?.path ?? ''}|${coordinator.currentSlot}';
    if (key == _factsKey) return;
    _factsKey = key;
    unawaited(_load(source, coordinator.currentSlot));
  }

  Future<void> _load(PageSource? source, int slot) async {
    final generation = ++_generation;
    if (source == null) {
      if (mounted) setState(() => _facts = const _TimeFacts());
      return;
    }
    try {
      final rootStat = await FileStat.stat(source.path);
      final rootKnown = rootStat.type != FileSystemEntityType.notFound;
      String? pagePath;
      try {
        pagePath = await source.getPageFilePath(slot);
      } on Object {
        pagePath = null;
      }
      final pageStat = pagePath == null ? null : await FileStat.stat(pagePath);
      if (!mounted || generation != _generation) return;
      setState(() {
        _facts = _TimeFacts(
          rootPath: source.path,
          rootModified: rootKnown ? rootStat.modified : null,
          rootAccessed: rootKnown ? rootStat.accessed : null,
          rootChanged: rootKnown ? rootStat.changed : null,
          pagePath: pagePath,
          pageModified: pageStat?.modified,
        );
      });
    } on Object {
      if (!mounted || generation != _generation) return;
      setState(() => _facts = const _TimeFacts());
    }
  }

  @override
  Widget build(BuildContext context) {
    final coordinator = ReaderSessionCoordinator.instance;
    return ListenableBuilder(
      listenable: coordinator,
      builder: (context, _) {
        final hasSession = coordinator.hasActiveSession;
        final facts = _facts;
        return CollapsibleCard(
          cardId: 'time_information',
          title: '时间信息',
          icon: AppGlyphs.clock,
          expressive: true,
          isExpanded: widget.isExpanded,
          onToggle: widget.onToggle,
          onMoveUp: widget.onMoveUp,
          onMoveDown: widget.onMoveDown,
          onHide: widget.onHide,
          child: !hasSession
              ? const InfoEmpty(
                  icon: AppGlyphs.history,
                  text: '打开书本后显示文件时间',
                  hint: 'dart:io 没有创建时间，只报量得到的这几项',
                  fields: [
                    ('来源', AppGlyphs.folder),
                    ('修改', AppGlyphs.edit),
                    ('访问', AppGlyphs.history),
                  ],
                )
              : facts?.rootPath == null
              ? const InfoEmpty(
                  icon: AppGlyphs.cloud,
                  text: '在线图源没有本地文件时间',
                  hint: '这一项要落到本地归档才有量具',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExpressiveTileGrid(
                      minTileWidth: 150,
                      children: [
                        ExpressiveStatTile(
                          value: formatInfoTimeOfDay(facts!.rootModified),
                          label: '来源修改于',
                          icon: AppGlyphs.clock,
                          highlight: true,
                          caption: formatInfoDateTime(facts.rootModified),
                        ),
                        ExpressiveStatTile(
                          value: formatInfoTimeOfDay(facts.pageModified),
                          label: '当前页修改于',
                          icon: AppGlyphs.photos,
                          caption: formatInfoDateTime(facts.pageModified),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    InfoFacts(
                      children: [
                        InfoRow(
                          label: '来源',
                          value: facts.rootPath,
                          icon: AppGlyphs.folder,
                        ),
                        InfoRow(
                          label: '修改',
                          value: formatInfoDateTime(facts.rootModified),
                          icon: AppGlyphs.edit,
                        ),
                        InfoRow(
                          label: '访问',
                          value: formatInfoDateTime(facts.rootAccessed),
                          icon: AppGlyphs.history,
                        ),
                        InfoRow(
                          label: '变更',
                          value: formatInfoDateTime(facts.rootChanged),
                          icon: AppGlyphs.info,
                        ),
                        if (facts.pagePath != null) ...[
                          const SizedBox(height: 4),
                          InfoRow(
                            label: '当前页文件',
                            value: facts.pagePath,
                            icon: AppGlyphs.cardMedium,
                          ),
                          InfoRow(
                            label: '页修改',
                            value: formatInfoDateTime(facts.pageModified),
                            icon: AppGlyphs.photos,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
        );
      },
    );
  }
}
