import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/comic_read.dart';
import 'package:zephyr/page/comic_read/cubit/image_size_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/animated_local_page.dart';
import 'package:zephyr/reader/image_surface.dart';
import 'package:zephyr/reader/neighbor_page_prefetch.dart';
import 'package:zephyr/video/view/active_video_scope.dart';
import 'package:zephyr/video/service/video_progress_store.dart';
import 'package:zephyr/workspace/widgets/reader/workspace_reader_fullscreen_scope.dart';
import 'package:zephyr/video/view/video_page_surface.dart';
import 'package:zephyr/widgets/picture_bloc/bloc/picture_bloc.dart';
import 'package:zephyr/widgets/picture_bloc/models/picture_info.dart';

class ReadImageWidget extends StatefulWidget {
  final PictureInfo pictureInfo;
  final int index;
  final bool isColumn;
  final int? cacheIndex;
  final int? displayNumber;
  final Alignment imageAlignment;

  /// 顶栏缩放/旋转面板算好的「这一页画多大」（未旋转的图片自身尺寸）；
  /// null 表示呈现层没参与，按老逻辑铺满宽度。
  final Size? paintSize;

  const ReadImageWidget({
    super.key,
    required this.pictureInfo,
    required this.index,
    required this.isColumn,
    this.cacheIndex,
    this.displayNumber,
    this.imageAlignment = Alignment.center,
    this.paintSize,
  });

  @override
  State<ReadImageWidget> createState() => _ReadImageWidgetState();
}

class _ReadImageWidgetState extends State<ReadImageWidget> {
  int get displayIndex => widget.displayNumber ?? widget.index + 1;
  int get cacheIndex => widget.cacheIndex ?? widget.index;
  bool get isColumn => widget.isColumn;

