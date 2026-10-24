import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/workspace/method/open_comic_item.dart';
import 'package:zephyr/workspace/model/history_insights.dart';
import 'package:zephyr/workspace/model/history_week_heatline.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/widgets/cards/history_insights_window.dart';

/// 移动端**工作台首页**——方向 01「书桌小组件」的 Flutter 落地,
/// 与 `design/mobile-workspace/home/index.html` 同一版式:
/// 大标题 → 继续阅读 hero → 阅读数据(2×2 小组件 + 近 12 周热力条)→
/// 阅读历史(可续读条目)→ 文件管理(入口卡)→ 阅读工具(嵌入控制面板三卡)。
///
/// 复用口径与设计阶段定的「同面板、两种宿主」一致,业务零复制:
/// - 数据读的就是洞察卡那份 [HistoryInsightsWindow] 同源查询
///   (`unifiedHistoryBox` 最近 500 条),聚合用同一套纯函数
///   (`buildReadingStreak` / `buildDailyTrend` / [buildWeekHeatline]);
/// - 继续阅读走工作台统一的 [openComicItem];
/// - 历史 / 文件的整页详情走 `WorkspaceMobileCardRoute`(standalone 复用);
/// - 阅读工具直接经 [WorkspaceCardRegistry] 嵌入控制面板的三张卡
///   (超分 / 翻译 / 画面调节,与桌面控制面板是同一份 builder)。
///
/// **诚实口径**:历史记录没有总页数,所以 hero 不画假的百分比进度条
/// (设计稿里的 57% 是示例数据),露出的是卷章与页码。
///
/// 展台(`≥ 760` 逻辑宽):hero 保持整宽,下方区块两列并排。
@RoutePage()
class WorkspaceMobileHomePage extends StatefulWidget {
  const WorkspaceMobileHomePage({super.key});

  static const double _kStandBreakpoint = 760;

  @override
  State<WorkspaceMobileHomePage> createState() =>
      _WorkspaceMobileHomePageState();
}

