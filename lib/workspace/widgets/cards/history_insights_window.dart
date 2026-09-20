import 'package:material_ui/material_ui.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/workspace/model/history_insights.dart';

/// 洞察卡片共用的**历史样本窗口**（neoview 里每张卡各自 `listRecent(0, 500)` 的同位物）。
///
/// 四张卡读的是同一份数据、同一套三态（在加载 / 出错 / 一条都没有），
/// 所以这三态只在这里处理一次：卡片拿到的永远是**非空**事件列表，只管画。
///
/// 窗口有界不是省时间那么简单：洞察问的是「最近在读什么」，
/// 全库历史里的三年前那次访问既拖慢首帧，也不会让图更有解释力。
const int kHistoryInsightWindow = 500;

typedef HistoryInsightsBuilder =
    Widget Function(BuildContext context, List<HistoryInsightEvent> events);

class HistoryInsightsWindow extends StatefulWidget {
  const HistoryInsightsWindow({
    super.key,
    this.limit = kHistoryInsightWindow,
    this.skeletonHeight = 88,
    this.loadingLabel = '正在统计阅读历史',
    required this.builder,
  });

  final int limit;

  /// 占位块的高度：柱状图与热力格的天然高度不同，让它们各自报一个。
  final double skeletonHeight;

  final String loadingLabel;

  final HistoryInsightsBuilder builder;

  @override
  State<HistoryInsightsWindow> createState() => _HistoryInsightsWindowState();
}

class _HistoryInsightsWindowState extends State<HistoryInsightsWindow> {
  late Stream<List<HistoryInsightEvent>> _events;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    final builder = objectbox.unifiedHistoryBox
        .query(UnifiedComicHistory_.deleted.equals(false))
        .order(UnifiedComicHistory_.lastReadAt, flags: Order.descending);
    _events = builder.watch(triggerImmediately: true).map((query) {
      // 已经是「最近优先」的次序，所以截前 N 条就是最近的 N 条。
      query.limit = widget.limit;
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
    return StreamBuilder<List<HistoryInsightEvent>>(
      stream: _events,
      builder: (context, snapshot) {
        final error = snapshot.error;
        if (error != null) {
          return _buildError(context, error);
        }
        if (snapshot.connectionState != ConnectionState.active) {
          return _buildSkeleton(context);
        }
        final events = snapshot.data ?? const <HistoryInsightEvent>[];
        if (events.isEmpty) return _buildEmpty(context);
        return widget.builder(context, events);
      },
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: widget.skeletonHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            widget.loadingLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Center(
        child: Text(
          '暂无历史访问记录',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// 查询失败（库被占用 / 磁盘异常）不留一个「重试」就等于让用户等下一次重启。
  /// 重试的写法是**重新建一条流**：旧流由 `StreamBuilder` 在 stream 换掉时取消。
  Widget _buildError(BuildContext context, Object error) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          error.toString(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () => setState(_subscribe),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: const Text('重试'),
          ),
        ),
      ],
    );
  }
}

/// 一根柱：高度按 `value / maxValue` 归一，**最低留 4%**（与 neoview 一样），
/// 否则「读过但只有 1 次」的那根会彻底看不见，图上就少了事实。
///
/// 只在**有界高度**里用（`SizedBox(height: …)` 或 `Expanded` 的定高槽位）：
/// 它靠 `FractionallySizedBox` 换算，父级高度无限时它量不出自己该多高。
class InsightBar extends StatelessWidget {
  const InsightBar({super.key, required this.ratio, required this.highlighted});

  final double ratio;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        widthFactor: 1,
        heightFactor: ratio.clamp(0.04, 1.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: highlighted
                ? theme.colorScheme.primary
                : theme.colorScheme.primary.withValues(alpha: 0.7),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ),
      ),
    );
  }
}
