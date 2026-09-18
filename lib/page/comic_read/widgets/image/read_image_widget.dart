import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/comic_read.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/image_surface.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/widgets/picture_bloc/bloc/picture_bloc.dart';
import 'package:zephyr/widgets/picture_bloc/models/picture_info.dart';

class ReadImageWidget extends StatefulWidget {
  final PictureInfo pictureInfo;
  final int index;
  final bool isColumn;
  final int? cacheIndex;
  final int? displayNumber;
  final Alignment imageAlignment;

  const ReadImageWidget({
    super.key,
    required this.pictureInfo,
    required this.index,
    required this.isColumn,
    this.cacheIndex,
    this.displayNumber,
    this.imageAlignment = Alignment.center,
  });

  @override
  State<ReadImageWidget> createState() => _ReadImageWidgetState();
}

class _ReadImageWidgetState extends State<ReadImageWidget> {
  int get displayIndex => widget.displayNumber ?? widget.index + 1;
  int get cacheIndex => widget.cacheIndex ?? widget.index;
  bool get isColumn => widget.isColumn;

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
    if (isLocalGpu) {
      final int localIndex = widget.pictureInfo.extern['localIndex'] as int? ?? widget.index;
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
      // 非当前页仍然要**提前把这一页解好**，否则就退回成了“翻到才解”：
      // 以前邻页自带一个 ImageSurface，顺手就把下一页解出来并推上纹理；
      // 改成只让当前页上屏之后，这个副作用也跟着没了，翻页就要现场等
      // 400–500 ms 的解码。所以要显式补一个**只预取、不上屏**的入口。
      return Container(
        color: backgroundColor,
        child: source != null && GpuPresentController.isPlatformSupported
            ? Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (isActiveSlot)
                    ImageSurface(
                      source: source,
                      index: localIndex,
                      presenter: presenter,
                    )
                  else
                    placeholder(
                      backgroundColor: backgroundColor,
                      foregroundColor: foregroundColor,
                    ),
                  if (!isActiveSlot)
                    _NeighborPrefetch(
                      source: source,
                      index: localIndex,
                      presenter: presenter,
                    ),
                ],
              )
            : placeholder(
                backgroundColor: backgroundColor,
                foregroundColor: foregroundColor,
              ),
      );
    }

    final pictureInfoTemp = widget.pictureInfo.copyWith(
      pictureType: PictureType.page,
    );

    return BlocProvider(
      create: (context) => PictureBloc()..add(GetPicture(pictureInfoTemp)),
      child: SizedBox(
        width: context.screenWidth,
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

/// 邻页的「只预取、不上屏」节点。
///
/// # 它解决的是这个回归
///
/// 以前每个 slot 都挂 `ImageSurface`，所以你在第 N 页时，**下一页已经被邻页 slot
/// 解好并画在它自己那一格里了** —— 翻过去是瞬间的。为了避免多个 slot 抢唯一那张
/// 上屏纹理（Ping-Pong → 红黄闪），改成只有当前页挂 `ImageSurface` 之后，这个
/// 「顺手把邻页解好」的副作用一起消失了，翻页退回成现场等 400–500 ms 的解码。
///
/// 本节点把丢掉的那部分单独补回来：它照常请求 native 侧解码并生成当前视口尺寸的
/// 预渲染帧（翻过去时 `show` 就能 <1 ms 命中），但**不写用户的 display buffer**，
/// 所以不会跟当前页抢纹理。
///
/// 它自己**不画任何东西**（`SizedBox.shrink`）：画面由占位或 `ImageSurface` 负责，
/// 这里只借 Flutter 的布局算出物理尺寸去发一次请求。
class _NeighborPrefetch extends StatefulWidget {
  const _NeighborPrefetch({
    required this.source,
    required this.index,
    required this.presenter,
  });

  final PageSource source;
  final int index;
  final GpuPresentController presenter;

  @override
  State<_NeighborPrefetch> createState() => _NeighborPrefetchState();
}

class _NeighborPrefetchState extends State<_NeighborPrefetch> {
  /// 已发过的请求。同一页 + 同一物理尺寸只发一次 —— 这个节点会在每帧布局后
  /// 被回调，不去重就是每帧一次跨语言往返。
  int? _requestedIndex;
  String? _requestedSize;

  @override
  void didUpdateWidget(_NeighborPrefetch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index ||
        !identical(oldWidget.source, widget.source)) {
      _requestedIndex = null;
      _requestedSize = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size physicalSize = Size(
          constraints.maxWidth * devicePixelRatio,
          constraints.maxHeight * devicePixelRatio,
        );
        final String sizeKey =
            '${physicalSize.width.round()}x${physicalSize.height.round()}';
        final bool alreadyRequested =
            _requestedIndex == widget.index && _requestedSize == sizeKey;
        if (!alreadyRequested && physicalSize.width >= 1 && physicalSize.height >= 1) {
          _requestedIndex = widget.index;
          _requestedSize = sizeKey;
          // 不能在 build 里 await：下一帧再发。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            unawaited(
              widget.presenter.prepareNeighbor(
                source: widget.source,
                index: widget.index,
                physicalSize: physicalSize,
              ),
            );
          });
        }
        return const SizedBox.shrink();
      },
    );
  }
}