class _WorkspaceMobileHomePageState extends State<WorkspaceMobileHomePage> {
  Stream<List<HistoryInsightEvent>>? _events;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  /// 与 [HistoryInsightsWindow] 同一条查询:最近 500 条、最近优先。
  /// 首页 hero / 小组件 / 热力条 / 历史条目读这一份,不再各查各的。
  void _subscribe() {
    final builder = objectbox.unifiedHistoryBox
        .query(UnifiedComicHistory_.deleted.equals(false))
        .order(UnifiedComicHistory_.lastReadAt, flags: Order.descending);
    _events = builder.watch(triggerImmediately: true).map((query) {
      query.limit = kHistoryInsightWindow;
      return [
        for (final item in query.find())
          HistoryInsightEvent(
            at: item.lastReadAt,
            source: item.source,
            comicId: item.comicId,
          ),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<HistoryInsightEvent>>(
          stream: _events,
          builder: (context, snapshot) {
            final events = snapshot.data ?? const <HistoryInsightEvent>[];
            final latest = events.isEmpty ? null : events.first;
            return LayoutBuilder(
              builder: (context, constraints) {
                final wide =
                    constraints.maxWidth >=
                    WorkspaceMobileHomePage._kStandBreakpoint;
                final sections = _Sections(events: events, latest: latest);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    const _HomeHeader(),
                    const SizedBox(height: 8),
                    _ContinueHero(latest: latest),
                    const SizedBox(height: 16),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              children: [sections.insights, sections.history],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              children: [sections.files, sections.tools],
                            ),
                          ),
                        ],
                      )
                    else ...[
                      sections.insights,
                      const SizedBox(height: 16),
                      sections.history,
                      const SizedBox(height: 16),
                      sections.files,
                      const SizedBox(height: 16),
                      sections.tools,
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// 大标题 + 今天的日期(设计稿右上角那行)。
class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              t.workspace.workspaceHome,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            '${now.month} 月 ${now.day} 日 · 周${weekdays[now.weekday - 1]}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 继续阅读 hero:最近一条历史(来自同一个事件窗口)。
class _ContinueHero extends StatelessWidget {
  const _ContinueHero({required this.latest});

  final HistoryInsightEvent? latest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = _latestRecord();
    final title = record?.title ?? '';
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Stack(
        children: [
          // MD3 Expressive 的圆装饰(设计稿 hero 右上角那块 cookie 形)。
          Positioned(
            right: -26,
            top: -30,
            child: IgnorePointer(
              child: Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CoverBadge(title: title),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record == null
                            ? t.workspace.continueReading
                            : '${t.workspace.continueReading} · ${_relativeDay(record.lastReadAt)}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer
                              .withValues(alpha: 0.72),
                        ),
                      ),
                      if (record != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _progressLabel(record),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.66),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.surface,
                            foregroundColor: theme.colorScheme.primary,
                          ),
                          onPressed: () => openComicItem(
                            context,
                            comicId: record.comicId,
                            from: record.source,
                          ),
                          child: Text(t.workspace.toContinue),
                        ),
                      ] else
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            t.workspace.noReadingYet,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer
                                  .withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  UnifiedComicHistory? _latestRecord() {
    if (latest == null) return null;
    final builder = objectbox.unifiedHistoryBox
        .query(
          UnifiedComicHistory_.deleted
              .equals(false)
              .and(UnifiedComicHistory_.comicId.equals(latest!.comicId)),
        )
        .order(UnifiedComicHistory_.lastReadAt, flags: Order.descending);
    return builder.build().findFirst();
  }

  String _relativeDay(DateTime at) {
    final now = DateTime.now();
    final day = DateTime(at.year, at.month, at.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return t.workspace.todayLabel;
    if (diff == 1) return t.workspace.yesterdayLabel;
    if (diff <= 7) return t.workspace.daysAgoLabel(n: diff);
    return '${at.month} 月 ${at.day} 日';
  }

  String _progressLabel(UnifiedComicHistory record) {
    final page = '${record.pageIndex + 1} ${t.workspace.pageUnit}';
    if (record.chapterTitle.isEmpty) return page;
    return '${record.chapterTitle} · $page';
  }
}

/// hero 里的封面位。真实封面渲染(在线 URL / 本地压缩包首页)与
/// `CoverWidget` 的插件链路绑得深,先用主色渐变 + 书名占位。
class _CoverBadge extends StatelessWidget {
  const _CoverBadge({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 88,
      height: 118,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.9),
            theme.colorScheme.primary.withValues(alpha: 0.55),
          ],
        ),
      ),
      alignment: Alignment.bottomLeft,
      padding: const EdgeInsets.all(10),
      child: title.isEmpty
          ? null
          : Text(
              title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

/// 四个区块(阅读数据 / 历史 / 文件 / 工具)。拆出来是因为展台两列时
/// 要按列分装,手机竖排时按顺序铺 —— 区块本身与排布无关。
class _Sections {
  _Sections({required this.events, required this.latest})
    : assert(events.isEmpty || identical(events.first, latest));

  final List<HistoryInsightEvent> events;
  final HistoryInsightEvent? latest;

  Widget get insights => const _InsightsSection();
  Widget get history => _HistorySection(events: events, latest: latest);
  Widget get files => const _FilesSection();
  Widget get tools => const _ToolsSection();
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ] else
            const Spacer(),
          if (actionLabel != null && onAction != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(99),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      actionLabel!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    GlyphIcon(
                      AppGlyphs.chevronForward,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 阅读数据:2×2 小组件 + 近 12 周热力条(设计稿同版式)。
class _InsightsSection extends StatelessWidget {
  const _InsightsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: t.workspace.readingInsights,
          subtitle: t.workspace.last12Weeks,
          actionLabel: t.workspace.openDetail,
          onAction: () =>
              context.pushRoute(const WorkspaceMobileInsightsRoute()),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: HistoryInsightsWindow(
              skeletonHeight: 148,
              builder: (context, events) => Column(
                children: [
                  _WidgetGrid(events: events),
                  const SizedBox(height: 12),
                  _Heatline(events: events),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WidgetGrid extends StatelessWidget {
  const _WidgetGrid({required this.events});

  final List<HistoryInsightEvent> events;

  @override
  Widget build(BuildContext context) {
    final streak = buildReadingStreak(events);
    final trend = buildDailyTrend(events);
    final readingNow = events.map((e) => e.comicId).toSet().length;
    final downloads = objectbox.unifiedDownloadBox
        .query(UnifiedComicDownload_.deleted.equals(false))
        .build()
        .count();
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: t.workspace.streakReading,
                value: '${streak.currentStreak}',
                unit: t.workspace.dayUnit,
                note: '${t.workspace.longestStreak} ${streak.longestStreak}',
                icon: AppGlyphs.fire,
                highlight: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                label: t.workspace.todayReading,
                value: '${trend.days.last.count}',
                unit: t.workspace.visitUnit,
                icon: AppGlyphs.clock,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: t.workspace.recentReading,
                value: '$readingNow',
                unit: t.workspace.bookUnit,
                icon: AppGlyphs.openBook,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                label: t.workspace.downloadedLabel,
                value: '$downloads',
                unit: t.workspace.bookUnit,
                icon: AppGlyphs.folderCopy,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    this.note,
    this.highlight = false,
  });

  final String label;
  final String value;
  final String unit;
  final Glyph icon;
  final String? note;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = highlight
        ? theme.colorScheme.secondaryContainer
        : theme.colorScheme.surfaceContainerLow;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: highlight
                  ? theme.colorScheme.surface
                  : theme.colorScheme.secondaryContainer,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: GlyphIcon(icon, size: 17, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 1),
          RichText(
            text: TextSpan(
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
                color: theme.colorScheme.onSurface,
              ),
              children: [
                TextSpan(text: value),
                TextSpan(
                  text: ' $unit',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 1),
            Text(
              note!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 近 12 周逐日热力条:84 格、四档色,今天收尾。
class _Heatline extends StatelessWidget {
  const _Heatline({required this.events});

  final List<HistoryInsightEvent> events;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heatline = buildWeekHeatline(events, now: DateTime.now());
    final levels = [
      theme.colorScheme.surfaceContainerHighest,
      theme.colorScheme.primary.withValues(alpha: 0.25),
      theme.colorScheme.primary.withValues(alpha: 0.5),
      theme.colorScheme.primary.withValues(alpha: 0.75),
      theme.colorScheme.primary,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.workspace.readingHeat,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 22,
          child: Row(
            children: [
              for (final (index, _) in heatline.counts.indexed)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0.75),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: levels[heatline.levelAt(index)],
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 阅读历史:跳过 hero 正在读的那条,露出后面两条可直接续读的记录。
class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.events, required this.latest});

  final List<HistoryInsightEvent> events;
  final HistoryInsightEvent? latest;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: t.workspace.readingHistory,
          subtitle: t.workspace.continueNextHint,
          actionLabel: t.workspace.openAll,
          onAction: () => context.pushRoute(
            WorkspaceMobileCardRoute(cardId: WorkspaceCardRegistry.history),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: _HistoryRows(events: events, latest: latest),
        ),
      ],
    );
  }
}

class _HistoryRows extends StatelessWidget {
  const _HistoryRows({required this.events, required this.latest});

  final List<HistoryInsightEvent> events;
  final HistoryInsightEvent? latest;

  @override
  Widget build(BuildContext context) {
    final rest = latest == null
        ? events
        : events.skipWhile((event) => identical(event, latest)).toList();
    final records = <UnifiedComicHistory>[];
    final seen = <String>{latest?.comicId ?? ''};
    for (final event in rest) {
      if (records.length >= 2) break;
      if (seen.contains(event.comicId)) continue;
      final record = _find(event.comicId);
      if (record == null) continue;
      seen.add(event.comicId);
      records.add(record);
    }
    if (records.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          t.workspace.noMoreHistory,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final (index, record) in records.indexed) ...[
          if (index > 0)
            Divider(
              height: 1,
              indent: 72,
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          _HistoryRow(record: record),
        ],
      ],
    );
  }

  UnifiedComicHistory? _find(String comicId) {
    final builder = objectbox.unifiedHistoryBox
        .query(
          UnifiedComicHistory_.deleted
              .equals(false)
              .and(UnifiedComicHistory_.comicId.equals(comicId)),
        )
        .order(UnifiedComicHistory_.lastReadAt, flags: Order.descending);
    return builder.build().findFirst();
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.record});

  final UnifiedComicHistory record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = '${record.pageIndex + 1} ${t.workspace.pageUnit}';
    final day = record.lastReadAt.toLocal();
    final when = '${day.month}/${day.day}';
    final chapter = record.chapterTitle.isEmpty ? when : record.chapterTitle;
    return InkWell(
      onTap: () =>
          openComicItem(context, comicId: record.comicId, from: record.source),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 58,
              alignment: Alignment.bottomLeft,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.75),
                    theme.colorScheme.primary.withValues(alpha: 0.4),
                  ],
                ),
              ),
              child: Text(
                record.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    chapter.isEmpty ? page : '$chapter · $page',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              when,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 文件管理:整卡入口。真实存储量要过文件管理核心(Rust 会话),
/// 这里不造假数字 —— 卡上只露名字与说明,数量与容量在整页里看。
class _FilesSection extends StatelessWidget {
  const _FilesSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: t.workspace.fileManagement,
          subtitle: t.workspace.filesBrowseSubtitle,
          actionLabel: t.workspace.openFilesAction,
          onAction: () => context.pushRoute(
            WorkspaceMobileCardRoute(cardId: WorkspaceCardRegistry.localFolder),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: () => context.pushRoute(
              WorkspaceMobileCardRoute(
                cardId: WorkspaceCardRegistry.localFolder,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: GlyphIcon(
                      AppGlyphs.folderCopy,
                      size: 19,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.workspace.localComics,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t.workspace.filesBrowseSubtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  GlyphIcon(
                    AppGlyphs.chevronForward,
                    size: 19,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 阅读工具:控制面板的三张卡(超分 / 翻译 / 画面调节)经注册表整批嵌入,
/// 与桌面控制面板同一份 builder —— 不另造开关。
///
/// **默认收起**:超分卡展开时带着模型管理等一大节,三张全铺开会把
/// 首页撑成一页设置;首页只露三行标题,要动哪项点哪项。
class _ToolsSection extends StatefulWidget {
  const _ToolsSection();

  @override
  State<_ToolsSection> createState() => _ToolsSectionState();
}

class _ToolsSectionState extends State<_ToolsSection> {
  static const _toolCardIds = [
    WorkspaceCardRegistry.superResolution,
    WorkspaceCardRegistry.translate,
    WorkspaceCardRegistry.imageTuning,
  ];

  /// 初始全在折叠集合里 = 三张卡默认收起,点标题行才展开。
  final Set<String> _collapsed = {..._toolCardIds};

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: t.workspace.readingTools,
          subtitle: t.workspace.toolsStandaloneHint,
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              children: [
                for (final cardId in _toolCardIds)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: _embeddedCard(context, cardId),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _embeddedCard(BuildContext context, String cardId) {
    final def = WorkspaceCardRegistry.I.find(cardId);
    if (def == null) return const SizedBox.shrink();
    return def.builder(
      context,
      WorkspaceCardChrome(
        expanded: !_collapsed.contains(cardId),
        onToggle: () => setState(() {
          if (!_collapsed.remove(cardId)) _collapsed.add(cardId);
        }),
        index: 0,
        count: 1,
        supported: def.supportedHere?.call() ?? true,
        unsupportedHint: def.unsupportedHint,
        widthSpan: def.defaultWidthSpan,
        heightSpan: def.defaultHeightSpan,
      ),
    );
  }
}
