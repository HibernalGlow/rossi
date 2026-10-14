import 'package:auto_route/annotations.dart';
import 'package:material_ui/material_ui.dart' hide Page;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/donwload_task/bloc/dowload_task_bloc.dart';
import 'package:zephyr/page/donwload_task/models/download_queue_overview.dart';
import 'package:zephyr/page/donwload_task/models/download_task_comic_scope.dart';
import 'package:zephyr/page/donwload_task/models/download_task_view_filter.dart';
import 'package:zephyr/page/donwload_task/widgets/download_batch_actions.dart';
import 'package:zephyr/page/donwload_task/widgets/download_queue_control_bar.dart';
import 'package:zephyr/page/donwload_task/widgets/download_settings_card.dart';
import 'package:zephyr/page/donwload_task/widgets/download_task_tiles.dart';
import 'package:zephyr/page/donwload_task/widgets/offline_comic_section.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/icons/icons.dart';

@RoutePage()
class DownloadTaskPage extends StatelessWidget {
  const DownloadTaskPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DowloadTaskBloc()..add(DowloadTaskEvent.started()),
      child: const _DownloadTaskView(),
    );
  }
}

class _DownloadTaskView extends StatefulWidget {
  const _DownloadTaskView();

  @override
  State<_DownloadTaskView> createState() => _DownloadTaskViewState();
}

class _DownloadTaskViewState extends State<_DownloadTaskView> {
  /// 建一次、订阅一次：任务行每秒都在刷新，每次 build 造一条新流会反复重订阅。
  final Stream<List<UnifiedComicDownload>> _offlineStream =
      watchOfflineComics();

  /// 状态筛选是「先只看哪一类」的临时视角，不写盘：它跟着这次来找什么，
  /// 下次进页默认还是全看。
  DownloadTaskViewFilter _filter = DownloadTaskViewFilter.all;

