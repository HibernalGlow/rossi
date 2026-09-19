import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:scrollview_observer/scrollview_observer.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/comic_read.dart';
import 'package:zephyr/page/comic_read/cubit/image_size_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_presentation_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_seamless_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_seamless_state.dart';
import 'package:zephyr/page/comic_read/controller/reader_image_prefetch_controller.dart';
import 'package:zephyr/page/comic_read/controller/reader_orientation_controller.dart';
import 'package:zephyr/page/comic_read/cubit/reader_state.dart';
import 'package:zephyr/page/comic_read/model/normal_comic_ep_info.dart';
import 'package:zephyr/page/comic_read/type/chapter_extern.dart';
import 'package:zephyr/page/comic_read/widgets/modes/read_mode_utils.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/util/input/reader_input_bridge.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/workspace/widgets/reader/workspace_reader_fullscreen_scope.dart';

// 自动阅读相关：计时器、暂停/继续、悬浮按钮。
part 'parts/comic_read_auto_read_part.dart';
// 初始化与释放：控制器、订阅、历史记录、启动收尾。
part 'parts/comic_read_init_part.dart';
// 交互相关：手势、缩放、指针事件、阅读模式容器。
part 'parts/comic_read_interaction_part.dart';
// 系统 UI 与音量键拦截相关。
part 'parts/comic_read_system_ui_part.dart';
// 页面拼装与历史定位相关。
part 'parts/comic_read_view_part.dart';

@RoutePage()
class ComicReadPage extends StatelessWidget {
  final String comicId;
  final int order;
  final String chapterId;
  final String requestId;
  final String storageChapterId;
  final String logicalKey;
  final ChapterExtern chapterExtern;
  final int epsNumber;
  final String from;
  final ComicEntryType type;
  final dynamic comicInfo;
  final StringSelectCubit stringSelectCubit;

  const ComicReadPage({
    super.key,
    required this.comicId,
    required this.order,
    this.chapterId = '',
    this.requestId = '',
    this.storageChapterId = '',
    this.logicalKey = '',
    this.chapterExtern = const <String, dynamic>{},
    required this.epsNumber,
    required this.from,
    required this.stringSelectCubit,
    required this.type,
    required this.comicInfo,
  });

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => PageBloc()
            ..add(
              PageEvent(
                comicId,
                order,
                chapterId,
                requestId,
                storageChapterId,
                logicalKey,
                chapterExtern,
                from,
                type,
                comicInfo: comicInfo,
              ),
            ),
        ),
        BlocProvider.value(value: stringSelectCubit),
        BlocProvider(create: (_) => ReaderCubit()),
        // 顶栏缩放/旋转面板的会话状态：一个 route 一份，换书换章即归零
        // （手动缩放与手动旋转刻意不落盘，见 `ReaderPresentationCubit`）。
        BlocProvider(
          create: (context) => ReaderPresentationCubit(
            settings: context.read<GlobalSettingCubit>(),
          ),
        ),
        BlocProvider(
          create: (_) => ReaderSeamlessCubit(
            comicId: comicId,
            from: from,
            type: type,
            comicInfo: comicInfo,
            initialOrder: order,
          ),
        ),
      ],
      child: _ComicReadPage(
        comicId: comicId,
        order: order,
        chapterId: chapterId,
        requestId: requestId,
        storageChapterId: storageChapterId,
        logicalKey: logicalKey,
        chapterExtern: chapterExtern,
        epsNumber: epsNumber,
        from: from,
        type: type,
        comicInfo: comicInfo,
      ),
    );
  }
}

class _ComicReadPage extends StatefulWidget {
  final String comicId;
  final int order;
  final String chapterId;
  final String requestId;
  final String storageChapterId;
  final String logicalKey;
  final ChapterExtern chapterExtern;
  final int epsNumber; // 这个的意思是一共有多少章
  final String from;
  final ComicEntryType type;
  final dynamic comicInfo;

  const _ComicReadPage({
    required this.comicId,
    required this.order,
    this.chapterId = '',
    this.requestId = '',
    this.storageChapterId = '',
    this.logicalKey = '',
    this.chapterExtern = const <String, dynamic>{},
    required this.epsNumber,
    required this.from,
    required this.type,
    required this.comicInfo,
  });

  @override
  State<_ComicReadPage> createState() => _ComicReadPageState();
}

