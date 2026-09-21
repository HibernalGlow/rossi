import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/theme_shape.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/util/context/context_extensions.dart';

import 'package:zephyr/widgets/picture_bloc/bloc/picture_bloc.dart';
import 'package:zephyr/widgets/picture_bloc/models/picture_info.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry.dart';

class CoverWidget extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final pictureInfo = PictureInfo(
      from: from,
      url: fileServer,
      path: path,
      cartoonId: id,
      pictureType: pictureType,
    );

    final width = this.width ?? context.screenWidth * 0.3;
    final height = this.height ?? (context.screenWidth * 0.3) / 0.75;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final decodeWidth = ((width * devicePixelRatio) * 1.2).round();
    final decodeHeight = ((height * devicePixelRatio) * 1.2).round();

    return BlocProvider(
      create: (context) => PictureBloc()..add(GetPicture(pictureInfo)),
      child: SizedBox(
        width: width,
        height: height,
        child: BlocBuilder<PictureBloc, PictureLoadState>(
          builder: (context, state) {
            switch (state.status) {
              case PictureLoadStatus.initial:
                return Container(
                  width: width,
                  height: height,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(
                      roundedCorner
                          ? themeRadius(
                              context,
                              fallback: kComicCardBorderRadius,
                            )
                          : 0.0,
                    ),
                  ),
                  child: Center(
                    child: Icon(Icons.image, color: Colors.grey[300], size: 30),
                  ),
                );
              case PictureLoadStatus.success:
                return RepaintBoundary(
                  child: Container(
                    width: width,
                    height: height,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(
                        roundedCorner ? 5.0 : 0.0,
                      ),
                      image: DecorationImage(
                        fit: BoxFit.cover,
                        image: ResizeImage(
                          FileImage(File(state.imagePath!)),
                          width: decodeWidth < 1 ? 1 : decodeWidth,
                          height: decodeHeight < 1 ? 1 : decodeHeight,
                        ),
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
                      context.read<PictureBloc>().add(GetPicture(pictureInfo));
                    },
                    child: const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Icon(Icons.refresh, size: 20),
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
