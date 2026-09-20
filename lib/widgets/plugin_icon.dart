import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/discover/service/plugin_display_label.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/widgets/picture_bloc/picture_bloc.dart';

/// 发现页和插件商店共用的图标，按 URL 缓存，不依赖插件是否已安装。
class PluginIcon extends StatelessWidget {
  const PluginIcon({super.key, required this.url, required this.placeholder});

  final String url;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    final iconUrl = url.trim();
    if (iconUrl.isEmpty) return placeholder;

    final pictureInfo = PictureInfo(
      from: 'plugin_icons',
      url: iconUrl,
      path: sha256.convert(utf8.encode(iconUrl)).toString(),
      pictureType: PictureType.avatar,
    );

    return BlocProvider(
      key: ValueKey(iconUrl),
      create: (_) =>
          PictureBloc()..add(GetPicture(pictureInfo, usePlugin: false)),
      child: BlocBuilder<PictureBloc, PictureLoadState>(
        builder: (context, state) {
          switch (state.status) {
            case PictureLoadStatus.initial:
            case PictureLoadStatus.failure:
              return placeholder;
            case PictureLoadStatus.success:
              return Image.file(
                File(state.imagePath!),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
              );
          }
        },
      ),
    );
  }
}

/// 插件**没给图标**时按名字生成的那一枚：底色是插件 id 哈希出的色相，
/// 字面是插件名缩写。
///
/// 为什么要有这东西：不少图源压根没有 `iconUrl`，于是发现页一排卡片全是同一枚
/// 拼图占位图 —— 而发现页的标签条要靠图标区分插件，占位图在这里等于没有信息。
/// 生成图标不需要任何插件配合，且同一个插件每次都是同一枚。
///
/// 颜色只借主题的 `primary` 换色相：饱和度与亮度留在主题的口径里，
/// 换主题（含动态取色 / AMOLED）它跟着走，不会变成一坨与界面无关的彩虹。
class GeneratedPluginIcon extends StatelessWidget {
  const GeneratedPluginIcon({
    super.key,
    required this.seed,
    required this.name,
  });

  /// 色相的种子 —— 用插件 uuid，不用显示名：显示名可以改，图标不该跟着变脸。
  final String seed;

  /// 插件显示名，缩写取它。为空时落到一个「?」。
  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = HSLColor.fromColor(
      scheme.primary,
    ).withHue(hueOfSeed(seed)).toColor();
    final foreground = base.computeLuminance() > 0.45
        ? scheme.onSurface
        : scheme.onPrimary;
    final short = pluginShortName(name);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 无界时按占位尺寸画：调用方没给约束也不该炸，只是字会偏大。
        final side = constraints.biggest.shortestSide;
        final box = side.isFinite && side > 0 ? side : 48.0;
        // 小尺寸（标签条上那 14~16px）塞两个字就是糊，只留第一个。
        final units = box < 28 ? 1 : 2;
        final label = short.isEmpty
            ? '?'
            : String.fromCharCodes(short.runes.take(units));
        return Container(
          decoration: BoxDecoration(
            color: base,
            // 与调用方那枚 ClipRRect(12) 同比例缩：标签条上 14px 的图标
            // 用 12 的圆角就成了一个圆。
            borderRadius: BorderRadius.circular((box * 0.25).clamp(2.0, 12.0)),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: foreground,
              fontSize: box * (units == 1 ? 0.5 : 0.32),
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
        );
      },
    );
  }
}