  /// 「先看哪一本」是同一档临时视角，同样不写盘。null = 不按漫画筛。
  String? _selectedComicId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DowloadTaskBloc, DowloadTaskState>(
      builder: (context, state) {
        final batchTargets = state.maybeWhen(
          loaded: (tasks, _) => tasks,
          orElse: () => const <DownloadTask>[],
        );
        return Scaffold(
          appBar: AppBar(
            title: Text(t.download.title),
            actions: [DownloadBatchActions(tasks: batchTargets)],
          ),
          body: state.when(
            initial: () => const Center(child: CircularProgressIndicator()),
            loaded: (tasks, pendingCount) {
              final overview = summarizeDownloadQueue(tasks);
              final comics = downloadTasksGroupedByComic([
                for (final task in tasks)
                  (comicId: task.comicId, comicName: task.comicName),
              ]);
              // 选中的那本整批下完或被删掉后就不在这份清单里了，此时自动回到「全部」：
              // 留着一个选中的空范围，屏幕上就只剩一句「当前筛选没有任务」。
              final selectedComicId =
                  comics.any((group) => group.comicId == _selectedComicId)
                  ? _selectedComicId
                  : null;
              // 筛选只改「看得见哪些行」，不改标题栏那三颗批量动作的作用域 ——
              // 那几颗的文案是「全部」，筛完偷偷缩成一小撮会让它说出假话。
              final visibleTasks = tasks
                  .where(
                    (task) =>
                        downloadTaskMatchesComicScope(
                          selectedComicId: selectedComicId,
                          comicId: task.comicId,
                        ) &&
                        downloadTaskMatchesViewFilter(
                          filter: _filter,
                          isDownloading: task.isDownloading,
                          stateCode: downloadTaskStateCode(task),
                        ),
                  )
                  .toList();
              final downloadingTasks = visibleTasks
                  .where((t) => t.isDownloading)
                  .toList();
              final pendingTasks = visibleTasks
                  .where((t) => !t.isDownloading)
                  .toList();
              // 失败的行单独立区：它等的是「重试」而不是「再等等」，混在等待区里
              // 批量重试没有落点，也看不出这一批还有多少章要重跑。
              final failedTasks = pendingTasks
                  .where((t) => downloadTaskStateCode(t) == 'failed')
                  .toList();
              final waitingTasks = pendingTasks
                  .where((t) => downloadTaskStateCode(t) != 'failed')
                  .toList();

              List<Widget> taskSection({
                required Widget header,
                required List<DownloadTask> rows,
                required bool withRetry,
              }) {
                if (rows.isEmpty) return const [];
                return [
                  SliverToBoxAdapter(child: header),
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final task = rows[index];
                      return DownloadTaskRow(
                        key: ValueKey(task.id),
                        task: task,
                        onRetry:
                            withRetry && downloadTaskStateCode(task) == 'failed'
                            ? () async {
                                await DownloadQueueManager.instance.retryTask(
                                  task.id,
                                );
                              }
                            : null,
                        onDelete: () {
                          context.read<DowloadTaskBloc>().add(
                            DowloadTaskEvent.taskDeleted(task.id),
                          );
                          showInfoToast(t.download.taskDeleted);
                        },
                      );
                    }, childCount: rows.length),
                  ),
                ];
              }

              final errorColor = Theme.of(context).colorScheme.error;

              return StreamBuilder<List<UnifiedComicDownload>>(
                stream: _offlineStream,
                builder: (context, snapshot) {
                  final offlineRecords = snapshot.data ?? const [];
                  return CustomScrollView(
                    slivers: [
                      const SliverToBoxAdapter(child: DownloadSettingsCard()),
                      if (tasks.isNotEmpty)
                        SliverToBoxAdapter(
                          child: DownloadQueueControlBar(
                            overview: overview,
                            filter: _filter,
                            onFilterChanged: (next) =>
                                setState(() => _filter = next),
                            comics: comics,
                            selectedComicId: selectedComicId,
                            onComicScopeChanged: (next) =>
                                setState(() => _selectedComicId = next),
                          ),
                        ),
                      if (tasks.isNotEmpty && visibleTasks.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: Text(
                              t.download.filterNoMatches,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      if (tasks.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text(
                              t.download.noTasks,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ...taskSection(
                        header: _TaskSectionHeader(
                          title: t.download.downloading,
                          color: Colors.blue,
                        ),
                        rows: downloadingTasks,
                        withRetry: false,
                      ),
                      ...taskSection(
                        header: _TaskSectionHeader(
                          title: t.download.failedTasks(
                            count: failedTasks.length,
                          ),
                          color: errorColor,
                          trailing: TextButton.icon(
                            onPressed: DownloadQueueManager
                                .instance
                                .retryAllFailedTasks,
                            icon: GlyphIcon(
                              AppGlyphs.refresh,
                              size: 16,
                              color: errorColor,
                            ),
                            label: Text(
                              t.download.retryFailedParts,
                              style: TextStyle(fontSize: 13, color: errorColor),
                            ),
                          ),
                        ),
                        rows: failedTasks,
                        withRetry: true,
                      ),
                      ...taskSection(
                        header: _TaskSectionHeader(
                          // 这一格是「不是失败的那些未下载行」，暂停的行平时也归在这里；
                          // 用户明确筛到「已暂停」时再叫「等待中」就是说谎了。
                          title: _filter == DownloadTaskViewFilter.paused
                              ? t.download.pausedTasks(
                                  count: waitingTasks.length,
                                )
                              : t.download.pending(count: waitingTasks.length),
                          color: Colors.grey,
                        ),
                        rows: waitingTasks,
                        withRetry: false,
                      ),
                      ...offlineComicSlivers(context, offlineRecords),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

/// 分区标题：左边状态名与计数，右边放该区的批量动作（失败区的「重试失败项」）。
class _TaskSectionHeader extends StatelessWidget {
  const _TaskSectionHeader({
    required this.title,
    required this.color,
    this.trailing,
  });

  final String title;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
