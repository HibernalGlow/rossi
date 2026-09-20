import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/cubit/image_size_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_seamless_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_seamless_state.dart';
import 'package:zephyr/page/comic_read/method/image_size_cache_store.dart';
import 'package:zephyr/page/comic_read/method/prefetch_image_sizes.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_state.dart';
import 'package:zephyr/page/comic_read/model/normal_comic_ep_info.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/reader_hover_reveal_layer.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';
import 'package:zephyr/reader/reader_ambient_background.dart';
import 'package:zephyr/util/context/context_extensions.dart';

class ComicReadSuccessWidget extends StatefulWidget {
  final String comicId;
  final String from;
  final NormalComicEpInfo epInfo;
  final int chapterOrder;
  final WidgetBuilder buildInteractiveViewer;
  final WidgetBuilder buildPageCount;
  final WidgetBuilder buildProgressBar;
  final WidgetBuilder buildAppBar;
  final WidgetBuilder buildBottom;
  final WidgetBuilder buildAutoReadControl;
  final int Function(ReadSettingState readSetting)? resolveTotalSlots;
  final void Function(
    BuildContext innerContext,
    ReadSettingState readSetting,
    int readMode,
  )
  onReady;

  const ComicReadSuccessWidget({
    super.key,
    required this.comicId,
    required this.from,
    required this.epInfo,
    required this.chapterOrder,
    required this.buildInteractiveViewer,
    required this.buildPageCount,
    required this.buildProgressBar,
    required this.buildAppBar,
    required this.buildBottom,
    required this.buildAutoReadControl,
    this.resolveTotalSlots,
    required this.onReady,
  });

  @override
  State<ComicReadSuccessWidget> createState() => _ComicReadSuccessWidgetState();
}

class _ComicReadSuccessWidgetState extends State<ComicReadSuccessWidget> {
  late final List<String> _pageKeys;
  late final Future<Map<int, Size>> _persistedSizeFuture;
  bool _initialPrefetchStarted = false;
  ReaderHoverController? _hoverController;

  @override
  void initState() {
    super.initState();
    _pageKeys = _buildPageKeys();
    _persistedSizeFuture = ImageSizeCacheStore(
      sourceTag: widget.from,
      pageKeys: _pageKeys,
    ).readIndexedSizes(pageKeys: _pageKeys, count: widget.epInfo.length);
  }

