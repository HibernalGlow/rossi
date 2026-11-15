import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/widgets/image_sleep.dart';
import 'package:zephyr/widgets/picture_bloc/models/picture_info.dart';

import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/widgets/picture_bloc/bloc/picture_bloc.dart';
import 'package:zephyr/icons/icons.dart';

class Cover extends StatefulWidget {
  final PictureInfo pictureInfo;
  final double height;
  final double borderRadius;
  final VoidCallback? onTap;

  const Cover({
    super.key,
    required this.pictureInfo,
    this.height = 180,
    this.borderRadius = 14,
    this.onTap,
  });

  @override
  State<Cover> createState() => _CoverState();
}

class _CoverState extends State<Cover> {
  late final PictureBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = PictureBloc()..add(GetPicture(widget.pictureInfo));
  }

  @override
  void didUpdateWidget(covariant Cover oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldInfo = oldWidget.pictureInfo;
    final nextInfo = widget.pictureInfo;
    if (oldInfo.from != nextInfo.from ||
        oldInfo.cartoonId != nextInfo.cartoonId ||
        oldInfo.path != nextInfo.path ||
        oldInfo.url != nextInfo.url ||
        oldInfo.chapterId != nextInfo.chapterId ||
        oldInfo.pictureType != nextInfo.pictureType) {
      // 详情页编辑返回后封面路径会变；复用同一个 bloc，但必须发新请求。
      _bloc.add(GetPicture(nextInfo));
    }
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.height / 4 * 3;
    final radius = BorderRadius.circular(widget.borderRadius);

    return SizedBox(
      height: widget.height,
      width: width,
      child: BlocProvider.value(
        value: _bloc,
        child: BlocBuilder<PictureBloc, PictureLoadState>(
          builder: (context, state) {
            switch (state.status) {
              case PictureLoadStatus.initial:
                return DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    color: context.theme.colorScheme.surfaceContainerHigh,
                    border: Border.all(
                      color: context.theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Center(
                    child: LoadingAnimationWidget.waveDots(
                      color: context.theme.colorScheme.primary,
                      size: 40,
                    ),
                  ),
                );
              case PictureLoadStatus.success:
                return InkWell(
                  onTap:
                      widget.onTap ??
                      () {
                        context.pushRoute(
                          FullRouteImageRoute(imagePath: state.imagePath!),
                        );
                      },
                  child: ClipRRect(
                    borderRadius: radius,
                    child: Image.file(
                      File(state.imagePath!),
                      fit: BoxFit.cover,
                      width: width,
                      height: widget.height,
                    ),
                  ),
                );
              case PictureLoadStatus.failure:
                if (state.result.toString().contains('404')) {
                  return ClipRRect(
                    borderRadius: radius,
                    child: Image.asset(
                      'asset/image/error_image/404.png',
                      fit: BoxFit.cover,
                    ),
                  );
                } else {
                  return InkWell(
                    onTap: () {
                      context.read<PictureBloc>().add(
                        GetPicture(widget.pictureInfo),
                      );
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        color:
                            context.theme.colorScheme.surfaceContainerHighest,
                      ),
                      child: const Center(child: GlyphIcon(AppGlyphs.refresh)),
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
