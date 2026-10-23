import 'dart:io';
import 'package:zephyr/widgets/library_image_geometry.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/theme_shape.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/util/context/context_extensions.dart';

import 'package:zephyr/widgets/picture_bloc/bloc/picture_bloc.dart';
import 'package:zephyr/widgets/picture_bloc/models/picture_info.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry.dart';
import 'package:zephyr/widgets/image_sleep.dart';
import 'package:zephyr/icons/icons.dart';

class CoverWidget extends StatefulWidget {
  final String fileServer;
  final String path;
  final String id;
  final PictureType pictureType;
  final String from;
  final bool roundedCorner;
  final double? width;
  final double? height;

  const CoverWidget({
    super.key,
    required this.fileServer,
    required this.path,
    required this.id,
    required this.pictureType,
    required this.from,
    this.roundedCorner = true,
    this.width,
    this.height,
  });

  @override
  State<CoverWidget> createState() => _CoverWidgetState();
}

class _CoverWidgetState extends State<CoverWidget> {
  /// 封面 provider 缓存（防闪，见 success 分支注释）。
  late PictureInfo _pictureInfo;
  late PictureBloc _bloc;

  /// 封面 provider 缓存（防闪，见 success 分支注释）。
  ImageProvider? _imageProvider;
  String? _imageProviderPath;
  int? _imageProviderWidth;
  int? _imageProviderHeight;

  @override
  void initState() {
    super.initState();
    _pictureInfo = _buildPictureInfo();
    // Bloc 由 State 持有：build 里只引用，不创建。
    // 以前写在 BlocProvider.create 闭包里，每次 build 都会 new 一个 Bloc
    // 并 add 一次 GetPicture（实例被丢弃但 IO 已发出），纯浪费。
    _bloc = PictureBloc()..add(GetPicture(_pictureInfo));
  }

  @override
  void didUpdateWidget(covariant CoverWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileServer != widget.fileServer ||
        oldWidget.path != widget.path ||
        oldWidget.id != widget.id ||
        oldWidget.pictureType != widget.pictureType ||
        oldWidget.from != widget.from ||
        oldWidget.width != widget.width ||
        oldWidget.height != widget.height) {
      _pictureInfo = _buildPictureInfo();
      // 尺寸/图源变了，旧的解码图失效，重新拉图。
      _imageProvider = null;
      _bloc.add(GetPicture(_pictureInfo));
    }
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  PictureInfo _buildPictureInfo() {
    return PictureInfo(
      from: widget.from,
      url: widget.fileServer,
      path: widget.path,
      cartoonId: widget.id,
      pictureType: widget.pictureType,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.width ?? context.screenWidth * 0.3;
    final height = widget.height ?? (context.screenWidth * 0.3) / 0.75;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = ((width * devicePixelRatio) * 1.2).round();
    final decodeHeight = ((height * devicePixelRatio) * 1.2).round();
    return BlocProvider.value(
      value: _bloc,
      child: SizedBox(
        width: width,
        height: height,
        child: BlocBuilder<PictureBloc, PictureLoadState>(
          // 只在图片路径/状态变化时重建，避免无关 rebuild 重新 resolve。
          buildWhen: (prev, curr) =>
              prev.status != curr.status ||
              prev.imagePath != curr.imagePath ||
              prev.result != curr.result,
          builder: (context, state) {
            switch (state.status) {
              case PictureLoadStatus.initial:
                return Container(
                  width: width,
                  height: height,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: .35),
                    borderRadius: BorderRadius.circular(
                      widget.roundedCorner
                          ? themeRadius(
                              context,
                              fallback: kComicCardBorderRadius,
                            )
                          : 0.0,
                    ),
                  ),
                  child: Center(
                    child: GlyphIcon(
                      AppGlyphs.photos,
                      color: Colors.grey[300],
                      size: 30,
                    ),
                  ),
                );
              case PictureLoadStatus.success:
                // image 对象缓存（上游 6bd115aa9 防闪）：选中切换等无关 rebuild
                // 不 new provider，DecorationImage 相等就不重新 resolve，封面不闪；
                // 换图（路径/目标尺寸变）时才重建。
                if (_imageProvider == null ||
                    _imageProviderPath != state.imagePath ||
                    _imageProviderWidth != decodeWidth ||
                    _imageProviderHeight != decodeHeight) {
                  _imageProviderPath = state.imagePath;
                  _imageProviderWidth = decodeWidth;
                  _imageProviderHeight = decodeHeight;
                  _imageProvider = ResizeImage(
                    FileImage(File(state.imagePath!)),
                    width: decodeWidth < 1 ? 1 : decodeWidth,
                    height: decodeHeight < 1 ? 1 : decodeHeight,
                    policy: ResizeImagePolicy.fit,
                  );
                }
                final provider = _imageProvider!;
                return LibraryImageGeometryReporter(
                  provider: provider,
                  child: RepaintBoundary(
                    child: ImageSleep(
                      child: Container(
                        width: width,
                        height: height,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: .35),
                          borderRadius: BorderRadius.circular(
                            widget.roundedCorner ? 5.0 : 0.0,
                          ),
                          image: DecorationImage(
                            fit:
                                LibraryImageGeometryScope.maybeOf(
                                      context,
                                    )?.keepFullImage ==
                                    true
                                ? BoxFit.contain
                                : BoxFit.cover,
                            image: provider,
                            onError: (error, stackTrace) {
                              logger.d(
                                '图片解码失败: ${state.imagePath}',
                                error: error,
                                stackTrace: stackTrace,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              case PictureLoadStatus.failure:
                if (state.result.toString().contains('404')) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(kComicCardBorderRadius),
                    child: Image.asset(
                      'asset/image/error_image/404.png',
                      fit: BoxFit.cover,
                    ),
                  );
                } else {
                  // 「重载封面」住在**顶边居中**，不住正中。
                  //
                  // 重试的点击目标本来就是整格封面（这个 InkWell 铺满），图标只是
                  // 个记号；但正中那一格另有其人 —— 封面的「直接阅读」按钮压在
                  // 标题渐变之上、就在正中间。两颗叠在同一个点上，谁都不该在那儿。
                  // 顶边居中是封面槽里唯一既空着又不与左右角标争位的地方。
                  return InkWell(
                    onTap: () {
                      context.read<PictureBloc>().add(GetPicture(_pictureInfo));
                    },
                    child: const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: GlyphIcon(AppGlyphs.refresh, size: 20),
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
}