class _ComicReadPageState extends State<_ComicReadPage>
    with WidgetsBindingObserver {
  dynamic get comicInfo => widget.comicInfo;
  String get comicId => widget.comicId;

  late final ComicEntryType _type;
  late bool isSkipped = false; // 是否跳转过
  final _pageController = PageController(initialPage: 0); // 横版阅读器
  late JumpChapter _jumpChapter; // 用来跳转章节的通用类
  late final ReaderActionController _actionController; // 统一动作控制器
  late final ReaderVolumeController _volumeController; // 音量键翻页控制器
  late final ReaderHistoryController _historyController; // 历史记录控制器
  late final ReaderAutoReadController _autoReadController; // 自动阅读控制器
  late final ReaderSystemUiController _systemUiController; // 系统 UI 控制器
  late final ReaderLifecycleController _lifecycleController; // 生命周期控制器
  late final ReaderOrientationController _orientationController;
  late final ReaderInputController _inputController; // 输入控制器
  /// 登记到 [ReaderInputBridge] 的按键处理器。留住**同一个 tear-off**，
  /// 注销时才能对上（`detach` 用 `identical` 判定）。
  KeyEventResult Function(KeyEvent event)? _readerKeyDispatch;
  final _imagePrefetchController = ReaderImagePrefetchController();
  NormalComicEpInfo epInfo = NormalComicEpInfo(); // 通用漫画章节信息
  NormalComicEpInfo _initialEpInfo = NormalComicEpInfo();
  late final ListObserverController observerController; // 列表观察控制器
  final scrollController = ScrollController(); // 列表滚动控制器
  BuildContext? _imageSizeContext;
  final TransformationController _transformationController =
      TransformationController();
  StreamSubscription<bool>? _volumeKeyPageTurnSubscription;
  bool _isScrollLockedByMultiTouch = false;
  bool _isUserScrollActive = false; // 用户是否正在拖拽/惯性滚动列表

  /// 上一次参与过「槽位配对」的版式设置（单/双页、首页留白）。
  ///
  /// 这两个开关不改图片**是哪一张**，改的是**槽位怎么切**：第 10 个槽位在单页下
  /// 是第 11 张图，双页下是第 21 张图。切换后如果只是把设置写下去，`currentSlot`
  /// 就指着另一张图了；而以前的处理更粗暴 —— 直接 `changePageIndex(0)` 把槽位清零，
  /// 于是「切一下单双页，页数跳回开头」。这里缓存一份，用「变了没有」来判断要不要
  /// 把位置按同一张图重算（见 [_syncPairingLayoutChange]）。
  ReadSettingState? _lastPairingSetting;

  bool get _isHistory =>
      _type == ComicEntryType.history ||
      _type == ComicEntryType.historyAndDownload;

  @override
  void initState() {
    super.initState();
    observerController = ListObserverController(controller: scrollController);
    _type = widget.type;

    _initAutoReadController();
    _initSystemUiController();
    _initHistoryController();
    _initVolumeController();
    _initLifecycleController();
    _orientationController = ReaderOrientationController();
    _initInputController();
    _initActionController();
    _setVolumeControllerAction();
    _inputController.setActionController(_actionController);
    _inputController.init();
    // 把**同一个**按键处理器登记到应用级桥：焦点离开阅读器子树时（例如打开阅读
    // 设置面板，模态路由会把主焦点拿走），由工作台按「阅读器上下文优先」把冒泡上来的
    // 按键转交回来 —— 否则左右键会落到 WidgetsApp 默认的方向焦点遍历上，表现为
    // 「按键被设置面板吃掉」。见 `ReaderInputBridge`。
    _readerKeyDispatch = _inputController.handleKeyEvent;
    ReaderInputBridge.instance.attach(_readerKeyDispatch!);
    _initVolumeKeyPageTurnSubscription();

    WidgetsBinding.instance.addObserver(this);
    _lifecycleController.init();
    unawaited(
      _orientationController.setLandscape(
        context.read<GlobalSettingCubit>().state.readSetting.landscapeReader,
      ),
    );
    _initJumpChapter(context.read<ReaderCubit>().state.isMenuVisible);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_lifecycleController.dispose());
    _volumeKeyPageTurnSubscription?.cancel();
    final readerKeyDispatch = _readerKeyDispatch;
    if (readerKeyDispatch != null) {
      ReaderInputBridge.instance.detach(readerKeyDispatch);
    }
    _inputController.dispose();
    _imagePrefetchController.dispose();
    _volumeController.dispose();
    _pageController.dispose();
    _transformationController.dispose();
    unawaited(_orientationController.restorePortrait());
    if (isLocalComicSource(widget.from, comicId)) {
      unawaited(LocalReadSession.instance.dispose());
    }
    ReaderSessionCoordinator.instance.detachSession(comicId);
    super.dispose();
  }

  void _setReaderLandscape(bool enabled) {
    unawaited(_orientationController.setLandscape(enabled));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    // 阅读器根背景显式设成「阅读背景色」，不留给主题默认值。
    //
    // 主题默认在浅色模式下就是白的，而页面区域的各层（slot / 占位 / 位图 / 纹理）
    // 在切页那一两帧里完全可能什么都没画上去 —— 漏出来的正是这层底色。
    // 设成阅读背景色之后，即使漏，漏出来的也是用户本来就该看到的颜色，
    // 而不是一道白闪。
    backgroundColor: context
        .watch<GlobalSettingCubit>()
        .state
        .readSetting
        .resolveReaderBackgroundColor(Theme.of(context).brightness),
    body: BlocListener<ReaderSeamlessCubit, ReaderSeamlessState>(
      listener: (context, seamlessState) {
        final order = seamlessState.currentChapterOrder;
        if (order != null && order != _jumpChapter.order) {
          _syncJumpChapterState(order: order);
        }
        // 章节加载/卸载会改变总槽位和条目，触发重建以同步 ReaderCubit.totalSlots。
        final totalSlots = context
            .read<ReaderSeamlessCubit>()
            .resolveTotalSlots(
              context.read<GlobalSettingCubit>().state.readSetting,
            );
        final currentSlot = context.read<ReaderCubit>().state.currentSlot;
        ReaderSessionCoordinator.instance.updateProgress(
          currentSlot: currentSlot,
          totalSlots: totalSlots,
        );
        setState(() {});
      },
      child: BlocBuilder<PageBloc, PageState>(
        builder: (context, state) {
          switch (state.status) {
            case PageStatus.initial:
              return const Center(child: CircularProgressIndicator());
            case PageStatus.failure:
              return ComicErrorWidget(
                state: state,
                event: PageEvent(
                  comicId,
                  widget.order,
                  widget.chapterId,
                  widget.requestId,
                  widget.storageChapterId,
                  widget.logicalKey,
                  widget.chapterExtern,
                  widget.from,
                  widget.type,
                  comicInfo: comicInfo,
                ),
              );
            case PageStatus.success:
              if (!_lifecycleController.hasBootstrappedReadState) {
                _lifecycleController.markReadStateBootstrapped();
                epInfo = state.epInfo!;
                _initialEpInfo = state.epInfo!;
                final readSetting = context
                    .read<GlobalSettingCubit>()
                    .state
                    .readSetting;
                context.read<ReaderSeamlessCubit>().bootstrap(
                  epInfo,
                  widget.order,
                  readSetting,
                );
              }
              return ComicReadSuccessWidget(
                comicId: comicId,
                from: widget.from,
                epInfo: _initialEpInfo,
                chapterOrder: widget.order,
                resolveTotalSlots: (readSetting) => context
                    .read<ReaderSeamlessCubit>()
                    .resolveTotalSlots(readSetting),
                buildInteractiveViewer: (_) =>
                    _inputController.buildInteractiveViewer(),
                buildPageCount: (_) => _pageCountWidget(),
                buildAppBar: (_) => _comicReadAppBar(),
                buildBottom: (innerContext) => _bottomWidget(innerContext),
                buildAutoReadControl: (_) => _autoReadControlWidget(),
                onReady: (innerContext, readSetting, readMode) {
                  // 单/双页、首页留白刚被切换过：把位置按「同一张图」对齐，
                  // 别让它停在旧槽位号上（那是「页数跳回开头」的另一半原因，
                  // 另一半见 chrome 里那些被删掉的 `changePageIndex(0)`）。
                  _syncPairingLayoutChange(readSetting);
                  _syncAutoRead(readSetting: readSetting, readMode: readMode);
                  _prefetchImagesAroundSlot(
                    context.read<ReaderCubit>().state.currentSlot,
                    readSetting,
                  );
                  _imageSizeContext = innerContext;
                  _historyController.markLoaded();
                  unawaited(
                    _historyController.handleHistoryScroll(innerContext),
                  );

                  final readerCubit = context.read<ReaderCubit>();
                  final seamlessCubit = context.read<ReaderSeamlessCubit>();
                  final totalSlots = seamlessCubit.resolveTotalSlots(
                    readSetting,
                  );
                  ReaderSessionCoordinator.instance.attachSession(
                    comicId: comicId,
                    from: widget.from,
                    title: epInfo.epName,
                    epInfo: epInfo,
                    localSource: LocalReadSession.instance.currentSource,
                    currentSlot: readerCubit.state.currentSlot,
                    totalSlots: totalSlots,
                    jumpToSlot: (slot) => _jumpToGlobalSlot(slot),
                  );
                },
              );
          }
        },
      ),
    ),
  );
  @override
  void didChangeMetrics() {
    _lifecycleController.didChangeMetrics();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleController.didChangeAppLifecycleState(state);
  }

  void _refreshState(VoidCallback fn) {
    // 统一走这里触发刷新，避免在异步回调中误调用 setState。
    if (!mounted) return;
    setState(fn);
  }

  /// 版式配对（单/双页、首页留白）变化后，把阅读位置对齐到**同一张图**。
  ///
  /// 调用点在 `ComicReadSuccessWidget.onReady` —— 每次设置变化都会走一遍，
  /// 但只有配对真的变了才动手，否则每次重建（新章节拼进来、主题切换…）
  /// 都会把位置重算一遍。
  ///
  /// 重算出来不能就地跳：此刻还在 build 阶段，[ReaderCubit.updateCurrentSlot]
  /// 会带着一票 `context.select(currentSlot)` 的监听者在 build 里 markNeedsBuild。
  /// 所以排到 postFrame —— 那时新配对的列表 / PageView 已经带着新的槽位数
  /// 建好了，跳过去才落得准。
  void _syncPairingLayoutChange(ReadSettingState readSetting) {
    final previous = _lastPairingSetting;
    _lastPairingSetting = readSetting;
    if (previous == null) return;
    if (previous.doublePageMode == readSetting.doublePageMode &&
        previous.doublePageLeadingBlank == readSetting.doublePageLeadingBlank) {
      return;
    }

    final seamlessCubit = context.read<ReaderSeamlessCubit>();
    final entries = isColumnReadMode(readSetting.readMode)
        ? seamlessCubit.buildColumnEntries(readSetting)
        : seamlessCubit.buildRowEntries(readSetting);
    final targetSlot = remapReadModeSlotIndexForPairingChange(
      entries: entries,
      slotIndex: context.read<ReaderCubit>().state.currentSlot,
      wasDoublePage: previous.doublePageMode,
      wasLeadingBlank: previous.doublePageLeadingBlank,
      useDoublePage: readSetting.doublePageMode,
      useLeadingBlank: readSetting.doublePageLeadingBlank,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_jumpToGlobalSlot(targetSlot));
    });
  }

  Future<void> _jumpToGlobalSlot(
    int targetGlobalSlot, {
    int prependedSlotCount = 0,
  }) async {
    if (!mounted) return;
    final cubit = context.read<ReaderCubit>();
    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
    final seamlessCubit = context.read<ReaderSeamlessCubit>();
    final totalSlots = seamlessCubit.resolveTotalSlots(readSetting);
    final maxSlot = (totalSlots - 1).clamp(0, 999999999);
    final safeTarget = targetGlobalSlot.clamp(0, maxSlot);
    cubit.updateCurrentSlot(safeTarget);
    cubit.updateSliderChanged(safeTarget.toDouble());
    seamlessCubit.applyCurrentChapterByGlobalSlot(safeTarget, readSetting);
    ReaderSessionCoordinator.instance.updateProgress(
      currentSlot: safeTarget,
      totalSlots: totalSlots,
    );

    final readMode = readSetting.readMode;
    if (isColumnReadMode(readMode)) {
      if (!scrollController.hasClients) return;

      // 列模式：先根据已缓存/默认尺寸做粗略同步偏移，
      // 再由 observerController.jumpTo 在 postFrame 做精确修正，
      // 减弱历史恢复、滑动条跳转、章节拼接等场景的视觉跳变。
      final imageContext = _imageSizeContext;
      if (imageContext != null && imageContext.mounted) {
        final imageSizeCubit = imageContext.read<ImageSizeCubit>();
        final containerWidth = MediaQuery.of(context).size.width;
        final contentWidth = getConstrainedImageWidth(
          containerWidth: containerWidth,
          enableSidePadding: readSetting.sidePaddingEnabled,
          sidePaddingPercent: readSetting.sidePaddingPercent,
        );
        final estimatedHeight = seamlessCubit
            .estimateColumnHeightBeforeGlobalSlot(
              safeTarget,
              readSetting,
              imageSizeCubit,
              contentWidth,
            );
        if (estimatedHeight > 0) {
          final newOffset = estimatedHeight + getReaderTopOffset(context);
          scrollController.jumpTo(
            newOffset.clamp(
              scrollController.position.minScrollExtent,
              scrollController.position.maxScrollExtent,
            ),
          );
        }
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !scrollController.hasClients) return;
        observerController.jumpTo(
          index: safeTarget,
          offset: (offset) => getReaderTopOffset(context),
        );
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(safeTarget);
      }
    });
  }
}