  @override
  void dispose() {
    _hoverController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = context.screenWidth;
    return FutureBuilder<Map<int, Size>>(
      future: _persistedSizeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        final persistedSize = snapshot.data ?? const <int, Size>{};
        return BlocProvider(
          create: (_) => ImageSizeCubit.create(
            defaultWidth: width,
            count: widget.epInfo.length,
            sourceTag: widget.from,
            pageKeys: _pageKeys,
            chapterOrder: widget.chapterOrder,
            persistedCache: persistedSize,
          ),
          child: Builder(
            builder: (innerContext) {
              _scheduleInitialPrefetch(innerContext);
              final cubit = innerContext.read<ReaderCubit>();
              final readMode = innerContext.select(
                (GlobalSettingCubit c) => c.state.readSetting.readMode,
              );
              final readSetting = innerContext.select(
                (GlobalSettingCubit c) => c.state.readSetting,
              );
              final backgroundColor = readSetting.resolveReaderBackgroundColor(
                Theme.of(innerContext).brightness,
              );
              final isDarkMode =
                  Theme.of(innerContext).brightness == Brightness.dark;
              final filterOpacityPercent = readSetting.readFilterOpacityPercent
                  .clamp(0, 100)
                  .toDouble();
              final enableReaderFilter =
                  isDarkMode &&
                  readSetting.readFilterEnabled &&
                  filterOpacityPercent > 0;

              final totalSlots = getReadModeSlotCount(
                imageCount: widget.epInfo.length,
                enableDoublePage: readSetting.doublePageMode,
                insertLeadingBlank:
                    readSetting.doublePageMode &&
                    readSetting.doublePageLeadingBlank,
              );
              final resolvedTotalSlots =
                  widget.resolveTotalSlots?.call(readSetting) ?? totalSlots;
              cubit.updateTotalSlots(resolvedTotalSlots);
              widget.onReady(innerContext, readSetting, readMode);

              _hoverController ??= ReaderHoverController(innerContext);
              _hoverController!.updateContext(innerContext);

              return ReaderHoverScope(
                controller: _hoverController!,
                child: BlocListener<ReaderCubit, ReaderState>(
                  // 悬停唤出的「锁」一解除（菜单收起 / 滑块松手），就用指针此刻的
                  // 实际位置把两侧悬停标记重新对一次账。
                  //
                  // 锁着的时候 `_checkScheduleHide*` 故意不排收起定时器（那是对的），
                  // 可 `setTopHovered(false)` / `setBottomHovered(false)` **也只有
                  // 那条定时器会调** —— 于是「指针在锁着的时候离开唤出区」这一下会被
                  // 整个丢掉，标记永久为真，被它 OR 住的那条栏再也收不起来
                  // （症状：点中间收起菜单，顶栏正常滑走、底栏不动）。补的就是这次
                  // 对账，见 `ReaderHoverController.syncHoveredWithPointer`。
                  listenWhen: isHoverRevealLockReleased,
                  listener: (context, state) =>
                      _hoverController?.syncHoveredWithPointer(),
                  child: BlocListener<ReaderSeamlessCubit, ReaderSeamlessState>(
                    listenWhen: (previous, current) =>
                        previous.loadedChapters.length !=
                        current.loadedChapters.length,
                    listener: _onSeamlessChaptersChanged,
                    child: Container(
                      // 这一层静态底色**保留**，它是自适应背景的兜底：
                      // 取色还没到 / 这一页没采到 / 不是本地漫画（取色那条路不适用）时，
                      // 露出来的就是它。自适应颜色只叠在它上面、在页面之下。
                      color: backgroundColor,
                      child: Stack(
                        children: [
                          // 阅读背景的**最底层**。它被 `RepaintBoundary` 圈住、
                          // 且只监听一个独立的调色板通知 —— 每次取色到达只重绘它自己，
                          // 上面那棵阅读子树（`InteractiveViewer` 与所有页面节点）
                          // 一次都不重建。这正是「不能影响阅读」在界面侧的落点。
                          Positioned.fill(
                            child: ReaderAmbientBackground(
                              baseColor: backgroundColor,
                              palette: ReaderAmbientStore.instance.palette,
                              enabled: readSetting.readerAmbientEnabled,
                              edgeMode: readSetting.readerAmbientEdge,
                              dimPercent: readSetting.readerAmbientDimPercent,
                              // 全局关了动画就直切：那 300 ms 的插值也是开销，
                              // 既然用户已经表态不要动画，就一起省掉。
                              animate: !readSetting.noAnimation,
                            ),
                          ),
                          Positioned.fill(
                            child: widget.buildInteractiveViewer(innerContext),
                          ),
                          if (enableReaderFilter)
                            Positioned.fill(
                              child: IgnorePointer(
                                ignoring: true,
                                child: Container(
                                  color: Colors.black.withValues(
                                    alpha: filterOpacityPercent / 100,
                                  ),
                                ),
                              ),
                            ),
                          Positioned.fill(
                            child: ReaderHoverRevealOverlay(
                              controller: _hoverController!,
                            ),
                          ),
                          widget.buildProgressBar(innerContext),
                          widget.buildPageCount(innerContext),
                          widget.buildAppBar(innerContext),
                          widget.buildBottom(innerContext),
                          widget.buildAutoReadControl(innerContext),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // 章节就绪后在后台预解析本地图片尺寸，让列表项高度提前就位，
  // 减少阅读过程中占位高度 → 真实高度的布局跳变。
  void _scheduleInitialPrefetch(BuildContext innerContext) {
    if (_initialPrefetchStarted) return;
    _initialPrefetchStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !innerContext.mounted) return;
      final readSetting = innerContext
          .read<GlobalSettingCubit>()
          .state
          .readSetting;
      unawaited(
        prefetchChapterImageSizes(
          imageSizeCubit: innerContext.read<ImageSizeCubit>(),
          docs: widget.epInfo.docs,
          comicId: widget.comicId,
          from: widget.from,
          chapterId: widget.epInfo.epId,
          chapterOrder: widget.chapterOrder,
          contentWidth: _resolveContentWidth(innerContext, readSetting),
        ),
      );
    });
  }

  // 无缝拼接加载出新章节时，同样预解析其图片尺寸。
  void _onSeamlessChaptersChanged(
    BuildContext context,
    ReaderSeamlessState state,
  ) {
    final imageSizeCubit = context.read<ImageSizeCubit>();
    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
    final contentWidth = _resolveContentWidth(context, readSetting);
    for (final chapter in state.loadedChapters) {
      unawaited(
        prefetchChapterImageSizes(
          imageSizeCubit: imageSizeCubit,
          docs: chapter.epInfo.docs,
          comicId: widget.comicId,
          from: widget.from,
          chapterId: chapter.epInfo.epId,
          chapterOrder: chapter.order,
          contentWidth: contentWidth,
        ),
      );
    }
  }

  double _resolveContentWidth(
    BuildContext context,
    ReadSettingState readSetting,
  ) {
    return getConstrainedImageWidth(
      containerWidth: context.screenWidth,
      enableSidePadding: readSetting.sidePaddingEnabled,
      sidePaddingPercent: readSetting.sidePaddingPercent,
    );
  }

  List<String> _buildPageKeys() {
    return List<String>.generate(widget.epInfo.length, (index) {
      if (index >= widget.epInfo.docs.length) {
        return '${widget.comicId}|${widget.epInfo.epId}|index_$index';
      }

      final doc = widget.epInfo.docs[index];
      final imageId = doc.id.isNotEmpty
          ? doc.id
          : (doc.originalName.isNotEmpty ? doc.originalName : doc.path);
      return '${widget.comicId}|${widget.epInfo.epId}|$imageId';
    }, growable: false);
  }
}