  /// 本地视频页。
  ///
  /// 走的是**另一条渲染路**：静态图页是「Rust 解像素 → GPU 纹理」，
  /// 视频页是「libmpv 解帧 → media_kit 注册的 textureId」。两者共用页序与
  /// 翻页，但不共用解码 —— 所以在这里提前分叉，不进下面的 GPU 分支。
  Widget _buildLocalVideoPage() {
    final source = LocalReadSession.instance.currentSource;
    if (source == null) {
      return const ColoredBox(color: Colors.black);
    }
    final int localIndex =
        widget.pictureInfo.extern['localIndex'] as int? ?? widget.index;
    final String entryName =
        widget.pictureInfo.extern['videoEntryName'] as String? ??
        widget.pictureInfo.path;
    final siblings =
        (widget.pictureInfo.extern['videoSiblings'] as List<Object?>?)
            ?.map((e) => '$e')
            .toList(growable: false) ??
        const <String>[];
    final sizeBytes = (widget.pictureInfo.extern['videoSize'] as int?) ?? 0;
    // 「当前页」的判据与 GPU 那条路同源：用 localIndex 比 currentSlot。
    // 双页模式下一个槽位会同时挂两页，两页都开播放器就是两条音频；
    // 非当前页只解码不发声，与纹理独占 Owner 是同一个约束的两种表现。
    final int currentSlot = context.select(
      (ReaderCubit c) => c.state.currentSlot,
    );
    final bool isActive = localIndex == currentSlot;

    return FutureBuilder<VideoSettings>(
      future: VideoSettingsStore.instance.load(),
      builder: (context, snapshot) {
        final settings = snapshot.data ?? const VideoSettings();
        return VideoPageSurface(
          key: ValueKey('${widget.pictureInfo.path}-$localIndex'),
          target: VideoPageTarget(
            sourcePath: source.path,
            entryName: entryName,
            pageIndex: localIndex,
            sizeBytes: sizeBytes,
            siblingEntryNames: siblings,
            progressKey: videoProgressKey(
              comicId: widget.pictureInfo.cartoonId,
              chapterId: widget.pictureInfo.chapterId,
              pageIndex: localIndex,
            ),
            resolveDirectPath: () => source.getPageFilePath(localIndex),
            readBytes: () => source.getPageBytes(localIndex),
          ),
          labels: videoLabels(),
          active: isActive,
          settings: VideoPageSettings(
            autoplay: settings.autoPlay,
            controlsPinned: settings.controlsPinned,
            hardwareDecode: settings.hardwareDecode,
            minRate: settings.minRate,
            maxRate: settings.maxRate,
            rateStep: settings.rateStep,
            autoHideMilliseconds: settings.autoHideMilliseconds,
            volumePercent: settings.volumePercent,
            deinterlace: settings.deinterlace,
            subtitleStyle: settings.subtitleStyle,
          ),
          // 全屏按钮走泳道那条路（铺满窗口，不是操作系统全屏）：
          // 没有 scope 时（独立阅读页）就是 null，按钮不出现效果而不是乱调 API。
          onFullscreen: ReaderFullscreenScope.maybeOf(
            context,
          )?.onToggleFullscreen,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final readSetting = context.select(
      (GlobalSettingCubit c) => c.state.readSetting,
    );
    final brightness = Theme.of(context).brightness;
    final backgroundColor = readSetting.resolveReaderBackgroundColor(
      brightness,
    );
    final foregroundColor = readSetting.resolveReaderForegroundColor(
      brightness,
    );

    // 本地漫画 GPU 呈现管线直通
    final bool isLocalGpu = widget.pictureInfo.extern['isLocalGpu'] == true;
    if (widget.pictureInfo.extern['isVideo'] == true && isLocalGpu) {
      return _buildLocalVideoPage();
    }
    if (isLocalGpu) {
      final int localIndex =
          widget.pictureInfo.extern['localIndex'] as int? ?? widget.index;
      final session = LocalReadSession.instance;
      final source = session.currentSource;
      final presenter = session.getOrCreatePresenter();

      // ── 独占 Owner 机制（对齐 mimageviewer NavigationSequence）──
      // GPU 外部纹理同一时刻只能对应一张画面。PageView 翻页滑动时，
      // 上一页与下一页会同时挂载。如果它们都向唯一的 presenter 发 present，
      // 就会在单个 CVPixelBuffer 上交替覆写（Ping-Pong 拔河），表现为
      // 红黄色块闪烁。解决方案：只有当前页挂 ImageSurface 驱动 GPU 上屏。
      //
      // 判「当前页」必须用 localIndex（真正要显示的那一页），不能用 widget.index：
      // 两者在卷/章偏移下会不同，拿 widget.index 比会把当前页判成非当前页，
      // 结果是**谁都不上屏** —— 一片空白，而且看起来像“GPU 瘫了”。
      final int currentSlot = context.select(
        (ReaderCubit c) => c.state.currentSlot,
      );
      final bool isActiveSlot = localIndex == currentSlot;

      // 不再写死 context.screenWidth，继承父容器传入的约束（contentWidth），
      // 消除 RenderFlex overflowed 导致的红黄条纹色块。
      //
      // ── 谁画什么：翻页那两半都得有画面 ──
      //
      // 共享纹理只有一张，而且它归**当前页**用。滑动期间旧页与新页谁都不是
      // 当前页，两边都只能画**自己那份位图** —— 所以每个槽位都挂 `ImageSurface`：
      // 当前页那个额外负责推上屏（`drivesPresentation`），邻页那个只画自己。
      //
      // 老做法是让非当前页画一个 `fontSize: 150` 的页码占位。那是「还没有像素」
      // 的显示，而现在邻页本来就有像素（它自己在解），没理由再顶一个大数字，
      // 翻页时也不该先看到号码再看图。
      //
      // 非当前页**仍然要提前把这一页解好**：改成只让当前页上屏之后，
      // 「邻页顺手把下一页解出来」的副作用一起没了，翻页就要现场等 400–500 ms。
      // 所以除了邻页自己解那张预览位图，还要补一个**只预取、不上屏**的入口
      // （`NeighborPagePrefetch`），让 native 侧把这一页的渲染帧也提前备好。
      //
      // 但"提前解"还不够，它得**在用户翻过去之前解完**。连翻时纹理那条路来不及：
      // 预取准入（`decide_prefetch_allowed`）在每次翻页后 100 ms 内一律拦住预取，
      // 而一次 `prepare` 本身要 200–300 ms —— 于是每一页都成了"新图"，
      // 翻过去现场解码，那一瞬两条路同时没料，透出阅读底色（也就是"黑一下"）。
      // 位图这条是唯一不占那条串行队列的兜底，所以它的**到达时间**才是关键：
      // 邻页按 `bitmapWidthScale` 缩小了解（见 `kNeighborBitmapWidthScale`），
      // 先让那一半有像素，清晰度交给紧跟着的纹理帧。
      final bool swipePreview = readSetting.swipePreviewEnabled;
      final Widget staticRoute =
          source != null && GpuPresentController.isPlatformSupported
          ? Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (isActiveSlot || swipePreview)
                  ImageSurface(
                    source: source,
                    index: localIndex,
                    presenter: presenter,
                    // 只有当前页推共享纹理：两个 slot 都推就是 Ping-Pong 拔河
                    // （同一张纹理被交替覆写）—— 那就是红黄闪的成因。
                    drivesPresentation: isActiveSlot,
                    // 关掉「翻页预览」即退回老行为：上屏成功就释放位图。
                    holdOwnBitmap: swipePreview,
                    // 邻页那份位图是**翻页滑动那两半**的画面，它必须在用户翻过去的
                    // 那一瞬间就位 —— 等一次 300–400 ms 的全宽解码等于没修。按
                    // [kNeighborBitmapWidthScale] 缩小，先有像素，再让纹理帧换成全清。
                    // 当前页那份是留给自己**退场**时画的，要清晰，不给系数。
                    bitmapWidthScale: isActiveSlot
                        ? 1.0
                        : kNeighborBitmapWidthScale,
                    onIntrinsicSize: (size) => context
                        .read<ImageSizeCubit>()
                        .updateIntrinsicSize(cacheIndex, size),
                  )
                else
                  placeholder(
                    backgroundColor: backgroundColor,
                    foregroundColor: foregroundColor,
                  ),
                if (!isActiveSlot)
                  NeighborPagePrefetch(
                    source: source,
                    index: localIndex,
                    presenter: presenter,
                  ),
              ],
            )
          : placeholder(
              backgroundColor: backgroundColor,
              foregroundColor: foregroundColor,
            );

      // 动图页在**上面那条路之外**：那条路是「Rust 解成一帧 → 上屏」，
      // 动图走到那里不会报错，只会安静地变成一张不会动的图。
      // 判定没回来之前先照常画 staticRoute，所以这里没有黑屏空窗。
      return Container(
        color: backgroundColor,
        child: source == null
            ? staticRoute
            : AnimatedLocalPage(
                source: source,
                index: localIndex,
                isColumn: isColumn,
                imageAlignment: widget.imageAlignment,
                paintSize: widget.paintSize,
                onIntrinsicSize: (size) => context
                    .read<ImageSizeCubit>()
                    .updateIntrinsicSize(cacheIndex, size),
                child: staticRoute,
              ),
      );
    }

    final pictureInfoTemp = widget.pictureInfo.copyWith(
      pictureType: PictureType.page,
    );

    return BlocProvider(
      create: (context) => PictureBloc()..add(GetPicture(pictureInfoTemp)),
      child: SizedBox(
        // 呈现层给了尺寸就照它，别再写死 screenWidth —— 侧边留白开着时
        // screenWidth 比父容器给的 contentWidth 宽，那是一条溢出红条。
        width: widget.paintSize?.width ?? context.screenWidth,
        height: widget.paintSize?.height,
        child: BlocBuilder<PictureBloc, PictureLoadState>(
          builder: (context, state) {
            switch (state.status) {
              case PictureLoadStatus.initial:
                return placeholder(
                  backgroundColor: backgroundColor,
                  foregroundColor: foregroundColor,
                );
              case PictureLoadStatus.success:
                return GestureDetector(
                  onLongPress: () {
                    context.pushRoute(
                      FullRouteImageRoute(imagePath: state.imagePath!),
                    );
                  },
                  child: Container(
                    color: backgroundColor,
                    child: ImageDisplay(
                      imagePath: state.imagePath!,
                      isColumn: isColumn,
                      pageSlotIndex: widget.index,
                      sizeCacheIndex: cacheIndex,
                      imageAlignment: widget.imageAlignment,
                      paintSize: widget.paintSize,
                    ),
                  ),
                );
              case PictureLoadStatus.failure:
                if (state.result.toString().contains('404')) {
                  return Image.asset(
                    'asset/image/error_image/404.png',
                    fit: BoxFit.fill,
                  );
                } else {
                  return Container(
                    color: backgroundColor,
                    child: InkWell(
                      onTap: () {
                        context.read<PictureBloc>().add(
                          GetPicture(widget.pictureInfo),
                        );
                      },
                      child: Center(
                        child: Text(
                          t.reader.imageLoadFailedRetry(
                            error: state.result.toString(),
                          ),
                          style: TextStyle(
                            fontSize: 20,
                            color: foregroundColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  );
                }
            }
          },
        ),
      ),
    );
  }

  Widget placeholder({
    required Color backgroundColor,
    required Color foregroundColor,
  }) => Container(
    color: backgroundColor,
    child: Center(
      child: Text(
        displayIndex.toString(),
        style: TextStyle(
          fontFamily: 'Pacifico-Regular',
          color: foregroundColor,
          fontSize: 150,
        ),
      ),
    ),
  );
}
